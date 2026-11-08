import XCTest
@testable import QuestifyCore

private final class RefundFactsSource {}
private enum RefundFactsReadError: Error { case failed }

@MainActor final class ProfileOrderRefundReadFactsTests: XCTestCase {
    private func facts(amount: Decimal? = nil, application: Int? = nil, payout: Int? = nil,
                       manual: String? = nil, deadline: String? = nil) -> ProfileOrderRefundReadFacts {
        .init(amount: amount, applicationCode: application, payoutCode: payout, manualCase: manual, deadline: deadline)
    }
    func testOriginalPayoutCodesAndUnknownFutureCodesStayDistinct() async {
        let cases: [(Int?, ProfileOrderRefundReadPayout)] = [(0, .processing), (1, .recordedComplete),
            (2, .manualPending), (3, .manualReview), (4, .recordedComplete), (5, .queued), (6, .dispatching),
            (nil, .unknown), (-1, .unknown), (99, .unknown)]
        for (code, expected) in cases { let value = facts(payout: code); XCTAssertEqual(value.payout, expected); XCTAssertEqual(value.payoutCode, code) }
    }
    func testApplicationApprovalAndManualNotesNeverInferPayoutCompletion() async {
        for application in [nil, 0, 1, 2, 99] as [Int?] {
            let value = facts(amount: 50, application: application, manual: "MANUAL_REFUND_EVIDENCE_VERIFIED")
            XCTAssertEqual(value.applicationCode, application); XCTAssertEqual(value.payout, .unknown); XCTAssertNil(value.payoutCode)
        }
    }
    func testQueuedProcessingAndDispatchingRemainIncompleteRecords() async {
        for payout in [0, 2, 3, 5, 6] {
            let value = facts(amount: 20, application: 1, payout: payout)
            XCTAssertNotEqual(value.payout, .recordedComplete)
        }
    }
    func testMissingAmountIsNotZeroOrDerivedFromStatus() async {
        XCTAssertNil(facts(application: 1, payout: 4).amountText)
        XCTAssertEqual(facts(amount: 0).amountText, "0")
        XCTAssertNil(facts(amount: -1).amountText); XCTAssertNil(facts(amount: Decimal.nan).amountText)
    }
    func testMoneyRetainsInvariantDecimalWithoutScalingOrDoubleRounding() async throws {
        for value in ["9007199254740993.123456789", "0.000000001", "39.5"] {
            XCTAssertEqual(facts(amount: try XCTUnwrap(Decimal(string: value))).amountText, value)
        }
    }
    func testAllMissingOrBlankFactsRemainNotProvidedRatherThanNoRefund() async {
        let value = facts(manual: " \n", deadline: "\t")
        XCTAssertFalse(value.hasReturnedFacts); XCTAssertNil(value.manualCase); XCTAssertNil(value.deadline)
        XCTAssertEqual(value.payout, .unknown); XCTAssertNil(value.applicationCode)
        XCTAssertTrue(facts(application: 0).hasReturnedFacts); XCTAssertTrue(facts(amount: 0).hasReturnedFacts)
    }
    func testOpaqueManualAndDeadlineTextArePreservedWithoutStatusOrTimeInference() async {
        let value = facts(payout: 5, manual: "profile.orders.refunded", deadline: "source deadline without timezone")
        XCTAssertEqual(value.manualCase, "profile.orders.refunded"); XCTAssertEqual(value.deadline, "source deadline without timezone")
        XCTAssertEqual(value.payout, .queued)
    }
    func testRequestedRecordAndBuyerMustMatchCurrentConfiguredIdentity() async {
        let identity = ProfileReadIdentity(accountID: 7, epoch: 1, viewerRevision: 2, approvalRevision: UUID())
        XCTAssertTrue(ProfileOrderRefundReadFacts.matchesAccount(requestedID: 10, recordID: 10, memberID: 7, identity: identity, configured: true))
        for (requested, record, member, owner, configured) in [
            (10, 11, Optional(7), Optional(identity), true),
            (10, 10, Optional(8), Optional(identity), true),
            (10, 10, nil, Optional(identity), true),
            (10, 10, Optional(7), nil, true),
            (10, 10, Optional(7), Optional(identity), false),
            (0, 0, Optional(7), Optional(identity), true),
        ] {
            XCTAssertFalse(ProfileOrderRefundReadFacts.matchesAccount(requestedID: requested, recordID: record, memberID: member, identity: owner, configured: configured))
        }
    }
    func testFreshOrderContainerMasksRefundFactsOnApprovalRevocation() async {
        let source = RefundFactsSource(), model = ProfileReadPresentation<ProfileOrderRefundReadFacts>()
        let identity = ProfileReadIdentity(accountID: 7, epoch: 1, approvalRevision: UUID())
        let owner = ProfileReadPresentationOwner(reader: source, identity: identity, configured: true, surface: "profile.order.detail", requestID: 10)
        model.activate(owner: owner, source: source)
        await model.load(owner: owner, currentOwner: { owner }) { self.facts(amount: 5, payout: 4) }
        let revoked = ProfileReadPresentationOwner(reader: source, identity: identity, configured: false, surface: "profile.order.detail", requestID: 10)
        XCTAssertNil(model.snapshot(for: revoked).value)
    }
    func testFailedRefundRefreshCannotLeaveCompletedFactsVisibleAndRetryShowsNewUnknown() async {
        let source = RefundFactsSource(), model = ProfileReadPresentation<ProfileOrderRefundReadFacts>()
        let owner = ProfileReadPresentationOwner(reader: source, identity: .init(accountID: 7, epoch: 1), configured: true, surface: "profile.order.detail", requestID: 10)
        model.activate(owner: owner, source: source)
        await model.load(owner: owner, currentOwner: { owner }) { self.facts(amount: 5, payout: 4) }
        await model.load(owner: owner, currentOwner: { owner }) { throw RefundFactsReadError.failed }
        XCTAssertNil(model.snapshot(for: owner).value); XCTAssertNotNil(model.snapshot(for: owner).error)
        await model.load(owner: owner, currentOwner: { owner }) { self.facts() }
        XCTAssertFalse(model.snapshot(for: owner).value!.hasReturnedFacts)
        XCTAssertEqual(model.snapshot(for: owner).value?.payout, .unknown)
    }
}
