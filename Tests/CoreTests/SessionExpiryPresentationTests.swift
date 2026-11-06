import XCTest
@testable import QuestifyCore

final class SessionExpiryPresentationTests: XCTestCase {
    private func context(_ epoch: UInt64, _ accountID: Int?, error: String? = nil, busy: Bool = false) -> SessionExpiryNoticeContext {
        .init(session: .init(epoch: epoch, accountID: accountID, isBusy: busy), errorKey: error)
    }
    private func expired() -> SessionExpiryPresentationState {
        var state = SessionExpiryPresentationState()
        XCTAssertFalse(state.observe(context(1, 7)))
        XCTAssertTrue(state.observe(context(2, nil, error: "auth.expired")))
        return state
    }

    func testColdGuestAndDeliberateLogoutDoNotPresent() {
        var cold = SessionExpiryPresentationState()
        XCTAssertFalse(cold.observe(context(1, nil, error: "auth.expired")))
        XCTAssertNil(cold.active)
        var signedIn = SessionExpiryPresentationState()
        signedIn.observe(context(1, 7))
        XCTAssertFalse(signedIn.observe(context(2, nil)))
        XCTAssertNil(signedIn.active)
    }

    func testExpiryPresentsOnlyOnceAndKeepsSamePromptAcrossDuplicateObservation() throws {
        var state = expired()
        let prompt = try XCTUnwrap(state.prompt)
        XCTAssertFalse(state.observe(context(2, nil, error: "auth.expired")))
        XCTAssertEqual(state.prompt, prompt); XCTAssertNil(state.signIn)
    }

    func testExplicitSignInKeepsPresenterIdentityAndConsumesPromptOnce() throws {
        var state = expired()
        let prompt = try XCTUnwrap(state.prompt), current = context(2, nil, error: "auth.expired")
        XCTAssertTrue(state.beginSignIn(prompt, current: current))
        XCTAssertNil(state.prompt); XCTAssertEqual(state.signIn, prompt); XCTAssertEqual(state.active?.id, prompt.id)
        XCTAssertFalse(state.beginSignIn(prompt, current: current))
        state.dismissPrompt(prompt) // Framework alert dismissal after the action.
        XCTAssertEqual(state.signIn, prompt)
    }

    func testLiveActionCheckRejectsChangedHostBeforeObservationArrives() throws {
        let replacements = [context(3, 8), context(3, 7), context(3, nil, error: "auth.expired"),
                            context(2, nil, error: "auth.expired", busy: true), context(2, nil)]
        for current in replacements {
            var state = expired(); let prompt = try XCTUnwrap(state.prompt)
            XCTAssertFalse(state.beginSignIn(prompt, current: current))
            XCTAssertNil(state.signIn)
        }
    }

    func testReauthenticationAndGuestEpochChangeRetireOldPrompt() throws {
        for current in [context(3, 7), context(3, 8), context(3, nil, error: "auth.expired")] {
            var state = expired(); let prompt = try XCTUnwrap(state.prompt)
            XCTAssertFalse(state.observe(current)); XCTAssertNil(state.prompt)
            XCTAssertFalse(state.beginSignIn(prompt, current: current)); XCTAssertNil(state.active)
        }
    }

    func testOldAlertCallbacksCannotReplaceOrDismissNewExpiry() throws {
        var state = expired(); let old = try XCTUnwrap(state.prompt)
        state.observe(context(3, 7))
        XCTAssertTrue(state.observe(context(4, nil, error: "auth.expired")))
        let fresh = try XCTUnwrap(state.prompt)
        XCTAssertNotEqual(old, fresh)
        state.dismissPrompt(old); state.dismissSignIn(old)
        XCTAssertFalse(state.beginSignIn(old, current: context(4, nil, error: "auth.expired")))
        XCTAssertEqual(state.prompt, fresh); XCTAssertNil(state.signIn)
    }

    func testStartedLoginSurvivesItsOwnGuestEpochAndFailureForExplicitRetry() throws {
        var state = expired(); let original = try XCTUnwrap(state.prompt)
        XCTAssertTrue(state.beginSignIn(original, current: context(2, nil, error: "auth.expired")))
        XCTAssertFalse(state.observe(context(3, nil, busy: true)))
        XCTAssertEqual(state.signIn, original)
        XCTAssertFalse(state.observe(context(3, nil, error: "auth.networkError")))
        XCTAssertEqual(state.signIn, original)
        XCTAssertFalse(state.observe(context(4, nil, busy: true)))
        XCTAssertEqual(state.signIn, original); XCTAssertNil(state.prompt)
    }

    func testNewAccountClosesStartedLoginAndOldSheetDismissalCannotClearNextLogin() throws {
        var state = expired(); let old = try XCTUnwrap(state.prompt)
        state.beginSignIn(old, current: context(2, nil, error: "auth.expired"))
        state.observe(context(3, 8)); XCTAssertNil(state.active)
        state.observe(context(4, nil, error: "auth.expired")); let fresh = try XCTUnwrap(state.prompt)
        state.beginSignIn(fresh, current: context(4, nil, error: "auth.expired"))
        state.dismissSignIn(old); state.dismissPrompt(old)
        XCTAssertEqual(state.signIn, fresh)
    }

    func testBrowseAndSheetCloseDoNotReopenWithoutNewExpiryTransition() throws {
        var browse = expired(); let prompt = try XCTUnwrap(browse.prompt)
        browse.dismissPrompt(prompt)
        XCTAssertFalse(browse.observe(context(2, nil, error: "auth.expired"))); XCTAssertNil(browse.active)
        var login = expired(); let original = try XCTUnwrap(login.prompt)
        login.beginSignIn(original, current: context(2, nil, error: "auth.expired"))
        login.dismissSignIn(original)
        XCTAssertFalse(login.observe(context(2, nil, error: "auth.expired"))); XCTAssertNil(login.active)
    }

    func testAccountSwitchAndNonExpiryErrorsDoNotInventExpiry() {
        var state = SessionExpiryPresentationState()
        state.observe(context(1, 7))
        XCTAssertFalse(state.observe(context(2, 8, error: "auth.expired")))
        XCTAssertFalse(state.observe(context(3, nil, error: "auth.networkError")))
        XCTAssertFalse(state.observe(context(4, nil, error: "auth.expired")))
        XCTAssertNil(state.active)
    }
}
