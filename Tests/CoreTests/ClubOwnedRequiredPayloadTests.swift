import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

final class ClubOwnedRequiredPayloadTests: XCTestCase {
    private func service(_ transport: OwnedPayloadTransport) throws -> ClubService {
        try ClubService(configuration: APIConfiguration(baseURL: URL(string: "https://example.com/fixture/")!), transport: transport)
    }
    func testMissingNullAndWrongShapeAreNotEmptySuccess() async throws {
        for data in ["{}", "{\"owned\":null}", "{\"owned\":{}}", "{\"owned\":false}"] {
            let transport = OwnedPayloadTransport(json: "{\"code\":200,\"data\":\(data)}")
            do { _ = try await service(transport).owned(token: "fixture-token"); XCTFail("Unknown payload must not become empty") }
            catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
            XCTAssertEqual(transport.requests.count, 1)
        }
    }
    func testExplicitEmptyAndNonemptyListsPreserveOriginalContract() async throws {
        let empty = OwnedPayloadTransport(json: #"{"code":200,"data":{"owned":[]}}"#)
        let emptyRows = try await service(empty).owned(token: "fixture-token")
        XCTAssertTrue(emptyRows.isEmpty)
        let full = OwnedPayloadTransport(json: #"{"code":200,"data":{"owned":[{"id":7,"isOwner":true}],"joined":[{"id":8}]}}"#)
        let rows = try await service(full).owned(token: "fixture-token")
        XCTAssertEqual(rows.map(\.id), [7])
        XCTAssertEqual(full.requests.first?.url?.path, "/fixture/api/club/my")
        XCTAssertEqual(full.requests.first?.httpMethod, "POST")
        XCTAssertEqual(full.requests.first?.value(forHTTPHeaderField: "Authorization"), "fixture-token")
    }
    func testAuthorityAndServiceErrorsPrecedePayloadDecoding() async throws {
        let cases: [(Int, Int, ClubReadFailure)] = [
            (401, 200, .unauthorized(message: nil)), (403, 200, .forbidden(message: nil)),
            (503, 200, .httpStatus(503, message: nil)),
            (200, 401, .unauthorized(message: nil)), (200, 403, .forbidden(message: nil)),
            (200, 503, .rejected(code: 503, message: nil))
        ]
        for (status, code, expected) in cases {
            let transport = OwnedPayloadTransport(json: "{\"code\":\(code),\"data\":{}}", status: status)
            do { _ = try await service(transport).owned(token: "fixture-token"); XCTFail("Expected original failure") }
            catch { XCTAssertEqual(error as? ClubReadFailure, expected) }
            XCTAssertEqual(transport.requests.count, 1)
        }
    }
}

private final class OwnedPayloadTransport: HTTPTransport {
    let json: String
    let status: Int
    private(set) var requests: [URLRequest] = []
    init(json: String, status: Int = 200) { self.json = json; self.status = status }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        return (Data(json.utf8), status)
    }
}
