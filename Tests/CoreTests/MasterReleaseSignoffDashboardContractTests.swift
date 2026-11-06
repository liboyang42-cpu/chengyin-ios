import XCTest
@testable import QuestifyCore

final class MasterReleaseSignoffDashboardContractTests: XCTestCase {
    func testDefaultEvaluationVerifiesAllFifteenPillarsAndFailClosedGates() {
        let report = MasterReleaseSignoffDashboardContract.evaluateMasterSignoff()

        XCTAssertTrue(report.isReadyForReleaseCandidate)
        XCTAssertEqual(report.verifiedPillarCount, 15)
        XCTAssertTrue(report.degradedPillars.isEmpty)
        XCTAssertTrue(report.allHighRiskGatesFailClosed)
        XCTAssertEqual(report.pillars.count, 15)
    }

    func testAllFifteenPillarReferenceCodesAndUnitCountsMatchSpecification() {
        let pillars = MasterReleaseSignoffDashboardContract.defaultVerifiedPillars()
        let byID = Dictionary(uniqueKeysWithValues: pillars.map { ($0.pillar, $0) })

        XCTAssertEqual(byID[.wave2TwentyOneScopes]?.requiredUnits, 21)
        XCTAssertEqual(byID[.wave2TwentyOneScopes]?.pillar.referenceCode, "w2-01..w2-21")

        XCTAssertEqual(byID[.wave3ThirteenHandoffLanes]?.requiredUnits, 13)
        XCTAssertEqual(byID[.wave3ThirteenHandoffLanes]?.pillar.referenceCode, "I00..I11 + BK")

        XCTAssertEqual(byID[.reformPlanNineteenWorkPackages]?.requiredUnits, 19)
        XCTAssertEqual(byID[.reformPlanNineteenWorkPackages]?.pillar.referenceCode, "W02..W20")

        XCTAssertEqual(byID[.unifiedDecisionsU01ToU08]?.requiredUnits, 8)
        XCTAssertEqual(byID[.mapVisualSpecMV01ToMV41]?.requiredUnits, 41)
        XCTAssertEqual(byID[.miniProgramNinetyNinePages]?.requiredUnits, 99)
        XCTAssertEqual(byID[.appStoreSubmissionReadiness]?.requiredUnits, 8)
        XCTAssertEqual(byID[.regionalEndpointAllowlist]?.pillar.referenceCode, "CN/US != 47.103.124.64")
        XCTAssertEqual(byID[.commerceWalletAndNonCashRewardSafety]?.pillar.referenceCode, "W17.4")
    }

    func testDegradedPillarOrIncompleteUnitCountBlocksReleaseCandidate() {
        var pillars = MasterReleaseSignoffDashboardContract.defaultVerifiedPillars()
        pillars[0] = MasterReleaseSignoffDashboardContract.PillarAssessment(
            pillar: .wave2TwentyOneScopes,
            status: .verified,
            completedUnits: 20,
            requiredUnits: 21,
            evidenceSummary: "缺少 1 个范围"
        )
        pillars[8] = MasterReleaseSignoffDashboardContract.PillarAssessment(
            pillar: .localizationCompleteness,
            status: .degraded,
            completedUnits: 2,
            requiredUnits: 2,
            evidenceSummary: "存在缺失翻译键"
        )

        let report = MasterReleaseSignoffDashboardContract.evaluateMasterSignoff(pillars: pillars)

        XCTAssertFalse(report.isReadyForReleaseCandidate)
        XCTAssertEqual(report.verifiedPillarCount, 13)
        XCTAssertEqual(report.degradedPillars, [.wave2TwentyOneScopes, .localizationCompleteness])
        XCTAssertTrue(report.allHighRiskGatesFailClosed)
    }

    func testViolatingAnyHighRiskFailClosedGateBlocksReleaseCandidate() {
        let unsafeGatePosture = MasterReleaseSignoffDashboardContract.HighRiskGatePosture(
            paymentAndCashDisabled: true,
            legacyHost4710312464Rejected: false,
            locationSharingDefaultOff: true,
            meetingNFCDormant: true,
            h5ContainerRejectedAsDesignOnly: true,
            unreviewedWriteEndpointsBlocked: true
        )

        let report = MasterReleaseSignoffDashboardContract.evaluateMasterSignoff(
            gatePosture: unsafeGatePosture
        )

        XCTAssertEqual(report.verifiedPillarCount, 15)
        XCTAssertFalse(report.allHighRiskGatesFailClosed)
        XCTAssertFalse(report.isReadyForReleaseCandidate)
    }
}
