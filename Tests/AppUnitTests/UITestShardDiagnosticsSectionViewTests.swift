@testable import QuestifyApp
import QuestifyCore
import XCTest

@MainActor
final class UITestShardDiagnosticsSectionViewTests: XCTestCase {
    func testDefaultShardsAndFixturesAreHealthyAndIsolated() {
        let view = UITestShardDiagnosticsSectionView()
        _ = view.body

        XCTAssertTrue(view.hasCompleteThreeShardCoverage)
        XCTAssertTrue(view.allShardsHealthy)
        XCTAssertTrue(view.allFixturesIsolated)
        XCTAssertEqual(view.shards.map(\.shardID), ["ui-0", "ui-1", "ui-2"])
        XCTAssertEqual(view.totalAssignedMethodCount, 143)
        XCTAssertTrue(view.statusHeadline.contains("ui-0/ui-1/ui-2"))
    }

    func testIncompleteOrFailingShardsReportUnhealthyState() {
        let missingThirdShard = Array(UITestShardDiagnosticsSectionView.defaultShards.prefix(2))
        let incompleteView = UITestShardDiagnosticsSectionView(shards: missingThirdShard)
        _ = incompleteView.body

        XCTAssertFalse(incompleteView.hasCompleteThreeShardCoverage)
        XCTAssertFalse(incompleteView.allShardsHealthy)
        XCTAssertTrue(incompleteView.statusHeadline.contains("分片不完整"))

        var failingShards = UITestShardDiagnosticsSectionView.defaultShards
        failingShards[1] = UITestShardSummaryRow(
            shardID: "ui-1",
            methodCount: 48,
            passedCount: 47,
            failedCount: 1,
            usesTestWithoutBuilding: true
        )
        let failingView = UITestShardDiagnosticsSectionView(shards: failingShards)
        _ = failingView.body

        XCTAssertTrue(failingView.hasCompleteThreeShardCoverage)
        XCTAssertFalse(failingView.allShardsHealthy)
        XCTAssertFalse(failingView.shards[1].isHealthy)
        XCTAssertTrue(failingView.statusHeadline.contains("test-without-building"))
    }

    func testFixtureWithoutSessionShortCircuitOrZeroNetworkFailsIsolationCheck() {
        let leakyFixture = UITestFixtureShortCircuitRow(
            launchFlag: "--leaky-fixture",
            surfaceTitle: "LeakyFixtureHost",
            bypassesSessionBootstrap: false,
            enforcesZeroNetwork: true
        )
        let view = UITestShardDiagnosticsSectionView(
            shards: UITestShardDiagnosticsSectionView.defaultShards,
            fixtures: [leakyFixture],
            zeroNetworkVerified: true
        )
        _ = view.body

        XCTAssertFalse(leakyFixture.isIsolated)
        XCTAssertFalse(view.allFixturesIsolated)
        XCTAssertTrue(view.statusHeadline.contains("session = nil"))

        let unverifiedNetworkView = UITestShardDiagnosticsSectionView(
            shards: UITestShardDiagnosticsSectionView.defaultShards,
            fixtures: UITestShardDiagnosticsSectionView.defaultFixtures,
            zeroNetworkVerified: false
        )
        _ = unverifiedNetworkView.body
        XCTAssertFalse(unverifiedNetworkView.allFixturesIsolated)
    }
}
