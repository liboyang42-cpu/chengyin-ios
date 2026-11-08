import XCTest
@testable import QuestifyCore

final class PlayQATextFeedbackStateTests: XCTestCase {
    func testUntouchedInputLeavesExistingProjectionInChargeOfItsVerdict() {
        let state = PlayQATextFeedbackState()
        XCTAssertTrue(state.showsResult(attempts: nil, finished: false))
        XCTAssertTrue(state.showsResult(attempts: 1, finished: false))
    }
    func testEditingRetryHidesPreviousAttemptAndUnchangedReadback() {
        var state = PlayQATextFeedbackState(); state.markEdited(attempts: 1, finished: false)
        for _ in 0..<3 { XCTAssertFalse(state.showsResult(attempts: 1, finished: false)) }
    }
    func testOnlyLaterServerAttemptRestoresFeedbackAfterEdit() {
        var state = PlayQATextFeedbackState(); state.markEdited(attempts: 1, finished: false)
        XCTAssertTrue(state.showsResult(attempts: 2, finished: false))
        state.markEdited(attempts: 2, finished: false)
        XCTAssertFalse(state.showsResult(attempts: 2, finished: false))
        XCTAssertTrue(state.showsResult(attempts: 3, finished: false))
    }
    func testServerTerminalResultCannotBeHiddenByLocalEditing() {
        var state = PlayQATextFeedbackState(); state.markEdited(attempts: 4, finished: false)
        XCTAssertTrue(state.showsResult(attempts: 4, finished: true))
        XCTAssertTrue(state.showsResult(attempts: nil, finished: true))
        state.markEdited(attempts: 4, finished: true)
        XCTAssertTrue(state.showsResult(attempts: 4, finished: true))
    }
    func testMissingZeroNegativeAndOlderAttemptCannotRestoreOldFailure() {
        var state = PlayQATextFeedbackState(); state.markEdited(attempts: 2, finished: false)
        for count in [nil, -1, 0, 1, 2] { XCTAssertFalse(state.showsResult(attempts: count, finished: false)) }
    }
    func testStaleEditCallbackCannotLowerTheEditedAttemptFence() {
        var state = PlayQATextFeedbackState(); state.markEdited(attempts: 4, finished: false)
        for count in [nil, -1, 0, 1] {
            state.markEdited(attempts: count, finished: false)
            XCTAssertFalse(state.showsResult(attempts: 4, finished: false))
        }
        XCTAssertTrue(state.showsResult(attempts: 5, finished: false))
    }
    func testFirstDraftDoesNotCreateAnAttemptToRestoreFeedback() {
        for count in [nil, -1, 0] {
            var state = PlayQATextFeedbackState(); state.markEdited(attempts: count, finished: false)
            XCTAssertFalse(state.showsResult(attempts: 0, finished: false))
            XCTAssertTrue(state.showsResult(attempts: 1, finished: false))
        }
    }
    func testHostScopeResetRestoresFreshServerPresentation() {
        var state = PlayQATextFeedbackState(); state.markEdited(attempts: 4, finished: false)
        state = .init()
        XCTAssertTrue(state.showsResult(attempts: 1, finished: false))
    }
}
