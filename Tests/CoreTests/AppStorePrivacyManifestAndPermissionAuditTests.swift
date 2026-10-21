import XCTest
@testable import QuestifyCore

final class AppStorePrivacyManifestAndPermissionAuditTests: XCTestCase {
    func testDefaultEvaluationPassesTrackingRequiredReasonAPIsUsageDescriptionsAndW135Decoupling() {
        let report = AppStorePrivacyManifestAndPermissionAudit.evaluate()

        XCTAssertTrue(report.isCompliant)
        XCTAssertTrue(report.blockerCodes.isEmpty)
        XCTAssertFalse(report.manifest.nsPrivacyTracking)
        XCTAssertTrue(report.manifest.nsPrivacyTrackingDomains.isEmpty)
        XCTAssertTrue(report.missingAPICategories.isEmpty)
        XCTAssertTrue(report.missingUsageDescriptionKeys.isEmpty)
        XCTAssertTrue(report.w135Decoupling.isDecoupled)
    }

    func testTrackingEnabledOrNonEmptyTrackingDomainsAreRejected() {
        let trackingManifest = AppStorePrivacyManifestAndPermissionAudit.PrivacyManifestDeclaration(
            nsPrivacyTracking: true,
            nsPrivacyTrackingDomains: ["tracker.example.com"]
        )
        let report = AppStorePrivacyManifestAndPermissionAudit.evaluate(manifest: trackingManifest)

        XCTAssertFalse(report.isCompliant)
        XCTAssertTrue(report.blockerCodes.contains(.trackingEnabled))
        XCTAssertTrue(report.blockerCodes.contains(.nonEmptyTrackingDomains))
    }

    func testMissingRequiredReasonAPICategoriesAreDetected() {
        var partialCategories = AppStorePrivacyManifestAndPermissionAudit.PrivacyManifestDeclaration.standardAPIDeclarations
        partialCategories.removeValue(forKey: .systemBootTime)
        partialCategories[.diskSpace] = []

        let manifest = AppStorePrivacyManifestAndPermissionAudit.PrivacyManifestDeclaration(
            declaredAPICategories: partialCategories
        )
        let report = AppStorePrivacyManifestAndPermissionAudit.evaluate(manifest: manifest)

        XCTAssertFalse(report.isCompliant)
        XCTAssertTrue(report.blockerCodes.contains(.missingOrEmptyRequiredReasonAPI))
        XCTAssertEqual(report.missingAPICategories, [.systemBootTime, .diskSpace])
    }

    func testMissingUsageDescriptionsAndForbiddenBackgroundLocationKeysAreRejected() {
        var descriptions = AppStorePrivacyManifestAndPermissionAudit.InfoPlistPermissionPosture.standardUsageDescriptions
        descriptions.removeValue(forKey: "NSPhotoLibraryAddUsageDescription")
        descriptions["NSMicrophoneUsageDescription"] = "   "
        descriptions["NSLocationAlwaysUsageDescription"] = "Background tracking"

        let plistPosture = AppStorePrivacyManifestAndPermissionAudit.InfoPlistPermissionPosture(
            usageDescriptions: descriptions
        )
        let report = AppStorePrivacyManifestAndPermissionAudit.evaluate(infoPlistPermissions: plistPosture)

        XCTAssertFalse(report.isCompliant)
        XCTAssertTrue(report.blockerCodes.contains(.missingOrBlankUsageDescription))
        XCTAssertTrue(report.blockerCodes.contains(.forbiddenBackgroundLocationKeyPresent))
        XCTAssertEqual(report.missingUsageDescriptionKeys, [.microphone, .photoLibraryAdd])
    }

    func testW135OSLocationPermissionNeverAutoEnablesSharingOrRoamPresence() {
        let coupledState = AppStorePrivacyManifestAndPermissionAudit.W135LocationPermissionDecouplingState(
            osLocationAuthorizedWhenInUse: true,
            peerPreciseLocationShareEnabledByDefault: true,
            roamApproximatePresenceEnabledByDefault: false,
            requiresExplicitSixDisclosureConsentToShare: true
        )
        let report = AppStorePrivacyManifestAndPermissionAudit.evaluate(w135Decoupling: coupledState)

        XCTAssertFalse(report.isCompliant)
        XCTAssertEqual(report.blockerCodes, [.w135LocationPermissionCoupledToSharing])
    }
}
