import XCTest
@testable import QuestifyCore

private let t0 = Date(timeIntervalSince1970: 1_000_000)
private func scope(theme: String = "theme-a", run: String = "run-1", release: String = "rel-1", binding: String = "bind-1") -> ThemeNPCSessionScope {
    ThemeNPCSessionScope(actorType: .player, actorID: "p1", merchantID: "m1", themeID: theme, releaseID: release, runID: run, bindingID: binding)!
}

final class SceneAIScopeTests: XCTestCase {
    func testScenarioDataClassesAreDisjointAndPrivateDataStaysInAssistant() {
        for scenario in SceneAIScenario.allCases {
            XCTAssertTrue(scenario.allowedData.isDisjoint(with: scenario.forbiddenData))
            if scenario != .merchantPrivateAssistant { XCTAssertFalse(scenario.allowedData.contains(.privateStoreOperations)) }
            if scenario != .themeDirectorNPC { XCTAssertFalse(scenario.allowedData.contains(.currentRunState)) }
            for forbidden: SceneAIDataClass in [.lockedCluesAndEndings, .otherThemeContent, .otherPlayerMemory, .merchantPriceFloor, .unpurchasedAnswers] {
                XCTAssertFalse(scenario.allowedData.contains(forbidden))
            }
        }
        XCTAssertTrue(SceneAIScenario.platformBackoffice.registeredBizTypes.isEmpty)
        XCTAssertFalse(SceneAIScenario.platformBackoffice.availableInApp)
    }
    func testIsolationKeysSeparateThemesRunsReleasesAndStoreModes() {
        let keys: [String] = [
            SceneAIScope.themeBinding(scope()).isolationKey, SceneAIScope.themeBinding(scope(theme: "theme-b")).isolationKey,
            SceneAIScope.themeBinding(scope(run: "run-2")).isolationKey, SceneAIScope.themeBinding(scope(release: "rel-2")).isolationKey,
            SceneAIScope.storePublic(merchantID: "m1", storeID: "s1").isolationKey,
            SceneAIScope.merchantPrivate(merchantID: "m1", storeID: "s1", operatorID: "o1").isolationKey
        ]
        XCTAssertEqual(Set(keys).count, keys.count)
        // Separator injection cannot collide two different component lists.
        XCTAssertNotEqual(SceneAIScope.storePublic(merchantID: "a1:b", storeID: "c").isolationKey,
                          SceneAIScope.storePublic(merchantID: "a", storeID: "1:bc").isolationKey)
    }
    func testClientThemeHintIsComparedNeverAuthorizing() {
        XCTAssertTrue(scope().agrees(withClientThemeHint: "theme-a"))
        XCTAssertTrue(scope().agrees(withClientThemeHint: nil))
        XCTAssertFalse(scope().agrees(withClientThemeHint: "theme-b"))
        XCTAssertFalse(scope().agrees(withClientThemeHint: "theme-a", releaseHint: "rel-old"))
        XCTAssertNil(ThemeNPCSessionScope(actorType: .player, actorID: "p1", merchantID: "m1", themeID: " theme", releaseID: "r", runID: "r", bindingID: "b"))
    }
    func testDefaultIsNonGenerativeAndKillSwitchesApply() {
        let theme = SceneAIScope.themeBinding(scope())
        XCTAssertEqual(SceneAIAvailability.disabled.mode(for: theme), .nonGenerative(reasonKey: "sceneAI.unavailable.global"))
        XCTAssertFalse(SceneAIAvailability.disabled.allowsStreamingDisplay)
        var on = SceneAIAvailability(); on.globalGenerationEnabled = true
        XCTAssertEqual(on.mode(for: theme), .nonGenerative(reasonKey: "sceneAI.unavailable.scenario"))
        on.enabledScenarios = [.themeDirectorNPC]
        XCTAssertEqual(on.mode(for: theme), .generative)
        on.disabledThemeIDs = ["theme-a"]
        XCTAssertEqual(on.mode(for: theme), .nonGenerative(reasonKey: "sceneAI.unavailable.theme"))
    }
    func testReplyFromAnotherScopeOrWithoutAuditIsDiscarded() {
        let sent = SceneAIScope.themeBinding(scope())
        let ok = SceneAIReplyEcho(scenario: .themeDirectorNPC, isolationKey: sent.isolationKey, traceID: "t", policyVersion: "p", promptVersion: "v", releaseID: "rel-1")
        XCTAssertEqual(SceneAIAvailability.decide(ok, sentFor: sent), .display)
        let otherTheme = SceneAIReplyEcho(scenario: .themeDirectorNPC, isolationKey: SceneAIScope.themeBinding(scope(theme: "theme-b")).isolationKey,
                                          traceID: "t", policyVersion: "p", promptVersion: "v", releaseID: "rel-1")
        XCTAssertEqual(SceneAIAvailability.decide(otherTheme, sentFor: sent), .discardScopeMismatch)
        let noTrace = SceneAIReplyEcho(scenario: .themeDirectorNPC, isolationKey: sent.isolationKey, traceID: "", policyVersion: "p", promptVersion: "v", releaseID: "rel-1")
        XCTAssertEqual(SceneAIAvailability.decide(noTrace, sentFor: sent), .discardMissingAudit)
    }
}

final class NPCNarrativePolicyTests: XCTestCase {
    private let visible = NPCVisibleContext(releaseID: "rel-1", currentNodeID: "n1", unlockedClueIDs: ["c1"], approvedToneKeys: ["calm"], availableSideQuestIDs: ["sq1"])
    func testOnlyWhitelistedVisibleActionsSurvive() {
        XCTAssertEqual(NPCNarrativePolicy.evaluate(rawAction: "PRESENT_UNLOCKED_CLUE", target: "c1", releaseID: "rel-1", visible: visible),
                       .accepted(NPCNarrativeProposal(action: .presentUnlockedClue, target: "c1")))
        XCTAssertEqual(NPCNarrativePolicy.evaluate(rawAction: "PRESENT_UNLOCKED_CLUE", target: "c-locked", releaseID: "rel-1", visible: visible), .dropped(.targetNotVisible))
        XCTAssertEqual(NPCNarrativePolicy.evaluate(rawAction: "ASK_CURRENT_NODE_QUESTION", target: "n2", releaseID: "rel-1", visible: visible), .dropped(.targetNotVisible))
        XCTAssertEqual(NPCNarrativePolicy.evaluate(rawAction: "EXPLAIN_KNOWN_RULE", target: nil, releaseID: "rel-0", visible: visible), .dropped(.staleRelease))
        XCTAssertEqual(NPCNarrativePolicy.evaluate(rawAction: "OPEN_DOOR", target: nil, releaseID: "rel-1", visible: visible), .dropped(.unknownAction))
        for effect in NPCForbiddenEffect.allCases {
            XCTAssertEqual(NPCNarrativePolicy.evaluate(rawAction: effect.rawValue, target: nil, releaseID: "rel-1", visible: visible), .dropped(.forbiddenEffect))
        }
    }
    func testModelSummaryOrPlayerClaimNeverBecomesFact() {
        let s = SceneAIScope.themeBinding(scope())
        func entry(_ layer: NPCMemoryEntry.Layer, _ source: NPCMemoryEntry.Source, event: String? = "e1", consent: String? = nil, key: String? = nil, expires: Date? = nil) -> NPCMemoryEntry {
            NPCMemoryEntry(memoryID: UUID().uuidString, isolationKey: key ?? s.isolationKey, layer: layer, source: source, sourceEventID: event, consentVersion: consent, expiresAt: expires, contentHash: "h")
        }
        XCTAssertTrue(entry(.runFact, .runtimeEvent).admissible(in: s, at: t0))
        XCTAssertTrue(entry(.runFact, .orderEvent).isTrustedFact)
        XCTAssertFalse(entry(.runFact, .playerStatement).admissible(in: s, at: t0))
        XCTAssertFalse(entry(.runFact, .modelSummary).admissible(in: s, at: t0))
        XCTAssertFalse(entry(.runFact, .runtimeEvent, event: nil).admissible(in: s, at: t0))
        XCTAssertFalse(entry(.consentedPreference, .modelSummary).admissible(in: s, at: t0))
        XCTAssertTrue(entry(.consentedPreference, .modelSummary, consent: "c1").admissible(in: s, at: t0))
        XCTAssertFalse(entry(.characterCanon, .modelSummary).admissible(in: s, at: t0))
        XCTAssertFalse(entry(.runFact, .runtimeEvent, key: SceneAIScope.themeBinding(scope(theme: "theme-b")).isolationKey).admissible(in: s, at: t0))
        XCTAssertFalse(entry(.runFact, .runtimeEvent, expires: t0).admissible(in: s, at: t0))
        let kept = entry(.runFact, .runtimeEvent)
        XCTAssertFalse(NPCMemoryEntry.respectsDeletion([kept], deleted: [kept.memoryID]))
    }
}

final class MerchantAIAuthoringTests: XCTestCase {
    private func revision(stage: MerchantAuthoringStage = .approved, version: Int = 3, hash: String = "h1", theme: Bool = true,
                          facts: MerchantAuthoringApproval? = .init(authority: .storeOwner, approverID: "owner", approvedHash: "h1"),
                          story: MerchantAuthoringApproval? = .init(authority: .themeOwner, approverID: "lead", approvedHash: "h1")) -> MerchantAuthoringRevision {
        MerchantAuthoringRevision(draftID: "d1", version: version, stage: stage, authorID: "editor", contentHash: hash,
                                  touchesThemeContent: theme, merchantFactsApproval: facts, themeContentApproval: story)
    }
    func testPublishNeedsBothDomainsOnReviewedHashAndEnabledCapability() {
        XCTAssertEqual(MerchantAuthoringGuard.publishBlockers(revision(), capabilityEnabled: false), [.capabilityDisabled])
        XCTAssertTrue(MerchantAuthoringGuard.publishBlockers(revision(), capabilityEnabled: true).isEmpty)
        XCTAssertEqual(MerchantAuthoringGuard.publishBlockers(revision(hash: "h2"), capabilityEnabled: true), [.editedAfterReview])
        XCTAssertEqual(MerchantAuthoringGuard.publishBlockers(revision(story: nil), capabilityEnabled: true), [.missingThemeApproval])
        XCTAssertTrue(MerchantAuthoringGuard.publishBlockers(revision(theme: false, story: nil), capabilityEnabled: true).isEmpty)
        XCTAssertEqual(MerchantAuthoringGuard.publishBlockers(revision(facts: .init(authority: .themeOwner, approverID: "lead", approvedHash: "h1")), capabilityEnabled: true), [.wrongAuthority])
        XCTAssertEqual(MerchantAuthoringGuard.publishBlockers(revision(facts: .init(authority: .storeOwner, approverID: "editor", approvedHash: "h1")), capabilityEnabled: true), [.selfApproval])
        XCTAssertTrue(MerchantAuthoringGuard.publishBlockers(revision(stage: .inReview), capabilityEnabled: true).contains(.notApproved))
    }
    func testPublishCommandCarriesExpectedVersionAndReviewedHash() {
        let id = UUID()
        XCTAssertNil(MerchantAuthoringGuard.publishCommand(revision(), requestID: id, capabilityEnabled: false))
        let command = MerchantAuthoringGuard.publishCommand(revision(), requestID: id, capabilityEnabled: true)
        XCTAssertEqual(command?.expectedVersion, 3); XCTAssertEqual(command?.reviewedHash, "h1"); XCTAssertEqual(command?.requestID, id)
    }
    func testReadbackCannotRewindOrLeavePublished() {
        XCTAssertTrue(MerchantAuthoringGuard.acceptsReadback(old: revision(stage: .draft, version: 1), new: revision(stage: .inReview, version: 3)))
        XCTAssertFalse(MerchantAuthoringGuard.acceptsReadback(old: revision(stage: .published, version: 4), new: revision(stage: .draft, version: 5)))
        XCTAssertFalse(MerchantAuthoringGuard.acceptsReadback(old: revision(version: 4), new: revision(version: 3)))
        XCTAssertFalse(MerchantAuthoringGuard.acceptsReadback(old: revision(version: 3), new: revision(hash: "other", version: 3)))
        XCTAssertTrue(MerchantAuthoringStage.withdrawn.allowedNext.isEmpty)
    }
    func testInStoreGameRequiresEveryOperationalFieldAndApprovedRules() {
        var game = InStoreGameDraft()
        XCTAssertEqual(game.missingFields(approvedTemplates: ["tpl"], approvedRewardRules: []), InStoreGameDraft.Field.allCases)
        game.interactionTemplateID = "tpl"; game.durationMinutes = 20; game.maxParticipants = 4; game.businessHoursText = "Open hours"
        game.needsStaff = false; game.noiseAndFilmingLimits = "Quiet"; game.accessibleAlternative = "Counter route"
        game.offlineFallback = "Paper card"; game.failureExit = "Leave anytime"; game.reward = .approvedRule(id: "unknown")
        XCTAssertEqual(game.missingFields(approvedTemplates: ["tpl"], approvedRewardRules: []), [.rewardRule])
        game.reward = .noReward
        XCTAssertTrue(game.missingFields(approvedTemplates: ["tpl"], approvedRewardRules: []).isEmpty)
        XCTAssertEqual(game.missingFields(approvedTemplates: [], approvedRewardRules: []), [.interactionTemplate])
    }
    func testProductDraftRejectsInventedPriceDiscountAndInventoryCopies() {
        let catalog = [CanonicalSKUFact(merchantID: "m1", skuID: "sku1", priceMinor: 2800, currency: "CNY"),
                       CanonicalSKUFact(merchantID: "m2", skuID: "sku2", priceMinor: 100, currency: "CNY")]
        XCTAssertTrue(MerchantProductDraft(merchantID: "m1", source: .canonical(skuID: "sku1"), claimedPriceMinor: 2800, claimedDiscountText: nil, createsThemeInventoryCopy: false).issues(catalog: catalog).isEmpty)
        XCTAssertEqual(MerchantProductDraft(merchantID: "m1", source: .canonical(skuID: "sku1"), claimedPriceMinor: 1999, claimedDiscountText: "Half price today", createsThemeInventoryCopy: true).issues(catalog: catalog),
                       [.priceClaimMismatch, .inventedDiscount, .duplicatesInventory])
        XCTAssertEqual(MerchantProductDraft(merchantID: "m1", source: .canonical(skuID: "sku2"), claimedPriceMinor: nil, claimedDiscountText: nil, createsThemeInventoryCopy: false).issues(catalog: catalog), [.otherMerchantSKU])
        XCTAssertEqual(MerchantProductDraft(merchantID: "m1", source: .manual(confirmedByPerson: false, hasPrice: true, hasFulfilment: true, hasStockRule: true, hasRefundTerms: true), claimedPriceMinor: 500, claimedDiscountText: nil, createsThemeInventoryCopy: false).issues(catalog: catalog),
                       [.manualSaleFieldsUnconfirmed, .priceClaimMismatch])
    }
}

final class EnvironmentBranchSelectorTests: XCTestCase {
    private let window = DateInterval(start: t0.addingTimeInterval(-3600), duration: 7200)
    private func snapshot(weather: EnvironmentSnapshot.Weather? = .clear, open: Bool? = true, expires: TimeInterval = 600) -> EnvironmentSnapshot {
        EnvironmentSnapshot(snapshotID: "snap", source: "fixture", observedAt: t0.addingTimeInterval(-60), expiresAt: t0.addingTimeInterval(expires),
                            runTimeZoneID: "Asia/Shanghai", weather: weather, storeOpen: open, reachablePlaceIDs: ["p1"])
    }
    private var branches: [ApprovedBranch] {[
        ApprovedBranch(branchID: "outdoor", window: window, indoor: false, requiresOpenStore: false, requiredPlaceIDs: ["p1"], isDeterministicFallback: false),
        ApprovedBranch(branchID: "cafe", window: nil, indoor: true, requiresOpenStore: true, requiredPlaceIDs: [], isDeterministicFallback: false),
        ApprovedBranch(branchID: "fallback", window: nil, indoor: true, requiresOpenStore: false, requiredPlaceIDs: [], isDeterministicFallback: true)
    ]}
    func testOnlyApprovedEligibleBranchesAreSelected() {
        XCTAssertEqual(EnvironmentBranchSelector.decide(proposedBranchID: "outdoor", branches: branches, snapshot: snapshot(), serverNow: t0), .selected(branchID: "outdoor", snapshotID: "snap"))
        XCTAssertEqual(EnvironmentBranchSelector.decide(proposedBranchID: "invented", branches: branches, snapshot: snapshot(), serverNow: t0), .fallback(branchID: "fallback", reason: .proposalNotApproved))
        XCTAssertEqual(EnvironmentBranchSelector.decide(proposedBranchID: "outdoor", branches: branches, snapshot: snapshot(weather: .rain), serverNow: t0), .fallback(branchID: "fallback", reason: .proposalConditionsUnmet))
        XCTAssertEqual(EnvironmentBranchSelector.decide(proposedBranchID: "cafe", branches: branches, snapshot: snapshot(open: false), serverNow: t0), .fallback(branchID: "fallback", reason: .proposalConditionsUnmet))
        // An afternoon start cannot keep a morning task whose window has passed.
        XCTAssertEqual(EnvironmentBranchSelector.decide(proposedBranchID: "outdoor", branches: branches, snapshot: snapshot(expires: 7200), serverNow: window.end), .fallback(branchID: "fallback", reason: .proposalConditionsUnmet))
    }
    func testStaleMissingSevereAndNoFallback() {
        XCTAssertEqual(EnvironmentBranchSelector.decide(proposedBranchID: "outdoor", branches: branches, snapshot: snapshot(expires: 0), serverNow: t0), .fallback(branchID: "fallback", reason: .snapshotStale))
        XCTAssertEqual(EnvironmentBranchSelector.decide(proposedBranchID: "outdoor", branches: branches, snapshot: nil, serverNow: t0), .fallback(branchID: "fallback", reason: .snapshotMissing))
        XCTAssertEqual(EnvironmentBranchSelector.decide(proposedBranchID: "cafe", branches: branches, snapshot: snapshot(weather: .severe), serverNow: t0), .pausedForSafety)
        XCTAssertEqual(EnvironmentBranchSelector.decide(proposedBranchID: "invented", branches: Array(branches.prefix(2)), snapshot: snapshot(), serverNow: t0), .noBranchAvailable)
    }
}

final class CommerceOrderReadbackTests: XCTestCase {
    private func line(_ id: String = "l1", quantity: Int = 2, tasks: [CommerceFulfilmentTask] = [], grants: [CommerceEntitlement] = [], refunds: [CommerceRefundRequest] = []) -> CommerceOrderLine {
        CommerceOrderLine(lineID: id, skuID: "sku", kind: .mixed, unitPriceMinor: 1000, quantity: quantity, currency: "CNY", fulfilment: tasks, entitlements: grants, refunds: refunds)
    }
    private func order(_ payment: CommerceOrderReadback.ServerPayment = .paid, _ lines: [CommerceOrderLine], asOf: Date = t0) -> CommerceOrderReadback? {
        CommerceOrderReadback(orderID: "o1", merchantID: "m1", asOf: asOf, payment: payment, lines: lines)
    }
    func testEntitlementNeverCountsAsFulfilmentAndProjectionComesFromLines() throws {
        let grant = CommerceEntitlement(grantSequence: 1, themeID: "theme", releaseID: "rel", state: .active)
        XCTAssertEqual(try XCTUnwrap(order(.paid, [line(tasks: [.init(sequence: 1, mode: .pickup, quantity: 2, state: .ready)], grants: [grant])])).projection, .awaitingFulfilment)
        XCTAssertEqual(try XCTUnwrap(order(.paid, [line(tasks: [.init(sequence: 1, mode: .pickup, quantity: 1, state: .fulfilled), .init(sequence: 2, mode: .pickup, quantity: 1, state: .ready)])])).projection, .partiallyFulfilled)
        XCTAssertEqual(try XCTUnwrap(order(.paid, [line(tasks: [.init(sequence: 1, mode: .pickup, quantity: 2, state: .fulfilled)])])).projection, .fulfilled)
        XCTAssertEqual(try XCTUnwrap(order(.unknown, [line()])).projection, .paymentUnknown)
        XCTAssertEqual(try XCTUnwrap(order(.paid, [line(refunds: [.init(refundNo: "r1", amountMinor: 1000, quantity: 1, state: .unknown)])])).projection, .refundUnknown)
    }
    func testMalformedLinesFailClosed() {
        XCTAssertNil(order(.paid, [line(tasks: [.init(sequence: 1, mode: .pickup, quantity: 3, state: .ready)])]))
        XCTAssertNil(order(.paid, [line(refunds: [.init(refundNo: "r1", amountMinor: 5000, quantity: 1, state: .succeeded)])]))
        XCTAssertNil(order(.paid, [line("l1"), line("l1")]))
    }
    func testLateReadbackCannotRevertTerminalFacts() throws {
        let refunded = try XCTUnwrap(order(.paid, [line(refunds: [.init(refundNo: "r1", amountMinor: 1000, quantity: 1, state: .succeeded)])]))
        let reverted = try XCTUnwrap(order(.paid, [line(refunds: [.init(refundNo: "r1", amountMinor: 1000, quantity: 1, state: .submitted)])], asOf: t0.addingTimeInterval(1)))
        XCTAssertFalse(CommerceOrderReadback.acceptsReadback(old: refunded, new: reverted))
        let older = try XCTUnwrap(order(.paid, [line()], asOf: t0.addingTimeInterval(-1)))
        XCTAssertFalse(CommerceOrderReadback.acceptsReadback(old: refunded, new: older))
        let unpaid = try XCTUnwrap(order(.unpaid, [line()], asOf: t0.addingTimeInterval(2)))
        XCTAssertFalse(CommerceOrderReadback.acceptsReadback(old: refunded, new: unpaid))
    }
    func testClientPaymentReturnOnlyQueriesAndQuoteChangesNeedConfirmation() {
        XCTAssertEqual(CommerceClientPaymentRules.onPaymentSurfaceReturned(orderID: "o1"), .queryOrder(orderID: "o1"))
        XCTAssertTrue(CommerceClientPaymentRules.quoteNeedsConfirmation(quotedVersion: "q1", quotedTotalMinor: 100, serverVersion: "q2", serverTotalMinor: 100))
        XCTAssertFalse(CommerceClientPaymentRules.quoteNeedsConfirmation(quotedVersion: "q1", quotedTotalMinor: 100, serverVersion: "q1", serverTotalMinor: 100))
        XCTAssertFalse(CommerceClientPaymentRules.paymentEnabled)
        XCTAssertFalse(MerchantAICommerceGates.disabled.paymentAndCashEnabled)
        XCTAssertTrue(MerchantAICommerceGates.reviewedEndpoints.isEmpty)
    }
}

final class MerchantStaffScopeTests: XCTestCase {
    private func grant(role: MerchantStaffRole = .redemptionStaff, held: Set<MerchantStaffRole.Permission> = [.basicRead, .verify], status: MerchantStaffScopeGrant.Status = .active,
                       until: Date? = nil, version: Int = 2) -> MerchantStaffScopeGrant {
        MerchantStaffScopeGrant(merchantID: "m1", storeID: "s1", userID: "u1", role: role, heldPermissions: held, validFrom: t0.addingTimeInterval(-10), validUntil: until, status: status, version: version)
    }
    func testProposedRolesNeverOverlapTheirProhibitions() {
        for role in MerchantStaffRole.allCases { XCTAssertTrue(role.proposedPermissions.isDisjoint(with: role.forbiddenPermissions), role.rawValue) }
        XCTAssertFalse(MerchantStaffRole.redemptionStaff.proposedPermissions.contains(.customerExport))
    }
    func testScopeChecksBothDimensionsAndRevocation() {
        XCTAssertEqual(MerchantStaffScopeCheck.decide(grant(), permission: .verify, merchantID: "m1", storeID: "s1", serverNow: t0, currentVersion: 2), .allowed)
        XCTAssertEqual(MerchantStaffScopeCheck.decide(grant(), permission: .verify, merchantID: "m1", storeID: "s2", serverNow: t0, currentVersion: 2), .denied(.otherStore))
        XCTAssertEqual(MerchantStaffScopeCheck.decide(grant(), permission: .verify, merchantID: "m9", storeID: "s1", serverNow: t0, currentVersion: 2), .denied(.otherMerchant))
        XCTAssertEqual(MerchantStaffScopeCheck.decide(grant(), permission: .verify, merchantID: "m1", storeID: "s1", serverNow: t0, currentVersion: 3), .denied(.staleVersion))
        XCTAssertEqual(MerchantStaffScopeCheck.decide(grant(status: .revoked), permission: .verify, merchantID: "m1", storeID: "s1", serverNow: t0, currentVersion: 2), .denied(.notActive))
        XCTAssertEqual(MerchantStaffScopeCheck.decide(grant(until: t0), permission: .verify, merchantID: "m1", storeID: "s1", serverNow: t0, currentVersion: 2), .denied(.expired))
        XCTAssertEqual(MerchantStaffScopeCheck.decide(grant(held: [.verify, .customerExport]), permission: .customerExport, merchantID: "m1", storeID: "s1", serverNow: t0, currentVersion: 2), .denied(.forbiddenForRole))
        XCTAssertEqual(MerchantStaffScopeCheck.decide(grant(), permission: .orderRead, merchantID: "m1", storeID: "s1", serverNow: t0, currentVersion: 2), .denied(.notHeld))
    }
    func testRedemptionPreviewAndCredentialFormat() {
        let preview = RedemptionPreviewReadback(previewID: "pv", storeID: "s1", itemTitle: "Item", quantityRemaining: 1, expiresAt: t0.addingTimeInterval(30))
        XCTAssertTrue(preview.confirmable(forStore: "s1", serverNow: t0))
        XCTAssertFalse(preview.confirmable(forStore: "s2", serverNow: t0))
        XCTAssertFalse(preview.confirmable(forStore: "s1", serverNow: t0.addingTimeInterval(30)))
        XCTAssertFalse(RedemptionCredentialFormat.looksOpaque("13800000000"))
        XCTAssertFalse(RedemptionCredentialFormat.looksOpaque("202610190000000001"))
        XCTAssertTrue(RedemptionCredentialFormat.looksOpaque("Zk3_q9-LmW2xP7rT"))
    }
}

final class RewardLedgerReadbackTests: XCTestCase {
    private func entry(_ id: String, amount: Int = 10, event: String = "ev1", reversalOf: String? = nil, season: String? = "s1") -> RewardLedgerEntry {
        RewardLedgerEntry(entryID: id, beneficiaryID: "b1", rewardType: .points, amount: amount, sourceEventID: event, ruleVersion: "r1", seasonID: season, reversalOf: reversalOf, recordedAt: t0)
    }
    func testDuplicateAwardsAndMalformedReversalsFailClosed() {
        XCTAssertThrowsError(try RewardLedgerReadback(validating: [entry("a"), entry("b")])) { XCTAssertEqual($0 as? RewardLedgerReadbackError, .duplicateBusinessKey) }
        XCTAssertThrowsError(try RewardLedgerReadback(validating: [entry("a"), entry("r", amount: -5, reversalOf: "a")])) { XCTAssertEqual($0 as? RewardLedgerReadbackError, .reversalMismatch) }
        XCTAssertThrowsError(try RewardLedgerReadback(validating: [entry("r", amount: -10, reversalOf: "missing")])) { XCTAssertEqual($0 as? RewardLedgerReadbackError, .reversalWithoutOriginal) }
        XCTAssertThrowsError(try RewardLedgerReadback(validating: [entry("a", amount: 0)])) { XCTAssertEqual($0 as? RewardLedgerReadbackError, .zeroAmount) }
    }
    func testReversalNetsToZeroAndHistoryIsAppendOnly() throws {
        let first = try RewardLedgerReadback(validating: [entry("a"), entry("c", event: "ev2", season: "s2")])
        let later = try RewardLedgerReadback(validating: first.entries + [entry("r", amount: -10, reversalOf: "a")])
        XCTAssertEqual(later.net(.points, beneficiary: "b1"), 10)
        XCTAssertEqual(later.seasonProjection(.points, beneficiary: "b1", seasonID: "s1"), 0)
        XCTAssertNoThrow(try RewardLedgerReadback.validateAppendOnly(old: first, new: later))
        let rewritten = try RewardLedgerReadback(validating: [entry("a", amount: 20), entry("c", event: "ev2", season: "s2")])
        XCTAssertThrowsError(try RewardLedgerReadback.validateAppendOnly(old: first, new: rewritten)) { XCTAssertEqual($0 as? RewardLedgerReadbackError, .historyRewritten) }
        XCTAssertThrowsError(try RewardLedgerReadback.validateAppendOnly(old: first, new: try RewardLedgerReadback(validating: [entry("a")]))) { XCTAssertEqual($0 as? RewardLedgerReadbackError, .entryRemoved) }
    }
}

final class SponsoredRewardPoolTests: XCTestCase {
    private func item(kind: SponsoredPrizeKind = .coupon, allocation: SponsoredAllocation = .fixedMilestone, reserved: Bool = false, pledge: String = "pl1") -> SponsoredPoolItem {
        SponsoredPoolItem(itemID: "i1", pledgeID: pledge, pledgeVersion: "v1", merchantID: "m1", storeID: "s1", kind: kind, allocation: allocation, title: "Item",
                          termsVersion: "t1", termsText: "Merchant terms", validFrom: t0, validUntil: t0.addingTimeInterval(86_400), remaining: 3, guaranteeReserved: reserved, asOf: t0)
    }
    func testAllCapabilitiesDefaultOffAndCashNeedsItsOwnSwitch() {
        for kind in SponsoredPrizeKind.allCases { for allocation in SponsoredAllocation.allCases {
            XCTAssertFalse(SponsoredRewardCapabilities.disabled.permits(kind, allocation))
        } }
        var caps = SponsoredRewardCapabilities(); caps.nonCash = true
        XCTAssertTrue(item().isPresentable(caps))
        XCTAssertFalse(item(kind: .cash).isPresentable(caps))
        XCTAssertFalse(item(allocation: .random).isPresentable(caps))
        caps.guaranteed = true
        XCTAssertFalse(item(allocation: .guaranteed, reserved: false).isPresentable(caps))
        XCTAssertTrue(item(allocation: .guaranteed, reserved: true).isPresentable(caps))
    }
    func testLimitedDisclosureUnlessQuotaIsReserved() {
        XCTAssertEqual(item().disclosure, .limitedWhileSuppliesLast)
        XCTAssertEqual(item(allocation: .guaranteed, reserved: false).disclosure, .limitedWhileSuppliesLast)
        XCTAssertEqual(item(allocation: .guaranteed, reserved: true).disclosure, .guaranteedReserved)
    }
    func testIssuedVoucherTermsCannotShrinkAndBindingStaysInScope() {
        let issued = SponsoredVoucherTerms(voucherID: "v1", termsVersion: "t1", validUntil: t0)
        XCTAssertFalse(SponsoredVoucherTerms.acceptsReadback(issued: issued, later: .init(voucherID: "v1", termsVersion: "t1", validUntil: t0.addingTimeInterval(-1))))
        XCTAssertFalse(SponsoredVoucherTerms.acceptsReadback(issued: issued, later: .init(voucherID: "v1", termsVersion: "t2", validUntil: t0)))
        var caps = SponsoredRewardCapabilities(); caps.nonCash = true
        XCTAssertNil(SponsoredRewardBinding.refusal(item: item(), authorizedPledgeIDs: ["pl1"], capabilities: caps, targetIsOfficialMap: false))
        XCTAssertEqual(SponsoredRewardBinding.refusal(item: item(pledge: "other"), authorizedPledgeIDs: ["pl1"], capabilities: caps, targetIsOfficialMap: false), .pledgeNotAuthorized)
        XCTAssertEqual(SponsoredRewardBinding.refusal(item: item(), authorizedPledgeIDs: ["pl1"], capabilities: caps, targetIsOfficialMap: true), .mapRulesOutOfScope)
        XCTAssertTrue(SponsoredRewardEligibility.merchantMayOffer(compliant: true, canFulfil: true, supplyAuthorized: true))
        XCTAssertNil(SponsoredPoolStatistics(pledged: 5, reviewedAvailable: 5, reserved: 0, awarded: 1, redeemed: 2, frozenOrExpired: 0, returnedToPool: 0, replenished: 0, asOf: t0))
    }
}
