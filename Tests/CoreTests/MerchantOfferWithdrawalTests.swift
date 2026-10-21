import Foundation
import XCTest
@testable import QuestifyCore

/// C8 dedicated test fragment. Not registered in the Xcode project by this
/// line; the integration owner registers it with the shared wiring.
final class MerchantOfferWithdrawalTests: XCTestCase {
    private func value(_ raw: String) throws -> MerchantContentValue {
        try JSONDecoder().decode(MerchantContentValue.self, from: Data(raw.utf8))
    }
    private func subject(state: String = "ACTIVE", offerActive: String = "true",
                         circle: String = "null", product: String = "2", lifecycle: String = "3",
                         reason: String = "null", offerID: String = "77") throws -> MerchantOfferWithdrawalSubject {
        let mine = try value("{\"id\":10,\"chapterId\":33,\"topicId\":10,\"offerId\":\(offerID),"
            + "\"offerState\":\"\(state)\",\"offerActive\":\(offerActive),\"circleThemeCode\":\(circle),"
            + "\"offerWithdrawReason\":\(reason)}")
        let topic = try value("{\"productType\":\(product),\"lifecycle\":\(lifecycle),\"circleThemeCode\":\(circle)}")
        return MerchantOfferWithdrawalSubject(mineRow: mine, topic: topic, chapterRequired: true)
    }

    // MARK: Reason and wire shape

    func testReasonTrimsAndEnforcesOneToFiveHundredUTF16() throws {
        XCTAssertEqual(try MerchantOfferWithdrawalReason(raw: "  暂停营业 \n").value, "暂停营业")
        XCTAssertThrowsError(try MerchantOfferWithdrawalReason(raw: "   "))
        XCTAssertNoThrow(try MerchantOfferWithdrawalReason(raw: String(repeating: "长", count: 500)))
        XCTAssertThrowsError(try MerchantOfferWithdrawalReason(raw: String(repeating: "长", count: 501)))
        // Backend counts Java UTF-16 length, so a surrogate pair counts as 2.
        XCTAssertNoThrow(try MerchantOfferWithdrawalReason(raw: String(repeating: "😀", count: 250)))
        XCTAssertThrowsError(try MerchantOfferWithdrawalReason(raw: String(repeating: "😀", count: 251)))
        XCTAssertEqual(MerchantOfferWithdrawalReason.length(of: "  ab "), 2)
    }

    func testRequestHasExactFieldsPathAndNoRequestIDOrMerchantIdentity() throws {
        let request = try MerchantOfferWithdrawalRequest(offerID: 77, rawReason: " 暂停营业 ")
        XCTAssertEqual(MerchantOfferWithdrawalRequest.path, "api/coop/offer/withdraw")
        XCTAssertEqual(request.fields, ["offerId": .integer(77), "reason": .string("暂停营业")])
        let json = String(decoding: try request.canonicalJSON(), as: UTF8.self)
        XCTAssertFalse(json.contains("requestId")); XCTAssertFalse(json.contains("merchant"))
        XCTAssertThrowsError(try MerchantOfferWithdrawalRequest(offerID: 0, rawReason: "x"))
    }

    func testResponseHintIsOnlyAHintAndMissingStaysUnknown() throws {
        XCTAssertEqual(try MerchantOfferWithdrawalResponseHint(data: value("{\"enrollmentPaused\":true}")).enrollmentPaused, true)
        XCTAssertEqual(try MerchantOfferWithdrawalResponseHint(data: value("{\"enrollmentPaused\":0}")).enrollmentPaused, false)
        XCTAssertNil(try MerchantOfferWithdrawalResponseHint(data: value("{}")).enrollmentPaused)
        XCTAssertThrowsError(try MerchantOfferWithdrawalResponseHint(data: value("{\"enrollmentPaused\":\"yes\"}")))
    }

    // MARK: Eligibility distinctions

    func testOrdinaryActiveSupplyIsEligibleAndImpactDisclosesPauseAndRetention() throws {
        let value = try subject()
        XCTAssertTrue(value.isEligible); XCTAssertNil(value.ineligibility)
        let impact = MerchantOfferWithdrawalImpact(subject: value)
        XCTAssertTrue(impact.mayPauseNewEnrolment); XCTAssertTrue(impact.retainsOrdersFulfilmentAndRedemption)
        XCTAssertFalse(impact.automaticRefundOrDissolution)
    }

    func testCircleTerminalAndNonOrdinaryAreDistinctlyIneligible() throws {
        XCTAssertEqual(try subject(circle: "\"AFTER_WORK\"").ineligibility, .circleSupply)
        XCTAssertEqual(try subject(lifecycle: "5").ineligibility, .topicTerminal)
        XCTAssertEqual(try subject(lifecycle: "6").ineligibility, .topicTerminal)
        XCTAssertEqual(try subject(product: "1").ineligibility, .notOrdinaryFreeExplore)
        XCTAssertEqual(try subject(lifecycle: "99").ineligibility, .lifecycleUnconfirmed)
    }

    func testWithdrawnDeactivatedAndUnconfirmedStatesAreNotEligible() throws {
        // status 0 + reason is withdrawn; status 0 without reason is only deactivated.
        XCTAssertEqual(try subject(state: "WITHDRAWN", offerActive: "false", reason: "\"首次原因\"").ineligibility,
                       .alreadyWithdrawn(serverReason: "首次原因"))
        XCTAssertEqual(try subject(state: "INACTIVE", offerActive: "false").ineligibility, .deactivatedNotWithdrawn)
        XCTAssertEqual(try subject(state: "EXPIRED", offerActive: "false").ineligibility, .stateUnconfirmed)
        XCTAssertEqual(try subject(state: "NONE", offerActive: "false", offerID: "null").ineligibility, .missingOffer)
        XCTAssertEqual(try subject(product: "null").ineligibility, .productUnconfirmed)
    }

    // MARK: Readback verification by original offerId

    func testReadbackConfirmsOnlyWithdrawnWithServerReasonForOriginalOffer() throws {
        let rows = [try value("{\"offerId\":78,\"offerState\":\"WITHDRAWN\",\"offerWithdrawReason\":\"别的原因\"}"),
                    try value("{\"offerId\":77,\"offerState\":\"WITHDRAWN\",\"offerWithdrawReason\":\"首次原因\"}")]
        XCTAssertEqual(MerchantOfferWithdrawalReadback.verify(offerID: 77, requestedReason: "首次原因", mineRows: rows),
                       .confirmed(serverReason: "首次原因", matchesRequestedReason: true))
        // A repeat submission keeps the first reason: the server reason wins
        // and this submission must not claim it saved its own text.
        XCTAssertEqual(MerchantOfferWithdrawalReadback.verify(offerID: 77, requestedReason: "后来重复提交", mineRows: rows),
                       .confirmed(serverReason: "首次原因", matchesRequestedReason: false))
    }

    func testReadbackRejectsNonWithdrawnMissingAmbiguousAndInconsistentRows() throws {
        XCTAssertEqual(MerchantOfferWithdrawalReadback.verify(offerID: 77, requestedReason: "x",
                       mineRows: [try value("{\"offerId\":77,\"offerState\":\"INACTIVE\"}")]),
                       .notWithdrawn(state: .inactive))
        XCTAssertEqual(MerchantOfferWithdrawalReadback.verify(offerID: 77, requestedReason: "x", mineRows: []), .offerMissing)
        let withdrawn = try value("{\"offerId\":77,\"offerState\":\"WITHDRAWN\",\"offerWithdrawReason\":\"原因\"}")
        XCTAssertEqual(MerchantOfferWithdrawalReadback.verify(offerID: 77, requestedReason: "x", mineRows: [withdrawn, withdrawn]),
                       .ambiguousMultipleRows)
        XCTAssertEqual(MerchantOfferWithdrawalReadback.verify(offerID: 77, requestedReason: "x",
                       mineRows: [try value("{\"offerId\":77,\"offerState\":\"WITHDRAWN\"}")]),
                       .inconsistentWithdrawnWithoutReason)
    }
}

@MainActor private final class WithdrawalFakeExecutor: MerchantOfferWithdrawalExecuting {
    var permitsSubmission = true
    var withdrawCount = 0, mineCount = 0
    var hint = MerchantOfferWithdrawalResponseHint(enrollmentPaused: true)
    var withdrawError: Error?
    var rows: [MerchantContentValue] = []
    var onWithdraw: (() -> Void)?
    func withdraw(_ request: MerchantOfferWithdrawalRequest, session: MerchantOfferWithdrawalSession) async throws -> MerchantOfferWithdrawalResponseHint {
        withdrawCount += 1; onWithdraw?()
        if let withdrawError { throw withdrawError }
        return hint
    }
    func mineRows(session: MerchantOfferWithdrawalSession) async throws -> [MerchantContentValue] {
        mineCount += 1; return rows
    }
}

@MainActor final class MerchantOfferWithdrawalCoordinatorTests: XCTestCase {
    private func value(_ raw: String) throws -> MerchantContentValue {
        try JSONDecoder().decode(MerchantContentValue.self, from: Data(raw.utf8))
    }
    private func subject() throws -> MerchantOfferWithdrawalSubject {
        let mine = try value(#"{"id":10,"chapterId":33,"topicId":10,"offerId":77,"offerState":"ACTIVE","offerActive":true}"#)
        return MerchantOfferWithdrawalSubject(mineRow: mine, topic: try value(#"{"productType":2,"lifecycle":3}"#), chapterRequired: true)
    }
    private func withdrawnRow(reason: String = "暂停营业") throws -> MerchantContentValue {
        try value("{\"offerId\":77,\"offerState\":\"WITHDRAWN\",\"offerWithdrawReason\":\"\(reason)\"}")
    }
    private func make(_ executor: WithdrawalFakeExecutor, session: MerchantOfferWithdrawalSession,
                      locks: MerchantOfferWithdrawalMemoryIntentLocks) -> MerchantOfferWithdrawalCoordinator {
        MerchantOfferWithdrawalCoordinator(currentSession: { session }, executor: executor, locks: locks)
    }

    func testConfirmDispatchesOnceThenReadbackConfirmsAndReleasesLock() async throws {
        let session = try MerchantOfferWithdrawalSession(accountID: 1, epoch: 1)
        let executor = WithdrawalFakeExecutor(); executor.rows = [try withdrawnRow()]
        let locks = MerchantOfferWithdrawalMemoryIntentLocks()
        let coordinator = make(executor, session: session, locks: locks)
        let review = try XCTUnwrap(coordinator.prepare(subject: try subject(), rawReason: " 暂停营业 "))
        await coordinator.confirm(review)
        await coordinator.confirm(review) // consumed review: no second dispatch
        XCTAssertEqual(executor.withdrawCount, 1); XCTAssertEqual(executor.mineCount, 1)
        XCTAssertEqual(coordinator.phase, .confirmed(serverReason: "暂停营业", matchesRequestedReason: true, enrollmentPausedHint: true))
        XCTAssertEqual(coordinator.consumeConfirmedOfferID(), 77)
        XCTAssertFalse(try locks.contains(MerchantOfferWithdrawalLockKey.make(session: session, offerID: 77)))
    }

    func testEnrollmentPausedFalseHintStillConfirmsFromReadback() async throws {
        let session = try MerchantOfferWithdrawalSession(accountID: 1, epoch: 1)
        let executor = WithdrawalFakeExecutor()
        executor.hint = .init(enrollmentPaused: false); executor.rows = [try withdrawnRow()]
        let coordinator = make(executor, session: session, locks: MerchantOfferWithdrawalMemoryIntentLocks())
        let review = try XCTUnwrap(coordinator.prepare(subject: try subject(), rawReason: "暂停营业"))
        await coordinator.confirm(review)
        XCTAssertEqual(coordinator.phase, .confirmed(serverReason: "暂停营业", matchesRequestedReason: true, enrollmentPausedHint: false))
    }

    func testUnknownKeepsIntentLockAndReadbackOnlyReconcilesWithoutResending() async throws {
        let session = try MerchantOfferWithdrawalSession(accountID: 1, epoch: 1)
        let executor = WithdrawalFakeExecutor()
        executor.withdrawError = MerchantOfferWithdrawalFailure.unknown
        let locks = MerchantOfferWithdrawalMemoryIntentLocks()
        let coordinator = make(executor, session: session, locks: locks)
        let review = try XCTUnwrap(coordinator.prepare(subject: try subject(), rawReason: "暂停营业"))
        await coordinator.confirm(review)
        XCTAssertEqual(coordinator.phase, .unknown(readback: nil))
        XCTAssertTrue(try locks.contains(MerchantOfferWithdrawalLockKey.make(session: session, offerID: 77)))
        // Preparing again must not create a second send while the intent is unresolved.
        XCTAssertNil(coordinator.prepare(subject: try subject(), rawReason: "暂停营业"))
        executor.rows = [try withdrawnRow(reason: "首次原因")]
        await coordinator.reconcileUnknown(offerID: 77, requestedReason: "暂停营业")
        XCTAssertEqual(executor.withdrawCount, 1) // readback only, never resent
        XCTAssertEqual(coordinator.phase, .confirmed(serverReason: "首次原因", matchesRequestedReason: false, enrollmentPausedHint: nil))
        XCTAssertFalse(try locks.contains(MerchantOfferWithdrawalLockKey.make(session: session, offerID: 77)))
    }

    func testUnknownReadbackNotWithdrawnKeepsLockAndDoesNotResend() async throws {
        let session = try MerchantOfferWithdrawalSession(accountID: 1, epoch: 1)
        let executor = WithdrawalFakeExecutor()
        executor.rows = [try value(#"{"offerId":77,"offerState":"ACTIVE","offerActive":true}"#)]
        let coordinator = make(executor, session: session, locks: MerchantOfferWithdrawalMemoryIntentLocks())
        let review = try XCTUnwrap(coordinator.prepare(subject: try subject(), rawReason: "暂停营业"))
        await coordinator.confirm(review)
        XCTAssertEqual(coordinator.phase, .unknown(readback: .notWithdrawn(state: .active)))
        XCTAssertEqual(executor.withdrawCount, 1)
    }

    func testDefinitiveRejectionReleasesLock() async throws {
        let session = try MerchantOfferWithdrawalSession(accountID: 1, epoch: 1)
        let executor = WithdrawalFakeExecutor()
        executor.withdrawError = MerchantOfferWithdrawalFailure.rejected(code: 500, message: "只能退出自己的章节供给")
        let locks = MerchantOfferWithdrawalMemoryIntentLocks()
        let coordinator = make(executor, session: session, locks: locks)
        let review = try XCTUnwrap(coordinator.prepare(subject: try subject(), rawReason: "暂停营业"))
        await coordinator.confirm(review)
        XCTAssertEqual(coordinator.phase, .rejected(message: "只能退出自己的章节供给"))
        XCTAssertFalse(try locks.contains(MerchantOfferWithdrawalLockKey.make(session: session, offerID: 77)))
        XCTAssertNotNil(coordinator.prepare(subject: try subject(), rawReason: "暂停营业"))
    }

    func testCrossAccountOldResponseIsNeverApplied() async throws {
        var current = try MerchantOfferWithdrawalSession(accountID: 1, epoch: 1)
        let other = try MerchantOfferWithdrawalSession(accountID: 2, epoch: 1)
        let executor = WithdrawalFakeExecutor(); executor.rows = [try withdrawnRow()]
        executor.onWithdraw = { current = other }
        let coordinator = MerchantOfferWithdrawalCoordinator(currentSession: { current }, executor: executor,
                                                             locks: MerchantOfferWithdrawalMemoryIntentLocks())
        let review = try XCTUnwrap(coordinator.prepare(subject: try subject(), rawReason: "暂停营业"))
        await coordinator.confirm(review)
        XCTAssertEqual(coordinator.phase, .unknown(readback: nil))
        XCTAssertEqual(executor.mineCount, 0) // old response discarded before any readback is applied
        XCTAssertNil(coordinator.confirmedOfferID)
    }

    func testAlreadyWithdrawnAndDormantExecutorNeverDispatch() async throws {
        let session = try MerchantOfferWithdrawalSession(accountID: 1, epoch: 1)
        let executor = WithdrawalFakeExecutor()
        let coordinator = make(executor, session: session, locks: MerchantOfferWithdrawalMemoryIntentLocks())
        let mine = try value(#"{"id":10,"chapterId":33,"topicId":10,"offerId":77,"offerState":"WITHDRAWN","offerActive":false,"offerWithdrawReason":"首次原因"}"#)
        let withdrawn = MerchantOfferWithdrawalSubject(mineRow: mine, topic: try value(#"{"productType":2,"lifecycle":3}"#))
        XCTAssertNil(coordinator.prepare(subject: withdrawn, rawReason: "后来重复提交"))
        XCTAssertEqual(coordinator.phase, .alreadyWithdrawn(serverReason: "首次原因"))
        XCTAssertEqual(executor.withdrawCount, 0)

        let dormant = MerchantOfferWithdrawalCoordinator(currentSession: { session })
        XCTAssertFalse(dormant.permitsSubmission)
        let review = try XCTUnwrap(dormant.prepare(subject: try subject(), rawReason: "暂停营业"))
        await dormant.confirm(review)
        XCTAssertEqual(dormant.phase, .disabled)
    }
}
