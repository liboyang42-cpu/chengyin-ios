import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class ShopNPCModernOutcomeAppTests: XCTestCase {
    func testProcessingPresentationCannotConfirmEarlyOrFabricateTranscript() async throws {
        let wire = Wire(); let flow = setup(wire); try flow.reviewText("Original question")
        await flow.transmit(reviewID: try XCTUnwrap(flow.pending).id)
        let host = UIHostingController(rootView: ShopNPCView(coordinator: flow, name: "Synthetic guide", greeting: nil))
        host.loadViewIfNeeded()
        XCTAssertEqual(flow.failure?.key, "shopNPCOutcome.processing"); XCTAssertFalse(flow.canConfirmPending)
        XCTAssertTrue(flow.messages.isEmpty); XCTAssertNotNil(flow.pending); XCTAssertEqual(wire.calls, 1)
    }
    func testTerminalNoticeRetainsReviewWithNoSendAction() async throws {
        let wire = Wire(); wire.status = "REJECTED"; wire.retryable = false
        let flow = setup(wire); try flow.reviewText("Original question"); let review = try XCTUnwrap(flow.pending)
        await flow.transmit(reviewID: review.id)
        let host = UIHostingController(rootView: ShopNPCView(coordinator: flow, name: "Synthetic guide", greeting: nil)
            .environment(\.locale, Locale(identifier: "zh-Hans")).dynamicTypeSize(.accessibility5))
        host.loadViewIfNeeded()
        XCTAssertTrue(flow.pendingIsTerminalServiceResponse); XCTAssertEqual(flow.pending, review); XCTAssertFalse(flow.canConfirmPending)
        XCTAssertEqual(flow.failure?.key, "shopNPCOutcome.rejected"); XCTAssertEqual(wire.calls, 1)
    }
    func testClosingReviewRetiresOnlyLocalNoticeWithoutAnotherRequest() async throws {
        let wire = Wire(); let flow = setup(wire); try flow.reviewText("Question"); await flow.transmit(reviewID: try XCTUnwrap(flow.pending).id)
        flow.cancelReview(); XCTAssertNil(flow.pending); XCTAssertNil(flow.serviceNotice); XCTAssertEqual(flow.serverRetrySecondsRemaining, 0)
        XCTAssertEqual(wire.calls, 1)
    }
    private func setup(_ wire: Wire) -> ShopNPCCoordinator {
        var grants = ShopNPCGrants(); grants.server = true; grants.provider = true; grants.legal = true; grants.access = true
        return .init(scope: .init(sessionID: "synthetic", accountID: "7", roleID: "player", accessRevision: 1, nodeID: ShopNPCNodeID(17)!),
            grants: grants, client: .init(transport: wire))
    }
    @MainActor private final class Wire: ShopNPCHTTPTransport {
        var calls = 0; var status = "PROCESSING"; var retryable = true
        func perform(_ request: ShopNPCHTTPRequest) async throws -> ShopNPCHTTPResponse {
            calls += 1; let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
            let id = try XCTUnwrap(body["requestId"] as? String)
            return .init(status: 200, body: try JSONSerialization.data(withJSONObject: ["code": 200, "data": ["requestId": id,
                "outcomeStatus": status, "retryable": retryable, "safetyDecision": "NOT_RUN", "retryAfterSeconds": 10, "safeText": "Synthetic service notice"]]))
        }
    }
}
