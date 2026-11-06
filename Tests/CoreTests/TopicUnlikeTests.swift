import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private actor UnlikeWire: HTTPTransport {
    enum Reply { case json(String, Int), fail }
    var replies: [Reply]
    private(set) var requests: [URLRequest] = []
    init(_ replies: [Reply]) { self.replies = replies }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        let reply = replies.isEmpty ? .json(#"{"code":200}"#, 200) : replies.removeFirst()
        switch reply {
        case .json(let text, let status): return (Data(text.utf8), status)
        case .fail: throw URLError(.networkConnectionLost)
        }
    }
    func fields(_ index: Int) -> String { String(data: requests[index].httpBody ?? Data(), encoding: .utf8) ?? "" }
}

@MainActor final class TopicUnlikeTests: XCTestCase {
    private let base = URL(string: "https://unlike.example/native")!
    private func make(_ wire: UnlikeWire, approved: Bool = true, market: RegionalMarket = .china,
                      session: @escaping () -> TopicUnlikeSession? = { try? TopicUnlikeSession(accountID: 4, epoch: 1, namespace: "synthetic", market: .china, token: "synthetic-unlike") }) throws -> TopicUnlikeController {
        let configuration = try APIConfiguration(baseURL: base)
        let approvals = approved ? [try TopicUnlikeApproval(endpoint: try OperationEndpointApproval(baseURL: base, namespace: "synthetic", accountID: 4, paths: TopicUnlikeApproval.paths), accountID: 4, expiresAt: Date().addingTimeInterval(600))] : []
        return TopicUnlikeController(configuration: configuration, approvals: approvals, transport: wire, current: session)
    }
    func testNoApprovalMeansNoConfirmationAndNoRequest() async throws {
        let wire = UnlikeWire([])
        let controller = try make(wire, approved: false)
        XCTAssertFalse(controller.isAvailable)
        XCTAssertNil(controller.request(topicID: 9))
        XCTAssertEqual(controller.phase, .idle)
        let count = await wire.requests.count; XCTAssertEqual(count, 0)
    }
    func testConfirmationIsRequiredAndSendsOneTypeZeroRequest() async throws {
        let wire = UnlikeWire([.json(#"{"code":200,"msg":"取消点赞成功"}"#, 200)])
        let controller = try make(wire)
        let id = try XCTUnwrap(controller.request(topicID: 9))
        let none = await wire.requests.count; XCTAssertEqual(none, 0)
        await controller.confirm(UUID())
        let stillNone = await wire.requests.count; XCTAssertEqual(stillNone, 0)
        await controller.confirm(id)
        XCTAssertEqual(controller.phase, .removed(topicID: 9))
        await controller.confirm(id)
        let requests = await wire.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].url, base.appendingPathComponent("api/topic/like"))
        let body = await wire.fields(0)
        XCTAssertTrue(body.contains("name=\"id\"\r\n\r\n9\r\n")); XCTAssertTrue(body.contains("name=\"type\"\r\n\r\n0\r\n"))
    }
    func testCancelSendsNothing() async throws {
        let wire = UnlikeWire([])
        let controller = try make(wire)
        let id = try XCTUnwrap(controller.request(topicID: 3))
        controller.cancel()
        await controller.confirm(id)
        let count = await wire.requests.count; XCTAssertEqual(count, 0)
        XCTAssertEqual(controller.phase, .idle)
    }
    func testBusinessRejectionIsADefiniteFailureWithServerMessage() async throws {
        let controller = try make(UnlikeWire([.json(#"{"code":500,"msg":"参数不合规"}"#, 200)]))
        let id = try XCTUnwrap(controller.request(topicID: 3)); await controller.confirm(id)
        XCTAssertEqual(controller.phase, .failed(topicID: 3, message: "参数不合规"))
        XCTAssertTrue(controller.unresolved.isEmpty)
    }
    func testLostResponseLocksTopicUntilReadbackFindsItGone() async throws {
        let wire = UnlikeWire([.fail, .json(#"{"code":200,"rows":[{"id":4},{"id":5}]}"#, 200)])
        let controller = try make(wire)
        let id = try XCTUnwrap(controller.request(topicID: 3)); await controller.confirm(id)
        XCTAssertEqual(controller.phase, .unknown(topicID: 3)); XCTAssertEqual(controller.unresolved, [3])
        XCTAssertNil(controller.request(topicID: 3), "an unresolved command is never re-sent")
        await controller.checkUnresolved(topicID: 3)
        XCTAssertEqual(controller.phase, .removed(topicID: 3)); XCTAssertTrue(controller.unresolved.isEmpty)
        let requests = await wire.requests
        XCTAssertEqual(requests.map { $0.url?.lastPathComponent }, ["like", "like_list"])
    }
    func testReadbackThatStillFindsTopicAllowsANewConfirmation() async throws {
        let wire = UnlikeWire([.json("<html>", 502), .json(#"{"code":200,"rows":[{"id":3}]}"#, 200)])
        let controller = try make(wire)
        let id = try XCTUnwrap(controller.request(topicID: 3)); await controller.confirm(id)
        XCTAssertEqual(controller.phase, .unknown(topicID: 3))
        await controller.checkUnresolved(topicID: 3)
        XCTAssertEqual(controller.phase, .failed(topicID: 3, message: nil))
        XCTAssertNotNil(controller.request(topicID: 3))
    }
    func testReadbackFailureStaysUnknownAndOutsideChinaIsUnavailable() async throws {
        let controller = try make(UnlikeWire([.fail, .fail]))
        let id = try XCTUnwrap(controller.request(topicID: 3)); await controller.confirm(id)
        await controller.checkUnresolved(topicID: 3)
        XCTAssertEqual(controller.phase, .unknown(topicID: 3))
        let global = try make(UnlikeWire([]), session: { try? TopicUnlikeSession(accountID: 4, epoch: 1, namespace: "synthetic", market: .unitedStates, token: "synthetic-unlike") })
        XCTAssertFalse(global.isAvailable)
    }
}
