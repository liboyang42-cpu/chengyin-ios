import XCTest
@testable import Questify

@MainActor private final class QuestionReuseAppTransport: ShopNPCHTTPTransport {
    var calls = 0
    func perform(_ request: ShopNPCHTTPRequest) async throws -> ShopNPCHTTPResponse {
        calls += 1
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
        let id = try XCTUnwrap(body["requestId"] as? String)
        return .init(status: 200, body: try JSONSerialization.data(withJSONObject: ["code": 200, "data": ["requestId": id,
            "outcomeStatus": "SUCCEEDED", "safetyDecision": "PASS", "retryable": false, "safeText": "Synthetic answer"]]))
    }
}
@MainActor final class ShopNPCQuestionReuseAppTests: XCTestCase {
    private func setup() async throws -> (ShopNPCCoordinator, ShopNPCQuestionReuseModel, QuestionReuseAppTransport, UUID) {
        let scope = ShopNPCScope(sessionID: "synthetic", accountID: "7", roleID: "player", accessRevision: 1, nodeID: ShopNPCNodeID(17)!)
        var grants = ShopNPCGrants(); grants.server = true; grants.provider = true; grants.legal = true; grants.access = true
        let wire = QuestionReuseAppTransport()
        let flow = ShopNPCCoordinator(scope: scope, grants: grants, client: .init(transport: wire))
        try flow.reviewText("Original question"); await flow.transmit(reviewID: try XCTUnwrap(flow.pending).id)
        return (flow, .init(coordinator: flow), wire, try XCTUnwrap(flow.messages.first).id)
    }
    func testEmptyDraftFillsLocallyWithoutAnotherSend() async throws {
        let (flow, model, wire, id) = try await setup(); let before = flow.messages
        XCTAssertEqual(model.select(messageID: id, draft: "", enabled: true), "Original question")
        XCTAssertNil(model.pending); XCTAssertNil(flow.pending); XCTAssertEqual(flow.messages, before); XCTAssertEqual(wire.calls, 1)
    }
    func testNonemptyDraftNeedsConfirmationAndCancelRetiresItsReceipt() async throws {
        let (flow, model, wire, id) = try await setup()
        XCTAssertNil(model.select(messageID: id, draft: "Keep my draft", enabled: true))
        let pending = try XCTUnwrap(model.pending)
        model.cancel(); XCTAssertNil(model.confirm(id: pending.id, draft: "Keep my draft", enabled: true))
        XCTAssertNil(flow.pending); XCTAssertEqual(wire.calls, 1)
    }
    func testConfirmationKeepsNewTypingAndDisabledComposerSafe() async throws {
        let (_, model, wire, id) = try await setup()
        _ = model.select(messageID: id, draft: "Before", enabled: true)
        var pending = try XCTUnwrap(model.pending)
        XCTAssertNil(model.confirm(id: pending.id, draft: "Newer text", enabled: true))
        _ = model.select(messageID: id, draft: "Before", enabled: true); pending = try XCTUnwrap(model.pending)
        XCTAssertNil(model.confirm(id: pending.id, draft: "Before", enabled: false))
        XCTAssertEqual(wire.calls, 1)
    }
    func testConfirmedReuseOnlyReturnsQuestionAndRetiresTheAction() async throws {
        let (flow, model, wire, id) = try await setup()
        _ = model.select(messageID: id, draft: "Before", enabled: true); let pending = try XCTUnwrap(model.pending)
        XCTAssertEqual(model.confirm(id: pending.id, draft: "Before", enabled: true), "Original question")
        XCTAssertNil(model.confirm(id: pending.id, draft: "Before", enabled: true))
        XCTAssertNil(flow.pending); XCTAssertEqual(wire.calls, 1)
    }
    func testSameQuestionIsNoOpAndRetiredSessionCannotFillDraft() async throws {
        let (flow, model, wire, id) = try await setup()
        XCTAssertNil(model.select(messageID: id, draft: "Original question", enabled: true)); XCTAssertNil(model.pending)
        flow.invalidate(); XCTAssertNil(model.select(messageID: id, draft: "", enabled: true)); XCTAssertEqual(wire.calls, 1)
    }
}
