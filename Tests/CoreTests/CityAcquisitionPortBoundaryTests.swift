import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class CityAcquisitionPortBoundaryTests: XCTestCase {
    func testChangedCredentialCannotReuseAcquisitionGrant() throws {
        let f = CityAcquisitionTests(), grant = try f.approval(writes: false), c = grant.context
        let changed = RuntimeDependencyContext(market: c.market, baseURL: c.baseURL, role: c.role,
            session: try .init(accountID: 7, epoch: 1, namespace: "city-acquire", token: "new-token", role: "player"))
        XCTAssertFalse(grant.matches(changed))
    }
    func testCookieRequestsDeniedAndOriginalReadDisablesCookies() async throws {
        let f = CityAcquisitionTests(), grant = try f.approval(writes: false), wire = CityAcquisitionTests.Wire()
        let service = f.service(grant, wire)
        wire.respond = { _ in try f.response(["contract": "CITY_ACQUISITION_V1", "memberId": 7, "regionId": "city-1", "titles": []]) }
        var request = URLRequest(url: f.base.appendingPathComponent("api/city-game/acquisition/titles").appending(queryItems: [.init(name: "regionId", value: "city-1")]))
        request.httpMethod = "GET"; request.setValue(grant.context.session.token, forHTTPHeaderField: "Authorization")
        do { _ = try await service.transport.send(request); XCTFail("Automatic cookies must be denied") } catch {}
        request.httpShouldHandleCookies = false; request.setValue("fake-cookie", forHTTPHeaderField: "Cookie")
        do { _ = try await service.transport.send(request); XCTFail("Explicit cookies must be denied") } catch {}
        XCTAssertTrue(wire.requests.isEmpty)
        _ = try await service.titles()
        XCTAssertEqual(wire.requests.count, 1); XCTAssertFalse(try XCTUnwrap(wire.requests.first).httpShouldHandleCookies)
    }
}
