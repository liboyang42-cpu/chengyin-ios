#if DEBUG
import SwiftUI

actor MerchantEngagementFixtureTransport: MerchantBusinessTestTransport {
    let scenario: String
    private var createdTask: MerchantBusinessObject?
    private var exportPolls = 0
    init(scenario: String) { self.scenario = scenario }
    private func object(_ raw: String) throws -> MerchantBusinessObject { try MerchantEngagementSyntheticFixtures.decode(raw).object! }
    private func envelope(_ value: MerchantBusinessValue) throws -> (Data, Int) { (try JSONEncoder().encode(MerchantBusinessValue.object(["code": .int(200), "data": value])), 200) }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let path = request.url?.path ?? ""
        let fields = request.httpBody.flatMap { try? JSONDecoder().decode(MerchantBusinessValue.self, from: $0).object } ?? [:]
        if path.hasSuffix("access/me") {
            if scenario == "inactive" { return try envelope(.object(["active": .bool(false), "permissions": .array([])])) }
            if scenario == "denied" { return (Data(#"{"code":403,"msg":"Synthetic denial"}"#.utf8), 200) }
            return try envelope(MerchantEngagementSyntheticFixtures.decode(MerchantEngagementSyntheticFixtures.access))
        }
        let sensitiveAction = request.httpMethod == "POST" && !path.hasSuffix("/preview") && !path.hasSuffix("/status") && !path.hasSuffix("/detail")
        if scenario == "unknown", sensitiveAction { throw URLError(.timedOut) }
        switch path {
        case "/api/merchant/crm/segments":
            return try envelope(request.httpMethod == "GET" ? MerchantEngagementSyntheticFixtures.decode(MerchantEngagementSyntheticFixtures.segments) : .object(["id": .int(71002)]))
        case "/api/merchant/crm/campaigns/coupons": return try envelope(MerchantEngagementSyntheticFixtures.decode(MerchantEngagementSyntheticFixtures.coupons))
        case "/api/merchant/crm/campaigns/preview": return try envelope(MerchantEngagementSyntheticFixtures.decode(MerchantEngagementSyntheticFixtures.audience))
        case "/api/merchant/crm/broadcast/preview": return try envelope(MerchantEngagementSyntheticFixtures.decode(MerchantEngagementSyntheticFixtures.broadcast))
        case "/api/merchant/crm/broadcast":
            return try envelope(.object(["id": .int(76001), "status": .string("PARTIAL_FAILED"), "audienceCount": .int(7), "consentedCount": .int(5), "noConsentCount": .int(2), "frequencySkippedCount": .int(1), "deliveredCount": .int(3), "failedCount": .int(1)]))
        case "/api/merchant/crm/campaigns":
            if request.httpMethod == "GET" { return try envelope(.array([.object(try createdTask ?? object(MerchantEngagementSyntheticFixtures.campaign))])) }
            var task = try object(MerchantEngagementSyntheticFixtures.campaign); task["id"] = .int(73002); task["title"] = fields["title"]; task["channel"] = fields["channel"]; createdTask = task
            return try envelope(.object(task))
        case "/api/merchant/crm/exports": return try envelope(.object(["id": .int(74001), "status": .string("PENDING"), "downloadToken": .string("synthetic-export-token")]))
        case "/api/merchant/crm/exports/74001/status":
            exportPolls += 1
            return try envelope(.object(["id": .int(74001), "status": .string(exportPolls > 1 ? "SUCCESS" : "RUNNING"), "rowCount": exportPolls > 1 ? .int(7) : .null]))
        case "/api/merchant/crm/exports/74001/download":
            guard request.value(forHTTPHeaderField: "X-CRM-Export-Token") == "synthetic-export-token" else { return (Data(), 403) }
            return (MerchantEngagementSyntheticFixtures.workbookBytes, 200) // Structurally valid, entirely synthetic masked workbook.
        case "/api/merchant/operators/invite/accept": return try envelope(.object(["id": .int(75001), "nickname": .string("Example operator"), "roleCode": .string("MERCHANT_MARKETING"), "status": .string("ACTIVE"), "acceptedAt": .string("2026-10-02 00:00:00"), "version": .int(0)]))
        case "/api/merchant/crm/customers/61001/detail": return try envelope(MerchantBusinessSyntheticFixtures.decode(MerchantBusinessSyntheticFixtures.customer))
        case "/api/merchant/crm/customers/61001/contact": return try envelope(.object(["phone": .string("+1 (202) 555-0100")]))
        case "/api/merchant/aftercare/detail": return try envelope(MerchantBusinessSyntheticFixtures.decode(MerchantBusinessSyntheticFixtures.refund))
        case "/api/common/uploadOSS": return (Data((#"{"code":200,"fileName":"upload/merchant-aftercare-evidence/"# + String(repeating: "a", count: 32) + #".png"}"#).utf8), 200)
        default:
            if path.hasPrefix("/api/merchant/crm/campaigns/") {
                var task = try createdTask ?? object(MerchantEngagementSyntheticFixtures.campaign)
                if path.hasSuffix("/dispatch") || path.hasSuffix("/retry") { task["status"] = .string("SUCCESS"); task["deliveredCount"] = .int(4); createdTask = task }
                return try envelope(.object(task))
            }
            throw MerchantBusinessFailure.invalid
        }
    }
}
/// Explicit offline UI-only wrapper. It never creates URLSession or a backend connection.
private struct MerchantEngagementOrdinaryFixtureTransport: HTTPTransport {
    let fixture: MerchantEngagementFixtureTransport
    func send(_ request: URLRequest) async throws -> (Data, Int) { try await fixture.send(request) }
}
@MainActor final class MerchantEngagementFixtureSession {
    var current: MerchantBusinessSession? = try? .init(accountID: 99001, epoch: 1, token: "synthetic-token")
}
@MainActor struct MerchantEngagementFixtureHostView: View {
    private let holder: MerchantEngagementFixtureSession
    private let reader: MerchantEngagementSessionReader
    private let journal: any MerchantBusinessIntentStore
    private let recovery = MerchantExportMemoryRecoveryStore()
    private let scenario: String
    @State private var revision = 0
    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let index = arguments.firstIndex(of: "--uitesting-merchant-engagement-scenario")
        scenario = index.flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil } ?? "ready"
        let holder = MerchantEngagementFixtureSession(), transport = MerchantEngagementFixtureTransport(scenario: scenario)
        self.holder = holder
        let configuration = try! APIConfiguration(baseURL: URL(string: "https://example.com")!)
        if scenario == "productionFactory" {
            let wire = MerchantEngagementOrdinaryFixtureTransport(fixture: transport)
            let command = MerchantEngagementCommand.saveSegment(name: "Example segment", filter: .init())
            let approval = try! MerchantEngagementProductionApproval(market: .china,
                endpoints: .init(baseURL: configuration.baseURL, namespace: "offline-ui", accountID: 99001, paths: ["api/merchant/crm/segments"]),
                grants: [.init(merchantID: 710, command: command)], reviewedPolicyVersion: "offline-ui-policy")
            func current() -> RuntimeDependencyContext? {
                guard let session = holder.current else { return nil }
                return .init(market: .china, baseURL: configuration.baseURL, role: "merchant",
                    session: try! .init(accountID: session.accountID, epoch: session.epoch, namespace: "offline-ui", token: "synthetic-token"))
            }
            reader = .init(service: .init(configuration: configuration, readTransport: wire), session: { holder.current },
                productionService: { command, merchantID in
                    MerchantEngagementProductionFactory(api: configuration, approval: approval, transport: wire, current: current).service(for: command, merchantID: merchantID)
                }, runtimeContext: current)
            journal = MerchantBusinessFileIntentStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("merchant-engagement-ui-" + UUID().uuidString).appendingPathComponent("intents.json"))
        } else {
            let service = MerchantEngagementService(configuration: configuration, readTransport: transport, testingActionTransport: scenario == "disabled" ? nil : transport)
            reader = .init(service: service, session: { holder.current })
            journal = MerchantBusinessMemoryIntentStore()
        }
    }
    var body: some View {
        VStack {
            if scenario == "sessionChange" {
                Button("merchant.engagement.fixtureSignOut") { holder.current = nil; revision += 1 }.accessibilityIdentifier("merchant.engagement.fixtureSignOut")
            }
            NavigationStack { MerchantEngagementHomeView(reader: reader, journal: journal, exportRecovery: recovery) }.id(revision)
        }
    }
}
#endif
