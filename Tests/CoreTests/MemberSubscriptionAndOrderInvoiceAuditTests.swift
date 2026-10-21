import XCTest
@testable import QuestifyCore

final class MemberSubscriptionAndOrderInvoiceAuditTests: XCTestCase {
    func testCanonicalChecksCoverW202ToW204AndPassEvaluation() {
        let checks = MemberSubscriptionAndOrderInvoiceAudit.canonicalChecks
        XCTAssertEqual(checks.map(\.ticketID), ["w2-02", "w2-03", "w2-04"])
        XCTAssertTrue(checks.allSatisfy(\.isCompliant))

        let result = MemberSubscriptionAndOrderInvoiceAudit.evaluate()
        XCTAssertEqual(result.totalChecks, 3)
        XCTAssertEqual(result.compliantChecks, 3)
        XCTAssertTrue(result.allStatesCovered)
        XCTAssertTrue(result.isMemberOrderReady)
    }

    func testMissingOrderLifecycleStateMarksCheckNonCompliantAndFailsEvaluation() {
        let incompleteStates: [AuditedOrderLifecycleState] = [.pending, .paid, .fulfilled, .cancelled]
        let checkMissingRefunded = MemberAndOrderAuditCheck(
            id: "order-missing-refunded",
            ticketID: "w2-03",
            coveredStates: incompleteStates,
            enforcesStoreKitForDigitalSubscriptions: true,
            supportsServerOrderReadback: true
        )
        XCTAssertFalse(checkMissingRefunded.isCompliant)

        let result = MemberSubscriptionAndOrderInvoiceAudit.evaluate(
            checks: [
                MemberSubscriptionAndOrderInvoiceAudit.canonicalChecks[0],
                checkMissingRefunded,
                MemberSubscriptionAndOrderInvoiceAudit.canonicalChecks[2],
            ]
        )
        XCTAssertEqual(result.totalChecks, 3)
        XCTAssertEqual(result.compliantChecks, 2)
        XCTAssertFalse(result.allStatesCovered)
        XCTAssertFalse(result.isMemberOrderReady)
    }

    func testStoreKitDigitalSubscriptionEnforcementIsRequiredForGuideline311Compliance() {
        let nonStoreKitCheck = MemberAndOrderAuditCheck(
            id: "member-center-bypassed-storekit",
            ticketID: "w2-02",
            coveredStates: AuditedOrderLifecycleState.allCases,
            enforcesStoreKitForDigitalSubscriptions: false,
            supportsServerOrderReadback: true
        )
        XCTAssertFalse(nonStoreKitCheck.isCompliant)

        let result = MemberSubscriptionAndOrderInvoiceAudit.evaluate(
            checks: [nonStoreKitCheck]
        )
        XCTAssertEqual(result.totalChecks, 1)
        XCTAssertEqual(result.compliantChecks, 0)
        XCTAssertTrue(result.allStatesCovered)
        XCTAssertFalse(result.isMemberOrderReady)
    }

    func testServerOrderReadbackIsRequiredForAfterSalesAndInvoiceReadiness() {
        let missingReadbackCheck = MemberAndOrderAuditCheck(
            id: "order-invoice-without-readback",
            ticketID: "w2-04",
            coveredStates: AuditedOrderLifecycleState.allCases,
            enforcesStoreKitForDigitalSubscriptions: true,
            supportsServerOrderReadback: false
        )
        XCTAssertFalse(missingReadbackCheck.isCompliant)

        let result = MemberSubscriptionAndOrderInvoiceAudit.evaluate(
            checks: [missingReadbackCheck]
        )
        XCTAssertEqual(result.totalChecks, 1)
        XCTAssertEqual(result.compliantChecks, 0)
        XCTAssertTrue(result.allStatesCovered)
        XCTAssertFalse(result.isMemberOrderReady)
    }
}
