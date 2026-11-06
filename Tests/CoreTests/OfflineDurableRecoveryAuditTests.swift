import XCTest
@testable import QuestifyCore

final class OfflineDurableRecoveryAuditTests: XCTestCase {
    func testAllThreeRecoveryPillarsAreRegisteredWithExpectedContracts() {
        let pillars = OfflineDurableRecoveryAudit.pillars
        XCTAssertEqual(pillars.map(\.pillarID), [
            .i02GameCommandJournal,
            .i06PlatformAudioAndTempSweep,
            .hw03RunAuthorityHostCoordinator
        ])

        let i02 = OfflineDurableRecoveryAudit.descriptor(for: .i02GameCommandJournal)
        XCTAssertEqual(i02?.storageSlotPattern, "<key>:game")
        XCTAssertEqual(i02?.encryptionAlgorithm, "AES.GCM")
        XCTAssertEqual(i02?.requiresAccountRealmFencing, true)
        XCTAssertEqual(i02?.preservesIdempotencyKeyAcrossRestart, true)

        let i06 = OfflineDurableRecoveryAudit.descriptor(for: .i06PlatformAudioAndTempSweep)
        XCTAssertEqual(i06?.primaryContractType, "PlatformAudioLifecyclePolicy")
        XCTAssertEqual(i06?.sweepsStaleTempArtifactsOnBoot, true)

        let hw03 = OfflineDurableRecoveryAudit.descriptor(for: .hw03RunAuthorityHostCoordinator)
        XCTAssertEqual(hw03?.primaryContractType, "RunAuthorityHostCoordinator")
        XCTAssertEqual(hw03?.detectsCASStateVersionConflict, true)
        XCTAssertEqual(hw03?.enforcesUnknownOutcomeLockBeforeRetry, true)
    }

    func testGameRecoverySlotFenceRejectsCrossAccountAndCrossRealmAccess() {
        let slotKey = OfflineDurableRecoveryAudit.makeGameRecoverySlotKey(baseKey: "acct-42:prod:act-99")
        XCTAssertEqual(slotKey, "acct-42:prod:act-99:game")

        let accepted = OfflineDurableRecoveryAudit.evaluateSlotFence(
            slotKey: slotKey,
            slotAccountID: 42,
            slotRealm: "prod",
            activeAccountID: 42,
            activeRealm: "prod",
            preservedRequestID: "req-idemp-001"
        )
        XCTAssertEqual(accepted, .accepted(slotKey: slotKey, preservedRequestID: "req-idemp-001"))

        let crossAccount = OfflineDurableRecoveryAudit.evaluateSlotFence(
            slotKey: slotKey,
            slotAccountID: 42,
            slotRealm: "prod",
            activeAccountID: 77,
            activeRealm: "prod",
            preservedRequestID: "req-idemp-001"
        )
        XCTAssertEqual(crossAccount, .rejectedAccountMismatch(expectedAccountID: 77, actualAccountID: 42))

        let crossRealm = OfflineDurableRecoveryAudit.evaluateSlotFence(
            slotKey: slotKey,
            slotAccountID: 42,
            slotRealm: "prod",
            activeAccountID: 42,
            activeRealm: "staging",
            preservedRequestID: "req-idemp-001"
        )
        XCTAssertEqual(crossRealm, .rejectedRealmMismatch(expectedRealm: "staging", actualRealm: "prod"))
    }

    func testUnknownOutcomeLockAndCASStateVersionConflictInvariants() {
        let locked = OfflineDurableRecoveryAudit.evaluateUnknownOutcomeRetry(
            hasUnresolvedPendingSlot: true,
            preservedRequestID: "req-idemp-002",
            localStateVersion: 12,
            authoritativeRemoteStateVersion: nil
        )
        XCTAssertEqual(
            locked,
            .lockedPendingAuthoritativeReadback(preservedRequestID: "req-idemp-002", expectedStateVersion: 12)
        )

        let conflict = OfflineDurableRecoveryAudit.evaluateUnknownOutcomeRetry(
            hasUnresolvedPendingSlot: true,
            preservedRequestID: "req-idemp-002",
            localStateVersion: 12,
            authoritativeRemoteStateVersion: 14
        )
        XCTAssertEqual(
            conflict,
            .requiresAuthoritativeSnapshotRecovery(localStateVersion: 12, remoteStateVersion: 14)
        )

        let fresh = OfflineDurableRecoveryAudit.evaluateUnknownOutcomeRetry(
            hasUnresolvedPendingSlot: false,
            preservedRequestID: "req-idemp-003",
            localStateVersion: 14,
            authoritativeRemoteStateVersion: 14
        )
        XCTAssertEqual(fresh, .allowFreshDispatch)
    }

    func testAudioLifecycleFailSafeAndStaleTempFileSweep() {
        let result = OfflineDurableRecoveryAudit.evaluateAudioInterruptionAndTempSweep(
            signal: .interruptionBegan,
            ownsConfiguration: true,
            candidateFileNames: ["voice-01.m4a", "recording-partial.tmp", "journal-write.tmp", "avatar.png"]
        )
        XCTAssertEqual(result.audioAction, .stop)
        XCTAssertEqual(result.staleTempFilesToSweep, ["recording-partial.tmp", "journal-write.tmp"])

        let resumeIgnored = OfflineDurableRecoveryAudit.evaluateAudioInterruptionAndTempSweep(
            signal: .interruptionEnded(shouldResume: true),
            ownsConfiguration: true,
            candidateFileNames: []
        )
        XCTAssertEqual(resumeIgnored.audioAction, .ignore)
        XCTAssertTrue(resumeIgnored.staleTempFilesToSweep.isEmpty)
    }
}
