import XCTest
#if canImport(QuestifyCore)
@testable import QuestifyCore
#elseif canImport(Core)
@testable import Core
#endif

final class ProductionCanaryRolloutAndPhasedReleaseContractTests: XCTestCase {

    func testCanonicalSevenDayPhasedReleaseStagesPass() {
        let result = ProductionCanaryRolloutAndPhasedReleaseContract.evaluate()
        XCTAssertEqual(result.totalStages, 7)
        XCTAssertEqual(result.compliantStages, 7)
        XCTAssertTrue(result.isCanaryPlanReady)

        let percentages = ProductionCanaryRolloutAndPhasedReleaseContract.canonicalStages.map(\.rolloutPercentage)
        XCTAssertEqual(percentages, [1, 2, 5, 10, 20, 50, 100])
    }

    func testCrashFreeThresholdUnder995PerMilleIsRejected() {
        var stages = ProductionCanaryRolloutAndPhasedReleaseContract.canonicalStages
        stages[3] = PhasedReleaseStageCheck(
            id: "phased-release-day-4",
            releaseDay: 4,
            rolloutPercentage: 10,
            minCrashFreePerMille: 990,
            supportsInstantFeatureFlagRollback: true
        )
        XCTAssertFalse(stages[3].isCompliant)

        let result = ProductionCanaryRolloutAndPhasedReleaseContract.evaluate(stages: stages)
        XCTAssertEqual(result.totalStages, 7)
        XCTAssertEqual(result.compliantStages, 6)
        XCTAssertFalse(result.isCanaryPlanReady)
    }

    func testMissingInstantFeatureFlagRollbackIsRejected() {
        var stages = ProductionCanaryRolloutAndPhasedReleaseContract.canonicalStages
        stages[5] = PhasedReleaseStageCheck(
            id: "phased-release-day-6",
            releaseDay: 6,
            rolloutPercentage: 50,
            minCrashFreePerMille: 996,
            supportsInstantFeatureFlagRollback: false
        )
        XCTAssertFalse(stages[5].isCompliant)

        let result = ProductionCanaryRolloutAndPhasedReleaseContract.evaluate(stages: stages)
        XCTAssertEqual(result.compliantStages, 6)
        XCTAssertFalse(result.isCanaryPlanReady)
    }

    func testInvalidRolloutPercentageIsRejected() {
        var stages = ProductionCanaryRolloutAndPhasedReleaseContract.canonicalStages
        stages[0] = PhasedReleaseStageCheck(
            id: "phased-release-day-1",
            releaseDay: 1,
            rolloutPercentage: 0,
            minCrashFreePerMille: 998,
            supportsInstantFeatureFlagRollback: true
        )
        XCTAssertFalse(stages[0].isCompliant)

        let result = ProductionCanaryRolloutAndPhasedReleaseContract.evaluate(stages: stages)
        XCTAssertEqual(result.compliantStages, 6)
        XCTAssertFalse(result.isCanaryPlanReady)
    }
}
