import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

final class MessagingServiceTests: XCTestCase {
    private func service(_ transport: MessagingTestTransport) throws -> MessagingService {
        MessagingService(configuration: try APIConfiguration(baseURL: URL(string: "https://example.com/fixture/")!), transport: transport)
    }
    func testConversationsUseEmptyMultipartPOSTAndRawAuthorizationOnly() async throws {
        let transport = MessagingTestTransport([.json(#"{"code":200,"data":[{"conversationId":19},{"conversationId":2}]}"#)])
        let rows = try await service(transport).conversations(token: "synthetic-token")
        XCTAssertEqual(rows.map(\.id), [19, 2])
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/fixture/api/im/conversations")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertNil(request.url?.query)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
        let body = try XCTUnwrap(String(data: try XCTUnwrap(request.httpBody), encoding: .utf8))
        XCTAssertFalse(body.contains("Content-Disposition"))
        XCTAssertTrue(body.hasSuffix("--\r\n"))
        XCTAssertEqual(transport.requests.count, 1)
    }
    func testHistoryUsesExactMultipartFieldNamesAndNeverMarksRead() async throws {
        let transport = MessagingTestTransport([
            .json(#"{"code":200,"data":{"list":[{"id":10,"conversationId":9}],"nextCursor":42,"hasMore":true}}"#),
            .json(#"{"code":200,"data":{"list":[{"id":1,"conversationId":9}],"hasMore":false}}"#)
        ])
        let api = try service(transport)
        let latest = try await api.messages(conversationID: 9, token: "synthetic-token")
        _ = try await api.messages(conversationID: 9, cursor: try XCTUnwrap(latest.nextCursor), token: "synthetic-token")
        XCTAssertEqual(transport.requests.count, 2)
        for (index, request) in transport.requests.enumerated() {
            XCTAssertEqual(request.url?.path, "/fixture/api/im/messages")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-token")
            let body = try XCTUnwrap(String(data: try XCTUnwrap(request.httpBody), encoding: .utf8))
            XCTAssertTrue(body.contains("name=\"conversation_id\"\r\n\r\n9\r\n"))
            XCTAssertTrue(body.contains("name=\"cursor_id\"\r\n\r\n\(index == 0 ? 0 : 42)\r\n"))
            XCTAssertTrue(body.contains("name=\"size\"\r\n\r\n30\r\n"))
            XCTAssertEqual(body.components(separatedBy: "Content-Disposition").count - 1, 3)
            XCTAssertFalse(body.contains("member"))
        }
    }
    func testDifferentSourceSizeCanBeInjectedWithoutInventedServerLimit() async throws {
        let transport = MessagingTestTransport([.json(#"{"code":200,"data":{"list":[],"hasMore":false}}"#)])
        _ = try await service(transport).messages(conversationID: 9, size: 15, token: "synthetic-token")
        let body = try XCTUnwrap(String(data: try XCTUnwrap(transport.requests.first?.httpBody), encoding: .utf8))
        XCTAssertTrue(body.contains("name=\"size\"\r\n\r\n15\r\n"))
    }
    func testInvalidRequestAndTokenNeverHitTransport() async throws {
        let transport = MessagingTestTransport([])
        let api = try service(transport)
        for (id, cursor, size) in [(0, 0, 30), (9, -1, 30), (9, 0, 0)] {
            do { _ = try await api.messages(conversationID: id, cursor: cursor, size: size, token: "synthetic-token"); XCTFail() }
            catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        }
        for token in ["", "bad\r\nheader", "  "] {
            do { _ = try await api.conversations(token: token); XCTFail() }
            catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testNoInventedAlternativeListEnvelopeOrMalformedSuccessFallback() async throws {
        for json in [#"{"code":200}"#, #"{"code":200,"data":null}"#, #"{"code":200,"data":{"list":[]}}"#, #"{"code":200,"data":{"rows":[]}}"#, #"{"code":200,"data":[{"conversationId":1},{"conversationId":1}]}"#, #"{"code":"200","data":[]}"#] {
            let transport = MessagingTestTransport([.json(json)])
            do { _ = try await service(transport).conversations(token: "synthetic-token"); XCTFail(json) }
            catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        }
    }
    func testHistoryRejectsWrongConversationAndMissingPagingContract() async throws {
        for json in [#"{"code":200,"data":{"list":[{"id":1,"conversationId":8}],"hasMore":false}}"#, #"{"code":200,"data":{}}"#, #"{"code":200,"data":{"list":[],"hasMore":true}}"#] {
            let transport = MessagingTestTransport([.json(json)])
            do { _ = try await service(transport).messages(conversationID: 9, token: "synthetic-token"); XCTFail(json) }
            catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        }
    }
    func testClosedUsesExactErrorCodeNotMessageTextOrHTTPAlone() async throws {
        let transport = MessagingTestTransport([
            .json(#"{"code":409,"errorCode":" HANGOUT_CLOSED ","msg":"Server wording"}"#),
            .json(#"{"code":500,"msg":"HANGOUT_CLOSED"}"#),
            .json(#"{"code":409,"errorCode":"OTHER","msg":"Closed"}"#, status: 409)
        ])
        let api = try service(transport)
        do { _ = try await api.messages(conversationID: 9, token: "synthetic-token"); XCTFail() }
        catch let failure as MessagingReadFailure {
            XCTAssertTrue(failure.isClosed)
            XCTAssertEqual(failure.message, "Server wording")
            XCTAssertEqual(failure.code, 409)
        }
        for _ in 0..<2 {
            do { _ = try await api.messages(conversationID: 9, token: "synthetic-token"); XCTFail() }
            catch let failure as MessagingReadFailure { XCTAssertFalse(failure.isClosed) }
        }
    }
    func testUnauthorizedBusinessAndHTTPAreBothRecognized() async throws {
        for status in [200, 401] {
            let transport = MessagingTestTransport([.json(#"{"code":401,"msg":"Synthetic sign-in required"}"#, status: status)])
            do { _ = try await service(transport).conversations(token: "synthetic-token"); XCTFail() }
            catch let failure as MessagingReadFailure {
                XCTAssertTrue(failure.isUnauthorized)
                XCTAssertEqual(failure.httpStatus, status == 401 ? 401 : nil)
            }
        }
    }
    func testRedirectAndNonJSONHTTPFailureDoNotDecodeAsEmptySuccess() async throws {
        for status in [302, 403, 503] {
            let transport = MessagingTestTransport([.json("not JSON", status: status)])
            do { _ = try await service(transport).conversations(token: "synthetic-token"); XCTFail() }
            catch let failure as MessagingReadFailure {
                XCTAssertEqual(failure.httpStatus, status)
                XCTAssertNil(failure.message)
            }
            XCTAssertEqual(transport.requests.count, 1)
        }
    }
}

struct MessagingTestReply {
    let data: Data
    let status: Int
    static func json(_ value: String, status: Int = 200) -> Self { Self(data: Data(value.utf8), status: status) }
}
final class MessagingTestTransport: HTTPTransport {
    private(set) var requests: [URLRequest] = []
    private var replies: [MessagingTestReply]
    init(_ replies: [MessagingTestReply]) { self.replies = replies }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        guard !replies.isEmpty else { throw APIError.malformedResponse }
        let result = replies.removeFirst()
        return (result.data, result.status)
    }
}
