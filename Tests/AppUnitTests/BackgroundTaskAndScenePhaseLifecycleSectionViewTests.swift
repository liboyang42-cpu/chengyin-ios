@testable import QuestifyApp
import QuestifyCore
import XCTest

@MainActor
final class BackgroundTaskAndScenePhaseLifecycleSectionViewTests: XCTestCase {
    func testDefaultReadySnapshotPassesAllScenePhaseAndBGTaskChecks() {
        let view = BackgroundTaskAndScenePhaseLifecycleSectionView(snapshot: .defaultReady)
        _ = view.body

        XCTAssertTrue(view.snapshot.isReady)
        XCTAssertFalse(view.snapshot.hasBackgroundPollingLeak)
        XCTAssertEqual(view.snapshot.activePollingCountInBackground, 0)
        XCTAssertEqual(view.snapshot.pendingUnflushedDraftCount, 0)
        XCTAssertTrue(view.snapshot.bgTaskExpirationHandlerRegistered)
        XCTAssertEqual(
            view.snapshot.rows.map(\.subsystemID),
            ["walking-gps-polling", "content-draft-autosave", "bgtask-expiration-fence"]
        )
        XCTAssertTrue(view.statusHeadline.contains("BGTask"))
    }

    func testBackgroundPollingLeakTriggersWarningState() {
        let leakySnapshot = ScenePhaseLifecycleSnapshot(
            activePollingCountInBackground: 2,
            pendingUnflushedDraftCount: 0,
            bgTaskExpirationHandlerRegistered: true
        )
        let view = BackgroundTaskAndScenePhaseLifecycleSectionView(snapshot: leakySnapshot)
        _ = view.body

        XCTAssertTrue(view.snapshot.hasBackgroundPollingLeak)
        XCTAssertFalse(view.snapshot.isReady)
        XCTAssertTrue(view.statusHeadline.contains("后台轮询泄漏告警"))
    }

    func testUnflushedDraftsAndMissingBGTaskHandlerReportNonReadyState() {
        let unflushedSnapshot = ScenePhaseLifecycleSnapshot(
            activePollingCountInBackground: 0,
            pendingUnflushedDraftCount: 1,
            bgTaskExpirationHandlerRegistered: true
        )
        let unflushedView = BackgroundTaskAndScenePhaseLifecycleSectionView(snapshot: unflushedSnapshot)
        _ = unflushedView.body

        XCTAssertFalse(unflushedView.snapshot.isReady)
        XCTAssertTrue(unflushedView.statusHeadline.contains("草稿落盘告警"))

        let missingHandlerSnapshot = ScenePhaseLifecycleSnapshot(
            activePollingCountInBackground: 0,
            pendingUnflushedDraftCount: 0,
            bgTaskExpirationHandlerRegistered: false
        )
        let handlerView = BackgroundTaskAndScenePhaseLifecycleSectionView(snapshot: missingHandlerSnapshot)
        _ = handlerView.body

        XCTAssertFalse(handlerView.snapshot.isReady)
        XCTAssertTrue(handlerView.statusHeadline.contains("BGTask"))
    }
}
