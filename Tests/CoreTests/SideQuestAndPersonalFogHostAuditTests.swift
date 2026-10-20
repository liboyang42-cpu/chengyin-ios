import XCTest
@testable import QuestifyCore

final class SideQuestAndPersonalFogHostAuditTests: XCTestCase {

    func testDefaultOffSideQuestFeatureAcceptGate() {
        let validDisabledGate = SideQuestAndPersonalFogHostAudit.FeatureGateAuditInput(
            isEnabledByDefault: false,
            isCurrentlyEnabled: false,
            attemptsAcceptWhileDisabled: false
        )
        XCTAssertEqual(
            SideQuestAndPersonalFogHostAudit.auditFeatureGate(validDisabledGate),
            .compliant(canAccept: false)
        )

        let defaultOnViolation = SideQuestAndPersonalFogHostAudit.FeatureGateAuditInput(
            isEnabledByDefault: true,
            isCurrentlyEnabled: true
        )
        XCTAssertEqual(
            SideQuestAndPersonalFogHostAudit.auditFeatureGate(defaultOnViolation),
            .defaultNotOffViolation
        )

        let bypassAcceptViolation = SideQuestAndPersonalFogHostAudit.FeatureGateAuditInput(
            isEnabledByDefault: false,
            isCurrentlyEnabled: false,
            attemptsAcceptWhileDisabled: true
        )
        XCTAssertEqual(
            SideQuestAndPersonalFogHostAudit.auditFeatureGate(bypassAcceptViolation),
            .acceptAllowedWhileDisabledViolation
        )
    }

    func testIndependentVsThemeBoundSpawnDiscoverability() {
        let independentSpawn = SideQuestAndPersonalFogHostAudit.SpawnDiscoverabilityAuditInput(
            spawnID: "spawn-ind-01",
            themeReleaseID: nil,
            activeThemeReleaseID: nil
        )
        XCTAssertTrue(independentSpawn.isIndependentSpawn)
        XCTAssertEqual(
            SideQuestAndPersonalFogHostAudit.auditSpawnDiscoverability(independentSpawn),
            .discoverableIndependent(spawnID: "spawn-ind-01")
        )

        let matchingThemeSpawn = SideQuestAndPersonalFogHostAudit.SpawnDiscoverabilityAuditInput(
            spawnID: "spawn-theme-02",
            themeReleaseID: "theme-rel-99",
            activeThemeReleaseID: "theme-rel-99"
        )
        XCTAssertFalse(matchingThemeSpawn.isIndependentSpawn)
        XCTAssertEqual(
            SideQuestAndPersonalFogHostAudit.auditSpawnDiscoverability(matchingThemeSpawn),
            .discoverableThemeBound(spawnID: "spawn-theme-02", themeReleaseID: "theme-rel-99")
        )

        let mismatchedThemeSpawn = SideQuestAndPersonalFogHostAudit.SpawnDiscoverabilityAuditInput(
            spawnID: "spawn-theme-02",
            themeReleaseID: "theme-rel-99",
            activeThemeReleaseID: "theme-rel-10"
        )
        XCTAssertEqual(
            SideQuestAndPersonalFogHostAudit.auditSpawnDiscoverability(mismatchedThemeSpawn),
            .hiddenThemeMismatch(
                spawnID: "spawn-theme-02",
                requiredThemeReleaseID: "theme-rel-99",
                activeThemeReleaseID: "theme-rel-10"
            )
        )
    }

    func testPhotoEvidenceSubmittedAwaitingReviewNonAutoCompleteGuard() {
        let awaitingReview = SideQuestAndPersonalFogHostAudit.PhotoEvidenceSubmissionAuditInput(
            attemptID: "att-101",
            requiresPhotoEvidence: true,
            localStatusAfterUpload: .submittedAwaitingReview,
            authoritativeServerReadbackStatus: nil,
            locallyAutoCompletedBeforeServerReadback: false
        )
        XCTAssertEqual(
            SideQuestAndPersonalFogHostAudit.auditPhotoEvidenceSubmission(awaitingReview),
            .awaitingAuthoritativeReview(attemptID: "att-101")
        )

        let prematureLocalComplete = SideQuestAndPersonalFogHostAudit.PhotoEvidenceSubmissionAuditInput(
            attemptID: "att-102",
            requiresPhotoEvidence: true,
            localStatusAfterUpload: .completed,
            authoritativeServerReadbackStatus: .submittedAwaitingReview,
            locallyAutoCompletedBeforeServerReadback: true
        )
        XCTAssertEqual(
            SideQuestAndPersonalFogHostAudit.auditPhotoEvidenceSubmission(prematureLocalComplete),
            .forbiddenLocalAutoCompleteViolation(attemptID: "att-102")
        )

        let authoritativeCompleted = SideQuestAndPersonalFogHostAudit.PhotoEvidenceSubmissionAuditInput(
            attemptID: "att-103",
            requiresPhotoEvidence: true,
            localStatusAfterUpload: .submittedAwaitingReview,
            authoritativeServerReadbackStatus: .completed,
            locallyAutoCompletedBeforeServerReadback: false
        )
        XCTAssertEqual(
            SideQuestAndPersonalFogHostAudit.auditPhotoEvidenceSubmission(authoritativeCompleted),
            .completedAfterAuthoritativeReadback(attemptID: "att-103")
        )
    }

    func testUnknownOutcomeReadbackLockAndAttemptSurvivalAcrossSpawnRemoval() {
        let resilientAttempt = SideQuestAndPersonalFogHostAudit.AttemptLifecycleResilienceAuditInput(
            attemptID: "att-201",
            hasUncertainNetworkMutationOutcome: true,
            isLockedByUnknownOutcome: true,
            allowsConcurrentMutationWhileLocked: false,
            underlyingSpawnExpiredOrRemoved: true,
            activeAttemptPreservedAfterSpawnRemoval: true
        )
        XCTAssertEqual(
            SideQuestAndPersonalFogHostAudit.auditAttemptLifecycleResilience(resilientAttempt),
            .resilientAndCompliant(attemptID: "att-201", isLockedByUnknownOutcome: true)
        )

        let unlockedUnknownOutcome = SideQuestAndPersonalFogHostAudit.AttemptLifecycleResilienceAuditInput(
            attemptID: "att-202",
            hasUncertainNetworkMutationOutcome: true,
            isLockedByUnknownOutcome: false
        )
        XCTAssertEqual(
            SideQuestAndPersonalFogHostAudit.auditAttemptLifecycleResilience(unlockedUnknownOutcome),
            .missingUnknownOutcomeReadbackLockViolation(attemptID: "att-202")
        )

        let droppedOnExpiry = SideQuestAndPersonalFogHostAudit.AttemptLifecycleResilienceAuditInput(
            attemptID: "att-203",
            hasUncertainNetworkMutationOutcome: false,
            isLockedByUnknownOutcome: false,
            underlyingSpawnExpiredOrRemoved: true,
            activeAttemptPreservedAfterSpawnRemoval: false
        )
        XCTAssertEqual(
            SideQuestAndPersonalFogHostAudit.auditAttemptLifecycleResilience(droppedOnExpiry),
            .attemptDroppedOnSpawnExpiryOrRemovalViolation(attemptID: "att-203")
        )
    }

    func testPersonalFogRevealSyncDefaultOffAndDisjointCellCountsAndFullReport() {
        let validFog = SideQuestAndPersonalFogHostAudit.PersonalFogHostAuditInput(
            revealSyncEnabledByDefault: false,
            confirmedCells: ["c-1", "c-2", "c-3"],
            predictedCells: ["p-1", "p-2"]
        )
        XCTAssertEqual(
            SideQuestAndPersonalFogHostAudit.auditPersonalFogHost(validFog),
            .compliant(confirmedCount: 3, predictedCount: 2)
        )

        let overlappingFog = SideQuestAndPersonalFogHostAudit.PersonalFogHostAuditInput(
            revealSyncEnabledByDefault: false,
            confirmedCells: ["c-1", "shared-cell"],
            predictedCells: ["shared-cell", "p-2"]
        )
        XCTAssertEqual(
            SideQuestAndPersonalFogHostAudit.auditPersonalFogHost(overlappingFog),
            .overlappingConfirmedAndPredictedCellsViolation(overlap: ["shared-cell"])
        )

        let fullReport = SideQuestAndPersonalFogHostAudit.FullHostAuditReport(
            featureGateVerdict: SideQuestAndPersonalFogHostAudit.auditFeatureGate(.init()),
            spawnDiscoverabilityVerdict: SideQuestAndPersonalFogHostAudit.auditSpawnDiscoverability(
                .init(spawnID: "spawn-1", themeReleaseID: nil, activeThemeReleaseID: nil)
            ),
            photoEvidenceVerdict: SideQuestAndPersonalFogHostAudit.auditPhotoEvidenceSubmission(
                .init(attemptID: "att-1")
            ),
            attemptResilienceVerdict: SideQuestAndPersonalFogHostAudit.auditAttemptLifecycleResilience(
                .init(attemptID: "att-1", hasUncertainNetworkMutationOutcome: true, isLockedByUnknownOutcome: true)
            ),
            personalFogVerdict: SideQuestAndPersonalFogHostAudit.auditPersonalFogHost(validFog)
        )
        XCTAssertTrue(fullReport.isCompliant)
    }
}
