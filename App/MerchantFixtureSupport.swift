#if DEBUG
import SwiftUI

/// Opt-in, wholly offline UI fixtures. The root may route this through a debug flag.
/// No token, endpoint, account enrollment or network transport is created.
enum MerchantFixtureScenario: String {
    case owner, finance, inactive, retry, empty
    static func selected(arguments: [String]) -> Self? {
        guard let index = arguments.firstIndex(of: "--uitesting-merchant-fixture"), arguments.indices.contains(index + 1) else { return nil }
        return Self(rawValue: arguments[index + 1])
    }
}

@MainActor
struct MerchantFixtureRootView: View {
    @StateObject private var reader: MerchantFixtureReader
    private let marketing = MerchantMarketingCoordinator(service: MerchantMarketingService(
        configuration: nil, transport: MerchantMarketingFixtureTransport(), currentSession: { nil }))
    init(scenario: MerchantFixtureScenario) { _reader = StateObject(wrappedValue: MerchantFixtureReader(scenario: scenario)) }
    var body: some View {
        VStack(spacing: 0) {
            Text("merchant.fixtureNotice").font(.caption.bold()).padding(8)
                .frame(maxWidth: .infinity).background(.yellow.opacity(0.2))
                .accessibilityIdentifier("merchant.fixture.notice")
            NavigationStack { MerchantHomeView(reader: reader, marketingModel: marketing) }
        }
    }
}

@MainActor
private final class MerchantFixtureReader: MerchantReading {
    let isConfigured = true
    @Published private(set) var isSignedIn = true
    @Published private(set) var sessionRevision: UInt64 = 0
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
        guard access.isOwner else { throw MerchantReadError.accessDenied }
        return try decode(#"{"pendingOrders":2,"pendingVerify":1,"verifiedCount":3}"#)
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
        if scenario == .empty { return try decode(#"{"rows":[],"total":0}"#) }
        return try decode(#"{"rows":[{"id":201,"bizType":"activity","title":"Fixture hosted activity","projectTypeText":"Fixture type","stateText":"Fixture server state","startTime":"2026-10-02 10:00","endTime":"2026-10-02 12:00","signupCount":3,"viewCount":12}],"total":1}"#)
    }
    private func decode<T: Decodable>(_ json: String) throws -> T { try JSONDecoder().decode(T.self, from: Data(json.utf8)) }
}
#endif
