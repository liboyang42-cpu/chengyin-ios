import XCTest
@testable import QuestifyCore

@MainActor private final class CouponPermitService: CouponCodeServing {
    var enabled = true
    var requests: [(Int, CouponCodeSession)] = []
    var polls = 0
    var failure: CouponCodeFailure?
    var suspended = false
    var pending: CheckedContinuation<CouponCodeReceipt, Error>?
    let receipt = try! JSONDecoder().decode(CouponCodeReceipt.self, from: Data(#"{"useStatus":0,"expiresIn":60,"token":"SYNTHETIC-NOT-REDEEMABLE"}"#.utf8))
    func issue(historyID: Int, session: CouponCodeSession) async throws -> CouponCodeReceipt {
        requests.append((historyID, session))
        if suspended { return try await withCheckedThrowingContinuation { pending = $0 } }
        if let failure { throw failure }; return receipt
    }
    func status(historyID: Int, session: CouponCodeSession) async throws -> OrderCouponStatus {
        polls += 1; return try JSONDecoder().decode(OrderCouponStatus.self, from: Data(#"{"useStatus":0}"#.utf8))
    }
    func image(_ receipt: CouponCodeReceipt) async throws -> Data { throw CouponCodeFailure.mediaUnavailable }
    func waitForIssue() async { while pending == nil { await Task.yield() } }
    func failPending() { let continuation = pending; pending = nil; continuation?.resume(throwing: CouponCodeFailure.unauthorized) }
}
@MainActor final class CouponCodePermitTests: XCTestCase {
    private func session(account: Int = 1, epoch: UInt64 = 1, namespace: String = "synthetic", role: String = "player", token: String = "synthetic") throws -> CouponCodeSession {
        try .init(accountID: account, epoch: epoch, namespace: namespace, role: role, token: token)
    }
    private func model(_ api: CouponPermitService, owner: CouponCodeSession) -> CouponCodeCoordinator {
        CouponCodeCoordinator(historyID: 71, service: api, currentSession: { owner })
    }
    func testPresentationDoesNotIssueWithoutExplicitCurrentConfirmation() async throws {
        let api = CouponPermitService(), model = self.model(api, owner: try session())
        let presentation = try XCTUnwrap(model.beginPresentation())
        let resume = try XCTUnwrap(model.offerResume(presentation: presentation)); await model.resume(permit: resume); await model.tick(presentation: presentation)
        XCTAssertTrue(api.requests.isEmpty); XCTAssertEqual(model.phase, .review)
        let offer = try XCTUnwrap(model.offerConfirmation(presentation: presentation))
        await model.confirmPresentation(permit: offer)
        XCTAssertEqual(api.requests.count, 1); XCTAssertEqual(api.requests[0].0, 71)
    }
    func testConfirmationQueuedThenClosedCannotIssue() async throws {
        let api = CouponPermitService(), model = self.model(api, owner: try session())
        let presentation = try XCTUnwrap(model.beginPresentation()), offer = try XCTUnwrap(model.offerConfirmation(presentation: presentation))
        model.endPresentation(presentation: presentation); await model.confirmPresentation(permit: offer)
        XCTAssertTrue(api.requests.isEmpty); XCTAssertNil(model.displayToken)
    }
    func testOldConfirmationCannotBorrowReopenedPresentation() async throws {
        let api = CouponPermitService(), model = self.model(api, owner: try session())
        let old = try XCTUnwrap(model.beginPresentation()), offer = try XCTUnwrap(model.offerConfirmation(presentation: old))
        model.endPresentation(presentation: old); let reopened = try XCTUnwrap(model.beginPresentation())
        await model.confirmPresentation(permit: offer); XCTAssertTrue(api.requests.isEmpty)
        let fresh = try XCTUnwrap(model.offerConfirmation(presentation: reopened)); await model.confirmPresentation(permit: fresh)
        XCTAssertEqual(api.requests.count, 1); XCTAssertTrue(model.canDisplay)
    }
    func testOldForegroundTickAndRetryCannotReviveAfterClose() async throws {
        let api = CouponPermitService(), model = self.model(api, owner: try session())
        let old = try XCTUnwrap(model.beginPresentation()), confirm = try XCTUnwrap(model.offerConfirmation(presentation: old))
        await model.confirmPresentation(permit: confirm)
        let retry = try XCTUnwrap(model.offerRetry(presentation: old))
        model.pause(presentation: old); model.endPresentation(presentation: old); _ = model.beginPresentation()
        XCTAssertNil(model.offerResume(presentation: old)); await model.tick(presentation: old); await model.retry(permit: retry)
        XCTAssertEqual(api.requests.count, 1); XCTAssertEqual(api.polls, 0); XCTAssertNil(model.displayToken)
    }
    func testBackgroundRevokesQueuedConfirmationAndRequiresFreshOffer() async throws {
        let api = CouponPermitService(), model = self.model(api, owner: try session())
        let p = try XCTUnwrap(model.beginPresentation()), old = try XCTUnwrap(model.offerConfirmation(presentation: p))
        model.pause(presentation: p); let resume = try XCTUnwrap(model.offerResume(presentation: p)); await model.resume(permit: resume); await model.confirmPresentation(permit: old)
        XCTAssertTrue(api.requests.isEmpty)
        let fresh = try XCTUnwrap(model.offerConfirmation(presentation: p)); await model.confirmPresentation(permit: fresh)
        XCTAssertEqual(api.requests.count, 1)
    }
    func testCoordinatorOwnerIsFrozenAtConstructionBeforeConsent() async throws {
        let api = CouponPermitService(); var owner: CouponCodeSession? = try session()
        let model = CouponCodeCoordinator(historyID: 71, service: api, currentSession: { owner })
        owner = try session(account: 2, epoch: 2)
        XCTAssertNil(model.beginPresentation()); await model.confirmPresentation()
        XCTAssertEqual(model.phase, .stale); XCTAssertTrue(api.requests.isEmpty)
    }
    func testEveryOwnerContextChangeRejectsOfferedConfirmation() async throws {
        let replacements = [try session(account: 2), try session(epoch: 2), try session(namespace: "other"), try session(role: "merchant"), try session(token: "other-token")]
        for replacement in replacements {
            let api = CouponPermitService(); var owner: CouponCodeSession? = try session()
            let model = CouponCodeCoordinator(historyID: 71, service: api, currentSession: { owner })
            let p = try XCTUnwrap(model.beginPresentation()), offer = try XCTUnwrap(model.offerConfirmation(presentation: p))
            owner = replacement; await model.confirmPresentation(permit: offer)
            XCTAssertTrue(api.requests.isEmpty); XCTAssertEqual(model.phase, .stale)
        }
    }
    func testRepeatedConfirmationAndSameOfferStaySingleFlight() async throws {
        let api = CouponPermitService(), model = self.model(api, owner: try session())
        let p = try XCTUnwrap(model.beginPresentation()), offer = try XCTUnwrap(model.offerConfirmation(presentation: p))
        await model.confirmPresentation(permit: offer); await model.confirmPresentation(permit: offer)
        XCTAssertNil(model.offerConfirmation(presentation: p)); XCTAssertEqual(api.requests.count, 1)
    }
    func testUnscopedCompatibilityCannotBypassViewLifecycleOrDismissal() async throws {
        let api = CouponPermitService(), model = self.model(api, owner: try session())
        let p = model.beginPresentation(); await model.confirmPresentation(); XCTAssertTrue(api.requests.isEmpty)
        model.endPresentation(presentation: p); await model.confirmPresentation(); XCTAssertTrue(api.requests.isEmpty)
        let legacy = self.model(api, owner: try session()); legacy.invalidate(); await legacy.confirmPresentation()
        XCTAssertTrue(api.requests.isEmpty)
    }
    func testCancelledQueuedConfirmationHasNoRequest() async throws {
        let api = CouponPermitService(), model = self.model(api, owner: try session())
        let p = try XCTUnwrap(model.beginPresentation()), offer = try XCTUnwrap(model.offerConfirmation(presentation: p))
        let task = Task { await model.confirmPresentation(permit: offer) }; task.cancel(); await task.value
        XCTAssertTrue(api.requests.isEmpty)
    }
    func testCloseDuringIssueSuppressesLateUnauthorizedCallback() async throws {
        let api = CouponPermitService(), owner = try session(); api.suspended = true; var unauthorized = 0
        let model = CouponCodeCoordinator(historyID: 71, service: api, currentSession: { owner }, onUnauthorized: { _ in unauthorized += 1 })
        let p = try XCTUnwrap(model.beginPresentation()), offer = try XCTUnwrap(model.offerConfirmation(presentation: p))
        let task = Task { await model.confirmPresentation(permit: offer) }; await api.waitForIssue()
        model.endPresentation(presentation: p); api.failPending(); await task.value
        XCTAssertEqual(unauthorized, 0); XCTAssertNil(model.receipt); XCTAssertNil(model.displayToken)
    }
    func testOldUnauthorizedAfterReopenCannotAffectNewReview() async throws {
        let api = CouponPermitService(), owner = try session(); api.suspended = true; var unauthorized = 0
        let model = CouponCodeCoordinator(historyID: 71, service: api, currentSession: { owner }, onUnauthorized: { _ in unauthorized += 1 })
        let p = try XCTUnwrap(model.beginPresentation()), offer = try XCTUnwrap(model.offerConfirmation(presentation: p))
        let task = Task { await model.confirmPresentation(permit: offer) }; await api.waitForIssue()
        model.endPresentation(presentation: p); let reopened = try XCTUnwrap(model.beginPresentation()); api.failPending(); await task.value
        XCTAssertEqual(unauthorized, 0); XCTAssertEqual(model.phase, .review)
        api.suspended = false
        let fresh = try XCTUnwrap(model.offerConfirmation(presentation: reopened)); await model.confirmPresentation(permit: fresh)
        XCTAssertTrue(model.canDisplay); XCTAssertEqual(api.requests.count, 2)
    }
    func testCurrentUnauthorizedStillInvalidatesCurrentCode() async throws {
        let api = CouponPermitService(), owner = try session(); api.failure = .unauthorized; var unauthorized = 0
        let model = CouponCodeCoordinator(historyID: 71, service: api, currentSession: { owner }, onUnauthorized: { _ in unauthorized += 1 })
        let p = try XCTUnwrap(model.beginPresentation()), offer = try XCTUnwrap(model.offerConfirmation(presentation: p))
        await model.confirmPresentation(permit: offer)
        XCTAssertEqual(unauthorized, 1); XCTAssertEqual(model.phase, .login); XCTAssertNil(model.displayToken)
    }
    func testCurrentApprovalRevocationImmediatelyHidesCodeAndStopsRenewal() async throws {
        let api = CouponPermitService(), model = self.model(api, owner: try session())
        let p = try XCTUnwrap(model.beginPresentation()), offer = try XCTUnwrap(model.offerConfirmation(presentation: p))
        await model.confirmPresentation(permit: offer); XCTAssertTrue(model.canDisplay)
        api.enabled = false; XCTAssertFalse(model.canDisplay)
        await model.tick(presentation: p)
        XCTAssertEqual(model.phase, .disabled); XCTAssertNil(model.receipt); XCTAssertNil(model.displayToken)
        XCTAssertEqual(api.requests.count, 1); XCTAssertEqual(api.polls, 0)
    }
    func testQueuedForegroundCannotUndoLaterBackground() async throws {
        let api = CouponPermitService(), model = self.model(api, owner: try session())
        let p = try XCTUnwrap(model.beginPresentation()), confirm = try XCTUnwrap(model.offerConfirmation(presentation: p))
        await model.confirmPresentation(permit: confirm); model.pause(presentation: p)
        let offered = try XCTUnwrap(model.offerResume(presentation: p)); model.pause(presentation: p)
        await model.resume(permit: offered); await model.tick(presentation: p)
        XCTAssertEqual(api.requests.count, 1); XCTAssertFalse(model.canDisplay); XCTAssertEqual(model.phase, .paused)
        let fresh = try XCTUnwrap(model.offerResume(presentation: p)); await model.resume(permit: fresh)
        XCTAssertEqual(api.requests.count, 2); XCTAssertTrue(model.canDisplay)
    }
    func testQueuedRetryCannotDispatchAfterApprovalRevocation() async throws {
        let api = CouponPermitService(), model = self.model(api, owner: try session())
        let p = try XCTUnwrap(model.beginPresentation()), confirm = try XCTUnwrap(model.offerConfirmation(presentation: p))
        await model.confirmPresentation(permit: confirm)
        let retry = try XCTUnwrap(model.offerRetry(presentation: p)); api.enabled = false
        await model.retry(permit: retry)
        XCTAssertEqual(api.requests.count, 1); XCTAssertFalse(model.canDisplay); XCTAssertEqual(model.phase, .disabled)
    }
    func testLateCloseCannotRevokeNewOfferedConfirmation() async throws {
        let api = CouponPermitService(), model = self.model(api, owner: try session())
        let old = try XCTUnwrap(model.beginPresentation())
        let fresh = try XCTUnwrap(model.beginPresentation()), confirmation = try XCTUnwrap(model.offerConfirmation(presentation: fresh))
        XCTAssertFalse(model.endPresentation(presentation: old)); XCTAssertTrue(model.presentation === fresh)
        await model.confirmPresentation(permit: confirmation)
        XCTAssertEqual(api.requests.count, 1); XCTAssertTrue(model.canDisplay)
    }
    func testLateCloseDoesNotHideNewCodeOrRevokeConsent() async throws {
        let api = CouponPermitService(), model = self.model(api, owner: try session())
        let old = try XCTUnwrap(model.beginPresentation()), fresh = try XCTUnwrap(model.beginPresentation())
        let confirmation = try XCTUnwrap(model.offerConfirmation(presentation: fresh)); await model.confirmPresentation(permit: confirmation)
        let token = model.displayToken
        XCTAssertFalse(model.endPresentation(presentation: old)); XCTAssertTrue(model.canDisplay)
        XCTAssertEqual(model.displayToken, token); XCTAssertNil(model.offerConfirmation(presentation: fresh))
        XCTAssertEqual(api.requests.count, 1)
    }
    func testCurrentCloseAfterStaleCloseStillRevokesRetryAndFurtherTick() async throws {
        let api = CouponPermitService(), model = self.model(api, owner: try session())
        let old = try XCTUnwrap(model.beginPresentation()), fresh = try XCTUnwrap(model.beginPresentation())
        let confirmation = try XCTUnwrap(model.offerConfirmation(presentation: fresh)); await model.confirmPresentation(permit: confirmation)
        let retry = try XCTUnwrap(model.offerRetry(presentation: fresh))
        XCTAssertFalse(model.endPresentation(presentation: old)); XCTAssertTrue(model.endPresentation(presentation: fresh))
        await model.retry(permit: retry); await model.tick(presentation: fresh)
        XCTAssertEqual(api.requests.count, 1); XCTAssertEqual(api.polls, 0); XCTAssertNil(model.displayToken)
    }
    func testNilCloseCannotRevokeLivePresentation() throws {
        let api = CouponPermitService(), model = self.model(api, owner: try session())
        let p = try XCTUnwrap(model.beginPresentation())
        XCTAssertFalse(model.endPresentation(presentation: nil)); XCTAssertTrue(model.presentation === p)
        XCTAssertNotNil(model.offerConfirmation(presentation: p))
    }
}
