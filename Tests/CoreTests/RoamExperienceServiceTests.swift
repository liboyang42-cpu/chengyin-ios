import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class RoamExperienceTestTransport: HTTPTransport {
    var response: String
    var status = 200
    var requests: [URLRequest] = []
    init(_ response: String) { self.response = response }
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return (Data(response.utf8), status) }
}
final class RoamExperienceServiceTests: XCTestCase {
    private func service(_ transport: RoamExperienceTestTransport) throws -> RoamExperienceService {
        try RoamExperienceService(configuration: APIConfiguration(baseURL: URL(string: "https://example.com/fixture/")!), transport: transport)
    }
    private func wrapped(_ json: String) -> String { "{\"code\":200,\"data\":\(json)}" }
    func testRecoveryGETUsesExactExclusiveQueryAndRawAuthorization() async throws {
        let transport = RoamExperienceTestTransport(wrapped(RoamExperienceSyntheticFixtures.settled))
        let fact = try await service(transport).sessionFact(.sessionID(901), token: "fixture-token")
        XCTAssertTrue(fact.hasCompleteSettlement)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "GET"); XCTAssertEqual(request.url?.path, "/fixture/api/roam/session")
        XCTAssertEqual(request.url?.query, "sessionId=901")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "fixture-token")
        XCTAssertNil(request.httpBody); XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
    }
    func testRecoveryKeyIsEncodedAndWrongResponseIdentityRejected() async throws {
        let transport = RoamExperienceTestTransport(wrapped(RoamExperienceSyntheticFixtures.settled))
        do { _ = try await service(transport).sessionFact(.clientSessionKey("other & key"), token: "fixture-token"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        let query = URLComponents(url: try XCTUnwrap(transport.requests.first?.url), resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(query, [URLQueryItem(name: "clientSessionKey", value: "other & key")])
    }
    func testAlbumPOSTIsMultipartReadWithExactPagination() async throws {
        let transport = RoamExperienceTestTransport(wrapped(RoamExperienceSyntheticFixtures.album))
        let page = try await service(transport).album(token: "fixture-token")
        XCTAssertEqual(page.list.count, 3)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "POST"); XCTAssertEqual(request.url?.path, "/fixture/api/roam/stamp/list")
        XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data") == true)
        let body = String(data: try XCTUnwrap(request.httpBody), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("name=\"pageNum\"\r\n\r\n1\r\n"))
        XCTAssertTrue(body.contains("name=\"pageSize\"\r\n\r\n20\r\n"))
        XCTAssertFalse(body.contains("picUrl")); XCTAssertFalse(body.contains("idempotencyKey"))
    }
    func testAlbumWrongReturnedPageCannotAdvance() async throws {
        let transport = RoamExperienceTestTransport(wrapped(RoamExperienceSyntheticFixtures.album))
        do { _ = try await service(transport).album(page: 2, token: "fixture-token"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
    }
    func testTilePageRejectsNonAdvancingCursor() async throws {
        let transport = RoamExperienceTestTransport(#"{"code":200,"data":{"tiles":["s000000"],"nextAfterId":7,"hasMore":true}}"#)
        do { _ = try await service(transport).tilePage(afterID: 7, token: "fixture-token"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        XCTAssertEqual(transport.requests.first?.url?.query, "afterId=7&limit=1000")
    }
    func testHistoricalTileVariantsAndNullBadge() async throws {
        let transport = RoamExperienceTestTransport(#"{"code":200,"data":["s000000",{"tileKey":"s000001"},{"key":"s000002"},{"tile":"s000003"}]}"#)
        let values = try await service(transport).historicalTiles(limit: 20, token: "fixture-token")
        XCTAssertEqual(values.count, 4); XCTAssertEqual(transport.requests.first?.url?.query, "limit=20")
        transport.response = #"{"code":200,"data":null}"#
        let badge = try await service(transport).shopBadge(token: "fixture-token")
        XCTAssertNil(badge)
    }
    func testInvalidInputsSendNoRequest() async throws {
        let transport = RoamExperienceTestTransport("{}")
        let reader = try service(transport)
        do { _ = try await reader.sessionFact(.sessionID(0), token: "fixture-token"); XCTFail() } catch { }
        do { _ = try await reader.album(page: 0, token: "fixture-token"); XCTFail() } catch { }
        do { _ = try await reader.tilePage(limit: 2001, token: "fixture-token"); XCTFail() } catch { }
        do { _ = try await reader.shopBadge(token: "bad\nheader"); XCTFail() } catch { }
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testUnauthorizedAndHTTPFailureCannotBecomeEmptyData() async throws {
        let transport = RoamExperienceTestTransport("not JSON")
        transport.status = 401
        do { _ = try await service(transport).shopBadge(token: "fixture-token"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        transport.status = 503; transport.response = #"{"code":200,"data":null}"#
        do { _ = try await service(transport).shopBadge(token: "fixture-token"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .httpStatus(503)) }
        transport.status = 200; transport.response = #"{"code":401,"data":{}}"#
        do { _ = try await service(transport).shopBadge(token: "fixture-token"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .unauthorized) }
    }
}
