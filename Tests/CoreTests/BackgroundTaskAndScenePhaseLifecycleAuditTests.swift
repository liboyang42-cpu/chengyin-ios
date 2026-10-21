import XCTest
@testable import QuestifyCore

final class BackgroundTaskAndScenePhaseLifecycleAuditTests: XCTestCase {
    func testCanonicalPoliciesPassSceneLifecycleReadiness() {
        let result = BackgroundTaskAndScenePhaseLifecycleAudit.evaluate()
        XCTAssertEqual(result.totalSubsystems, 4)
        XCTAssertEqual(result.compliantSubsystems, 4)
        XCTAssertTrue(result.isSceneLifecycleReady)
        XCTAssertEqual(
            BackgroundTaskAndScenePhaseLifecycleAudit.canonicalPolicies.map(\.subsystem),
            [
                "roam-location-and-fog-sync",
                "im-and-lead-progress-polling",
                "publish-and-journal-draft-store",
                "audio-and-tts-playback-session"
            ]
        )
        XCTAssertLessThanOrEqual(BackgroundTaskAndScenePhaseLifecycleAudit.maxBGTaskExpirationSeconds, 25.0)
    }

    func testBackgroundPollingLeakFailsCompliance() {
        var policies = BackgroundTaskAndScenePhaseLifecycleAudit.canonicalPolicies
        policies[1] = ScenePhaseLifecyclePolicyCheck(
            id: "im-and-lead-progress-polling",
            subsystem: "im-and-lead-progress-polling",
            suspendsPollingOnBackground: false,
            flushesPendingDraftsBeforeSuspend: true,
            handlesBGTaskExpirationCleanly: true
        )
        XCTAssertFalse(policies[1].isCompliant)

        let result = BackgroundTaskAndScenePhaseLifecycleAudit.evaluate(policies: policies)
        XCTAssertEqual(result.totalSubsystems, 4)
        XCTAssertEqual(result.compliantSubsystems, 3)
        XCTAssertFalse(result.isSceneLifecycleReady)
    }

    func testUnflushedDraftBeforeSuspendFailsCompliance() {
        var policies = BackgroundTaskAndScenePhaseLifecycleAudit.canonicalPolicies
        policies[2] = ScenePhaseLifecyclePolicyCheck(
            id: "publish-and-journal-draft-store",
            subsystem: "publish-and-journal-draft-store",
            suspendsPollingOnBackground: true,
            flushesPendingDraftsBeforeSuspend: false,
            handlesBGTaskExpirationCleanly: true
        )
        XCTAssertFalse(policies[2].isCompliant)

        let result = BackgroundTaskAndScenePhaseLifecycleAudit.evaluate(policies: policies)
        XCTAssertEqual(result.totalSubsystems, 4)
        XCTAssertEqual(result.compliantSubsystems, 3)
        XCTAssertFalse(result.isSceneLifecycleReady)
    }

    func testMissingBGTaskExpirationHandlerFailsCompliance() {
        var policies = BackgroundTaskAndScenePhaseLifecycleAudit.canonicalPolicies
        policies[0] = ScenePhaseLifecyclePolicyCheck(
            id: "roam-location-and-fog-sync",
            subsystem: "roam-location-and-fog-sync",
            suspendsPollingOnBackground: true,
            flushesPendingDraftsBeforeSuspend: true,
            handlesBGTaskExpirationCleanly: false
        )
        XCTAssertFalse(policies[0].isCompliant)

        let result = BackgroundTaskAndScenePhaseLifecycleAudit.evaluate(policies: policies)
        XCTAssertEqual(result.totalSubsystems, 4)
        XCTAssertEqual(result.compliantSubsystems, 3)
        XCTAssertFalse(result.isSceneLifecycleReady)
    }
}
