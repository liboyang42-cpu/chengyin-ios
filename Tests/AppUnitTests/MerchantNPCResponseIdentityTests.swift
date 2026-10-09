import XCTest
@testable import Questify

@MainActor final class MerchantNPCResponseIdentityAppTests: XCTestCase {
    func testBadReplyCannotMintComposerClearReceiptOrArchivedAnswer() async {
        let wire = Wire(); wire.wrongID = true; let flow = setup(wire)
        let receipt = await flow.send("Original question")
        XCTAssertNil(receipt); XCTAssertEqual(flow.failure, .unknownOutcome); XCTAssertTrue(flow.conversationHistory.turns.isEmpty)
        XCTAssertFalse(MerchantNPCComposerRetention.shouldClear(submitted: "Original question", currentDraft: "Original question",
            capturedGeneration: 1, currentGeneration: 1, completion: receipt, coordinator: flow))
        XCTAssertNotNil(flow.requestID); XCTAssertEqual(wire.requests.count, 1)
    }
    func testVerifiedOriginalRetryCanClearOnlyOriginalInput() async throws {
        let wire = Wire(); wire.wrongID = true; let flow = setup(wire); await flow.send("Original question")
        let id = try XCTUnwrap(flow.requestID); wire.wrongID = false
        let receipt = await flow.retry(requestID: id)
        XCTAssertEqual(receipt?.requestID, id); XCTAssertEqual(wire.requests[0].body, wire.requests[1].body)
        XCTAssertTrue(MerchantNPCComposerRetention.shouldClear(submitted: "Original question", currentDraft: "Original question",
            capturedGeneration: 1, currentGeneration: 1, completion: receipt, coordinator: flow))
        XCTAssertFalse(MerchantNPCComposerRetention.shouldClear(submitted: "Original question", currentDraft: "New typing",
            capturedGeneration: 1, currentGeneration: 1, completion: receipt, coordinator: flow))
    }
    func testUnknownStatusCannotUsePreviousSuccessfulReply() async {
        let wire = Wire(); let flow = setup(wire); let before = await flow.send("Original question"); XCTAssertNotNil(before)
        wire.status = "UNKNOWN"; let receipt = await flow.send("New question")
        XCTAssertNil(receipt); XCTAssertEqual(flow.conversationHistory.turns.count, 1); XCTAssertEqual(flow.message, "New question")
        XCTAssertFalse(flow.canSend); XCTAssertEqual(flow.failure, .unknownOutcome)
    }
    private func setup(_ wire: Wire) -> MerchantNPCChatCoordinator {
        let scope = MerchantNPCScope(accountID: 7, namespace: "synthetic", epoch: UUID(), merchantRowID: PublicMerchantRowID(9)!, accessRevision: UUID())
        var grants = MerchantNPCGrants(); grants.server = true; grants.provider = true; grants.legal = true
        return .init(scope: scope, client: .init(transport: wire), currentScope: { scope }, grants: { grants })
    }
    @MainActor private final class Wire: MerchantNPCHTTPTransport {
        var wrongID = false; var status = "SUCCEEDED"; var requests: [MerchantNPCHTTPRequest] = []
        func perform(_ request: MerchantNPCHTTPRequest) async throws -> MerchantNPCHTTPResponse {
            requests.append(request); let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
            let id = try XCTUnwrap(sent["requestId"] as? String)
            return .init(status: 200, body: try JSONSerialization.data(withJSONObject: ["code": 200, "data": ["requestId": wrongID ? UUID().uuidString : id,
                "outcomeStatus": status, "safetyDecision": "PASS", "retryable": false, "safeText": "Safe reply"]]))
        }
    }
}
