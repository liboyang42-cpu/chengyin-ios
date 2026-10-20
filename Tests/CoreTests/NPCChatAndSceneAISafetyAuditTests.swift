import XCTest
@testable import QuestifyCore

final class NPCChatAndSceneAISafetyAuditTests: XCTestCase {
    private let isolationKey = "16:STORE_PUBLIC_NPC11:merchant-018:store-01"

    func testDefaultFailClosedAvailabilityAndRemoteDeleteGates() {
        let report = NPCChatAndSceneAISafetyAudit.audit(
            isolationKey: isolationKey,
            sceneAIDefaultDisabled: true,
            allowsStreamingDisplay: false,
            remoteChatDeleteGateEnabled: false,
            remoteChatDeleteApproved: false
        )
        XCTAssertTrue(report.isSafetyCompliant)
        XCTAssertTrue(report.sceneAIDefaultDisabled)
        XCTAssertTrue(report.isNonGenerativeBadgeActive)
        XCTAssertTrue(report.isStreamingOffBadgeActive)
        XCTAssertFalse(report.remoteChatDeleteGateEnabled)
        XCTAssertEqual(NPCChatAndSceneAISafetyAudit.remoteChatDeleteRoute, "/api/npc/chat/delete")

        let unapprovedDeleteReport = NPCChatAndSceneAISafetyAudit.audit(
            isolationKey: isolationKey,
            sceneAIDefaultDisabled: true,
            allowsStreamingDisplay: true,
            remoteChatDeleteGateEnabled: true,
            remoteChatDeleteApproved: false
        )
        XCTAssertFalse(unapprovedDeleteReport.isSafetyCompliant)
        XCTAssertEqual(
            unapprovedDeleteReport.violations,
            [
                .streamingDisplayEnabled,
                .unapprovedRemoteChatDeleteEnabled
            ]
        )
    }

    func testSensitiveDataClassesAreRejectedFromNPCChatPrompts() {
        let report = NPCChatAndSceneAISafetyAudit.audit(
            isolationKey: isolationKey,
            requestedDataClasses: [
                .approvedStoreFacts,
                .unlockedClues,
                .coordinates,
                .contactInfo,
                .paymentCredentials,
                .otherPlayerMemory
            ]
        )

        XCTAssertTrue(report.isSafetyCompliant)
        XCTAssertEqual(
            report.rejectedDataClasses,
            [
                .contactInfo,
                .coordinates,
                .otherPlayerMemory,
                .paymentCredentials
            ]
        )
    }

    func testReplyValidationDropsForbiddenAuthorityEffectsAndKeepsNarrativeActions() {
        let report = NPCChatAndSceneAISafetyAudit.audit(
            isolationKey: isolationKey,
            proposedEffects: [
                .presentUnlockedClue,
                .walletMutation,
                .inventoryMutation,
                .orderMutation,
                .grantReward,
                .changePrice,
                .explainKnownRule
            ]
        )

        XCTAssertTrue(report.isSafetyCompliant)
        XCTAssertEqual(
            report.acceptedNarrativeEffects,
            [.explainKnownRule, .presentUnlockedClue]
        )
        XCTAssertEqual(
            report.droppedForbiddenEffects,
            [
                .changePrice,
                .grantReward,
                .inventoryMutation,
                .orderMutation,
                .walletMutation
            ]
        )
    }

    func testMemoryReadbackFilteringAndDeletionFenceEnforcement() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let validRecord = NPCSafetyMemoryRecordCandidate(
            memoryID: "mem-valid-1",
            isolationKey: isolationKey,
            hasActiveConsent: true,
            expiresAt: now.addingTimeInterval(3_600),
            isDeletedLocallyOrRemotely: false
        )
        let expiredRecord = NPCSafetyMemoryRecordCandidate(
            memoryID: "mem-expired-2",
            isolationKey: isolationKey,
            hasActiveConsent: true,
            expiresAt: now.addingTimeInterval(-10),
            isDeletedLocallyOrRemotely: false
        )
        let revokedConsentRecord = NPCSafetyMemoryRecordCandidate(
            memoryID: "mem-revoked-3",
            isolationKey: isolationKey,
            hasActiveConsent: false,
            expiresAt: now.addingTimeInterval(3_600),
            isDeletedLocallyOrRemotely: false
        )
        let wrongScopeRecord = NPCSafetyMemoryRecordCandidate(
            memoryID: "mem-foreign-4",
            isolationKey: "other-scope-key",
            hasActiveConsent: true,
            expiresAt: now.addingTimeInterval(3_600),
            isDeletedLocallyOrRemotely: false
        )

        let cleanReport = NPCChatAndSceneAISafetyAudit.audit(
            isolationKey: isolationKey,
            memoryCandidates: [validRecord, expiredRecord, revokedConsentRecord, wrongScopeRecord],
            deletedMemoryIDFence: ["mem-deleted-earlier"],
            referenceDate: now
        )
        XCTAssertTrue(cleanReport.isSafetyCompliant)
        XCTAssertEqual(cleanReport.admissibleRecords, [validRecord])
        XCTAssertTrue(cleanReport.reappearedDeletedMemoryIDs.isEmpty)

        let fenceViolatedReport = NPCChatAndSceneAISafetyAudit.audit(
            isolationKey: isolationKey,
            memoryCandidates: [validRecord, expiredRecord],
            deletedMemoryIDFence: ["mem-valid-1"],
            referenceDate: now
        )
        XCTAssertFalse(fenceViolatedReport.isSafetyCompliant)
        XCTAssertTrue(fenceViolatedReport.admissibleRecords.isEmpty)
        XCTAssertEqual(fenceViolatedReport.reappearedDeletedMemoryIDs, ["mem-valid-1"])
        XCTAssertEqual(
            fenceViolatedReport.violations,
            [.deletionFenceViolated(reappearedMemoryIDs: ["mem-valid-1"])]
        )
    }
}
