import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class RoamFixtureTransport: HTTPTransport {
    var response: String
    var status: Int
    private(set) var requests: [URLRequest] = []
    init(_ response: String = #"{"code":200,"data":[]}"#, status: Int = 200) { self.response = response; self.status = status }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); return (Data(response.utf8), status)
    }
}
final class RoamServiceTests: XCTestCase {
    private let area = RoamSearchArea(coordinate: RoamCoordinate(latitude: 1.25, longitude: 2.5)!, label: "Explicit synthetic test area")
    private func service(_ transport: RoamFixtureTransport) throws -> RoamService {
        try RoamService(configuration: APIConfiguration(baseURL: URL(string: "https://example.com/fixture/")!), transport: transport)
    }
    private func fields(_ request: URLRequest) -> [String: String] {
        Dictionary(uniqueKeysWithValues: (URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }
    private func body(_ request: URLRequest) -> String { String(data: request.httpBody ?? Data(), encoding: .utf8) ?? "" }
    func testPoisUseGETWithExactQueryRawAuthAndNoBody() async throws {
        let transport = RoamFixtureTransport(#"{"code":200,"data":[{"id":1,"name":"Place","lat":"1","lng":"2"},null,"skip"]}"#)
        let rows = try await service(transport).places(area: area, token: "fixture-token")
        XCTAssertEqual(rows.count, 1)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "GET"); XCTAssertEqual(request.url?.path, "/fixture/api/roam/pois")
        XCTAssertEqual(fields(request), ["lat": "1.25", "lng": "2.5", "radius": "3000"])
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "fixture-token")
        XCTAssertNil(request.httpBody)
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
    }
    func testMapNearbyUsesPOSTMultipartAndLongCoordinateFieldNames() async throws {
        let transport = RoamFixtureTransport()
        _ = try await service(transport).routeNodes(area: area, token: "fixture-token")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "POST"); XCTAssertEqual(request.url?.path, "/fixture/api/map/nearby")
        XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
        let value = body(request)
        for (key, content) in ["latitude": "1.25", "longitude": "2.5", "radius": "2000", "limit": "50"] {
            XCTAssertTrue(value.contains("name=\"\(key)\"\r\n\r\n\(content)\r\n"))
        }
        XCTAssertFalse(value.contains("name=\"lat\"")); XCTAssertNil(request.url?.query)
    }
    func testPlayersUseReadOnlyPOSTAndNormalizeInvalidRows() async throws {
        let transport = RoamFixtureTransport(#"{"code":200,"data":[{"memberId":1,"lat":1,"lng":2},{"memberId":2},null,{"memberId":0,"lat":1,"lng":2}]}"#)
        let result = try await service(transport).players(area: area, radiusM: 1000, token: "fixture-token")
        XCTAssertEqual(result.map(\.id), [1])
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/fixture/api/roam/nearby-runners"); XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertTrue(body(request).contains("name=\"lat\"\r\n\r\n1.25\r\n"))
        XCTAssertTrue(body(request).contains("name=\"radius\"\r\n\r\n1000\r\n"))
        XCTAssertFalse(body(request).contains("sessionId")); XCTAssertFalse(body(request).contains("explorePct"))
    }
    func testEventsNullDataIsEmptyAndDoesNotCallRetiredWrite() async throws {
        let transport = RoamFixtureTransport(#"{"code":200,"data":null}"#)
        let result = try await service(transport).events(area: area, token: "fixture-token")
        XCTAssertTrue(result.items.isEmpty)
        XCTAssertEqual(transport.requests.first?.httpMethod, "GET")
        XCTAssertEqual(transport.requests.first?.url?.path, "/fixture/api/roam/hangout/nearby")
    }
    func testSuccessNullIsNormalForExploreDayAndArrays() async throws {
        let transport = RoamFixtureTransport(#"{"code":200,"data":null}"#)
        let api = try service(transport)
        let day = try await api.exploreDay(area: area, token: "fixture-token")
        XCTAssertNil(day)
        XCTAssertEqual(fields(try XCTUnwrap(transport.requests.last)), ["lat": "1.25", "lng": "2.5"])
        let places = try await api.places(area: area, token: "fixture-token")
        let players = try await api.players(area: area, token: "fixture-token")
        let routes = try await api.routeNodes(area: area, token: "fixture-token")
        XCTAssertTrue(places.isEmpty); XCTAssertTrue(players.isEmpty); XCTAssertTrue(routes.isEmpty)
    }
    func testGatewayAndEnvelopeUnauthorizedWinBeforeMalformedPayload() async throws {
        for (status, response) in [(401, "<html>unauthorized</html>"), (200, #"{"code":401,"msg":{},"data":"wrong"}"#)] {
            let transport = RoamFixtureTransport(response, status: status)
            do { _ = try await service(transport).nodeDetail(id: 1, token: "fixture-token"); XCTFail() }
            catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        }
    }
    func testGatewayFailureCannotBeMaskedBySuccessEnvelope() async throws {
        let transport = RoamFixtureTransport(#"{"code":200,"data":[]}"#, status: 503)
        do { _ = try await service(transport).places(area: area, token: "fixture-token"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .httpStatus(503)) }
    }
    func testBusinessFailureCannotBecomeEmptySuccess() async throws {
        let transport = RoamFixtureTransport(#"{"code":403,"data":[]}"#)
        do { _ = try await service(transport).routeNodes(area: area, token: "fixture-token"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .businessCode(403)) }
    }
    func testNodeNotFoundBusinessStateAndMismatchedIdentity() async throws {
        let transport = RoamFixtureTransport(#"{"code":500,"msg":"节点不存在","data":{}}"#)
        do { _ = try await service(transport).nodeDetail(id: 1, token: "fixture-token"); XCTFail() }
        catch { XCTAssertEqual(error as? RoamReadFailure, .nodeNotFound) }
        transport.response = #"{"code":200,"data":{"poiId":2,"status":1}}"#
        do { _ = try await service(transport).nodeDetail(id: 1, token: "fixture-token"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        transport.response = #"{"code":200,"data":null}"#
        do { _ = try await service(transport).nodeDetail(id: 1, token: "fixture-token"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
    }
    func testMerchantUsesJSONPublicReadWithTopLevelFeaturedAndOptionalAuth() async throws {
        let transport = RoamFixtureTransport(#"{"code":200,"data":{"id":8},"featured":{"name":"Sample","featuredType":1,"featuredId":9}}"#)
        let result = try await service(transport).merchantDetail(id: 8)
        XCTAssertEqual(result.featured?.name, "Sample")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "POST"); XCTAssertEqual(request.url?.path, "/fixture/api/merchant/public-detail")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Int], ["id": 8])
    }
    func testInvalidInputsNeverReachTransport() async throws {
        let transport = RoamFixtureTransport()
        let api = try service(transport)
        for radius in [0, -1, 20001] {
            do { _ = try await api.places(area: area, radiusM: radius, token: "fixture-token"); XCTFail() }
            catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        }
        do { _ = try await api.nodeDetail(id: 0, token: "fixture-token"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        do { _ = try await api.players(area: area, token: "invalid\r\nheader"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testMissingOrMalformedEnvelopeIsAnErrorNotAnEmptyMap() async throws {
        for response in ["{}", #"{"code":"200","data":[]}"#, #"{"code":200,"data":{}}"#, "<html>unavailable</html>"] {
            let transport = RoamFixtureTransport(response)
            do { _ = try await service(transport).places(area: area, token: "fixture-token"); XCTFail(response) }
            catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        }
    }
}

/// Exact real builder/parser round trip, including Swift's single-Character CRLF.
final class ManualMapMultipartRoundTripTests: XCTestCase {
    private let base = URL(string: "https://example.test/native")!
    private let area = RoamSearchArea(coordinate: RoamCoordinate(latitude: 31.2, longitude: 121.5)!, label: "Manual")
    private func request(radius: String = "2000.0", limit: String = "50") throws -> URLRequest {
        try AuthRequestBuilder.makeFormRequest(url: base.appendingPathComponent("api/map/nearby"),
            fields: ["latitude": "31.2", "longitude": "121.5", "radius": radius, "limit": limit],
            token: "synthetic-7", boundary: "map-test")
    }
    func testBuilderMultipartPreservesEveryValueCharacterForBothReaderRadii() throws {
        XCTAssertEqual("\r\n".count, 1)
        for radius in ["1", "2000", "2000.0", "20000"] {
            for limit in ["1", "50", "100"] {
                XCTAssertEqual(ManualMapReadRoute(request: try request(radius: radius, limit: limit), baseURL: base, area: area), .nearby)
            }
        }
    }
    func testMalformedMultipartAndUnreviewedFieldsRemainRejected() throws {
        let original = try request()
        let body = try XCTUnwrap(String(data: try XCTUnwrap(original.httpBody), encoding: .utf8))
        for invalid in [
            body.replacingOccurrences(of: "\r\n", with: "\n"),
            body.replacingOccurrences(of: "50\r\n", with: "5\r\n0\r\n"),
            body.replacingOccurrences(of: "name=\"limit\"", with: "name=\"latitude\""),
            body.replacingOccurrences(of: "name=\"limit\"", with: "name=\"status\""),
            body.replacingOccurrences(of: "--map-test--\r\n", with: "--map-test--"),
            body + "trailing"
        ] {
            var modified = original; modified.httpBody = Data(invalid.utf8)
            XCTAssertNil(ManualMapReadRoute(request: modified, baseURL: base, area: area))
        }
        for radius in ["0", "20001", "2000.5", "02000", "NaN"] {
            XCTAssertNil(ManualMapReadRoute(request: try request(radius: radius), baseURL: base, area: area))
        }
    }
}
