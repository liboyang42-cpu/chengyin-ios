import XCTest
import SwiftUI
#if canImport(QuestifyApp)
@testable import QuestifyApp
#if canImport(QuestifyCore)
import QuestifyCore
#elseif canImport(Core)
import Core
#endif
#else
@testable import Questify
#endif

@MainActor
final class CloudCIShardStatusSectionViewTests: XCTestCase {
    func testDefaultNativePipelineSnapshotCoversControlsBuildAndAllTestShards() {
        let snapshot = CIPipelineReadinessSnapshot.defaultNativePipeline
        XCTAssertEqual(snapshot.workflowPath, ".github/workflows/native-ios.yml")
        XCTAssertEqual(snapshot.rows.map(\.id), ["controls", "build", "core", "app-unit", "ui-0", "ui-1", "ui-2"])
        XCTAssertEqual(snapshot.rows.first?.runnerImage, "ubuntu-24.04")
        XCTAssertEqual(snapshot.rows.dropFirst().map(\.runnerImage), Array(repeating: "macos-26", count: 6))
        XCTAssertEqual(snapshot.passedCount, 1)
        XCTAssertEqual(snapshot.pendingCount, 6)
        XCTAssertEqual(snapshot.failedCount, 0)
        XCTAssertEqual(snapshot.summaryText, "通过 1 · 待机执行 6 · 失败 0")

        let view = CloudCIShardStatusSectionView(snapshot: snapshot)
        _ = view.body
        XCTAssertEqual(view.snapshot, snapshot)
    }

    func testCustomShardSnapshotTracksFailedAndPassedCounts() {
        let rows: [CIShardStatusRow] = [
            CIShardStatusRow(
                id: "controls",
                title: "controls",
                runnerImage: "ubuntu-24.04",
                stage: .controls,
                state: .passed,
                detail: "Structural checks passed"
            ),
            CIShardStatusRow(
                id: "build",
                title: "build",
                runnerImage: "macos-26",
                stage: .build,
                state: .passed,
                detail: "Xcode build-for-testing passed"
            ),
            CIShardStatusRow(
                id: "ui-0",
                title: "test (ui-0)",
                runnerImage: "macos-26",
                stage: .testShard,
                state: .failed,
                detail: "Shard 0 timed out"
            )
        ]
        let snapshot = CIPipelineReadinessSnapshot(workflowPath: ".github/workflows/native-ios.yml", rows: rows)
        XCTAssertEqual(snapshot.passedCount, 2)
        XCTAssertEqual(snapshot.pendingCount, 0)
        XCTAssertEqual(snapshot.failedCount, 1)
        XCTAssertEqual(rows.map(\.badgeText), ["PASSED", "PASSED", "FAILED"])

        let view = CloudCIShardStatusSectionView(snapshot: snapshot)
        _ = view.body
        XCTAssertEqual(view.snapshot.summaryText, "通过 2 · 待机执行 0 · 失败 1")
    }
}
