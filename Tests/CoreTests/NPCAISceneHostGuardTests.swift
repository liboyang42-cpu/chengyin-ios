import XCTest
@testable import QuestifyCore

final class NPCAISceneHostGuardTests: XCTestCase {
    private let serverNow = Date(timeIntervalSince1970: 1_760_900_000)

    private func makeThemeSession(
        theme: String = "theme-city-1",
        release: String = "rel-2026-10",
        run: String = "run-99",
        binding: String = "bind-npc-7"
    ) -> ThemeNPCSessionScope {
        ThemeNPCSessionScope(
            actorType: .player,
            actorID: "player-1",
            merchantID: "merchant-1",
            themeID: theme,
            releaseID: release,
            runID: run,
            bindingID: binding
        )!
    }

    func testDefaultGuardIsNonGenerativeAndStreamingStaysOffAcrossStoreThemeAndRoam() {
        let hostGuard = NPCAISceneHostGuard.disabled

        let storeDecision = hostGuard.preflight(
            context: .storePublic(merchantID: "merchant-1", storeID: "store-1"),
            bizType: "merchant_npc_chat",
            requestedData: [.approvedStoreFacts]
        )
        let expectedStoreScope = SceneAIScope.storePublic(merchantID: "merchant-1", storeID: "store-1")
        XCTAssertEqual(
            storeDecision,
            .nonGenerative(
                scope: expectedStoreScope,
                isolationKey: expectedStoreScope.isolationKey,
                reasonKey: "sceneAI.unavailable.global",
                allowsStreamingDisplay: false
            )
        )
        XCTAssertFalse(storeDecision.allowsStreamingDisplay)

        let session = makeThemeSession()
        let themeDecision = hostGuard.preflight(
            context: .themeBound(session: session, clientThemeHint: "theme-city-1", clientReleaseHint: "rel-2026-10"),
            bizType: "npc_chat",
            requestedData: [.approvedStoreFacts, .currentRunState, .unlockedClues]
        )
        let expectedThemeScope = SceneAIScope.themeBinding(session)
        XCTAssertEqual(
            themeDecision,
            .nonGenerative(
                scope: expectedThemeScope,
                isolationKey: expectedThemeScope.isolationKey,
                reasonKey: "sceneAI.unavailable.global",
                allowsStreamingDisplay: false
            )
        )

        let roamFallbackDecision = hostGuard.preflight(
            context: .roam(session: nil, storeMerchantID: "merchant-1", storeID: "store-2"),
            bizType: "merchant_npc_chat",
            requestedData: [.approvedStoreFacts]
        )
        let expectedRoamStoreScope = SceneAIScope.storePublic(merchantID: "merchant-1", storeID: "store-2")
        XCTAssertEqual(
            roamFallbackDecision,
            .nonGenerative(
                scope: expectedRoamStoreScope,
                isolationKey: expectedRoamStoreScope.isolationKey,
                reasonKey: "sceneAI.unavailable.global",
                allowsStreamingDisplay: false
            )
        )
    }

    func testPreflightRejectsClientHintMismatchForbiddenDataAndUnregisteredBizTypes() {
        var availability = SceneAIAvailability()
        availability.globalGenerationEnabled = true
        availability.enabledScenarios = [.storePublicNPC, .themeDirectorNPC]
        let hostGuard = NPCAISceneHostGuard(availability: availability)
        let session = makeThemeSession()

        // Client hint mismatch fails closed even when switches are enabled.
        XCTAssertEqual(
            hostGuard.preflight(
                context: .themeBound(session: session, clientThemeHint: "other-theme"),
                bizType: "npc_chat"
            ),
            .rejected(.clientHintMismatch)
        )
        XCTAssertEqual(
            hostGuard.preflight(
                context: .roam(session: session, clientThemeHint: "theme-city-1", clientReleaseHint: "rel-stale"),
                bizType: "npc_chat"
            ),
            .rejected(.clientHintMismatch)
        )

        // Store-public NPC cannot request current run state or private store operations.
        XCTAssertEqual(
            hostGuard.preflight(
                context: .storePublic(merchantID: "merchant-1", storeID: "store-1"),
                bizType: "merchant_npc_chat",
                requestedData: [.approvedStoreFacts, .privateStoreOperations]
            ),
            .rejected(.forbiddenDataClasses([.privateStoreOperations]))
        )

        // Theme NPC cannot request locked clues/endings or use unregistered bizType.
        XCTAssertEqual(
            hostGuard.preflight(
                context: .themeBound(session: session),
                bizType: "npc_chat",
                requestedData: [.unlockedClues, .lockedCluesAndEndings]
            ),
            .rejected(.forbiddenDataClasses([.lockedCluesAndEndings]))
        )
        XCTAssertEqual(
            hostGuard.preflight(
                context: .themeBound(session: session),
                bizType: "npc_event",
                requestedData: [.approvedStoreFacts]
            ),
            .rejected(.unregisteredBizType("npc_event"))
        )

        // Valid theme preflight succeeds with streaming display still forced false.
        let validTheme = hostGuard.preflight(
            context: .roam(session: session, clientThemeHint: "theme-city-1"),
            bizType: "npc_chat",
            requestedData: [.approvedStoreFacts, .currentRunState]
        )
        let expectedScope = SceneAIScope.themeBinding(session)
        XCTAssertEqual(
            validTheme,
            .generative(
                scope: expectedScope,
                isolationKey: expectedScope.isolationKey,
                bizType: "npc_chat",
                allowsStreamingDisplay: false
            )
        )
    }

    func testReplyValidationEnforcesScopeAndAuditEchoBeforeDisplay() {
        let hostGuard = NPCAISceneHostGuard.disabled
        let session = makeThemeSession()
        let sentScope = SceneAIScope.themeBinding(session)

        let validEcho = SceneAIReplyEcho(
            scenario: .themeDirectorNPC,
            isolationKey: sentScope.isolationKey,
            traceID: "trace-101",
            policyVersion: "pol-v2",
            promptVersion: "prm-v5",
            releaseID: "rel-2026-10"
        )
        let displayed = hostGuard.validateReply(
            safeText: "欢迎来到钟楼节点。",
            echo: validEcho,
            sentFor: sentScope
        )
        guard case .display(let reply) = displayed else {
            return XCTFail("Expected display outcome, got \(displayed)")
        }
        XCTAssertEqual(reply.safeText, "欢迎来到钟楼节点。")
        XCTAssertEqual(reply.isolationKey, sentScope.isolationKey)
        XCTAssertFalse(reply.allowsStreamingDisplay)

        // Wrong isolation key is discarded.
        let otherScope = SceneAIScope.themeBinding(makeThemeSession(theme: "theme-other"))
        let wrongScopeEcho = SceneAIReplyEcho(
            scenario: .themeDirectorNPC,
            isolationKey: otherScope.isolationKey,
            traceID: "trace-101",
            policyVersion: "pol-v2",
            promptVersion: "prm-v5",
            releaseID: "rel-2026-10"
        )
        XCTAssertEqual(
            hostGuard.validateReply(safeText: "串场回复", echo: wrongScopeEcho, sentFor: sentScope),
            .discarded(.scopeMismatch)
        )

        // Missing audit version is discarded.
        let missingAuditEcho = SceneAIReplyEcho(
            scenario: .themeDirectorNPC,
            isolationKey: sentScope.isolationKey,
            traceID: "",
            policyVersion: "pol-v2",
            promptVersion: "prm-v5",
            releaseID: "rel-2026-10"
        )
        XCTAssertEqual(
            hostGuard.validateReply(safeText: "缺少审计", echo: missingAuditEcho, sentFor: sentScope),
            .discarded(.missingAudit)
        )
    }

    func testReplyValidationDropsForbiddenBusinessEffectsWhileKeepingDisplayableSafeText() {
        let hostGuard = NPCAISceneHostGuard.disabled
        let session = makeThemeSession()
        let sentScope = SceneAIScope.themeBinding(session)
        let visible = NPCVisibleContext(
            releaseID: "rel-2026-10",
            currentNodeID: "node-belltower",
            unlockedClueIDs: ["clue-lantern"],
            approvedToneKeys: ["mysterious"],
            availableSideQuestIDs: ["sq-tea"]
        )
        let echo = SceneAIReplyEcho(
            scenario: .themeDirectorNPC,
            isolationKey: sentScope.isolationKey,
            traceID: "trace-202",
            policyVersion: "pol-v1",
            promptVersion: "prm-v1",
            releaseID: "rel-2026-10"
        )

        // Whitelisted visible clue is accepted.
        let acceptedOutcome = hostGuard.validateReply(
            safeText: "看看这盏旧灯笼。",
            echo: echo,
            sentFor: sentScope,
            proposal: NPCAISceneRawProposal(rawAction: "PRESENT_UNLOCKED_CLUE", target: "clue-lantern"),
            visibleContext: visible
        )
        guard case .display(let acceptedReply) = acceptedOutcome else {
            return XCTFail("Expected display outcome")
        }
        XCTAssertEqual(
            acceptedReply.acceptedProposal,
            NPCNarrativeProposal(action: .presentUnlockedClue, target: "clue-lantern")
        )
        XCTAssertNil(acceptedReply.droppedProposalReason)

        // Every forbidden business effect is dropped while preserving safeText.
        for effect in NPCForbiddenEffect.allCases {
            let outcome = hostGuard.validateReply(
                safeText: "台词本身可展示，但越权动作被丢弃。",
                echo: echo,
                sentFor: sentScope,
                proposal: NPCAISceneRawProposal(rawAction: effect.rawValue, target: "any"),
                visibleContext: visible
            )
            guard case .display(let reply) = outcome else {
                return XCTFail("Expected safeText to remain displayable for \(effect)")
            }
            XCTAssertNil(reply.acceptedProposal)
            XCTAssertEqual(reply.droppedProposalReason, .forbiddenEffect)
        }

        // Store-public NPC has no quest visible context, so narrative proposals are dropped.
        let storeScope = SceneAIScope.storePublic(merchantID: "merchant-1", storeID: "store-1")
        let storeEcho = SceneAIReplyEcho(
            scenario: .storePublicNPC,
            isolationKey: storeScope.isolationKey,
            traceID: "trace-store",
            policyVersion: "pol-v1",
            promptVersion: "prm-v1",
            releaseID: nil
        )
        let storeOutcome = hostGuard.validateReply(
            safeText: "本店今日营业至晚十点。",
            echo: storeEcho,
            sentFor: storeScope,
            proposal: NPCAISceneRawProposal(rawAction: "PRESENT_UNLOCKED_CLUE", target: "clue-lantern"),
            visibleContext: visible
        )
        guard case .display(let storeReply) = storeOutcome else {
            return XCTFail("Expected store reply display")
        }
        XCTAssertNil(storeReply.acceptedProposal)
        XCTAssertEqual(storeReply.droppedProposalReason, .targetNotVisible)
    }

    func testMemoryReadbackFilterEnforcesScopeProvenanceConsentExpiryAndDeletionFence() {
        let hostGuard = NPCAISceneHostGuard.disabled
        let scope = SceneAIScope.themeBinding(makeThemeSession())
        let otherScope = SceneAIScope.storePublic(merchantID: "merchant-1", storeID: "store-1")

        let validRuntimeFact = NPCMemoryEntry(
            memoryID: "mem-fact-1",
            isolationKey: scope.isolationKey,
            layer: .runFact,
            source: .runtimeEvent,
            sourceEventID: "evt-100",
            consentVersion: nil,
            expiresAt: serverNow.addingTimeInterval(3600),
            contentHash: "hash-1"
        )
        let validConsentedPref = NPCMemoryEntry(
            memoryID: "mem-pref-1",
            isolationKey: scope.isolationKey,
            layer: .consentedPreference,
            source: .playerStatement,
            sourceEventID: nil,
            consentVersion: "consent-v1",
            expiresAt: nil,
            contentHash: "hash-2"
        )
        let untrustedModelClaim = NPCMemoryEntry(
            memoryID: "mem-untrusted",
            isolationKey: scope.isolationKey,
            layer: .runFact,
            source: .modelSummary,
            sourceEventID: "evt-fake",
            consentVersion: nil,
            expiresAt: nil,
            contentHash: "hash-3"
        )
        let expiredEntry = NPCMemoryEntry(
            memoryID: "mem-expired",
            isolationKey: scope.isolationKey,
            layer: .characterCanon,
            source: .reviewedContent,
            sourceEventID: nil,
            consentVersion: nil,
            expiresAt: serverNow,
            contentHash: "hash-4"
        )
        let wrongScopeEntry = NPCMemoryEntry(
            memoryID: "mem-other-scope",
            isolationKey: otherScope.isolationKey,
            layer: .characterCanon,
            source: .reviewedContent,
            sourceEventID: nil,
            consentVersion: nil,
            expiresAt: nil,
            contentHash: "hash-5"
        )

        let filtered = hostGuard.filterMemoryReadback(
            [validRuntimeFact, validConsentedPref, untrustedModelClaim, expiredEntry, wrongScopeEntry],
            in: scope,
            at: serverNow
        )
        XCTAssertEqual(filtered, .admissible([validRuntimeFact, validConsentedPref]))

        // Reappearance of a deleted memory ID triggers the deletion fence.
        let fenced = hostGuard.filterMemoryReadback(
            [validRuntimeFact, validConsentedPref],
            in: scope,
            at: serverNow,
            deletedMemoryIDs: ["mem-pref-1"]
        )
        XCTAssertEqual(fenced, .deletionFenceViolated(reappearedMemoryIDs: ["mem-pref-1"]))
    }
}
