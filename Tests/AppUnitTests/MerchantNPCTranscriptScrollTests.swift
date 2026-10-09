import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class MerchantNPCTranscriptScrollTests: XCTestCase {
    private let scope = MerchantNPCScope(accountID: 7, namespace: "synthetic", epoch: UUID(), merchantRowID: PublicMerchantRowID(9)!, accessRevision: UUID())
    private final class Owner {}
    private func event(_ owner: AnyObject, scope: MerchantNPCScope? = nil, request: UUID? = nil,
                       replyID: UUID? = nil, last: UUID? = nil, sending: Bool = false, stopping: Bool = false,
                       reply: MerchantNPCTranscriptScrollEvent.ReplyState = .none, retryable: Bool = false,
                       deadline: Date? = nil, failure: MerchantNPCTranscriptScrollEvent.FailureState = .none) -> MerchantNPCTranscriptScrollEvent {
        .init(owner: ObjectIdentifier(owner), scope: scope ?? self.scope, requestID: request, replyID: replyID, lastTurnID: last,
              status: .init(sending: sending, stopping: stopping, reply: reply, retryable: retryable, retryDeadline: deadline, failure: failure))
    }
    private func consume(_ event: MerchantNPCTranscriptScrollEvent?, _ policy: inout MerchantNPCTranscriptScrollPolicy,
                         active: Bool = true, voiceOver: Bool = false) -> Bool {
        policy.consume(event, isActive: active, voiceOverEnabled: voiceOver)
    }
    func testInitialAndUnrelatedRendersDoNotMoveAReaderOfOlderHistory() {
        let owner = Owner(); let current = event(owner, replyID: UUID(), last: UUID(), reply: .succeeded)
        var policy = MerchantNPCTranscriptScrollPolicy()
        XCTAssertFalse(consume(current, &policy))
        for _ in 0..<20 { XCTAssertFalse(consume(current, &policy)) }
    }
    func testNewSendAndNewReplyEachProduceOneIntent() {
        let owner = Owner(); let id = UUID(); var policy = MerchantNPCTranscriptScrollPolicy()
        policy.synchronize(event(owner), isActive: true)
        let pending = event(owner, request: id, sending: true)
        XCTAssertTrue(consume(pending, &policy)); XCTAssertFalse(consume(pending, &policy))
        let answered = event(owner, replyID: id, last: id, reply: .succeeded)
        XCTAssertTrue(consume(answered, &policy)); XCTAssertFalse(consume(answered, &policy))
    }
    func testCurrentReplyOutsideRetainedHistoryStillProducesIntent() {
        let owner = Owner(); let id = UUID(); let oldLast = UUID(); var policy = MerchantNPCTranscriptScrollPolicy()
        policy.synchronize(event(owner, request: id, last: oldLast, sending: true), isActive: true)
        XCTAssertTrue(consume(event(owner, replyID: id, last: oldLast, reply: .succeeded), &policy))
    }
    func testChangedLastIdentityWorksWithoutAnyMessageCount() {
        let owner = Owner(); var policy = MerchantNPCTranscriptScrollPolicy()
        policy.synchronize(event(owner, last: UUID()), isActive: true)
        let next = event(owner, last: UUID())
        XCTAssertTrue(consume(next, &policy)); XCTAssertFalse(consume(next, &policy))
    }
    func testPendingServiceStatusAndDeadlineChangeScrollOnlyOnce() {
        let owner = Owner(); let id = UUID(); var policy = MerchantNPCTranscriptScrollPolicy()
        let first = event(owner, request: id, replyID: id, reply: .processing, retryable: true, deadline: Date(timeIntervalSince1970: 10))
        policy.synchronize(first, isActive: true)
        let changed = event(owner, request: id, replyID: id, reply: .failed, retryable: true, deadline: Date(timeIntervalSince1970: 20))
        XCTAssertTrue(consume(changed, &policy))
        for _ in 0..<20 { XCTAssertFalse(consume(changed, &policy)) }
    }
    func testUnknownAndStopSettlingExposeRetryControlsWithoutTimerScrolls() {
        let owner = Owner(); let id = UUID(); var policy = MerchantNPCTranscriptScrollPolicy()
        policy.synchronize(event(owner, request: id, sending: true), isActive: true)
        XCTAssertTrue(consume(event(owner, request: id, stopping: true, failure: .unknownOutcome), &policy))
        let settled = event(owner, request: id, failure: .unknownOutcome)
        XCTAssertTrue(consume(settled, &policy)); XCTAssertFalse(consume(settled, &policy))
    }
    func testHTTPRejectionWithoutReplyIDIsAVisibleNewStatus() {
        let owner = Owner(); var policy = MerchantNPCTranscriptScrollPolicy()
        policy.synchronize(event(owner, request: UUID(), sending: true), isActive: true)
        let failed = event(owner, failure: .rejected)
        XCTAssertTrue(consume(failed, &policy)); XCTAssertFalse(consume(failed, &policy))
    }
    func testAbandonOrClearDoesNotReplayAnOlderTurn() {
        let owner = Owner(); let last = UUID(); var policy = MerchantNPCTranscriptScrollPolicy()
        policy.synchronize(event(owner, request: UUID(), last: last, failure: .unknownOutcome), isActive: true)
        XCTAssertFalse(consume(event(owner, last: last), &policy))
        XCTAssertFalse(consume(event(owner), &policy))
    }
    func testInactiveEventsCannotBeReplayedWhenEventCallbackPrecedesSceneCallback() {
        let owner = Owner(); let old = event(owner); let next = event(owner, replyID: UUID(), last: UUID(), reply: .succeeded)
        var policy = MerchantNPCTranscriptScrollPolicy(); policy.synchronize(old, isActive: true)
        policy.synchronize(old, isActive: false)
        XCTAssertFalse(consume(next, &policy, active: false))
        XCTAssertFalse(consume(next, &policy, active: true))
        policy.synchronize(next, isActive: true)
        XCTAssertFalse(consume(next, &policy))
    }
    func testInactiveEventsCannotBeReplayedWhenSceneCallbackComesFirst() {
        let owner = Owner(); let next = event(owner, replyID: UUID(), reply: .succeeded)
        var policy = MerchantNPCTranscriptScrollPolicy(); policy.synchronize(event(owner), isActive: false)
        policy.synchronize(next, isActive: true)
        XCTAssertFalse(consume(next, &policy))
        XCTAssertTrue(consume(event(owner, request: UUID(), sending: true), &policy))
    }
    func testStaleNilAndRestoredContextMustBeReseeded() {
        let owner = Owner(); let current = event(owner, replyID: UUID(), reply: .succeeded)
        var policy = MerchantNPCTranscriptScrollPolicy(); policy.synchronize(current, isActive: true)
        XCTAssertFalse(consume(nil, &policy)); XCTAssertFalse(consume(current, &policy))
        XCTAssertTrue(consume(event(owner, request: UUID(), sending: true), &policy))
    }
    func testDifferentOwnerOrScopeCannotBorrowAnOldScrollIntent() {
        let first = Owner(); let second = Owner(); let id = UUID(); var policy = MerchantNPCTranscriptScrollPolicy()
        policy.synchronize(event(first, request: id), isActive: true)
        XCTAssertFalse(consume(event(second, request: id, sending: true), &policy))
        let otherScope = MerchantNPCScope(accountID: 8, namespace: "synthetic", epoch: UUID(), merchantRowID: PublicMerchantRowID(10)!, accessRevision: UUID())
        XCTAssertFalse(consume(event(second, scope: otherScope, request: id, replyID: id, reply: .processing), &policy))
        XCTAssertTrue(consume(event(second, scope: otherScope, request: UUID(), sending: true), &policy))
    }
    func testVoiceOverConsumesEventsWithoutScrollingOrCatchUpAfterDisable() {
        let owner = Owner(); var policy = MerchantNPCTranscriptScrollPolicy()
        policy.synchronize(event(owner), isActive: true)
        let next = event(owner, replyID: UUID(), reply: .succeeded)
        XCTAssertFalse(consume(next, &policy, voiceOver: true))
        policy.synchronize(next, isActive: true)
        XCTAssertFalse(consume(next, &policy, voiceOver: false))
        XCTAssertTrue(consume(event(owner, request: UUID(), sending: true), &policy))
    }
    func testDisappearanceDiscardsAnyPendingIntent() {
        let owner = Owner(); let next = event(owner, request: UUID(), sending: true)
        var policy = MerchantNPCTranscriptScrollPolicy(); policy.synchronize(event(owner), isActive: true)
        policy.synchronize(nil, isActive: false)
        XCTAssertFalse(consume(next, &policy))
    }
    func testCapturedEventContainsOnlyIdentifiersAndFixedStatus() async throws {
        let (flow, wire, _) = setup(); await flow.send("Synthetic question")
        let calls = wire.requests.count; let current = try XCTUnwrap(MerchantNPCTranscriptScrollEvent.capture(flow))
        XCTAssertEqual(Set(Mirror(reflecting: current).children.compactMap(\.label)),
                       Set(["owner", "scope", "requestID", "replyID", "lastTurnID", "status"]))
        XCTAssertEqual(current.lastTurnID, flow.conversationHistory.turns.last?.id)
        XCTAssertEqual(current.replyID, flow.reply?.requestID); XCTAssertEqual(current.status.reply, .succeeded)
        XCTAssertEqual(wire.requests.count, calls)
    }
    func testRealHistoryTwentyTurnCapStillChangesTheEvent() async throws {
        let (flow, _, _) = setup(); var policy = MerchantNPCTranscriptScrollPolicy()
        policy.synchronize(MerchantNPCTranscriptScrollEvent.capture(flow), isActive: true)
        for index in 0..<21 {
            await flow.send("Synthetic question \(index)")
            let next = try XCTUnwrap(MerchantNPCTranscriptScrollEvent.capture(flow))
            XCTAssertTrue(consume(next, &policy)); XCTAssertFalse(consume(next, &policy))
        }
        XCTAssertEqual(flow.conversationHistory.turns.count, 20)
        XCTAssertTrue(flow.conversationHistory.hasOmittedTurns)
    }
    func testCaptureRejectsStaleOrInterruptedOwnerWithoutTransport() async {
        let (flow, wire, state) = setup(); await flow.send("Synthetic question")
        let calls = wire.requests.count; let scope = state.scope
        state.scope = nil; XCTAssertNil(MerchantNPCTranscriptScrollEvent.capture(flow))
        state.scope = scope; flow.interrupt(); XCTAssertNil(MerchantNPCTranscriptScrollEvent.capture(flow))
        XCTAssertEqual(wire.requests.count, calls)
    }
    func testBilingualLargeTextSmallScreenConstructionDoesNotSend() async {
        let (flow, wire, _) = setup(); await flow.send("Synthetic question"); let calls = wire.requests.count
        for locale in ["en", "zh-Hans"] {
            for width in [320.0, 430.0] {
                let host = UIHostingController(rootView: MerchantNPCChatView(coordinator: flow)
                    .environment(\.locale, Locale(identifier: locale)).dynamicTypeSize(.accessibility5))
                host.loadViewIfNeeded()
                host.view.frame = CGRect(x: 0, y: 0, width: width, height: 568)
                host.view.layoutIfNeeded()
            }
        }
        XCTAssertEqual(wire.requests.count, calls)
    }
    private func setup() -> (MerchantNPCChatCoordinator, Wire, State) {
        let state = State(); let wire = Wire()
        let flow = MerchantNPCChatCoordinator(scope: state.scope!, client: .init(transport: wire), currentScope: { state.scope }, grants: { state.grants })
        return (flow, wire, state)
    }
    @MainActor private final class State {
        var scope: MerchantNPCScope? = .init(accountID: 7, namespace: "synthetic", epoch: UUID(), merchantRowID: PublicMerchantRowID(9)!, accessRevision: UUID())
        var grants: MerchantNPCGrants = { var value = MerchantNPCGrants(); value.server = true; value.provider = true; value.legal = true; return value }()
    }
    @MainActor private final class Wire: MerchantNPCHTTPTransport {
        var requests: [MerchantNPCHTTPRequest] = []
        func perform(_ request: MerchantNPCHTTPRequest) async throws -> MerchantNPCHTTPResponse {
            requests.append(request)
            let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
            let id = try XCTUnwrap(sent["requestId"] as? String)
            let data: [String: Any] = ["requestId": id, "outcomeStatus": "SUCCEEDED", "safetyDecision": "PASS", "retryable": false, "safeText": "Synthetic safe reply"]
            return .init(status: 200, body: try JSONSerialization.data(withJSONObject: ["code": 200, "data": data]))
        }
    }
}
