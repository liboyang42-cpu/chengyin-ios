import XCTest
@testable import QuestifyCore

final class XcodeGenAndProjectScaffoldIntegrityAuditTests: XCTestCase {

    func testFiveCanonicalTargetsCompletenessAndSourceRoots() {
        let eval = XcodeGenAndProjectScaffoldIntegrityAudit.auditTargetTopology()
        XCTAssertTrue(eval.hasAllFiveCanonicalTargets)
        XCTAssertTrue(eval.isCompliant)
        XCTAssertEqual(
            eval.presentTargets,
            [
                "QuestifyCore",
                "QuestifyApp",
                "QuestifyCoreTests",
                "QuestifyAppUnitTests",
                "QuestifyUITests"
            ]
        )
        XCTAssertEqual(XcodeGenAndProjectScaffoldIntegrityAudit.CanonicalTarget.questifyCore.sourceRootDirectory, "Core")
        XCTAssertEqual(XcodeGenAndProjectScaffoldIntegrityAudit.CanonicalTarget.questifyApp.sourceRootDirectory, "App")
        XCTAssertFalse(XcodeGenAndProjectScaffoldIntegrityAudit.CanonicalTarget.questifyApp.isTestTarget)
        XCTAssertTrue(XcodeGenAndProjectScaffoldIntegrityAudit.CanonicalTarget.questifyAppUnitTests.isTestTarget)

        let missingEval = XcodeGenAndProjectScaffoldIntegrityAudit.auditTargetTopology(
            presentTargets: ["QuestifyCore", "QuestifyApp"]
        )
        XCTAssertFalse(missingEval.hasAllFiveCanonicalTargets)
        XCTAssertFalse(missingEval.isCompliant)
        XCTAssertEqual(
            missingEval.missingTargets,
            ["QuestifyCoreTests", "QuestifyAppUnitTests", "QuestifyUITests"]
        )
    }

    func testDuplicateSwiftBasenameInSameTargetIsRejectedCaseInsensitively() {
        let eval = XcodeGenAndProjectScaffoldIntegrityAudit.auditTargetTopology(
            swiftFilesByTarget: [
                "QuestifyApp": [
                    "App/RoamHomeView.swift",
                    "Core/roamhomeview.swift",
                    "App/UniqueView.swift"
                ]
            ]
        )
        XCTAssertFalse(eval.isCompliant)
        XCTAssertEqual(eval.duplicateStemsByTarget["QuestifyApp"], ["roamhomeview"])
        XCTAssertEqual(
            eval.violations,
            [.duplicateSwiftBasenames(target: "QuestifyApp", stems: ["roamhomeview"])]
        )
    }

    func testProjectPbxprojDriftAndUnreferencedSwiftSourcesAreRejected() {
        let clean = XcodeGenAndProjectScaffoldIntegrityAudit.auditProjectZeroDrift(
            committedPbxprojDigest: "sha256:abc123",
            generatedPbxprojDigest: "sha256:abc123",
            diskSwiftFiles: ["App/QuestifyApp.swift", "Core/TeamPagePresentation.swift"],
            pbxprojReferencedSwiftFiles: ["App/QuestifyApp.swift", "Core/TeamPagePresentation.swift"]
        )
        XCTAssertTrue(clean.isZeroDrift)
        XCTAssertTrue(clean.isCompliant)
        XCTAssertTrue(clean.violations.isEmpty)

        let drifted = XcodeGenAndProjectScaffoldIntegrityAudit.auditProjectZeroDrift(
            committedPbxprojDigest: "sha256:abc123",
            generatedPbxprojDigest: "sha256:def456",
            diskSwiftFiles: ["App/QuestifyApp.swift", "Core/OrphanedFile.swift"],
            pbxprojReferencedSwiftFiles: ["App/QuestifyApp.swift"]
        )
        XCTAssertFalse(drifted.isZeroDrift)
        XCTAssertFalse(drifted.isCompliant)
        XCTAssertEqual(drifted.unreferencedSwiftFiles, ["Core/OrphanedFile.swift"])
        XCTAssertEqual(
            drifted.violations,
            [
                .pbxprojDriftDetected(committedDigest: "sha256:abc123", generatedDigest: "sha256:def456"),
                .unreferencedSwiftSources(["Core/OrphanedFile.swift"])
            ]
        )
    }

    func testLocalizationScriptsAndBilingualCatalogCompletenessVerification() {
        let validCatalog: [String: [XcodeGenAndProjectScaffoldIntegrityAudit.LocalizationCatalogEntry]] = [
            "RoamPrivateTools": [
                .init(key: "roam.capsule.title", englishValue: "Time Capsule", simplifiedChineseValue: "时间胶囊")
            ],
            "MerchantStoreParity": [
                .init(key: "merchant.shop.apply", englishValue: "Store Application", simplifiedChineseValue: "门店入驻申请")
            ]
        ]
        let compliant = XcodeGenAndProjectScaffoldIntegrityAudit.auditLocalizationAndTooling(
            roamPrivateToolsCheckPassed: true,
            catalogsByTable: validCatalog
        )
        XCTAssertTrue(compliant.isCompliant)
        XCTAssertTrue(compliant.missingScripts.isEmpty)

        let incompleteCatalog: [String: [XcodeGenAndProjectScaffoldIntegrityAudit.LocalizationCatalogEntry]] = [
            "RoamPrivateTools": [
                .init(key: "roam.capsule.missingZh", englishValue: "Time Capsule", simplifiedChineseValue: "   ")
            ]
        ]
        let failed = XcodeGenAndProjectScaffoldIntegrityAudit.auditLocalizationAndTooling(
            presentScripts: ["tools/generate_project.py"],
            roamPrivateToolsCheckPassed: false,
            catalogsByTable: incompleteCatalog
        )
        XCTAssertFalse(failed.isCompliant)
        XCTAssertEqual(failed.incompleteKeysByTable["RoamPrivateTools"], ["roam.capsule.missingZh"])
        XCTAssertTrue(failed.violations.contains(.roamPrivateToolsCheckFailed))
    }
}
