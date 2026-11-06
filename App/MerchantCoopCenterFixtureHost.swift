#if DEBUG
import SwiftUI
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Offline synthetic cooperation center. Requests terminate in memory; nothing is sent or saved.
enum MerchantCoopCenterFixtureScenario: String {
    case normal, official, focus, empty, error, denied, signedOut
}

enum MerchantCoopCenterFixtureData {
    /// 2026-10-01 12:00 +08:00, so deadlines below are deterministic.
    static let now = Date(timeIntervalSince1970: 1_790_827_200)
    static let routes = #"""
    [{"id":70,"name":"Synthetic harbour walk","imgUrl":"","productType":1,"startDate":"2026-10-12","endDate":"2026-10-14","cityKeyword":"Sample City","locationCount":3,"remainingMerchantCount":3,"termsModes":["PERK"],"perkMinValue":20,"recruitDeadline":"2026-10-10 18:00:00","merchantSignUpEndDate":"2026-10-10 18:00:00"},
     {"id":71,"name":"Synthetic lantern trail","productType":2,"startDate":"2026-10-20","endDate":"2026-10-20","cityKeyword":"Sample City","locationCount":5,"remainingMerchantCount":1,"termsModes":["REVSHARE"],"maxPerHeadFee":8.5,"merchantSignUpEndDate":"2026-10-15"},
     {"id":72,"name":"Synthetic market loop","productType":1,"startDate":"2026-09-01","endDate":"2026-09-02","locationCount":2,"remainingMerchantCount":0,"termsModes":["PERK","TRAFFIC"],"recruitDeadline":"2026-09-20"},
     {"id":73,"name":"Synthetic river route","productType":1,"termsModes":["TRAFFIC"],"remainingMerchantCount":null},
     {"id":74,"name":"Synthetic garden stroll","productType":2,"startDate":"2026-11-01","endDate":"2026-11-03","cityKeyword":"Sample City","locationCount":4,"remainingMerchantCount":2,"termsModes":[],"recruitDeadline":"2026-10-30"},
     {"id":"","name":"Dropped: missing id"}]
    """#
    static func home(empty: Bool) -> String {
        let items = empty ? "[]" : routes
        let recruiting = empty ? #""count":0,"openCount":0,"shownCount":0,"hasMoreOpen":false"# : #""count":12,"openCount":12,"shownCount":5,"hasMoreOpen":true"#
        return #"{"recruiting":{"# + recruiting + #","items":"# + items + #"},"coupons":{"couponCount":1,"received":0,"verified":0},"content":{"topicCount":1,"freeExploreCount":0,"activityCount":0},"analytics":{},"funnel":[]}"#
    }
    static let events = #"""
    [{"id":81,"title":"Synthetic city festival","subtitle":"Sample partner recruitment","city":"Sample City","status":1,"contractVersion":2,"fulfillmentPolicy":"OPTIONAL_PARTNERS","recruitmentBlocked":false},
     {"id":82,"title":"Synthetic night market","subtitle":"Sample stalls wanted","city":"","status":2,"contractVersion":2,"fulfillmentPolicy":"REQUIRED_FULFILLMENT","recruitmentBlocked":true,"recruitmentBlockedReason":"  "},
     {"id":83,"title":"Synthetic lantern evening","city":"Sample City","status":1,"contractVersion":2,"fulfillmentPolicy":"REQUIRED_FULFILLMENT","recruitmentBlocked":true,"recruitmentBlockedReason":"Synthetic: a key host is missing"},
     {"id":84,"title":"Hidden: ended event","status":5,"contractVersion":2,"fulfillmentPolicy":"OPTIONAL_PARTNERS"},
     {"id":85,"title":"Hidden: no merchant policy","status":1}]
    """#
}

final class MerchantCoopCenterFixtureTransport: MerchantContentOfflineTransport {
    let scenario: MerchantCoopCenterFixtureScenario
    private let fallback = MerchantContentFixtureTransport()
    private var homeReads = 0
    init(scenario: MerchantCoopCenterFixtureScenario) { self.scenario = scenario }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        switch request.url?.path ?? "" {
        case "/api/merchant/access/me":
            if scenario == .denied { return envelope(#"{"active":false,"permissions":[]}"#) }
            return envelope(MerchantContentFixtureData.access)
        case "/api/merchant/marketing-home":
            homeReads += 1
            // The error scenario fails once, then an explicit retry succeeds.
            if scenario == .error && homeReads == 1 { throw URLError(.notConnectedToInternet) }
            return envelope(MerchantCoopCenterFixtureData.home(empty: scenario == .empty))
        default: return try await fallback.send(request)
        }
    }
    private func envelope(_ data: String) -> (Data, Int) { (Data((#"{"code":200,"msg":"ok","data":"# + data + "}").utf8), 200) }
}

@MainActor final class MerchantCoopCenterFixtureOfficialReader: OfficialEventReading {
    let scenario: MerchantCoopCenterFixtureScenario
    private var reads = 0
    let scope = UUID()
    init(scenario: MerchantCoopCenterFixtureScenario) { self.scenario = scenario }
    var isConfigured: Bool { true }
    var isAuthenticated: Bool { scenario != .signedOut }
    var isOfflineExample: Bool { true }
    private func rows() throws -> [OfficialEvent] {
        try JSONDecoder().decode([OfficialEvent].self, from: Data(MerchantCoopCenterFixtureData.events.utf8))
    }
    func events(city: String?) async throws -> [OfficialEvent] {
        reads += 1
        guard city == nil else { throw APIError.invalidRequest }
        switch scenario {
        case .signedOut: throw APIError.unauthorized
        case .denied: throw OfficialReadFailure.forbidden
        case .empty: return []
        case .error where reads == 1: throw APIError.httpStatus(503)
        default: return try rows()
        }
    }
    func detail(id: Int) async throws -> OfficialEvent {
        guard isAuthenticated else { throw APIError.unauthorized }
        guard let row = try rows().first(where: { $0.id == id }) else { throw APIError.httpStatus(404) }
        return row
    }
    func myEvents() async throws -> [OfficialEvent] { throw APIError.invalidRequest }
    func partyInbox() async throws -> [OfficialPartyInvite] { throw APIError.invalidRequest }
    func canPublish() async throws -> Bool { false }
    func myPublished() async throws -> OfficialPublished { throw APIError.invalidRequest }
    func broadcastStats(id: Int) async throws -> OfficialBroadcastStats { throw APIError.invalidRequest }
}

@MainActor final class MerchantCoopCenterFixtureEnvironment: ObservableObject {
    let scenario: MerchantCoopCenterFixtureScenario
    let service: MerchantContentService
    let official: MerchantCoopCenterFixtureOfficialReader
    init(scenario: MerchantCoopCenterFixtureScenario) {
        self.scenario = scenario
        var session: MerchantContentSession?
        if scenario != .signedOut {
            session = try? MerchantContentSession(accountID: 1, epoch: 1, storageScope: "offline-merchant-coop-center-fixture", token: "fixture-token")
        }
        let captured = session
        service = MerchantContentService(configuration: try? APIConfiguration(baseURL: URL(string: "https://merchant-coop-center.example")!),
            transport: MerchantCoopCenterFixtureTransport(scenario: scenario), currentSession: { captured })
        official = MerchantCoopCenterFixtureOfficialReader(scenario: scenario)
    }
}

/// Registered by the lead under `--uitesting-module merchant-city-npc --w2-19-page coopCenter`.
@MainActor struct MerchantCoopCenterFixtureHost: View {
    @StateObject private var environment: MerchantCoopCenterFixtureEnvironment
    @Environment(\.locale) private var locale
    init(scenario: String) {
        _environment = StateObject(wrappedValue: .init(scenario: MerchantCoopCenterFixtureScenario(rawValue: scenario) ?? .normal))
    }
    var body: some View {
        VStack(spacing: 0) {
            NavigationStack {
                MerchantCoopCenterView(content: environment.service, official: environment.official,
                    initialTab: environment.scenario == .official ? .official : .plaza,
                    focusTopicID: environment.scenario == .focus ? 74 : nil,
                    now: { MerchantCoopCenterFixtureData.now },
                    inboxDestination: { close in AnyView(CooperationBrowserView(reader: CooperationFixtureReader(), onClose: close)) })
            }
            Text(mcc("merchantCoopCenter.fixture.banner", locale)).font(.footnote).padding(6)
                .frame(maxWidth: .infinity).background(.regularMaterial)
                .accessibilityIdentifier("merchantCoopCenter.fixture.banner")
        }
    }
}
#endif
