import SwiftUI
import XCTest
#if canImport(Questify)
@testable import Questify
#elseif canImport(QuestifyApp)
@testable import QuestifyApp
#endif
#if canImport(QuestifyCore)
@testable import QuestifyCore
#endif

@MainActor final class SideQuestAndPersonalFogAuditSectionViewTests: XCTestCase {
    func testStandardSnapshotEnforcesPhotoEvidenceGuardUnknownReadbackLockAttemptSurvivalAndDefaultOffFogSync() {
        let snapshot = SideQuestAndPersonalFogAuditSnapshot.standard
        XCTAssertEqual(snapshot.rows.count, 4)
        XCTAssertEqual(snapshot.enforcedRowCount, 4)
        XCTAssertTrue(snapshot.isCompliant)
        XCTAssertFalse(snapshot.sideQuestAcceptFeatureEnabled)
        XCTAssertFalse(snapshot.photoEvidenceAwaitingReviewAutoCompleted)
        XCTAssertTrue(snapshot.unknownOutcomeBlocksNewAccepts)
        XCTAssertEqual(snapshot.survivedAttemptsCountAfterSpawnRemoval, 1)
        XCTAssertFalse(snapshot.personalFogRevealSyncEnabled)
        XCTAssertEqual(
            snapshot.rows.map(\.kind),
            [
                .photoEvidenceNonAutoCompleteGuard,
                .unknownAcceptOutcomeReadbackLock,
                .attemptSurvivalAcrossSpawnRemoval,
                .personalFogDefaultOffSync,
            ]
        )
        XCTAssertEqual(
            snapshot.rows.map(\.id),
            [
                "photo-evidence-guard",
                "unknown-accept-readback-lock",
                "attempt-survival-across-removal",
                "personal-fog-default-off-sync",
            ]
        )

        let view = SideQuestAndPersonalFogAuditSectionView(snapshot: snapshot)
        _ = view.body
    }

    func testNonCompliantSnapshotsAreFlaggedAndRenderCleanly() {
        let autoCompletedPhotoSnapshot = SideQuestAndPersonalFogAuditSnapshot(
            photoEvidenceAwaitingReviewAutoCompleted: true
        )
        XCTAssertFalse(autoCompletedPhotoSnapshot.isCompliant)
        _ = SideQuestAndPersonalFogAuditSectionView(snapshot: autoCompletedPhotoSnapshot).body

        let bypassedUnknownLockSnapshot = SideQuestAndPersonalFogAuditSnapshot(
            unknownOutcomeBlocksNewAccepts: false
        )
        XCTAssertFalse(bypassedUnknownLockSnapshot.isCompliant)
        _ = SideQuestAndPersonalFogAuditSectionView(snapshot: bypassedUnknownLockSnapshot).body

        let fogSyncEnabledSnapshot = SideQuestAndPersonalFogAuditSnapshot(
            personalFogRevealSyncEnabled: true
        )
        XCTAssertFalse(fogSyncEnabledSnapshot.isCompliant)
        _ = SideQuestAndPersonalFogAuditSectionView(snapshot: fogSyncEnabledSnapshot).body
    }
}
