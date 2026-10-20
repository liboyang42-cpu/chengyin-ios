import XCTest
@testable import QuestifyCore

final class AccountDeletionAndGDPRPIPLComplianceAuditTests: XCTestCase {

    func testCanonicalStepsPassAccountDeletionAndPIPLComplianceAudit() {
        let steps = AccountDeletionAndGDPRPIPLComplianceAudit.canonicalSteps
        XCTAssertEqual(steps.count, 4)
        XCTAssertEqual(
            steps.map(\.id),
            [
                "in-app-account-cancel-entry",
                "unsettled-order-and-wallet-precheck",
                "explicit-confirmation-and-cooling-notice",
                "immediate-token-and-local-store-purge"
            ]
        )
        XCTAssertTrue(steps.allSatisfy(\.isCompliant))

        let result = AccountDeletionAndGDPRPIPLComplianceAudit.evaluate()
        XCTAssertEqual(result.totalSteps, 4)
        XCTAssertEqual(result.compliantSteps, 4)
        XCTAssertTrue(result.isAccountDeletionCompliant)
    }

    func testExternalCustomerServiceForcedCallIsRejectedPerGuideline511v() {
        var steps = AccountDeletionAndGDPRPIPLComplianceAudit.canonicalSteps
        steps[0] = AccountDeletionComplianceCheck(
            id: "in-app-account-cancel-entry",
            stepName: "In-App Account Cancel & Privacy Consent Withdrawal Entry",
            reachableInAppWithoutExternalCustomerServiceCall: false,
            checksUnsettledOrdersAndWalletBalanceBeforeDelete: true,
            wipesLocalKeychainAndJournalsImmediately: true
        )
        XCTAssertFalse(steps[0].isCompliant)

        let result = AccountDeletionAndGDPRPIPLComplianceAudit.evaluate(steps: steps)
        XCTAssertEqual(result.totalSteps, 4)
        XCTAssertEqual(result.compliantSteps, 3)
        XCTAssertFalse(result.isAccountDeletionCompliant)
    }

    func testMissingUnsettledOrderAndWalletBalancePrecheckIsRejected() {
        var steps = AccountDeletionAndGDPRPIPLComplianceAudit.canonicalSteps
        steps[1] = AccountDeletionComplianceCheck(
            id: "unsettled-order-and-wallet-precheck",
            stepName: "Unsettled Order & Wallet Balance Pre-Deletion Check",
            reachableInAppWithoutExternalCustomerServiceCall: true,
            checksUnsettledOrdersAndWalletBalanceBeforeDelete: false,
            wipesLocalKeychainAndJournalsImmediately: true
        )
        XCTAssertFalse(steps[1].isCompliant)

        let result = AccountDeletionAndGDPRPIPLComplianceAudit.evaluate(steps: steps)
        XCTAssertEqual(result.totalSteps, 4)
        XCTAssertEqual(result.compliantSteps, 3)
        XCTAssertFalse(result.isAccountDeletionCompliant)
    }

    func testIncompleteLocalStorePurgeOrEmptyStepListIsRejected() {
        var steps = AccountDeletionAndGDPRPIPLComplianceAudit.canonicalSteps
        steps[3] = AccountDeletionComplianceCheck(
            id: "immediate-token-and-local-store-purge",
            stepName: "Immediate Session Credential, Journal & Local Cache Purge",
            reachableInAppWithoutExternalCustomerServiceCall: true,
            checksUnsettledOrdersAndWalletBalanceBeforeDelete: true,
            wipesLocalKeychainAndJournalsImmediately: false
        )
        XCTAssertFalse(steps[3].isCompliant)

        let result = AccountDeletionAndGDPRPIPLComplianceAudit.evaluate(steps: steps)
        XCTAssertEqual(result.totalSteps, 4)
        XCTAssertEqual(result.compliantSteps, 3)
        XCTAssertFalse(result.isAccountDeletionCompliant)

        let emptyResult = AccountDeletionAndGDPRPIPLComplianceAudit.evaluate(steps: [])
        XCTAssertEqual(emptyResult.totalSteps, 0)
        XCTAssertEqual(emptyResult.compliantSteps, 0)
        XCTAssertFalse(emptyResult.isAccountDeletionCompliant)
    }
}
