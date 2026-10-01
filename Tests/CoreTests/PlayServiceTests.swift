import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

final class PlayServiceTests: XCTestCase {
    private func service(_ transport: any HTTPTransport) throws -> PlayService {
        PlayService(configuration: try APIConfiguration(baseURL: URL(string: "https://example.com/fixture/")!), transport: transport)
    }
    func testNodesGetUsesExactlyOneSourceSessionQueryAndRawAuthorization() async throws {
        for scope in [PlaySessionScope.activity(41), .topic(71)] {
            let transport = PlayRecordingTransport(body: PlayTestData.envelope)
            let data = try await service(transport).nodes(scope: scope, token: "synthetic-token")
            XCTAssertEqual(data.topicID, 71)
            let request = try XCTUnwrap(transport.requests.first)
            XCTAssertEqual(request.httpMethod, "GET"); XCTAssertEqual(request.url?.path, "/fixture/api/play/nodes")
            let items = try XCTUnwrap(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems)
            XCTAssertEqual(Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") }), scope.fields)
            XCTAssertNil(request.httpBody)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-token")
            XCTAssertEqual(transport.requests.count, 1)
        }
    }
    func testRouteStateGetHasSameSessionScopeAndRejectsInvalidIDBeforeNetwork() async throws {
        let transport = PlayRecordingTransport(body: #"{"code":"200","data":{"routeMode":"LINEAR","version":0,"status":"ACTIVE"}}"#)
        _ = try await service(transport).routeState(scope: .topic(71), token: "synthetic-token")
        XCTAssertEqual(transport.requests.first?.url?.path, "/fixture/api/play/route-state")
        XCTAssertEqual(transport.requests.first?.url?.query, "topicId=71")
        do { _ = try await service(transport).nodes(scope: .activity(0), token: "synthetic-token"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        XCTAssertEqual(transport.requests.count, 1)
    }
    func testMultipartAnswerPreservesExactUserTextAndNoOtherProofOrOutcomeFields() async throws {
        let transport = PlayRecordingTransport(body: PlayTestData.receipt)
        let snapshot = try PlayTestData.snapshot()
        let text = "A & + = 中文\nsecond line"
        _ = try await service(transport).answer(snapshot: snapshot, nodeID: 7, answer: text, token: "synthetic-token")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/fixture/api/play/answer"); XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertNil(request.url?.query)
        let contentType = try XCTUnwrap(request.value(forHTTPHeaderField: "Content-Type"))
        XCTAssertTrue(contentType.hasPrefix("multipart/form-data; boundary="))
        let boundary = String(contentType.dropFirst("multipart/form-data; boundary=".count))
        let body = try XCTUnwrap(String(data: request.httpBody ?? Data(), encoding: .utf8))
        XCTAssertTrue(body.contains("name=\"activityId\"\r\n\r\n41\r\n"))
        XCTAssertTrue(body.contains("name=\"nodeId\"\r\n\r\n7\r\n"))
        XCTAssertTrue(body.contains("name=\"answer\"\r\n\r\n\(text)\r\n"))
        XCTAssertTrue(body.hasSuffix("--\(boundary)--\r\n"))
        for forbidden in ["topicId", "latitude", "longitude", "outcomeCode", "targetNodeId", "routeActionId", "expectedRouteVersion", "code\""] {
            XCTAssertFalse(body.contains("name=\"" + forbidden), forbidden)
        }
        XCTAssertEqual(transport.requests.count, 1)
    }
    func testTopicAnswerNeverSendsActivityID() async throws {
        let transport = PlayRecordingTransport(body: PlayTestData.receipt)
        _ = try await service(transport).answer(snapshot: PlayTestData.snapshot(scope: .topic(71)), nodeID: 7, answer: "answer", token: "synthetic-token")
        let body = String(data: transport.requests[0].httpBody!, encoding: .utf8)!
        XCTAssertTrue(body.contains("name=\"topicId\"\r\n\r\n71\r\n"))
        XCTAssertFalse(body.contains("activityId"))
    }
    func testInvalidAnswerAndCredentialNeverReachTransport() async throws {
        let transport = PlayRecordingTransport(body: PlayTestData.receipt)
        for answer in ["", " \n "] {
            do { _ = try await service(transport).answer(snapshot: PlayTestData.snapshot(), nodeID: 7, answer: answer, token: "synthetic-token"); XCTFail() }
            catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        }
        do { _ = try await service(transport).nodes(scope: .activity(41), token: "bad\nheader"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testBusinessCodeStringsPreserveErrorsAndUnknownCodesFailClosed() async throws {
        for code in ["409", "\" 409 \"", "true", "null", "\"broken\""] {
            let transport = PlayRecordingTransport(body: "{\"code\":\(code),\"msg\":\"原始服务端消息\"}")
            do { _ = try await service(transport).nodes(scope: .activity(41), token: "synthetic-token"); XCTFail(code) }
            catch let failure as PlayFailure {
                XCTAssertEqual(failure.message, "原始服务端消息")
                XCTAssertEqual(failure.code, code.contains("409") ? 409 : nil)
            }
            XCTAssertEqual(transport.requests.count, 1)
        }
    }
    func testHTTP402IsNotMissingPassAndRedirectNeverDecodesSuccess() async throws {
        for status in [200, 402, 302] {
            let transport = PlayRecordingTransport(body: #"{"code":402,"msg":"Server message"}"#, status: status)
            do { _ = try await service(transport).nodes(scope: .activity(41), token: "synthetic-token"); XCTFail() }
            catch let failure as PlayFailure {
                XCTAssertEqual(failure.needsPass, status == 200)
                XCTAssertEqual(failure.httpStatus, status == 200 ? nil : status)
            }
            XCTAssertEqual(transport.requests.count, 1)
        }
    }
    func testMissingDataAndReceiptNodeMismatchAreNotSuccess() async throws {
        let badRead = PlayRecordingTransport(body: #"{"code":200}"#)
        do { _ = try await service(badRead).nodes(scope: .activity(41), token: "synthetic-token"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        let badReceipt = PlayRecordingTransport(body: #"{"code":200,"data":{"nodeId":8}}"#)
        do { _ = try await service(badReceipt).answer(snapshot: PlayTestData.snapshot(), nodeID: 7, answer: "answer", token: "synthetic-token"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
    }
}

final class PlayRecordingTransport: HTTPTransport {
    let body: String
    let status: Int
    private(set) var requests: [URLRequest] = []
    init(body: String, status: Int = 200) { self.body = body; self.status = status }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); return (Data(body.utf8), status)
    }
}

enum PlayTestData {
    static let result = #"{"topicId":71,"topicName":"Synthetic route","mode":1,"playable":true,"total":2,"doneCount":0,"nodes":[{"nodeId":7,"done":false,"validationMethod":1,"question":"Synthetic question"},{"nodeId":8,"done":false,"locked":true}]}"#
    static let envelope = "{\"code\":\"200\",\"data\":\(result)}"
    static let receipt = #"{"code":200,"data":{"nodeId":7,"firstTime":true,"done":1,"total":2,"completed":false}}"#
    static func snapshot(scope: PlaySessionScope = .activity(41)) throws -> PlaySnapshot {
        try PlaySnapshot(scope: scope, result: JSONDecoder().decode(PlayNodesResult.self, from: Data(result.utf8)))
    }
}
