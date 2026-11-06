import XCTest
@testable import QuestifyCore

final class RoamAndExplorationParityAuditTests: XCTestCase {
    func testBaselineAuditPassesAllFivePillars() {
        let report = RoamAndExplorationParityAudit.runAudit()
        XCTAssertTrue(report.isPassing)
        XCTAssertEqual(report.auditedPillars, RoamAndExplorationParityPillar.allCases)
        XCTAssertTrue(report.violations.isEmpty)
        XCTAssertFalse(PersonalFogFeature.revealSyncEnabled)
    }

    func testE0617StatusClassificationDistinguishes404And410GoneFrom503Error() {
        XCTAssertEqual(RoamAndExplorationParityAudit.classifySubpageStatus(code: 200), .ok)
        XCTAssertEqual(RoamAndExplorationParityAudit.classifySubpageStatus(code: 404), .gone)
        XCTAssertEqual(RoamAndExplorationParityAudit.classifySubpageStatus(code: 410), .gone)
        XCTAssertEqual(RoamAndExplorationParityAudit.classifySubpageStatus(code: 503), .error)
        XCTAssertEqual(RoamAndExplorationParityAudit.classifySubpageStatus(code: 500), .error)
    }

    func testI01ArrivalSampleThresholdsEnforce80mAdvisoryAnd100mOr30sInvalidAction() {
        XCTAssertEqual(
            RoamAndExplorationParityAudit.evaluateArrivalSample(accuracyMeters: 45, ageSeconds: 10),
            .qualified
        )
        XCTAssertEqual(
            RoamAndExplorationParityAudit.evaluateArrivalSample(accuracyMeters: 80, ageSeconds: 30),
            .qualified
        )
        XCTAssertEqual(
            RoamAndExplorationParityAudit.evaluateArrivalSample(accuracyMeters: 85, ageSeconds: 12),
            .advisoryWarning
        )
        XCTAssertEqual(
            RoamAndExplorationParityAudit.evaluateArrivalSample(accuracyMeters: 100, ageSeconds: 25),
            .advisoryWarning
        )
        XCTAssertEqual(
            RoamAndExplorationParityAudit.evaluateArrivalSample(accuracyMeters: 101, ageSeconds: 10),
            .invalidAction
        )
        XCTAssertEqual(
            RoamAndExplorationParityAudit.evaluateArrivalSample(accuracyMeters: 35, ageSeconds: 31),
            .invalidAction
        )
        XCTAssertEqual(
            RoamAndExplorationParityAudit.evaluateArrivalSample(accuracyMeters: -1, ageSeconds: 5),
            .invalidAction
        )
    }

    func testAuditFlagsMissingSubpagesDriftAndEnabledRevealSync() {
        let brokenEntries: [RoamExplorationPillarAuditEntry] = [
            RoamExplorationPillarAuditEntry(
                pillar: .w208RoamEntryMerchantAndSubpages,
                verifiedTypes: ["RoamSubpagePresentation"],
                e0617GoneMappedCorrectly: false
            ),
            RoamExplorationPillarAuditEntry(
                pillar: .w209PassportPrivateTools,
                verifiedTypes: ["RoamPassportPrivateToolsReading"],
                privateToolSubpagesCovered: [.capsule, .explorationGoals]
            ),
            RoamExplorationPillarAuditEntry(
                pillar: .fW14W15StoryWalkingAndFog,
                verifiedTypes: ["StoryWalkingNavigationHostBridge", "PersonalFogRoamOverlayProjection"],
                arrivalOpensVerificationOnly: false,
                revealSyncEnabledByDefault: true
            )
        ]

        let report = RoamAndExplorationParityAudit.runAudit(entries: brokenEntries)
        XCTAssertFalse(report.isPassing)
        XCTAssertTrue(report.violations.contains(.missingPillar(.i00I11ReceivedStamps)))
        XCTAssertTrue(report.violations.contains(.missingPillar(.i01PlayArrivalAccuracy)))
        XCTAssertTrue(report.violations.contains(.e0617MappingDrift))
        XCTAssertTrue(report.violations.contains(
            .missingPrivateToolSubpages([.explorationExport, .anniversary, .monthlyRecap])
        ))
        XCTAssertTrue(report.violations.contains(.arrivalAutoCompletesInsteadOfVerification))
        XCTAssertTrue(report.violations.contains(.revealSyncUnexpectedlyEnabled))
    }
}
