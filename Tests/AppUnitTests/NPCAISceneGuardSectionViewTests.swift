@testable import QuestifyApp
import QuestifyCore
import XCTest

@MainActor
final class NPCAISceneGuardSectionViewTests: XCTestCase {
    func testDefaultFailClosedDisabledAvailabilityStatePresentation() {
        let view = NPCAISceneGuardSectionView()
        _ = view.body

        let expectedScope = SceneAIScope.storePublic(
            merchantID: "merchant-shanghai-01",
            storeID: "store-bund-01"
        )
        XCTAssertEqual(view.isolationKeyText, expectedScope.isolationKey)
        XCTAssertTrue(view.isNonGenerativeBadgeVisible)
        XCTAssertTrue(view.isStreamingDisabledBadgeVisible)
        XCTAssertEqual(view.streamingBadgeLabel, "STREAMING OFF")
        XCTAssertEqual(view.preflightModeLabel, "NON-GENERATIVE · sceneAI.unavailable.global")
        XCTAssertTrue(view.rejectedDataClasses.isEmpty)
        XCTAssertEqual(view.rejectedDataClassesText, "none")
        XCTAssertEqual(view.droppedForbiddenEffectsText, "forbidden_effect")
        XCTAssertEqual(view.admissibleRecords.count, 1)
        XCTAssertEqual(view.admissibleMemoryCount, 1)
        XCTAssertEqual(view.totalMemoryCandidatesCount, 3)
    }

    func testActiveScenarioPreflightVerdictWithRejectedSensitiveDataClasses() throws {
        var availability = SceneAIAvailability()
        availability.globalGenerationEnabled = true
        availability.enabledScenarios = [.themeDirectorNPC]
        let hostGuard = NPCAISceneHostGuard(availability: availability)

        let session = try XCTUnwrap(
            ThemeNPCSessionScope(
                actorType: .player,
                actorID: "player-101",
                merchantID: "merchant-202",
                themeID: "theme-303",
                releaseID: "rel-404",
                runID: "run-505",
                bindingID: "bind-606"
            )
        )
        let context = NPCAISceneHostContext.themeBound(
            session: session,
            clientThemeHint: "theme-303",
            clientReleaseHint: "rel-404"
        )

        let rejectedVerdict = hostGuard.preflight(
            context: context,
            bizType: "npc_chat",
            requestedData: [.approvedStoreFacts, .lockedCluesAndEndings, .otherPlayerMemory]
        )

        let scope = SceneAIScope.themeBinding(session)
        let echo = SceneAIReplyEcho(
            scenario: .themeDirectorNPC,
            isolationKey: scope.isolationKey,
            traceID: "trace-1",
            policyVersion: "pol-1",
            promptVersion: "prm-1",
            releaseID: "rel-404"
        )
        let reply = hostGuard.validateReply(
            safeText: "Welcome to the clocktower.",
            echo: echo,
            sentFor: scope
        )
        let readback = hostGuard.filterMemoryReadback(
            [],
            in: scope,
            at: Date(timeIntervalSince1970: 1_720_000_000)
        )

        let view = NPCAISceneGuardSectionView(
            preflightVerdict: rejectedVerdict,
            replyValidation: reply,
            memoryReadback: readback
        )
        _ = view.body

        XCTAssertEqual(view.preflightModeLabel, "PREFLIGHT REJECTED")
        XCTAssertFalse(view.isNonGenerativeBadgeVisible)
        XCTAssertTrue(view.isStreamingDisabledBadgeVisible)
        XCTAssertEqual(
            view.rejectedDataClasses,
            [.lockedCluesAndEndings, .otherPlayerMemory]
        )
        XCTAssertEqual(
            view.rejectedDataClassesText,
            "LOCKED_CLUES_AND_ENDINGS, OTHER_PLAYER_MEMORY"
        )
        XCTAssertTrue(view.isolationKeyText.contains("forbidden_data_classes"))
    }

    func testReplyValidationWithDroppedForbiddenAuthorityEffectsAndAcceptedProposal() throws {
        var availability = SceneAIAvailability()
        availability.globalGenerationEnabled = true
        availability.enabledScenarios = [.themeDirectorNPC]
        let hostGuard = NPCAISceneHostGuard(availability: availability)

        let session = try XCTUnwrap(
            ThemeNPCSessionScope(
                actorType: .team,
                actorID: "team-01",
                merchantID: "merchant-01",
                themeID: "theme-01",
                releaseID: "rel-01",
                runID: "run-01",
                bindingID: "bind-01"
            )
        )
        let scope = SceneAIScope.themeBinding(session)
        let context = NPCAISceneHostContext.themeBound(session: session)
        let preflight = hostGuard.preflight(
            context: context,
            bizType: "npc_chat",
            requestedData: [.approvedStoreFacts, .unlockedClues]
        )
        let echo = SceneAIReplyEcho(
            scenario: .themeDirectorNPC,
            isolationKey: scope.isolationKey,
            traceID: "trace-auth-01",
            policyVersion: "pol-v2",
            promptVersion: "prm-v3",
            releaseID: "rel-01"
        )
        let visible = NPCVisibleContext(
            releaseID: "rel-01",
            currentNodeID: "node-courtyard",
            unlockedClueIDs: ["clue-lantern"],
            approvedToneKeys: ["calm"],
            availableSideQuestIDs: ["sq-tea"]
        )

        let forbiddenReply = hostGuard.validateReply(
            safeText: "I cannot alter the store price, traveler.",
            echo: echo,
            sentFor: scope,
            proposal: NPCAISceneRawProposal(
                rawAction: NPCForbiddenEffect.changePrice.rawValue,
                target: "item-ticket"
            ),
            visibleContext: visible
        )
        let readback = NPCAIMemoryReadbackOutcome.admissible([])

        let droppedView = NPCAISceneGuardSectionView(
            preflightVerdict: preflight,
            replyValidation: forbiddenReply,
            memoryReadback: readback
        )
        _ = droppedView.body

        XCTAssertEqual(droppedView.preflightModeLabel, "GENERATIVE · npc_chat")
        XCTAssertEqual(droppedView.narrativeActionDecisionText, "DIALOGUE ONLY (proposal dropped)")
        XCTAssertEqual(droppedView.droppedForbiddenEffectsText, "forbidden_effect")
        XCTAssertEqual(droppedView.safeReplyPreviewText, "I cannot alter the store price, traveler.")

        let acceptedReply = hostGuard.validateReply(
            safeText: "Examine the brass lantern by the gate.",
            echo: echo,
            sentFor: scope,
            proposal: NPCAISceneRawProposal(
                rawAction: NPCNarrativeAction.presentUnlockedClue.rawValue,
                target: "clue-lantern"
            ),
            visibleContext: visible
        )
        let acceptedView = NPCAISceneGuardSectionView(
            preflightVerdict: preflight,
            replyValidation: acceptedReply,
            memoryReadback: readback
        )
        _ = acceptedView.body

        XCTAssertEqual(
            acceptedView.narrativeActionDecisionText,
            "ACCEPTED (PRESENT_UNLOCKED_CLUE -> clue-lantern)"
        )
        XCTAssertEqual(acceptedView.droppedForbiddenEffectsText, "none")
    }

    func testMemoryReadbackFilteringForAdmissibleExpiredRevokedAndDeletedRecords() {
        let hostGuard = NPCAISceneHostGuard.disabled
        let scope = SceneAIScope.storePublic(merchantID: "m-10", storeID: "s-20")
        let now = Date(timeIntervalSince1970: 1_750_000_000)

        let validCanon = NPCMemoryEntry(
            memoryID: "mem-valid-canon",
            isolationKey: scope.isolationKey,
            layer: .characterCanon,
            source: .reviewedContent,
            sourceEventID: nil,
            consentVersion: nil,
            expiresAt: now.addingTimeInterval(1_800),
            contentHash: "hash-1"
        )
        let validRunFact = NPCMemoryEntry(
            memoryID: "mem-valid-fact",
            isolationKey: scope.isolationKey,
            layer: .runFact,
            source: .runtimeEvent,
            sourceEventID: "evt-88",
            consentVersion: nil,
            expiresAt: nil,
            contentHash: "hash-2"
        )
        let expiredEntry = NPCMemoryEntry(
            memoryID: "mem-expired",
            isolationKey: scope.isolationKey,
            layer: .characterCanon,
            source: .reviewedContent,
            sourceEventID: nil,
            consentVersion: nil,
            expiresAt: now.addingTimeInterval(-10),
            contentHash: "hash-3"
        )
        let revokedConsentEntry = NPCMemoryEntry(
            memoryID: "mem-revoked-consent",
            isolationKey: scope.isolationKey,
            layer: .consentedPreference,
            source: .playerStatement,
            sourceEventID: nil,
            consentVersion: "",
            expiresAt: now.addingTimeInterval(1_800),
            contentHash: "hash-4"
        )

        let candidateEntries = [validCanon, validRunFact, expiredEntry, revokedConsentEntry]
        let admissibleOutcome = hostGuard.filterMemoryReadback(
            candidateEntries,
            in: scope,
            at: now,
            deletedMemoryIDs: ["mem-deleted-earlier"]
        )

        let preflight = hostGuard.preflight(
            context: .storePublic(merchantID: "m-10", storeID: "s-20"),
            bizType: "merchant_npc_chat"
        )
        let reply = NPCAISceneReplyOutcome.discarded(.missingAudit)

        let admissibleView = NPCAISceneGuardSectionView(
            preflightVerdict: preflight,
            replyValidation: reply,
            memoryReadback: admissibleOutcome,
            totalMemoryCandidatesCount: candidateEntries.count
        )
        _ = admissibleView.body

        XCTAssertEqual(admissibleView.admissibleRecords, [validCanon, validRunFact])
        XCTAssertEqual(admissibleView.admissibleMemoryCount, 2)
        XCTAssertEqual(admissibleView.memoryFenceBadgeText, "DELETION/EXPIRY/CONSENT VERIFIED")
        XCTAssertEqual(
            admissibleView.memoryReadbackSummaryText,
            "Admissible memories: 2 kept, 2 filtered by deletion/expiry/consent."
        )

        let fenceViolatedOutcome = hostGuard.filterMemoryReadback(
            candidateEntries,
            in: scope,
            at: now,
            deletedMemoryIDs: ["mem-valid-fact"]
        )
        let violatedView = NPCAISceneGuardSectionView(
            preflightVerdict: preflight,
            replyValidation: reply,
            memoryReadback: fenceViolatedOutcome,
            totalMemoryCandidatesCount: candidateEntries.count
        )
        _ = violatedView.body

        XCTAssertTrue(violatedView.admissibleRecords.isEmpty)
        XCTAssertEqual(violatedView.admissibleMemoryCount, 0)
        XCTAssertEqual(violatedView.memoryFenceBadgeText, "FENCE VIOLATION (1)")
        XCTAssertTrue(violatedView.memoryReadbackSummaryText.contains("mem-valid-fact"))
    }
}
