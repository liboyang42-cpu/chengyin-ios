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
    func testUnresolvedServicePresentationKeepsReviewWithoutRetryOrTerminalGuidance() async throws {
        for locale in ["en", "zh-Hans"] {
            let wire = Wire(); wire.unresolved = true
            let flow = setup(wire); try flow.reviewText("Original complete question\nSecond line")
            let review = try XCTUnwrap(flow.pending); await flow.transmit(reviewID: review.id)
            let host = UIHostingController(rootView: ShopNPCView(coordinator: flow, name: "Synthetic guide", greeting: nil)
                .environment(\.locale, Locale(identifier: locale)).dynamicTypeSize(.accessibility5))
            host.loadViewIfNeeded()
            XCTAssertEqual(flow.pending, review); XCTAssertTrue(flow.pendingIsNonRetryableProcessing)
            XCTAssertFalse(flow.pendingIsTerminalServiceResponse); XCTAssertFalse(flow.canConfirmPending)
            XCTAssertEqual(flow.failure, .replyUnresolved); XCTAssertEqual(flow.failure?.key, "merchantNPC.unavailable")
            XCTAssertEqual(flow.serviceNotice, "Synthetic service notice"); XCTAssertEqual(flow.serverRetrySecondsRemaining, 0)
            XCTAssertTrue(flow.messages.isEmpty); XCTAssertEqual(wire.calls, 1)
        }
    }
    func testUnresolvedReviewCannotBeSentByReusedButtonIntent() async throws {
        let wire = Wire(); wire.unresolved = true
        let flow = setup(wire); try flow.reviewText("Keep this input"); let review = try XCTUnwrap(flow.pending)
        let intent = try flow.prepareTransmission(reviewID: review.id)
        await flow.transmit(reviewID: review.id, intent: intent)
        await flow.transmit(reviewID: review.id, intent: intent)
        XCTAssertThrowsError(try flow.prepareTransmission(reviewID: review.id))
        await flow.transmit(reviewID: review.id)
        XCTAssertEqual(flow.pending, review); XCTAssertEqual(flow.failure, .replyUnresolved)
        XCTAssertTrue(flow.pendingIsNonRetryableProcessing); XCTAssertEqual(wire.calls, 1)
    }
    func testExplicitLocalCancelUnlocksReviewWithoutDispatchOrServerResolution() async throws {
        let wire = Wire(); wire.unresolved = true
        let flow = setup(wire); try flow.reviewText("Retained question"); let review = try XCTUnwrap(flow.pending)
        await flow.transmit(reviewID: review.id)
        XCTAssertTrue(flow.pendingIsNonRetryableProcessing); XCTAssertFalse(flow.canConfirmPending)
        flow.cancelReview()
        XCTAssertNil(flow.pending); XCTAssertNil(flow.serviceNotice); XCTAssertNil(flow.failure)
        XCTAssertFalse(flow.pendingIsNonRetryableProcessing); XCTAssertTrue(flow.messages.isEmpty); XCTAssertEqual(wire.calls, 1)
        try flow.reviewText("Retained question")
        XCTAssertNotEqual(flow.pending?.id, review.id); XCTAssertTrue(flow.canConfirmPending); XCTAssertEqual(wire.calls, 1)
    }
    func testSuspendAndExplicitRestoreDoNotTurnServerDenialIntoRetryPermission() async throws {
        let wire = Wire(); wire.unresolved = true
        let flow = setup(wire); try flow.reviewText("Private review"); let review = try XCTUnwrap(flow.pending)
        await flow.transmit(reviewID: review.id); flow.suspend(); flow.cancelReview()
        XCTAssertTrue(flow.isSuspended); XCTAssertEqual(flow.pending, review)
        flow.resumeAfterInterruption()
        XCTAssertFalse(flow.isSuspended); XCTAssertTrue(flow.pendingIsNonRetryableProcessing)
        XCTAssertEqual(flow.pending, review); XCTAssertFalse(flow.canConfirmPending); XCTAssertEqual(wire.calls, 1)
        flow.invalidate()
        XCTAssertNil(flow.pending); XCTAssertNil(flow.serviceNotice); XCTAssertFalse(flow.pendingIsNonRetryableProcessing)
        XCTAssertTrue(flow.messages.isEmpty); XCTAssertEqual(wire.calls, 1)
    }
    func testSessionOwnerRetiresUnresolvedReviewBeforeNextAccount() async throws {
        let wire = Wire(); wire.unresolved = true
        let owner = ShopNPCSessionOwner(); let flow = setup(wire); owner.register(flow)
        try flow.reviewText("Private review"); await flow.transmit(reviewID: try XCTUnwrap(flow.pending).id)
        XCTAssertTrue(flow.pendingIsNonRetryableProcessing)
        owner.invalidate()
        XCTAssertFalse(flow.active); XCTAssertNil(flow.pending); XCTAssertNil(flow.serviceNotice); XCTAssertTrue(flow.messages.isEmpty)
        XCTAssertFalse(flow.pendingIsNonRetryableProcessing); XCTAssertEqual(wire.calls, 1)
        flow.resumeAfterInterruption(); XCTAssertFalse(flow.active); XCTAssertEqual(wire.calls, 1)
    }
    private func setup(_ wire: Wire) -> ShopNPCCoordinator {
        var grants = ShopNPCGrants(); grants.server = true; grants.provider = true; grants.legal = true; grants.access = true
        return .init(scope: .init(sessionID: "synthetic", accountID: "7", roleID: "player", accessRevision: 1, nodeID: ShopNPCNodeID(17)!),
            grants: grants, client: .init(transport: wire))
    }
    @MainActor private final class Wire: ShopNPCHTTPTransport {
        var calls = 0; var status = "PROCESSING"; var retryable = true
        var unresolved = false
        func validateResume(scope: ShopNPCScope, grants: ShopNPCGrants) throws {
            guard scope.valid, grants.textAllowed else { throw ShopNPCFailure.stale }
        }
        func perform(_ request: ShopNPCHTTPRequest) async throws -> ShopNPCHTTPResponse {
            calls += 1; let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
            let id = try XCTUnwrap(body["requestId"] as? String)
            var payload: [String: Any] = ["requestId": id, "outcomeStatus": status, "retryable": retryable,
                "safetyDecision": "NOT_RUN", "retryAfterSeconds": 10, "safeText": "Synthetic service notice"]
            if unresolved {
                payload["outcomeStatus"] = "PROCESSING"; payload["safetyDecision"] = "UNKNOWN"
                payload["retryable"] = false; payload["errorCode"] = "REQUEST_OUTCOME_UNKNOWN"
            }
            return .init(status: 200, body: try JSONSerialization.data(withJSONObject: ["code": 200, "data": payload]))
        }
    }
}
