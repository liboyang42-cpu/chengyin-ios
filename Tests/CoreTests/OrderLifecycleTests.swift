import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class OrderLifecycleTests: XCTestCase {
    private func detail(_ extra: String) throws -> OrderLifecycleDetail {
        try JSONDecoder().decode(OrderLifecycleDetail.self, from: Data(("{\"id\":7," + extra + "}").utf8))
    }
    func testOwnerFieldsRemainBoundToExactRegistration() throws {
        let d = try OrderLifecycleSyntheticFixtures.detail(OrderLifecycleSyntheticFixtures.paid)
        XCTAssertEqual(d.id, 9701); XCTAssertEqual(d.ownerID, 9801); XCTAssertEqual(d.ownerType, 2)
        XCTAssertEqual(d.ownerMemberID, 9901); XCTAssertEqual(d.teamMode, 2); XCTAssertEqual(d.teamMaxMembers, 4)
    }
    func testActivityOwnerPrecedesTopicAndUnknownFieldsStayUnknown() throws {
        let d = try detail(#""cmsActivity":{"name":"Activity","teamMode":1},"cmsTopic":{"name":"Topic","teamMode":2}"#)
        XCTAssertEqual(d.title, "Activity"); XCTAssertEqual(d.teamMode, 1)
        XCTAssertNil(d.teamMaxMembers); XCTAssertNil(d.payableAmount); XCTAssertNil(d.paymentStatus)
        XCTAssertEqual(d.summary().state, .unknown)
    }
    func testCancelledDoesNotMeanRefunded() throws {
        let d = try detail(#""registrationStatus":3,"paymentStatus":2"#)
        XCTAssertEqual(d.summary().state, .cancelled)
        XCTAssertFalse(d.timeline().contains { $0.id == "refund" })
    }
    func testOnlyPayoutOneAndFourConfirmRefund() throws {
        for code in [1, 4] {
            let d = try detail("\"registrationStatus\":3,\"refundApplication\":{\"payoutStatus\":\(code)}")
            XCTAssertEqual(d.summary().state, .refunded)
        }
        for code in [0, 2, 3, 5, 99] {
            let d = try detail("\"registrationStatus\":3,\"refundApplication\":{\"payoutStatus\":\(code)}")
            XCTAssertEqual(d.summary().state, .refunding)
        }
    }
    func testManualRefundPrecedesAllPayoutStates() throws {
        let d = try detail(#""registrationStatus":3,"manualRefundCaseStatus":"PENDING_ASSESSMENT","refundApplication":{"payoutStatus":1}"#)
        XCTAssertEqual(d.summary().state, .manualRefund)
    }
    func testZeroAmountAndRejectedRefundFallBackToRegistration() throws {
        for refund in [#"{"payoutStatus":5,"refundAmount":0}"#, #"{"payoutStatus":5,"status":2,"refundAmount":20}"#] {
            let d = try detail("\"registrationStatus\":3,\"refundApplication\":\(refund)")
            XCTAssertEqual(d.summary().state, .cancelled)
        }
    }
    func testVerificationAndNonRefundablePrecedeTime() throws {
        let verified = try detail(#""registrationStatus":2,"verificationStatus":1,"refundInfo":{"refundable":false}"#)
        XCTAssertEqual(verified.summary().state, .completed)
        let denied = try detail(#""registrationStatus":2,"verificationStatus":0,"refundInfo":{"refundable":false},"cmsActivity":{"endDate":"2000-01-01 12:00:00"}"#)
        XCTAssertEqual(denied.summary().state, .nonRefundable)
    }
    func testAbsoluteAndChinaTimeStableAcrossDeviceZone() throws {
        XCTAssertEqual(OrderLifecycleTime.date("2026-10-01 12:00:00"), OrderLifecycleTime.date("2026-10-01T04:00:00Z"))
        XCTAssertEqual(OrderLifecycleTime.display("2026-10-01T04:00:00Z"), "2026-10-01 12:00")
        XCTAssertNil(OrderLifecycleTime.date("bad")); XCTAssertNil(OrderLifecycleTime.date("2026-02-30 12:00:00"))
        XCTAssertNil(OrderLifecycleTime.date("1234")); XCTAssertNil(OrderLifecycleTime.display(nil))
    }
    func testScheduleBoundariesUseProvidedNow() throws {
        let d = try detail(#""registrationStatus":2,"cmsActivity":{"startDate":"2026-10-01 12:00:00","endDate":"2026-10-01 13:00:00"}"#)
        XCTAssertEqual(d.summary(now: try XCTUnwrap(OrderLifecycleTime.date("2026-10-01 11:59:59"))).state, .notStarted)
        XCTAssertEqual(d.summary(now: try XCTUnwrap(OrderLifecycleTime.date("2026-10-01 12:00:00"))).state, .inProgress)
        XCTAssertEqual(d.summary(now: try XCTUnwrap(OrderLifecycleTime.date("2026-10-01 13:00:01"))).state, .completed)
    }
    func testTimelineRequiresPaymentStatusForPaidRow() throws {
        let d = try detail(#""registrationStatus":2,"verificationStatus":1"#)
        XCTAssertEqual(d.timeline().map(\.id), ["created", "payment"])
        XCTAssertFalse(d.timeline().last?.done ?? true)
    }
    func testRefundTimelineUsesPayoutTimeNotLocalNow() throws {
        let d = try OrderLifecycleSyntheticFixtures.detail(OrderLifecycleSyntheticFixtures.refunded)
        XCTAssertEqual(d.timeline().map(\.id), ["created", "paid", "refund"])
        XCTAssertEqual(d.timeline().last?.time, "2026-10-01 12:03")
        XCTAssertEqual(d.timeline().last?.done, true)
    }
    func testPaymentAcceptanceDoesNotBecomeCashSettlement() {
        XCTAssertEqual(OrderPaymentObservation(payment: nil, registration: 2), .registrationAccepted)
        XCTAssertEqual(OrderPaymentObservation(payment: 2, registration: 1), .paid)
        XCTAssertEqual(OrderPaymentObservation(payment: 3, registration: 1), .failed)
        XCTAssertEqual(OrderPaymentObservation(payment: nil, registration: nil), .unknown)
        XCTAssertEqual(OrderPaymentObservation(payment: 1, registration: 1), .pending)
    }
    func testMalformedAndNegativeAmountsRejected() {
        for raw in ["-1", "\"4.00\"", "true"] {
            XCTAssertThrowsError(try detail("\"payableAmount\":\(raw)"))
        }
    }
    func testClosedContradictoryOrUnknownStatusCannotBeReviewed() throws {
        let d = try detail(#""registrationStatus":1,"paymentStatus":2,"verificationStatus":0"#)
        XCTAssertFalse(OrderLifecycleCoordinator.isReviewable(.cancel, detail: d))
        XCTAssertFalse(OrderLifecycleCoordinator.isReviewable(.payment, detail: d))
        let unknown = try detail(#""registrationStatus":2,"paymentStatus":2,"verificationStatus":0"#)
        XCTAssertFalse(OrderLifecycleCoordinator.isReviewable(.refund, detail: unknown))
    }
    func testCancelAndRefundRoutesAreDistinct() {
        XCTAssertEqual(OrderLifecycleAction.cancel.sourcePath, "api/registration/cancel")
        XCTAssertEqual(OrderLifecycleAction.refund.sourcePath, "api/registration/cancel-refund")
    }
    func testPassExpiryUsesAbsoluteTimeAndMissingExpiryStaysUnknown() throws {
        let metadata = try JSONDecoder().decode(OrderPassMetadata.self, from: Data(#"{"expiresAt":100000,"ttlMs":300000}"#.utf8))
        XCTAssertEqual(metadata.remainingSeconds(now: Date(timeIntervalSince1970: 99)), 1)
        XCTAssertEqual(metadata.remainingSeconds(now: Date(timeIntervalSince1970: 150)), 0)
        let missing = try JSONDecoder().decode(OrderPassMetadata.self, from: Data(#"{"ttlMs":300000}"#.utf8))
        XCTAssertNil(missing.remainingSeconds(now: Date()))
    }
    func testPassUnknownEntitlementDoesNotBecomeUnused() throws {
        let d = try detail(#""registrationStatus":2,"entitlements":[{"id":9}]"#)
        XCTAssertEqual(OrderPassAvailability(detail: d), .unknown)
    }
    func testAllCredentialAndVerificationOperationsHardOff() {
        for operation in OrderPassSourceOperation.allCases { XCTAssertFalse(operation.isDispatchEnabled) }
        XCTAssertEqual(OrderPassSourceOperation.verifyDynamicTicket.fieldNames, ["code"])
        XCTAssertEqual(OrderPassSourceOperation.chooseStation.fieldNames, ["code", "registrationMerchantId"])
    }
    func testChoiceFlagsBeatBusinessFailureCodeWithoutBecomingSuccess() throws {
        let receipt = try JSONDecoder().decode(OrderVerificationReceipt.self, from: Data(OrderLifecycleSyntheticFixtures.chapterChoice.utf8))
        XCTAssertEqual(receipt.outcome, .needsChoice); XCTAssertEqual(receipt.choices.map(\.id), [9721, 9722])
        XCTAssertTrue(receipt.containsChoice(9721)); XCTAssertFalse(receipt.containsChoice(9999))
    }
    func testStationChoiceUsesRegistrationMerchantIDNotStationID() throws {
        let receipt = try JSONDecoder().decode(OrderVerificationReceipt.self, from: Data(OrderLifecycleSyntheticFixtures.stationChoice.utf8))
        XCTAssertEqual(receipt.choices.map(\.id), [9731]); XCTAssertFalse(receipt.containsChoice(9999))
    }
    func testEmptyChoicesRemainNonRedeemedAndAuthorizationWins() throws {
        let empty = try JSONDecoder().decode(OrderVerificationReceipt.self, from: Data(#"{"code":200,"data":{"needChapterChoice":true}}"#.utf8))
        XCTAssertEqual(empty.outcome, .needsChoice); XCTAssertTrue(empty.choices.isEmpty)
        XCTAssertThrowsError(try JSONDecoder().decode(OrderVerificationReceipt.self, from: Data(#"{"code":401,"data":{"needChapterChoice":true}}"#.utf8)))
    }
    func testCouponMissingStatusStaysUnknown() throws {
        let value = try JSONDecoder().decode(OrderCouponStatus.self, from: Data("{}".utf8))
        XCTAssertEqual(value.stateKey, "unknown")
    }
}

extension OrderLifecycleTests {
    func testTeamContextRequiresOwnedActivityAndAllowedMode() throws {
        let paid = try OrderLifecycleSyntheticFixtures.detail(OrderLifecycleSyntheticFixtures.paid)
        XCTAssertEqual(paid.teamCreationSource?.registrationID, 9701)
        XCTAssertEqual(paid.teamCreationSource?.context.ownerID, 9801)
        XCTAssertEqual(paid.teamCreationSource?.context.sizes, [2, 3, 4])
        let pending = try OrderLifecycleSyntheticFixtures.detail()
        XCTAssertNil(pending.teamCreationSource)
    }
    func testTeamContextNeverSubstitutesRegistrationIDForOwnerID() throws {
        let route = try detail(#""ownerType":1,"ownerId":91,"registrationStatus":2,"cmsTopic":{"name":"Route","teamMode":2}"#)
        XCTAssertNil(route.teamCreationSource)
        let noOwner = try detail(#""ownerType":2,"registrationStatus":2,"cmsActivity":{"name":"Activity","teamMode":2}"#)
        XCTAssertNil(noOwner.teamCreationSource)
    }
    func testUnknownTeamModeNeverGrantsEligibility() throws {
        let value = try detail(#""ownerType":2,"ownerId":91,"registrationStatus":2,"cmsActivity":{"name":"Activity","teamMaxMembers":4}"#)
        XCTAssertNil(value.teamCreationSource)
    }
}
