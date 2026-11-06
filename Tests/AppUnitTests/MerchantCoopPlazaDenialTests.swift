import XCTest
@testable import Questify

@MainActor private final class PlazaDenialOfficial: OfficialEventReading {
    var scope = UUID(), isConfigured = true, isAuthenticated = true, isOfflineExample = true
    func events(city: String?) async throws -> [OfficialEvent] { [] }
    func detail(id: Int) async throws -> OfficialEvent { throw APIError.notConfigured }
    func myEvents() async throws -> [OfficialEvent] { [] }
    func partyInbox() async throws -> [OfficialPartyInvite] { [] }
    func canPublish() async throws -> Bool { false }
    func myPublished() async throws -> OfficialPublished { throw APIError.notConfigured }
    func broadcastStats(id: Int) async throws -> OfficialBroadcastStats { throw APIError.notConfigured }
}
@MainActor private final class PlazaDenialWire: HTTPTransport {
    enum Mode { case allowed, accessDenied, http403, business403, unauthorized, offline }
    struct Offline: Error {}
    var mode = Mode.allowed
    var homeCalls = 0
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let path = request.url?.path ?? ""
        if path.hasSuffix("access/me") {
            let permissions = mode == .accessDenied ? "" : "merchant:marketing:read"
            return (Data("{\"code\":200,\"data\":{\"active\":true,\"merchant\":{\"id\":31},\"roleCode\":\"MERCHANT_MANAGER\",\"permissions\":[\"\(permissions)\"]}}".utf8), 200)
        }
        guard path.hasSuffix("marketing-home") else { XCTFail("Unexpected route"); throw Offline() }
        homeCalls += 1
        switch mode {
        case .offline: throw Offline()
        case .http403: return (Data(#"{"code":403}"#.utf8), 403)
        case .business403: return (Data(#"{"code":403}"#.utf8), 200)
        case .unauthorized: return (Data(#"{"code":401}"#.utf8), 401)
        default:
            return (Data(#"{"code":200,"data":{"recruiting":{"count":2,"hasMoreOpen":true,"items":[{"id":70,"name":"Synthetic route"}]},"coupons":{"couponCount":0,"received":0,"verified":0},"content":{"topicCount":0,"freeExploreCount":0,"activityCount":0}}}"#.utf8), 200)
        }
    }
}
@MainActor final class MerchantCoopPlazaDenialTests: XCTestCase {
    private func makeModel(_ wire: PlazaDenialWire) throws -> MerchantCoopCenterModel {
        let session = try MerchantContentSession(accountID: 7, epoch: 1, storageScope: "synthetic-plaza", token: "synthetic-token")
        let content = MerchantContentService(configuration: try APIConfiguration(baseURL: URL(string: "https://example.test/")!), transport: wire, currentSession: { session })
        return .init(content: content, official: PlazaDenialOfficial(), focusTopicID: 70, now: { Date(timeIntervalSince1970: 1_790_827_200) })
    }
    private func load(_ model: MerchantCoopCenterModel) async {
        model.loadRoutes()
        for _ in 0..<200 where model.routesLoading { await Task.yield() }
        XCTAssertFalse(model.routesLoading)
    }
    func testCurrentAuthorizationRefusalsClearCardsCountAndFocusThenExplicitReloadCanRecover() async throws {
        let modes: [PlazaDenialWire.Mode] = [.accessDenied, .http403, .business403, .unauthorized]
        for mode in modes {
            let wire = PlazaDenialWire(), model = try makeModel(wire)
            await load(model)
            XCTAssertEqual(model.routes.count, 1); XCTAssertNotNil(model.routeScope); XCTAssertEqual(model.focusedRouteID, "70")
            wire.mode = mode
            await load(model)
            XCTAssertTrue(model.routes.isEmpty); XCTAssertNil(model.routeScope); XCTAssertNil(model.focusedRouteID)
            XCTAssertEqual(model.routesIssue, mode == .unauthorized ? .signIn : .denied)
            XCTAssertTrue(model.events.isEmpty); XCTAssertNil(model.eventsIssue)
            wire.mode = .allowed
            await load(model)
            XCTAssertEqual(model.routes.count, 1); XCTAssertNil(model.routesIssue)
        }
    }
    func testOrdinaryNetworkFailureRetainsExistingCardsAndCountContract() async throws {
        let wire = PlazaDenialWire(), model = try makeModel(wire)
        await load(model)
        let routes = model.routes, scope = model.routeScope
        wire.mode = .offline
        await load(model)
        XCTAssertEqual(model.routes, routes); XCTAssertEqual(model.routeScope, scope)
        XCTAssertEqual(model.focusedRouteID, "70"); XCTAssertEqual(model.routesIssue, .failed(nil))
    }
}
