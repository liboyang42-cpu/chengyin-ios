import XCTest
#if canImport(QuestifyCore)
@testable import QuestifyCore
#elseif canImport(Core)
@testable import Core
#endif

final class ColdStartLaunchLatencyAndPrewarmAuditTests: XCTestCase {

    func testCanonicalStagesPassColdStartLatencyBudget() {
        let result = ColdStartLaunchLatencyAndPrewarmAudit.evaluate()
        XCTAssertEqual(result.totalStages, 4)
        XCTAssertEqual(result.compliantStages, 4)
        XCTAssertLessThanOrEqual(result.totalBudgetMs, 400)
        XCTAssertTrue(result.isColdStartFast)
    }

    func testStageBudgetOver400MsIsRejected() {
        var stages = ColdStartLaunchLatencyAndPrewarmAudit.canonicalStages
        stages[2] = ColdStartStageBudgetCheck(
            id: "first-root-view-skeleton-render",
            stageName: "first-root-view-skeleton-render",
            budgetMs: 450,
            usesLazySubsystemsOnMainActor: true,
            zeroSyncNetworkOrHeavyDiskIO: true
        )
        XCTAssertFalse(stages[2].isCompliant)

        let result = ColdStartLaunchLatencyAndPrewarmAudit.evaluate(stages: stages)
        XCTAssertEqual(result.totalStages, 4)
        XCTAssertEqual(result.compliantStages, 3)
        XCTAssertFalse(result.isColdStartFast)
    }

    func testEagerMainActorBlockingSubsystemIsDetected() {
        var stages = ColdStartLaunchLatencyAndPrewarmAudit.canonicalStages
        stages[1] = ColdStartStageBudgetCheck(
            id: "appsession-container-bootstrap",
            stageName: "appsession-container-bootstrap",
            budgetMs: 90,
            usesLazySubsystemsOnMainActor: false,
            zeroSyncNetworkOrHeavyDiskIO: true
        )
        XCTAssertFalse(stages[1].isCompliant)

        let result = ColdStartLaunchLatencyAndPrewarmAudit.evaluate(stages: stages)
        XCTAssertEqual(result.compliantStages, 3)
        XCTAssertFalse(result.isColdStartFast)
    }

    func testSynchronousNetworkOrHeavyDiskIOIsRejected() {
        var stages = ColdStartLaunchLatencyAndPrewarmAudit.canonicalStages
        stages[0] = ColdStartStageBudgetCheck(
            id: "process-main-to-questify-app-init",
            stageName: "process-main-to-questify-app-init",
            budgetMs: 80,
            usesLazySubsystemsOnMainActor: true,
            zeroSyncNetworkOrHeavyDiskIO: false
        )
        XCTAssertFalse(stages[0].isCompliant)

        let result = ColdStartLaunchLatencyAndPrewarmAudit.evaluate(stages: stages)
        XCTAssertEqual(result.compliantStages, 3)
        XCTAssertFalse(result.isColdStartFast)
    }
}
