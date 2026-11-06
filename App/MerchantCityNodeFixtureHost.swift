#if DEBUG
import SwiftUI
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Offline, stateful `city-node` source. Requests end here; no socket, camera or location exists.
final class MerchantCityNodeFixtureTransport: MerchantContentOfflineTransport {
    let scenario: String
    private(set) var requests: [URLRequest] = []
    private var nodes: [MerchantContentValue]
    private var applications: [MerchantContentValue]
    private var nextApplicationID = 92
    init(scenario: String) {
        self.scenario = scenario
        if scenario == "empty" { nodes = []; applications = [] } else {
            nodes = [
                .object(["poiId": .integer(701), "name": .string("Synthetic riverside node"), "status": .integer(1), "templateTitle": .string("Synthetic hidden phrase"),
                         "tags": .string("Night walk"), "validationMethod": .integer(4)]),
                .object(["poiId": .integer(702), "name": .string("Synthetic courtyard node"), "status": .integer(0), "validationMethod": .integer(5)])]
            applications = [
                .object(["id": .integer(81), "name": .string("Synthetic café placement"), "applicationType": .integer(1), "auditStatus": .integer(2),
                         "auditReason": .string("Synthetic reason: the storefront sign is not fully visible.")]),
                .object(["id": .integer(83), "name": .string("Synthetic square claim"), "applicationType": .integer(2), "auditStatus": .integer(0), "merchantId": .null])]
        }
    }
    private var used: MerchantContentValue {
        switch scenario { case "full": return .integer(3); case "unknownQuota": return .string("1"); default: return .integer(nodes.filter { $0["status"].integer == 1 }.count) }
    }
    private var maximum: MerchantContentValue { .integer(scenario == "noQuota" ? 0 : 3) }
    private var access: String {
        scenario == "denied" ? #"{"active":true,"merchant":{"id":31,"name":"Synthetic store"},"roleCode":"MERCHANT_CHECKIN","permissions":["merchant:verify"]}"#
            : #"{"active":true,"merchant":{"id":31,"name":"Synthetic store"},"roleCode":"MERCHANT_OWNER","permissions":["merchant:project:manage","merchant:verify"]}"#
    }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        let path = request.url?.path ?? ""
        if path == "/api/merchant/access/me" { return envelope(access) }
        if scenario == "error" { throw URLError(.notConnectedToInternet) }
        switch path {
        case "/api/merchant/city-node/list":
            return try envelope(.object(["nodes": .array(nodes), "applications": .array(applications), "used": used, "max": maximum]))
        case "/api/merchant/city-node/claimable":
            if scenario == "claimEmpty" { return envelope("[]") }
            return envelope(#"[{"id":801,"name":"Synthetic plaza node","description":"Synthetic platform point"},{"id":802,"name":"Synthetic bridge node","cityCode":"SYN-01"}]"#)
        case "/api/merchant/city-node/poster-code":
            if scenario == "posterError" { return envelope(#"{"nodeName":"Synthetic riverside node"}"#) }
            return envelope(#"{"code":"SYNTHETIC-NOT-REDEEMABLE","qrcodeUrl":"https://example.invalid/synthetic-poster.png","nodeName":"Synthetic riverside node"}"#)
        case "/api/merchant/info":
            if scenario == "noCoordinates" { return envelope(#"{"id":31,"name":"Synthetic store","address":"","locationLat":0,"locationLng":0}"#) }
            return envelope(#"{"id":31,"name":"Synthetic store","address":"1 Synthetic Street","locationLat":12.3,"locationLng":45.6}"#)
        case "/api/template/my-list":
            return envelope(#"{"rows":[{"id":71,"title":"Synthetic hidden menu","interactionType":"hidden_menu","validationMethod":3},{"id":73,"title":"Saved synthetic template","validationMethod":4}]}"#)
        default: break
        }
        if scenario == "uncertain" { throw URLError(.timedOut) }
        if scenario == "rejected" { return (Data(#"{"code":500,"msg":"Synthetic rejection: try again later"}"#.utf8), 200) }
        let body = request.httpBody ?? Data()
        let poi = Self.field("poiId", body).flatMap(Int.init)
        switch path {
        case "/api/merchant/city-node/claim":
            if let poi { applications.insert(.object(["id": .integer(poi), "name": .string("Synthetic claim"), "applicationType": .integer(2), "auditStatus": .integer(0), "merchantId": .null]), at: 0) }
            return envelope(String(poi ?? 0))
        case "/api/merchant/city-node/claim/cancel":
            applications.removeAll { $0["id"].integer == poi }
            return envelope(#""已撤回认领申请""#)
        case "/api/merchant/city-node/offline":
            let online = Self.field("status", body) == "1"
            nodes = nodes.map { row in
                guard row["poiId"].integer == poi, var object = row.object else { return row }
                object["status"] = .integer(online ? 1 : 0); return .object(object)
            }
            return envelope(online ? #""已上架""# : #""已下线""#)
        case "/api/merchant/city-node/save":
            let id = nextApplicationID; nextApplicationID += 1
            if scenario != "readbackMissing" {
                applications.insert(.object(["id": .integer(id), "name": .string(Self.field("name", body) ?? "Synthetic store"), "applicationType": .integer(1), "auditStatus": .integer(0)]), at: 0)
            }
            return envelope(scenario == "objectId" ? #"{"id":\#(id)}"# : String(id))
        default: return envelope("{}")
        }
    }
    /// Multipart field reader for the existing AuthRequestBuilder form body.
    static func field(_ name: String, _ body: Data) -> String? {
        let text = String(decoding: body, as: UTF8.self)
        guard let header = text.range(of: "name=\"\(name)\"\r\n\r\n") else { return nil }
        let rest = text[header.upperBound...]
        return String(rest[..<(rest.range(of: "\r\n--")?.lowerBound ?? rest.endIndex)])
    }
    private func envelope(_ data: String) -> (Data, Int) { (Data(("{\"code\":200,\"msg\":\"Synthetic acknowledgement\",\"data\":" + data + "}").utf8), 200) }
    private func envelope(_ value: MerchantContentValue) throws -> (Data, Int) {
        try (JSONEncoder().encode(MerchantContentValue.object(["code": .integer(200), "msg": .string("ok"), "data": value])), 200)
    }
}

/// Only exposes the raw access grant used to decide `merchant:verify`; every mutation is refused.
@MainActor final class MerchantCityNodeFixtureBusinessReader: MerchantBusinessReading {
    let verify: Bool
    var scope: MerchantBusinessScope? = .init(realm: "synthetic://merchant-city-node", accountID: 1, epoch: 1)
    let isConfigured = true
    let isOfflineExample = true
    let canExecuteSyntheticMutation = false
    init(verify: Bool) { self.verify = verify }
    func access() async throws -> MerchantBusinessAccess {
        let permissions = verify ? #"["merchant:project:manage","merchant:verify"]"# : #"["merchant:project:manage"]"#
        let raw = #"{"active":true,"merchant":{"id":31,"name":"Synthetic store"},"roleCode":"MERCHANT_MANAGER","permissions":"# + permissions + "}"
        guard let object = try JSONDecoder().decode(MerchantBusinessValue.self, from: Data(raw.utf8)).object else { throw MerchantBusinessFailure.malformed }
        return try .init(object)
    }
    func snapshot(_ query: MerchantBusinessQuery) async throws -> MerchantBusinessSnapshot { throw MerchantBusinessFailure.disabled }
    func execute(_ mutation: MerchantBusinessMutation, requestID: String, scope: MerchantBusinessScope) async throws -> MerchantBusinessReceipt {
        throw MerchantBusinessFailure.disabled
    }
}

@MainActor final class MerchantCityNodeFixturePlaces: PublishingPlaceSearching {
    func search(_ query: String) async throws -> [PublishingPlace] {
        [try PublishingPlace(id: "synthetic-door", name: "Synthetic shop door", address: "2 Synthetic Street", latitude: 12.31, longitude: 45.61)]
    }
}

@MainActor final class MerchantCityNodeFixtureEnvironment: ObservableObject {
    let transport: MerchantCityNodeFixtureTransport
    let service: MerchantContentService
    let business: MerchantCityNodeFixtureBusinessReader
    let journal = MerchantBusinessMemoryIntentStore()
    let places = MerchantCityNodeFixturePlaces()
    let operations = MerchantOperationsFixtureReader()
    private var session: MerchantContentSession? = try? .init(accountID: 1, epoch: 1, storageScope: "offline-merchant-city-node-fixture", token: "fixture-token")
    init(scenario: String) {
        let transport = MerchantCityNodeFixtureTransport(scenario: scenario)
        self.transport = transport
        business = .init(verify: scenario != "noVerify")
        var current: (() -> MerchantContentSession?)?
        service = MerchantContentService(configuration: try? APIConfiguration(baseURL: URL(string: "https://merchant-city-node.example.invalid")!),
            transport: transport, currentSession: { current?() }, journal: MerchantContentMemoryPendingStorage(), execution: .injectedOfflineHarness)
        current = { [weak self] in self?.session }
    }
}

struct MerchantCityNodeFixtureBanner: View {
    var body: some View {
        MerchantCityNodeCopy.text("merchantCityNode.fixture.banner").font(.footnote).padding(6).frame(maxWidth: .infinity).background(.regularMaterial)
            .accessibilityIdentifier("cityNodeFixture.banner")
    }
}

/// `--w2-19-page cityNode`: normal, empty, error, denied, full, noQuota, unknownQuota, noVerify, rejected, uncertain, posterError, claimEmpty.
@MainActor struct MerchantCityNodeHubFixtureHost: View {
    @StateObject private var environment: MerchantCityNodeFixtureEnvironment
    init(scenario: String) { _environment = StateObject(wrappedValue: MerchantCityNodeFixtureEnvironment(scenario: scenario)) }
    var body: some View {
        VStack(spacing: 0) {
            NavigationStack {
                MerchantCityNodeHubView(service: environment.service, businessReader: environment.business, businessJournal: environment.journal,
                                        placeSearch: environment.places, isOfflineFixture: true)
            }
            MerchantCityNodeFixtureBanner()
        }.environment(\.merchantCityTemplateHandoffFactory, { [environment] in .init(reader: environment.operations) })
    }
}

/// `--w2-19-page cityNodeCreate`: normal, objectId, configured, noCoordinates, error, denied, full, readbackMissing, uncertain, rejected.
@MainActor struct MerchantCityNodeCreateFixtureHost: View {
    @StateObject private var environment: MerchantCityNodeFixtureEnvironment
    @State private var path: [Int] = [1]
    private let seed: Int?
    init(scenario: String) {
        _environment = StateObject(wrappedValue: MerchantCityNodeFixtureEnvironment(scenario: scenario))
        seed = ["normal", "noCoordinates", "error", "denied"].contains(scenario) ? nil : 71
    }
    var body: some View {
        VStack(spacing: 0) {
            NavigationStack(path: $path) {
                // Root stands in for the hub so a successful readback's dismiss is observable.
                MerchantCityNodeCopy.text("merchantCityNode.title").accessibilityIdentifier("cityNodeFixture.returned")
                    .navigationDestination(for: Int.self) { _ in
                        MerchantCityNodeCreateView(service: environment.service, placeSearch: environment.places, isOfflineFixture: true, templateSeed: seed)
                    }
            }
            MerchantCityNodeFixtureBanner()
        }.environment(\.merchantCityTemplateHandoffFactory, { [environment] in .init(reader: environment.operations) })
    }
}
#endif
