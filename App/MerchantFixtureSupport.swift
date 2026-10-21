#if DEBUG
import SwiftUI

/// Opt-in, wholly offline UI fixtures. The root may route this through a debug flag.
/// No token, endpoint, account enrollment or network transport is created.
enum MerchantFixtureScenario: String {
    case owner, finance, inactive, retry, empty, projectBrowser
    static func selected(arguments: [String]) -> Self? {
        guard let index = arguments.firstIndex(of: "--uitesting-merchant-fixture"), arguments.indices.contains(index + 1) else { return nil }
        return Self(rawValue: arguments[index + 1])
    }
}

@MainActor
struct MerchantFixtureRootView: View {
    @StateObject private var reader: MerchantFixtureReader
    @State private var marketing = MerchantMarketingCoordinator(service: MerchantMarketingService(
        configuration: nil, transport: MerchantMarketingFixtureTransport(), currentSession: { nil }))
    init(scenario: MerchantFixtureScenario) { _reader = StateObject(wrappedValue: MerchantFixtureReader(scenario: scenario)) }
    var body: some View {
        VStack(spacing: 0) {
            Text("merchant.fixtureNotice").font(.caption.bold()).padding(8)
                .frame(maxWidth: .infinity).background(.yellow.opacity(0.2))
                .accessibilityIdentifier("merchant.fixture.notice")
            if reader.projectBrowserDiagnostics {
                Text(String(reader.projectsReadCount)).accessibilityIdentifier("merchant.projectBrowser.fixture.readCount")
            }
            NavigationStack { MerchantHomeView(reader: reader, marketingModel: marketing) }
        }
    }
}

@MainActor
private final class MerchantFixtureReader: MerchantReading {
    let isConfigured = true
    @Published private(set) var isSignedIn = true
    @Published private(set) var sessionRevision: UInt64 = 0
    @Published private(set) var projectsReadCount = 0
    var projectBrowserDiagnostics: Bool { scenario == .projectBrowser }
    private let scenario: MerchantFixtureScenario
    private var didFailAccess = false
    init(scenario: MerchantFixtureScenario) { self.scenario = scenario }
    func merchantAccess() async throws -> MerchantAccess {
        try Task.checkCancellation()
        if scenario == .retry, !didFailAccess { didFailAccess = true; throw APIError.httpStatus(503) }
        if scenario == .inactive {
            return try decode(#"{"active":false,"applicationState":"DISABLED","roleCode":"MERCHANT_OWNER","merchant":{"id":31,"name":"Fixture Store","status":1,"accountStatus":2}}"#)
        }
        if scenario == .finance {
            return try decode(#"{"active":true,"merchant":{"id":31,"name":"Fixture Store"},"roleCode":"MERCHANT_FINANCE","permissions":["merchant:finance:read","merchant:order:read"]}"#)
        }
        return try decode(#"{"active":true,"merchant":{"id":31,"name":"Fixture Store"},"roleCode":"MERCHANT_OWNER","permissions":["merchant:finance:read","merchant:order:read","merchant:project:manage"]}"#)
    }
    func merchantDashboard(access: MerchantAccess) async throws -> MerchantDashboard {
        guard access.canReadDashboard else { throw MerchantReadError.accessDenied }
        return try decode(#"{"revenue":"1250.50","pendingOrders":2,"revenue7d":[{"date":"09-30","amount":"0.00"},{"date":"10-01","amount":"1250.50"}]}"#)
    }
    func merchantTodo(access: MerchantAccess) async throws -> MerchantTodo {
        guard access.isOwner || access.canReadAftercare else { throw MerchantReadError.accessDenied }
        let decoded: MerchantTodo = try decode(#"{"pendingOrders":2,"pendingVerify":1,"verifiedCount":3,"pendingPredict":2}"#)
        return decoded.scoped(for: access)
    }
    func merchantEvents(access: MerchantAccess) async throws -> [MerchantEvent] {
        guard access.isOwner else { throw MerchantReadError.accessDenied }
        return try decode(#"[{"content":"Fixture event","time":"10-01 09:00"}]"#)
    }
    func merchantOrders(access: MerchantAccess, filter: MerchantOrderFilter) async throws -> [MerchantOrder] {
        guard access.allows(.orders) else { throw MerchantReadError.accessDenied }
        if scenario == .empty { return [] }
        let values: [MerchantOrder] = try decode(#"[{"id":101,"orderSn":"Fixture order 101","status":1,"aftersaleStatus":1,"payAmount":"25.00","createTime":"2026-10-01 09:00"},{"id":102,"orderSn":"Fixture order 102","status":4,"aftersaleStatus":4,"payAmount":null,"createTime":"2026-09-30 08:00"}]"#)
        // Filtering here is fixture-only; production filters are sent to the server.
        return values.filter { (filter.status == nil || $0.status == filter.status?.rawValue) && (filter.aftersaleStatus == nil || $0.aftersaleStatus == filter.aftersaleStatus?.rawValue) }
    }
    func merchantProjects(access: MerchantAccess) async throws -> MerchantProjectPage {
        guard access.allows(.projects) else { throw MerchantReadError.accessDenied }
        projectsReadCount += 1
        if scenario == .projectBrowser {
            return try decode(#"{"rows":[{"id":201,"bizType":"topic","title":"Synthetic running theme","state":"running","ownerType":"member","addressName":"East lane"},{"id":202,"bizType":"topic","title":"Synthetic pending theme","state":"pending","ownerType":"member"},{"id":203,"bizType":"topic","title":"Synthetic rejected theme","state":"rejected","ownerType":"member"},{"id":204,"bizType":"topic","title":"Synthetic draft theme","state":"draft","ownerType":"member"},{"id":205,"bizType":"topic","title":"Synthetic second running theme","state":"running"},{"id":301,"bizType":"activity","title":"Synthetic fulfillment activity","state":"notStarted","ownerType":"merchant","addressName":"West lane","pendingVerifyCount":2},{"id":302,"bizType":"activity","title":"Synthetic hosted activity","state":"pending","ownerType":"member","pendingVerifyCount":9},{"id":303,"bizType":"activity","title":"Synthetic unknown activity state","state":"future","ownerType":"merchant","pendingVerifyCount":0},{"id":401,"bizType":"future-kind","title":"Synthetic future project type","state":"future"}],"total":205}"#)
        }
        if scenario == .empty { return try decode(#"{"rows":[],"total":0}"#) }
        return try decode(#"{"rows":[{"id":201,"bizType":"activity","title":"Fixture hosted activity","projectTypeText":"Fixture type","stateText":"Fixture server state","startTime":"2026-10-02 10:00","endTime":"2026-10-02 12:00","signupCount":3,"viewCount":12}],"total":1}"#)
    }
    private func decode<T: Decodable>(_ json: String) throws -> T { try JSONDecoder().decode(T.self, from: Data(json.utf8)) }
}
#endif
