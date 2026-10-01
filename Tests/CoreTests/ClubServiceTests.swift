import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

/// In-memory transport only; no socket, URLSession or live server.
private final class ClubFixtureTransport: HTTPTransport {
    var json = #"{"code":200,"data":[]}"#
    var status = 200
    var failure: Error?
    private(set) var requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        if let failure { throw failure }
        return (Data(json.utf8), status)
    }
}

final class ClubServiceTests: XCTestCase {
    private func service(_ transport: ClubFixtureTransport) throws -> ClubService {
        try ClubService(configuration: APIConfiguration(baseURL: URL(string: "https://example.com/fixture/")!), transport: transport)
    }
    private func club(_ json: String = #"{"id":7,"isJoined":true}"#) throws -> ClubRecord {
        try JSONDecoder().decode(ClubRecord.self, from: Data(json.utf8))
    }
    private func assertRequest(_ request: URLRequest, path: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(request.url?.absoluteString, "https://example.com/fixture/" + path, file: file, line: line)
        XCTAssertEqual(request.httpMethod, "POST", file: file, line: line)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "fixture-token", file: file, line: line)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json", file: file, line: line)
        XCTAssertEqual(request.timeoutInterval, 20, file: file, line: line)
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData, file: file, line: line)
        XCTAssertNil(request.url?.query, file: file, line: line)
    }
    func testHomeUsesJSONAndKeepsTheFourSourceSections() async throws {
        let t = ClubFixtureTransport()
        t.json = #"{"code":200,"data":{"owned":[{"id":7,"isOwner":true}],"joined":[],"nearby":[{"id":8}],"events":[{"id":9,"clubId":7,"title":"Fixture"}]}}"#
        let home = try await service(t).home(token: "fixture-token")
        XCTAssertEqual(home.owned.first?.id, 7); XCTAssertEqual(home.nearby.first?.id, 8); XCTAssertEqual(home.events.first?.id, 9)
        let request = try XCTUnwrap(t.requests.first)
        assertRequest(request, path: "api/club/home")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.httpBody, Data("{}".utf8))
    }
    func testMyUsesOwnedOnlyNotJoinedAndDoesNotPromoteRole() async throws {
        let t = ClubFixtureTransport()
        t.json = #"{"code":200,"data":{"owned":[{"id":7}],"joined":[{"id":8}]}}"#
        let rows = try await service(t).owned(token: "fixture-token")
        XCTAssertEqual(rows.map(\.id), [7]); XCTAssertFalse(rows[0].isOwner)
        assertRequest(t.requests[0], path: "api/club/my")
        XCTAssertEqual(t.requests[0].httpBody, Data("{}".utf8))
        XCTAssertEqual(t.requests[0].value(forHTTPHeaderField: "Content-Type"), "application/json")
    }
    func testDirectoryUsesEmptyMultipartAndBareArray() async throws {
        let t = ClubFixtureTransport()
        t.json = #"{"code":200,"data":[{"id":7,"name":"Fixture"}]}"#
        let rows = try await service(t).directory(token: "fixture-token")
        XCTAssertEqual(rows.map(\.id), [7])
        let request = t.requests[0]
        assertRequest(request, path: "api/club/list")
        XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
        let body = String(data: try XCTUnwrap(request.httpBody), encoding: .utf8) ?? ""
        XCTAssertFalse(body.contains("name=\"")); XCTAssertFalse(body.contains("pageNum"))
    }
    func testSearchUsesJSONNameWithoutInventedPaginationOrScope() async throws {
        let t = ClubFixtureTransport()
        _ = try await service(t).directory(name: "  城市 Walk & Run  ", token: "fixture-token")
        let request = t.requests[0]
        assertRequest(request, path: "api/club/list")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: String])
        XCTAssertEqual(fields, ["name": "  城市 Walk & Run  "])
    }
    func testBlankSearchReturnsSourceUnfilteredMultipart() async throws {
        let t = ClubFixtureTransport()
        _ = try await service(t).directory(name: " \n ", token: "fixture-token")
        XCTAssertTrue(t.requests[0].value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data") == true)
    }
    func testDetailUsesIdFormAndMembersUsesClubIdForm() async throws {
        let t = ClubFixtureTransport(), s = try service(t)
        t.json = #"{"code":200,"data":{"id":7,"isJoined":true}}"#
        let detail = try await s.detail(id: 7, token: "fixture-token")
        assertRequest(t.requests[0], path: "api/club/detail")
        let detailBody = String(data: try XCTUnwrap(t.requests[0].httpBody), encoding: .utf8) ?? ""
        XCTAssertTrue(detailBody.contains("name=\"id\"\r\n\r\n7\r\n")); XCTAssertFalse(detailBody.contains("clubId"))
        t.json = #"{"code":200,"data":[{"memberId":31,"role":1,"isOwner":false}]}"#
        let members = try await s.members(in: detail, token: "fixture-token")
        XCTAssertEqual(members.first?.memberId, 31)
        assertRequest(t.requests[1], path: "api/club/members")
        let memberBody = String(data: try XCTUnwrap(t.requests[1].httpBody), encoding: .utf8) ?? ""
        XCTAssertTrue(memberBody.contains("name=\"clubId\"\r\n\r\n7\r\n")); XCTAssertFalse(memberBody.contains("name=\"id\""))
    }
    func testMemberGateCannotUseViewerAdminInsteadOfMembership() async throws {
        let t = ClubFixtureTransport()
        do {
            _ = try await service(t).members(in: club(#"{"id":7,"viewerIsAdmin":true}"#), token: "fixture-token")
            XCTFail()
        } catch { XCTAssertEqual(error as? ClubReadFailure, .membershipRequired) }
        XCTAssertTrue(t.requests.isEmpty)
    }
    func testDetailIdentityMismatchIsNotDisplayed() async throws {
        let t = ClubFixtureTransport(); t.json = #"{"code":200,"data":{"id":8}}"#
        do { _ = try await service(t).detail(id: 7); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
    }
    func testMalformedAndRowsWrappedDirectoryCannotPretendToBeEmpty() async throws {
        for json in ["not json", "{}", #"{"code":200}"#, #"{"code":200,"data":null}"#, #"{"code":200,"data":{"rows":[]}}"#, #"{"code":200,"data":[true]}"#] {
            let t = ClubFixtureTransport(); t.json = json
            do { _ = try await service(t).directory(); XCTFail(json) }
            catch { XCTAssertEqual(error as? APIError, .malformedResponse, json) }
        }
    }
    func testActualEmptyArrayIsSuccessfulEmptyDirectory() async throws {
        let t = ClubFixtureTransport()
        let rows = try await service(t).directory()
        XCTAssertTrue(rows.isEmpty)
    }
    func testAuthAndForbiddenHavePriorityOverMalformedPayloadAndMessage() async throws {
        let cases: [(Int, String, ClubReadFailure)] = [
            (401, "bad json", .unauthorized(message: nil)),
            (403, "bad json", .forbidden(message: nil)),
            (403, #"{"msg":"HTTP-only denial"}"#, .forbidden(message: "HTTP-only denial")),
            (200, #"{"code":401,"msg":{},"data":true}"#, .unauthorized(message: nil)),
            (200, #"{"code":403,"msg":"Server denial","data":true}"#, .forbidden(message: "Server denial"))
        ]
        for (status, json, expected) in cases {
            let t = ClubFixtureTransport(); t.status = status; t.json = json
            do { _ = try await service(t).directory(); XCTFail() }
            catch { XCTAssertEqual(error as? ClubReadFailure, expected) }
            XCTAssertEqual(t.requests.count, 1)
        }
    }
    func testBusinessAndHTTPFailurePreserveVerbatimMessage() async throws {
        let t = ClubFixtureTransport(); t.json = #"{"code":409,"msg":"  Source decision  "}"#
        do { _ = try await service(t).directory(); XCTFail() }
        catch { XCTAssertEqual(error as? ClubReadFailure, .rejected(code: 409, message: "  Source decision  ")) }
        t.status = 503
        do { _ = try await service(t).directory(); XCTFail() }
        catch { XCTAssertEqual(error as? ClubReadFailure, .httpStatus(503, message: "  Source decision  ")) }
    }
    func testInvalidTokenAndIDNeverReachTransport() async throws {
        let t = ClubFixtureTransport(), s = try service(t)
        for token in ["", " ", "bad\r\nheader", "bad\tvalue"] {
            do { _ = try await s.owned(token: token); XCTFail() }
            catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        }
        for id in [0, -1] {
            do { _ = try await s.detail(id: id); XCTFail() }
            catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        }
        XCTAssertTrue(t.requests.isEmpty)
    }
    func testGuestDirectoryDoesNotInventAuthorizationHeader() async throws {
        let t = ClubFixtureTransport()
        _ = try await service(t).directory()
        XCTAssertNil(t.requests[0].value(forHTTPHeaderField: "Authorization"))
    }
    func testTransportFailureIsNotRetriedOrConvertedToEmpty() async throws {
        let t = ClubFixtureTransport(); t.failure = URLError(.notConnectedToInternet)
        do { _ = try await service(t).directory(); XCTFail() }
        catch { XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet) }
        XCTAssertEqual(t.requests.count, 1)
    }
}
