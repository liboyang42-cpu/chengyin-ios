import XCTest
@testable import QuestifyCore

final class PlayRuntimeAndAuxiliaryBindingAuditTests: XCTestCase {

    func testW211AuxiliaryBindingAndI09LifecyclePollingEnforcement() {
        let validBinding = PlayRuntimeAndAuxiliaryBindingAudit.auditAuxiliaryBinding(
            activeRunID: "run-101",
            boundRunID: "run-101",
            isSessionActive: true,
            allowsAuxiliaryPresentation: true
        )
        XCTAssertTrue(validBinding.isCompliant)

        let crossRunBinding = PlayRuntimeAndAuxiliaryBindingAudit.auditAuxiliaryBinding(
            activeRunID: "run-101",
            boundRunID: "run-999",
            isSessionActive: false,
            allowsAuxiliaryPresentation: true
        )
        XCTAssertFalse(crossRunBinding.isCompliant)
        XCTAssertEqual(
            crossRunBinding.violations,
            [
                .auxiliaryCrossRunBinding(expectedRunID: "run-101", boundRunID: "run-999"),
                .auxiliaryActiveWhileSessionInactive
            ]
        )

        let foregroundPolling = PlayRuntimeAndAuxiliaryBindingAudit.auditLeadProgressPolling(
            isSurfaceVisible: true,
            isAppForeground: true,
            isRunActive: true,
            isPollingTaskRunning: true
        )
        XCTAssertTrue(foregroundPolling.shouldPoll)
        XCTAssertTrue(foregroundPolling.isCompliant)

        let backgroundLeak = PlayRuntimeAndAuxiliaryBindingAudit.auditLeadProgressPolling(
            isSurfaceVisible: true,
            isAppForeground: false,
            isRunActive: true,
            isPollingTaskRunning: true
        )
        XCTAssertFalse(backgroundLeak.shouldPoll)
        XCTAssertFalse(backgroundLeak.isCompliant)
        XCTAssertEqual(backgroundLeak.violations, [.pollingRemainsActiveOutsideForegroundOrActiveRun])
    }

    func testI01ArrivalAccuracy80mAdvisoryAnd100mOr30sRejection() {
        let precise = PlayRuntimeAndAuxiliaryBindingAudit.auditArrivalAccuracy(
            accuracyMeters: 42.0,
            fixAgeSeconds: 5.0
        )
        XCTAssertEqual(precise.classification, .preciseReady)
        XCTAssertFalse(precise.shows80mAdvisory)
        XCTAssertTrue(precise.dispatchesArrivalAction)
        XCTAssertTrue(precise.isCompliant)

        let advisory = PlayRuntimeAndAuxiliaryBindingAudit.auditArrivalAccuracy(
            accuracyMeters: 92.5,
            fixAgeSeconds: 12.0
        )
        XCTAssertEqual(advisory.classification, .advisoryWarning)
        XCTAssertTrue(advisory.shows80mAdvisory)
        XCTAssertTrue(advisory.dispatchesArrivalAction)
        XCTAssertTrue(advisory.isCompliant)

        let inaccurateFix = PlayRuntimeAndAuxiliaryBindingAudit.auditArrivalAccuracy(
            accuracyMeters: 125.0,
            fixAgeSeconds: 45.0,
            shows80mAdvisory: false,
            dispatchesArrivalAction: true
        )
        XCTAssertEqual(inaccurateFix.classification, .rejectedInvalidAction)
        XCTAssertFalse(inaccurateFix.isCompliant)
        XCTAssertEqual(
            inaccurateFix.violations,
            [
                .arrivalFixAcceptedDespiteInaccurateHorizontal(accuracyMeters: 125.0),
                .arrivalFixAcceptedDespiteStaleTimestamp(fixAgeSeconds: 45.0)
            ]
        )
    }

    func testI02GameCommandJournalEncryptedRecoverySlotFencing() {
        let validSlot = PlayRuntimeAndAuxiliaryBindingAudit.auditGameCommandJournalSlot(
            baseSessionKey: "cn.questify.session.u101",
            configuredGameSlotKey: "cn.questify.session.u101:game",
            journalWrittenBeforeDispatch: true,
            retainsUnknownOutcomeAcrossRelaunch: true
        )
        XCTAssertTrue(validSlot.isCompliant)
        XCTAssertEqual(validSlot.expectedGameSlotKey, "cn.questify.session.u101:game")

        let mismatchedSlot = PlayRuntimeAndAuxiliaryBindingAudit.auditGameCommandJournalSlot(
            baseSessionKey: "cn.questify.session.u101",
            configuredGameSlotKey: "cn.questify.session.u101",
            journalWrittenBeforeDispatch: false,
            retainsUnknownOutcomeAcrossRelaunch: true
        )
        XCTAssertFalse(mismatchedSlot.isCompliant)
        XCTAssertEqual(
            mismatchedSlot.violations,
            [
                .invalidGameRecoverySlotKey(
                    expected: "cn.questify.session.u101:game",
                    actual: "cn.questify.session.u101"
                ),
                .commandDispatchedWithoutPreWriteJournal
            ]
        )
    }

    func testHW03RunAuthorityCASConflictAndUnknownOutcomeLock() {
        let lockedCompliant = PlayRuntimeAndAuxiliaryBindingAudit.auditRunAuthorityCASAndLock(
            expectedStateVersion: 7,
            serverStateVersion: 8,
            pendingUnknownRequestID: "req-cas-01",
            retryRequestID: "req-cas-01",
            allowsCompetingMutation: false,
            requiresStateRefetchOnConflict: true
        )
        XCTAssertTrue(lockedCompliant.hasVersionConflict)
        XCTAssertTrue(lockedCompliant.isLockedForUnknownOutcome)
        XCTAssertTrue(lockedCompliant.isCompliant)

        let violatedLock = PlayRuntimeAndAuxiliaryBindingAudit.auditRunAuthorityCASAndLock(
            expectedStateVersion: 7,
            serverStateVersion: 8,
            pendingUnknownRequestID: "req-cas-01",
            retryRequestID: "req-cas-02",
            allowsCompetingMutation: true,
            requiresStateRefetchOnConflict: false
        )
        XCTAssertFalse(violatedLock.isCompliant)
        XCTAssertEqual(
            violatedLock.violations,
            [
                .casConflictIgnored(expectedVersion: 7, serverVersion: 8),
                .competingMutationAllowedDuringUnknownOutcomeLock(pendingRequestID: "req-cas-01"),
                .retryChangedIdempotentRequestID(originalID: "req-cas-01", retryID: "req-cas-02")
            ]
        )
    }
}
