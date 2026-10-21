import XCTest
@testable import QuestifyCore

final class AppStoreSubmissionReadinessAuditTests: XCTestCase {
    private var validInfoPlist: [String: String] {
        [
            "NSLocationWhenInUseUsageDescription": "Use your location while exploring nearby city points and verifying check-in distance.",
            "NSCameraUsageDescription": "Use the camera to scan QR codes or take aftercare evidence photos when you choose.",
            "NSMicrophoneUsageDescription": "Record voice clues or audio stories only when you actively hold the record button.",
            "NSPhotoLibraryUsageDescription": "Select photos or videos from your library when composing a post or theme draft.",
            "NSPhotoLibraryAddUsageDescription": "Save a walk card to Photos when you choose Save to Photos."
        ]
    }

    private var compliantDeletionPolicy: AppStoreSubmissionReadinessAudit.DeletionCompliancePolicy {
        .init(
            inAppAccountDeletionEntryAvailable: true,
            accountDeletionRequiresExplicitConfirmation: true,
            accountDeletionRevokesLocalSessionOnReceipt: true,
            npcChatLocalClearAvailable: true,
            npcChatRemoteDeleteEnabled: false,
            npcChatRemoteDeleteEndpointApproved: false
        )
    }

    private var compliantUGCPolicy: AppStoreSubmissionReadinessAudit.UGCSafetyAndCacheEvictionPolicy {
        .init(
            evictsCachedMediaOnHTTP404: true,
            evictsCachedMediaOnDeletedState: true,
            squareReportEntryAvailable: true,
            squareBlockAuthorAvailable: true,
            squareModerationGateEnabled: true,
            imReportConversationAvailable: true,
            imBlockPeerAvailable: true
        )
    }

    func testAllEightSubmissionChecksPassWithCompliantConfiguration() {
        let report = AppStoreSubmissionReadinessAudit.evaluate(
            infoPlist: validInfoPlist,
            deletionPolicy: compliantDeletionPolicy,
            ledgerPolicy: .compliantDefault,
            ugcPolicy: compliantUGCPolicy,
            signInPolicy: .failClosedDefault
        )

        XCTAssertTrue(report.isReadyForSubmission)
        XCTAssertEqual(report.passedChecks, AppStoreSubmissionReadinessAudit.CheckID.allCases)
        XCTAssertTrue(report.failedChecks.isEmpty)
        XCTAssertTrue(report.violations.isEmpty)
    }

    func testPrivacyUsageDescriptionsRejectMissingEmptyBuildVariableAndPlaceholderValues() {
        var brokenPlist = validInfoPlist
        brokenPlist.removeValue(forKey: "NSLocationWhenInUseUsageDescription")
        brokenPlist["NSCameraUsageDescription"] = "   "
        brokenPlist["NSMicrophoneUsageDescription"] = "TODO: fill microphone string"
        brokenPlist["NSPhotoLibraryUsageDescription"] = "$(CUSTOM_PHOTO_DESC)"

        let report = AppStoreSubmissionReadinessAudit.evaluate(
            infoPlist: brokenPlist,
            deletionPolicy: compliantDeletionPolicy,
            ugcPolicy: compliantUGCPolicy
        )

        XCTAssertFalse(report.isReadyForSubmission)
        XCTAssertEqual(report.failedChecks, [.iosRel01PrivacyUsageDescriptions])
        XCTAssertEqual(
            report.violations,
            [
                .missingOrInvalidPrivacyUsageKeys([
                    .locationWhenInUse,
                    .camera,
                    .microphone,
                    .photoLibrary
                ])
            ]
        )
    }

    func testAccountAndNPCChatDeletionPlusUGCCacheEvictionGatesFailClosed() {
        let badDeletion = AppStoreSubmissionReadinessAudit.DeletionCompliancePolicy(
            inAppAccountDeletionEntryAvailable: true,
            accountDeletionRequiresExplicitConfirmation: false,
            accountDeletionRevokesLocalSessionOnReceipt: true,
            npcChatLocalClearAvailable: true,
            npcChatRemoteDeleteEnabled: true,
            npcChatRemoteDeleteEndpointApproved: false
        )
        let badUGC = AppStoreSubmissionReadinessAudit.UGCSafetyAndCacheEvictionPolicy(
            evictsCachedMediaOnHTTP404: true,
            evictsCachedMediaOnDeletedState: false,
            squareReportEntryAvailable: true,
            squareBlockAuthorAvailable: false,
            squareModerationGateEnabled: true,
            imReportConversationAvailable: false,
            imBlockPeerAvailable: true
        )

        let report = AppStoreSubmissionReadinessAudit.evaluate(
            infoPlist: validInfoPlist,
            deletionPolicy: badDeletion,
            ugcPolicy: badUGC
        )

        XCTAssertFalse(report.isReadyForSubmission)
        XCTAssertEqual(
            report.failedChecks,
            [
                .iosRel02AccountDeletionGate,
                .iosRel03NPCChatLogDeletionGate,
                .iosRel05DeletedMediaCacheEviction,
                .iosRel06SquareUGCModeration,
                .iosRel07IMConversationSafety
            ]
        )
    }

    func testNonCashLedgerRejectsWithdrawableTransferableOrCashRedeemableAssets() {
        let violatingLedger = AppStoreSubmissionReadinessAudit.NonCashRewardLedgerPolicy(
            rules: [
                .init(kind: .points, withdrawable: true),
                .init(kind: .stamps, transferable: true),
                .init(kind: .fragments, redeemableForCash: true)
                // `.seasonScores` intentionally omitted to verify missing-asset detection as well.
            ]
        )

        let report = AppStoreSubmissionReadinessAudit.evaluate(
            infoPlist: validInfoPlist,
            deletionPolicy: compliantDeletionPolicy,
            ledgerPolicy: violatingLedger,
            ugcPolicy: compliantUGCPolicy
        )

        XCTAssertFalse(report.isReadyForSubmission)
        XCTAssertEqual(report.failedChecks, [.iosRel04NonCashRewardLedger])
        XCTAssertEqual(
            report.violations,
            [.nonCashRewardLedgerViolations([.points, .stamps, .fragments, .seasonScores])]
        )
    }

    func testSignInWithAppleParityGateEnforcesThirdPartyLoginRestrictions() {
        let wechatWithoutApple = AppStoreSubmissionReadinessAudit.SignInParityPolicy(
            wechatSignInEnabled: true,
            otherThirdPartySignInEnabled: false,
            appleSignInEnabled: false,
            appleSignInEntitlementConfigured: false
        )
        let reportWithoutApple = AppStoreSubmissionReadinessAudit.evaluate(
            infoPlist: validInfoPlist,
            deletionPolicy: compliantDeletionPolicy,
            ugcPolicy: compliantUGCPolicy,
            signInPolicy: wechatWithoutApple
        )
        XCTAssertFalse(reportWithoutApple.isReadyForSubmission)
        XCTAssertEqual(reportWithoutApple.failedChecks, [.iosRel08SignInWithAppleParity])
        XCTAssertEqual(reportWithoutApple.violations, [.signInWithAppleParityViolated])

        let appleWithoutEntitlement = AppStoreSubmissionReadinessAudit.SignInParityPolicy(
            wechatSignInEnabled: true,
            otherThirdPartySignInEnabled: false,
            appleSignInEnabled: true,
            appleSignInEntitlementConfigured: false
        )
        XCTAssertFalse(appleWithoutEntitlement.isCompliant)

        let bothEnabledAndConfigured = AppStoreSubmissionReadinessAudit.SignInParityPolicy(
            wechatSignInEnabled: true,
            otherThirdPartySignInEnabled: true,
            appleSignInEnabled: true,
            appleSignInEntitlementConfigured: true
        )
        let passingParityReport = AppStoreSubmissionReadinessAudit.evaluate(
            infoPlist: validInfoPlist,
            deletionPolicy: compliantDeletionPolicy,
            ugcPolicy: compliantUGCPolicy,
            signInPolicy: bothEnabledAndConfigured
        )
        XCTAssertTrue(passingParityReport.isReadyForSubmission)
    }
}
