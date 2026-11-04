import XCTest
@testable import Questify

@MainActor final class NativeFriendRemovalPresentationTests: XCTestCase {
    func testRealRowPresentationReviewCancelDoesNotSendAndResolvedCallbackRefreshesOwner() async {
        let state = NativeFriendRemovalFixtureState(loseResponse: false), flow = state.makeRemoval(item: state.item)
        var resolved = 0; let model = NativeFriendRemovalViewModel(flow, onResolved: { resolved += 1 })
        await model.flow.load(); model.flow.reviewRemoval(); model.flow.cancelReview()
        XCTAssertEqual(state.removeCount, 0); XCTAssertEqual(state.settleCount, 0)
        model.flow.reviewRemoval(); await model.flow.confirm(); XCTAssertEqual(resolved, 1); XCTAssertEqual(state.removeCount, 1)
        await state.home.load(); XCTAssertTrue(state.home.friends.isEmpty); XCTAssertEqual(model.flow.result?.peerID, state.item.peerID)
    }
    func testRecoveryPresentationDoesNotDependOnRemovedRowOrCurrentlySelectedPeer() async {
        let state = NativeFriendRemovalFixtureState(loseResponse: true), flow = state.makeRemoval(item: state.item)
        await flow.load(); flow.reviewRemoval(); await flow.confirm(); let original = flow.pendingCommand; flow.invalidate()
        await state.home.load(); XCTAssertTrue(state.home.friends.isEmpty)
        let recovery = state.makeRemoval(item: nil); await recovery.load(); XCTAssertNil(recovery.item); XCTAssertEqual(recovery.pendingCommand, original)
        await recovery.recover(); XCTAssertEqual(recovery.result?.outcome, "APPLIED"); XCTAssertEqual(state.removeCount, 1); XCTAssertEqual(state.receiptCount, 1); XCTAssertEqual(state.settleCount, 0)
    }
    func testOtherSelectedRowCannotLabelOriginalRecoveryBeforeOrAfterTerminalResult() async {
        let state = NativeFriendRemovalFixtureState(loseResponse: true), first = state.makeRemoval(item: state.item)
        await first.load(); first.reviewRemoval(); await first.confirm()
        let otherRow = NativeFriendItem(peerID: 7, nickname: "Different selected friend", state: .friend, version: 3, message: "", expiresAtMS: 0)
        let recovery = state.makeRemoval(item: otherRow); await recovery.load()
        XCTAssertNil(recovery.presentationItem); XCTAssertEqual(recovery.pendingCommand?.peerID, 9)
        await recovery.recover(); XCTAssertNil(recovery.presentationItem); XCTAssertEqual(recovery.result?.peerID, 9)
        XCTAssertEqual(recovery.currentRelationship?.peerID, 9); XCTAssertEqual(state.removeCount, 1)
    }

}
