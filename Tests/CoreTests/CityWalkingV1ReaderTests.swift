import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class CityWalkingV1ReaderTests: XCTestCase {
    private let base = URL(string: "https://example.test/native")!
    private func reader(_ wire: Wire, current: @escaping () -> Bool = { true }) throws -> CityWalkingAuthorityReader {
        let session = try PlayExperienceSession(accountID: 17, epoch: 3, namespace: "fixture", token: "not-live")
        return .init(owner: .init(market: .china, baseURL: base, role: "player", session: session), transport: wire, current: current)
    }
    private func response(_ changes: [String: Any] = [:]) throws -> Data {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        var value: [String: Any] = ["schemaVersion": 1, "kind": "cityNode", "id": 7, "title": "原公开地点",
            "longitude": 120.0, "latitude": 30.0, "datum": "wgs84", "region": "CN",
            "authorityRevision": "city:7:original", "issuedAtMs": now, "expiresAtMs": now + 120_000]
        changes.forEach { value[$0.key] = $0.value }
        return try JSONSerialization.data(withJSONObject: value)
    }
    func testOriginalV1ReadPreservesIdentityAndCoordinates() async throws {
        let wire = Wire(); wire.data = try response()
        let value = try await reader(wire).authorize(.init(kind: .cityNode, id: 7))
        XCTAssertEqual(value.reference.id, 7); XCTAssertEqual(value.coordinate.region, "CN")
        XCTAssertEqual(value.coordinate.datum, .wgs84); XCTAssertNil(value.releaseID)
        XCTAssertEqual(wire.requests.count, 1)
        XCTAssertTrue(CityWalkingReadRoute.accepts(try XCTUnwrap(wire.requests.first), baseURL: base))
        XCTAssertEqual(wire.requests.first?.value(forHTTPHeaderField: "Authorization"), "not-live")
    }
    func testStaleIdentityRefusesBeforeTransport() async throws {
        let wire = Wire()
        do { _ = try await reader(wire, current: { false }).authorize(.init(kind: .cityNode, id: 7)); XCTFail() }
        catch { XCTAssertEqual(error as? WalkingNavigationFailure, .staleContext) }
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testLateIdentityChangeRejectsResponse() async throws {
        let wire = Wire(); wire.data = try response(); var active = true
        wire.beforeReturn = { active = false }
        do { _ = try await reader(wire, current: { active }).authorize(.init(kind: .cityNode, id: 7)); XCTFail() }
        catch { XCTAssertEqual(error as? WalkingNavigationFailure, .staleContext) }
        XCTAssertEqual(wire.requests.count, 1)
    }
    func testV2WrongTargetDatumAndExpiredLeaseAreRejected() async throws {
        let invalidValues: [[String: Any]] = [["schemaVersion": 2], ["id": 8], ["datum": "gcj02"],
            ["expiresAtMs": 1], ["authorityRevision": "city:8:other"], ["region": "cn"]]
        for invalid in invalidValues {
            let wire = Wire(); wire.data = try response(invalid)
            do { _ = try await reader(wire).authorize(.init(kind: .cityNode, id: 7)); XCTFail("Invalid declaration accepted") } catch {}
        }
    }
    func testOtherTargetKindsDoNotUseCityEndpoint() async throws {
        let wire = Wire()
        do { _ = try await reader(wire).authorize(.init(kind: .merchant, id: 7)); XCTFail() } catch {}
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testRouteRejectsWritesDuplicateParametersAndOtherOrigin() {
        for suffix in ["?poi_id=7&poi_id=7", "?poi_id=07", "?poi_id=0", "?poi_id=7&member=17"] {
            let request = URLRequest(url: URL(string: base.absoluteString + "/api/city/walking/target" + suffix)!)
            XCTAssertFalse(CityWalkingReadRoute.accepts(request, baseURL: base))
        }
        var request = URLRequest(url: base.appendingPathComponent("api/city/walking/target?poi_id=7"))
        request.httpMethod = "POST"
        XCTAssertFalse(CityWalkingReadRoute.accepts(request, baseURL: base))
        XCTAssertFalse(CityWalkingReadRoute.accepts(URLRequest(url: URL(string: "https://other.test/api/city/walking/target?poi_id=7")!), baseURL: base))
    }
    private final class Wire: HTTPTransport {
        var data = Data(); var requests: [URLRequest] = []; var beforeReturn: (() -> Void)?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request); beforeReturn?(); return (data, 200)
        }
    }
}
