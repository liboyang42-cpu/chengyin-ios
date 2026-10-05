import XCTest
@testable import QuestifyCore

@MainActor private final class TemplateMediaIdentityTestStorage: TemplateAuthoringStorage {
    var values: [String: Data] = [:]
    func read(_ key: String) throws -> Data? { values[key] }
    func write(_ data: Data, key: String) throws { values[key] = data }
    func remove(_ key: String) throws { values.removeValue(forKey: key) }
}

@MainActor final class TemplateAuthoringMediaIdentityTests: XCTestCase {
    private func owner(account: Int = 1, namespace: String = "template-media-tests",
                       epoch: UInt64 = 1, authorization: String = "member",
                       draft: TemplateAuthoringIdentity = .init()) throws -> TemplateAuthoringMediaOwner {
        .init(session: try .init(accountID: account, namespace: namespace, epoch: epoch,
                                 authorizationRevision: authorization), draft: draft)
    }

    private func target(_ scope: TemplateAuthoringMediaIdentityScope, slotID: UUID) throws -> TemplateAuthoringMediaTargetIdentity {
        try XCTUnwrap(scope.visibleTargets.first { $0.slot.id == slotID })
    }

    private func fixedSlots() -> [TemplateAuthoringMediaSlot] {
        var fields: [TemplateAuthoringMediaField] = [.questionImage, .questionAudio, .narration]
        for letter in TemplateChoiceOptionMedia.Letter.allCases {
            fields += [.optionImage(letter), .optionAudio(letter)]
        }
        return fields.map { .init(field: $0) }
    }

    func testCapturedInitiatingActionCannotStartAfterSameSlotEditorReset() throws {
        for reason in [TemplateAuthoringMediaIdentityScope.ResetReason.restored, .discarded, .editorReloaded, .ownerChanged] {
            let owner = try owner(), slot = TemplateAuthoringMediaSlot(field: .questionImage)
            let scope = try TemplateAuthoringMediaIdentityScope(owner: owner, slots: [slot], currentOwner: { owner })
            let capturedTarget = try target(scope, slotID: slot.id)
            let oldAction = { try scope.beginSelection(target: capturedTarget) }
            try scope.reset(owner: owner, slots: [slot], reason: reason)
            let current = try scope.beginSelection(target: try target(scope, slotID: slot.id))
            XCTAssertThrowsError(try oldAction()) { error in
                XCTAssertEqual(error as? TemplateAuthoringMediaIdentityScope.Failure, .staleTarget)
            }
            XCTAssertTrue(scope.finishSelection(current))
        }
    }

    func testCapturedInitiatingActionCannotStartAfterClearOrReplacement() throws {
        for reason in [TemplateAuthoringMediaIdentityScope.ReferenceChange.cleared, .replaced] {
            let owner = try owner(), slot = TemplateAuthoringMediaSlot(field: .questionAudio)
            let scope = try TemplateAuthoringMediaIdentityScope(owner: owner, slots: [slot], currentOwner: { owner })
            let capturedTarget = try target(scope, slotID: slot.id)
            let oldAction = { try scope.beginSelection(target: capturedTarget) }
            try scope.referenceDidChange(slotID: slot.id, reason: reason)
            let current = try scope.beginSelection(target: try target(scope, slotID: slot.id))
            XCTAssertThrowsError(try oldAction()) { error in
                XCTAssertEqual(error as? TemplateAuthoringMediaIdentityScope.Failure, .staleTarget)
            }
            XCTAssertTrue(scope.isCurrent(current)); XCTAssertTrue(scope.finishSelection(current))
        }
    }

    func testCapturedInitiatingActionCannotStartAfterReorderOrInvisibleTopologyEvent() throws {
        for explicitEvent in [false, true] {
            let owner = try owner(), slots = fixedSlots()
            let scope = try TemplateAuthoringMediaIdentityScope(owner: owner, slots: slots, currentOwner: { owner })
            let capturedTarget = try target(scope, slotID: slots[0].id)
            let oldAction = { try scope.beginSelection(target: capturedTarget) }
            if explicitEvent { try scope.topologyDidChange() }
            else { try scope.synchronizeSlots(Array(slots.reversed())) }
            let current = try scope.beginSelection(target: try target(scope, slotID: slots[0].id))
            XCTAssertThrowsError(try oldAction()) { error in
                XCTAssertEqual(error as? TemplateAuthoringMediaIdentityScope.Failure, .staleTarget)
            }
            XCTAssertTrue(scope.finishSelection(current))
        }
    }

    func testCapturedInitiatingActionCannotStartAfterDeleteAndSameIDReinsertion() throws {
        let owner = try owner(), slot = TemplateAuthoringMediaSlot(field: .storyBeatImage(beatID: UUID()))
        let scope = try TemplateAuthoringMediaIdentityScope(owner: owner, slots: [slot], currentOwner: { owner })
        let capturedTarget = try target(scope, slotID: slot.id)
        let oldAction = { try scope.beginSelection(target: capturedTarget) }
        try scope.synchronizeSlots([]); try scope.synchronizeSlots([slot])
        let current = try scope.beginSelection(target: try target(scope, slotID: slot.id))
        XCTAssertThrowsError(try oldAction()) { error in
            XCTAssertEqual(error as? TemplateAuthoringMediaIdentityScope.Failure, .staleTarget)
        }
        XCTAssertTrue(scope.finishSelection(current))
    }

    func testCapturedOptionAActionCannotStartForOptionBAssignedSameSlotID() throws {
        let owner = try owner(), slot = TemplateAuthoringMediaSlot(field: .optionAudio(.a))
        let scope = try TemplateAuthoringMediaIdentityScope(owner: owner, slots: [slot], currentOwner: { owner })
        let capturedTarget = try target(scope, slotID: slot.id)
        let oldAction = { try scope.beginSelection(target: capturedTarget) }
        try scope.synchronizeSlots([.init(field: .optionAudio(.b), id: slot.id)])
        let current = try scope.beginSelection(target: try target(scope, slotID: slot.id))
        XCTAssertThrowsError(try oldAction()) { error in
            XCTAssertEqual(error as? TemplateAuthoringMediaIdentityScope.Failure, .staleTarget)
        }
        XCTAssertEqual(current.slot.field, .optionAudio(.b)); XCTAssertTrue(scope.finishSelection(current))
    }

    func testCapturedInitiatingActionCannotCrossOwnerChangeOrRetiredAccountRoundTrip() throws {
        let original = try owner(), draft = original.draft
        let alternatives = [try owner(account: 2, draft: draft), try owner(namespace: "other", draft: draft),
                            try owner(epoch: 2, draft: draft), try owner(authorization: "changed", draft: draft),
                            try owner(), original]
        for replacement in alternatives {
            var currentOwner: TemplateAuthoringMediaOwner? = original
            let slot = TemplateAuthoringMediaSlot(field: .questionAudio)
            let scope = try TemplateAuthoringMediaIdentityScope(owner: original, slots: [slot], currentOwner: { currentOwner })
            let capturedTarget = try target(scope, slotID: slot.id)
            let oldAction = { try scope.beginSelection(target: capturedTarget) }
            scope.retire()
            currentOwner = try owner(account: 2, draft: draft)
            currentOwner = replacement // Includes an otherwise unobserved A -> B -> A round trip.
            try scope.reset(owner: replacement, slots: [slot], reason: .ownerChanged)
            let current = try scope.beginSelection(target: try target(scope, slotID: slot.id))
            XCTAssertThrowsError(try oldAction()) { error in
                XCTAssertEqual(error as? TemplateAuthoringMediaIdentityScope.Failure, .staleTarget)
            }
            XCTAssertEqual(current.owner, replacement); XCTAssertTrue(scope.finishSelection(current))
        }
    }

    func testCapturedTargetCannotStartInAnotherEditorOrAfterCompletionOrCancellation() throws {
        let owner = try owner(), slot = TemplateAuthoringMediaSlot(field: .narration)
        let first = try TemplateAuthoringMediaIdentityScope(owner: owner, slots: [slot], currentOwner: { owner })
        let second = try TemplateAuthoringMediaIdentityScope(owner: owner, slots: [slot], currentOwner: { owner })
        let capturedTarget = try target(first, slotID: slot.id)
        XCTAssertThrowsError(try second.beginSelection(target: capturedTarget))
        let selection = try first.beginSelection(target: capturedTarget)
        XCTAssertTrue(first.finishSelection(selection))
        XCTAssertThrowsError(try first.beginSelection(target: capturedTarget))
        let nextTarget = try target(first, slotID: slot.id)
        let next = try first.beginSelection(target: nextTarget)
        XCTAssertTrue(first.cancelSelection(next))
        XCTAssertThrowsError(try first.beginSelection(target: nextTarget))
    }

    func testCapturesFullOwnerEditorSlotRevisionAndSelectionIdentity() throws {
        let owner = try owner(), slot = TemplateAuthoringMediaSlot(field: .questionImage)
        let scope = try TemplateAuthoringMediaIdentityScope(owner: owner, slots: [slot], currentOwner: { owner })
        let first = try scope.beginSelection(target: try target(scope, slotID: slot.id))
        let next = try scope.beginSelection(target: try target(scope, slotID: slot.id))
        XCTAssertEqual(first.owner, owner)
        XCTAssertEqual(first.owner.draft.draftID, owner.draft.draftID)
        XCTAssertEqual(first.slot, slot)
        XCTAssertEqual(first.editorID, next.editorID)
        XCTAssertEqual(first.slotRevision, next.slotRevision)
        XCTAssertNotEqual(first.selectionID, next.selectionID)
        XCTAssertFalse(scope.isCurrent(first)); XCTAssertTrue(scope.isCurrent(next))
    }

    func testAllFixedFieldsAndChoicesKeepIndependentSelections() throws {
        let owner = try owner(), slots = fixedSlots()
        let scope = try TemplateAuthoringMediaIdentityScope(owner: owner, slots: slots, currentOwner: { owner })
        let identities = try slots.map { try scope.beginSelection(target: try target(scope, slotID: $0.id)) }
        XCTAssertEqual(identities.count, 11)
        XCTAssertEqual(Set(identities.map(\.selectionID)).count, 11)
        for identity in identities { XCTAssertTrue(scope.isCurrent(identity)) }
        XCTAssertTrue(scope.finishSelection(identities[0]))
        for identity in identities.dropFirst() { XCTAssertTrue(scope.isCurrent(identity)) }
    }

    func testCompletionIsSingleUseAndCannotFinishANewerSelection() throws {
        let owner = try owner(), slot = TemplateAuthoringMediaSlot(field: .narration)
        let scope = try TemplateAuthoringMediaIdentityScope(owner: owner, slots: [slot], currentOwner: { owner })
        let first = try scope.beginSelection(target: try target(scope, slotID: slot.id))
        let next = try scope.beginSelection(target: try target(scope, slotID: slot.id))
        XCTAssertFalse(scope.finishSelection(first)); XCTAssertTrue(scope.isCurrent(next))
        XCTAssertTrue(scope.finishSelection(next)); XCTAssertFalse(scope.finishSelection(next))
        XCTAssertFalse(scope.isCurrent(next))
    }

    func testCancelInvalidatesOnlyItsSelectionAndLateCancelLeavesNewerSelection() throws {
        let owner = try owner(), slots = fixedSlots()
        let scope = try TemplateAuthoringMediaIdentityScope(owner: owner, slots: slots, currentOwner: { owner })
        let first = try scope.beginSelection(target: try target(scope, slotID: slots[0].id))
        let sibling = try scope.beginSelection(target: try target(scope, slotID: slots[1].id))
        XCTAssertTrue(scope.cancelSelection(first)); XCTAssertFalse(scope.finishSelection(first))
        let next = try scope.beginSelection(target: try target(scope, slotID: slots[0].id))
        XCTAssertFalse(scope.cancelSelection(first))
        XCTAssertTrue(scope.isCurrent(next)); XCTAssertTrue(scope.isCurrent(sibling))
    }

    func testClearAndReplacementAdvanceRevisionWithoutTouchingSibling() throws {
        for reason in [TemplateAuthoringMediaIdentityScope.ReferenceChange.cleared, .replaced] {
            let owner = try owner(), slots = fixedSlots()
            let scope = try TemplateAuthoringMediaIdentityScope(owner: owner, slots: slots, currentOwner: { owner })
            let original = try scope.beginSelection(target: try target(scope, slotID: slots[0].id))
            let sibling = try scope.beginSelection(target: try target(scope, slotID: slots[1].id))
            // Report explicit replacement even if the host's old and new raw strings are equal.
            try scope.referenceDidChange(slotID: slots[0].id, reason: reason)
            XCTAssertFalse(scope.isCurrent(original)); XCTAssertTrue(scope.isCurrent(sibling))
            let next = try scope.beginSelection(target: try target(scope, slotID: slots[0].id))
            XCTAssertNotEqual(original.slotRevision, next.slotRevision)
            XCTAssertEqual(original.editorID, next.editorID)
        }
    }

    func testTwoEditorsForSameOwnerAndSlotsCannotConsumeEachOthersSelection() throws {
        let owner = try owner(), slots = fixedSlots()
        let first = try TemplateAuthoringMediaIdentityScope(owner: owner, slots: slots, currentOwner: { owner })
        let second = try TemplateAuthoringMediaIdentityScope(owner: owner, slots: slots, currentOwner: { owner })
        let original = try first.beginSelection(target: try target(first, slotID: slots[0].id))
        let parallel = try second.beginSelection(target: try target(second, slotID: slots[0].id))
        XCTAssertNotEqual(original.editorID, parallel.editorID)
        XCTAssertFalse(second.finishSelection(original)); XCTAssertFalse(first.finishSelection(parallel))
        XCTAssertTrue(first.isCurrent(original)); XCTAssertTrue(second.isCurrent(parallel))
    }

    func testReorderInvalidatesEvenTheSlotWhosePositionDidNotMove() throws {
        let owner = try owner(), beatID = UUID()
        let slots = [TemplateAuthoringMediaSlot(field: .questionAudio),
                     .init(field: .storyBeatImage(beatID: beatID)),
                     .init(field: .storyBeatImage(beatID: beatID))]
        let scope = try TemplateAuthoringMediaIdentityScope(owner: owner, slots: slots, currentOwner: { owner })
        let pending = try slots.map { try scope.beginSelection(target: try target(scope, slotID: $0.id)) }
        try scope.synchronizeSlots([slots[0], slots[2], slots[1]])
        for identity in pending { XCTAssertFalse(scope.isCurrent(identity)) }
        XCTAssertEqual(scope.visibleSlots, [slots[0], slots[2], slots[1]])
        let next = try scope.beginSelection(target: try target(scope, slotID: slots[0].id))
        XCTAssertNotEqual(next.slotRevision, pending[0].slotRevision)
    }

    func testDeleteAndReinsertSameIDCannotReviveOldSelection() throws {
        let owner = try owner(), slot = TemplateAuthoringMediaSlot(field: .storyBeatImage(beatID: UUID()))
        let scope = try TemplateAuthoringMediaIdentityScope(owner: owner, slots: [slot], currentOwner: { owner })
        let first = try scope.beginSelection(target: try target(scope, slotID: slot.id))
        try scope.synchronizeSlots([])
        XCTAssertFalse(scope.isCurrent(first))
        XCTAssertThrowsError(try scope.beginSelection(target: first.target)) { error in
            XCTAssertEqual(error as? TemplateAuthoringMediaIdentityScope.Failure, .staleTarget)
        }
        try scope.synchronizeSlots([slot])
        let next = try scope.beginSelection(target: try target(scope, slotID: slot.id))
        XCTAssertNotEqual(first.slotRevision, next.slotRevision)
        XCTAssertFalse(scope.finishSelection(first)); XCTAssertTrue(scope.isCurrent(next))
    }

    func testChangingFieldWithSameSlotIDInvalidatesOldTarget() throws {
        let owner = try owner(), slot = TemplateAuthoringMediaSlot(field: .optionAudio(.a))
        let scope = try TemplateAuthoringMediaIdentityScope(owner: owner, slots: [slot], currentOwner: { owner })
        let old = try scope.beginSelection(target: try target(scope, slotID: slot.id))
        let replacement = TemplateAuthoringMediaSlot(field: .optionAudio(.b), id: slot.id)
        try scope.synchronizeSlots([replacement])
        XCTAssertFalse(scope.isCurrent(old))
        let next = try scope.beginSelection(target: try target(scope, slotID: slot.id))
        XCTAssertEqual(next.slot.field, .optionAudio(.b)); XCTAssertNotEqual(next.slotRevision, old.slotRevision)
    }

    func testNoOpSynchronizationRetainsPendingSelections() throws {
        let owner = try owner(), slots = fixedSlots()
        let scope = try TemplateAuthoringMediaIdentityScope(owner: owner, slots: slots, currentOwner: { owner })
        let identity = try scope.beginSelection(target: try target(scope, slotID: slots[0].id))
        try scope.synchronizeSlots(slots)
        XCTAssertTrue(scope.isCurrent(identity))
    }

    func testExplicitTopologyEventInvalidatesAnUnchangedMediaList() throws {
        let owner = try owner(), slots = fixedSlots()
        let scope = try TemplateAuthoringMediaIdentityScope(owner: owner, slots: slots, currentOwner: { owner })
        let pending = try slots.map { try scope.beginSelection(target: try target(scope, slotID: $0.id)) }
        // Example: move/delete an empty story beat, absent from the flattened media list.
        try scope.topologyDidChange()
        XCTAssertEqual(scope.visibleSlots, slots)
        for identity in pending { XCTAssertFalse(scope.isCurrent(identity)) }
        let next = try scope.beginSelection(target: try target(scope, slotID: slots[0].id))
        XCTAssertNotEqual(next.slotRevision, pending[0].slotRevision)
    }

    func testInvalidTopologyFailsClosedUntilExplicitReset() throws {
        let owner = try owner(), slot = TemplateAuthoringMediaSlot(field: .questionImage)
        let scope = try TemplateAuthoringMediaIdentityScope(owner: owner, slots: [slot], currentOwner: { owner })
        let identity = try scope.beginSelection(target: try target(scope, slotID: slot.id))
        XCTAssertThrowsError(try scope.synchronizeSlots([slot, slot]))
        XCTAssertFalse(scope.isCurrent(identity)); XCTAssertTrue(scope.visibleSlots.isEmpty)
        XCTAssertThrowsError(try scope.beginSelection(target: identity.target))
        try scope.reset(owner: owner, slots: [slot], reason: .editorReloaded)
        XCTAssertFalse(scope.isCurrent(identity)); XCTAssertEqual(scope.visibleSlots, [slot])
    }

    func testDuplicateFixedFieldOrSlotIDIsRejectedButStoryImagesRemainDistinct() throws {
        let owner = try owner(), slot = TemplateAuthoringMediaSlot(field: .questionImage)
        for invalid in [[slot, slot], [slot, .init(field: .questionImage)],
                        [slot, .init(field: .questionAudio, id: slot.id)]] {
            XCTAssertThrowsError(try TemplateAuthoringMediaIdentityScope(owner: owner, slots: invalid,
                                                                       currentOwner: { owner })) { error in
                XCTAssertEqual(error as? TemplateAuthoringMediaIdentityScope.Failure, .invalidSlots)
            }
        }
        let beatID = UUID()
        let images = [TemplateAuthoringMediaSlot(field: .storyBeatImage(beatID: beatID)),
                      .init(field: .storyBeatImage(beatID: beatID))]
        let scope = try TemplateAuthoringMediaIdentityScope(owner: owner, slots: images, currentOwner: { owner })
        XCTAssertEqual(scope.visibleSlots, images)
    }

    func testRestoreDiscardAndReloadMintNewIncarnationEvenForSameDraftAndSlots() throws {
        for reason in [TemplateAuthoringMediaIdentityScope.ResetReason.restored, .discarded, .editorReloaded, .ownerChanged] {
            let owner = try owner(), slots = fixedSlots()
            let scope = try TemplateAuthoringMediaIdentityScope(owner: owner, slots: slots, currentOwner: { owner })
            let old = try scope.beginSelection(target: try target(scope, slotID: slots[0].id))
            try scope.reset(owner: owner, slots: slots, reason: reason)
            let next = try scope.beginSelection(target: try target(scope, slotID: slots[0].id))
            XCTAssertEqual(old.owner.draft.draftID, next.owner.draft.draftID)
            XCTAssertNotEqual(old.editorID, next.editorID)
            XCTAssertNotEqual(old.slotRevision, next.slotRevision)
            XCTAssertFalse(scope.isCurrent(old)); XCTAssertTrue(scope.isCurrent(next))
        }
    }

    func testFailedResetInvalidatesOldLeaseBeforeValidation() throws {
        let owner = try owner(), slot = TemplateAuthoringMediaSlot(field: .narration)
        let scope = try TemplateAuthoringMediaIdentityScope(owner: owner, slots: [slot], currentOwner: { owner })
        let old = try scope.beginSelection(target: try target(scope, slotID: slot.id))
        XCTAssertThrowsError(try scope.reset(owner: owner, slots: [slot, slot], reason: .restored))
        XCTAssertFalse(scope.isCurrent(old)); XCTAssertTrue(scope.visibleSlots.isEmpty)
        let other = try self.owner()
        XCTAssertThrowsError(try scope.reset(owner: other, slots: [slot], reason: .ownerChanged))
        XCTAssertThrowsError(try scope.beginSelection(target: old.target))
    }

    func testEverySessionDimensionAndDraftIdentityInvalidatesLease() throws {
        let original = try owner(), draft = original.draft
        let alternatives = [try owner(account: 2, draft: draft), try owner(namespace: "other", draft: draft),
                            try owner(epoch: 2, draft: draft), try owner(authorization: "changed", draft: draft),
                            try owner()]
        XCTAssertEqual(original.session.ownerKey, alternatives[2].session.ownerKey)
        for alternative in alternatives {
            var current: TemplateAuthoringMediaOwner? = original
            let slot = TemplateAuthoringMediaSlot(field: .questionAudio)
            let scope = try TemplateAuthoringMediaIdentityScope(owner: original, slots: [slot], currentOwner: { current })
            let old = try scope.beginSelection(target: try target(scope, slotID: slot.id))
            current = alternative
            XCTAssertFalse(scope.isCurrent(old)); XCTAssertTrue(scope.visibleSlots.isEmpty)
            current = original
            XCTAssertFalse(scope.isCurrent(old))
            XCTAssertThrowsError(try scope.beginSelection(target: old.target))
        }
    }

    func testExplicitRetirementFencesUnobservedAccountRoundTrip() throws {
        let original = try owner(), other = try owner(account: 2)
        var current: TemplateAuthoringMediaOwner? = original
        let slot = TemplateAuthoringMediaSlot(field: .questionImage)
        let scope = try TemplateAuthoringMediaIdentityScope(owner: original, slots: [slot], currentOwner: { current })
        let old = try scope.beginSelection(target: try target(scope, slotID: slot.id))
        // Hosts must retire before the transition. Equality polling alone cannot see A -> B -> A.
        scope.retire(); current = other; current = original
        XCTAssertFalse(scope.isCurrent(old)); XCTAssertThrowsError(try scope.beginSelection(target: old.target))
        try scope.reset(owner: original, slots: [slot], reason: .ownerChanged)
        XCTAssertFalse(scope.isCurrent(old)); XCTAssertTrue(scope.isCurrent(try scope.beginSelection(target: try target(scope, slotID: slot.id))))
    }

    func testSignOutRetiresScopeAndRejectsEveryMutation() throws {
        let original = try owner()
        var current: TemplateAuthoringMediaOwner? = original
        let slot = TemplateAuthoringMediaSlot(field: .questionImage)
        let scope = try TemplateAuthoringMediaIdentityScope(owner: original, slots: [slot], currentOwner: { current })
        let old = try scope.beginSelection(target: try target(scope, slotID: slot.id))
        current = nil
        XCTAssertFalse(scope.finishSelection(old)); XCTAssertFalse(scope.cancelSelection(old))
        XCTAssertThrowsError(try scope.beginSelection(target: old.target))
        XCTAssertThrowsError(try scope.referenceDidChange(slotID: slot.id, reason: .cleared))
        XCTAssertThrowsError(try scope.synchronizeSlots([slot]))
        XCTAssertThrowsError(try scope.topologyDidChange())
        XCTAssertThrowsError(try TemplateAuthoringMediaIdentityScope(owner: original, slots: [slot], currentOwner: { nil }))
    }

    func testMissingSlotDoesNotInvalidateOtherPendingTarget() throws {
        let owner = try owner(), slot = TemplateAuthoringMediaSlot(field: .optionImage(.d))
        let scope = try TemplateAuthoringMediaIdentityScope(owner: owner, slots: [slot], currentOwner: { owner })
        let pending = try scope.beginSelection(target: try target(scope, slotID: slot.id))
        XCTAssertThrowsError(try scope.referenceDidChange(slotID: UUID(), reason: .replaced))
        XCTAssertTrue(scope.isCurrent(pending))
    }

    func testRealCoordinatorDiscardPreservesDraftIDSoHostMustResetMediaIncarnation() throws {
        let session = try owner().session
        let store = TemplateAuthoringLocalStore(storage: TemplateMediaIdentityTestStorage())
        let coordinator = TemplateAuthoringCoordinator(store: store, currentSession: { session })
        coordinator.open(seed: .init(title: "Local media draft")); coordinator.saveLocal()
        let identity = coordinator.identity
        let owner = TemplateAuthoringMediaOwner(session: session, draft: identity)
        let slot = TemplateAuthoringMediaSlot(field: .questionImage)
        let scope = try TemplateAuthoringMediaIdentityScope(owner: owner, slots: [slot], currentOwner: {
            .init(session: session, draft: coordinator.identity)
        })
        let old = try scope.beginSelection(target: try target(scope, slotID: slot.id))
        coordinator.discardLocal()
        XCTAssertEqual(coordinator.identity, identity)
        XCTAssertEqual(try store.active(session: session), identity)
        XCTAssertEqual(store.load(session: session, identity: identity), .missing)
        // No host wiring is installed by this seam; the lifecycle callback is explicit.
        try scope.reset(owner: owner, slots: [slot], reason: .discarded)
        let next = try scope.beginSelection(target: try target(scope, slotID: slot.id))
        XCTAssertNotEqual(old.editorID, next.editorID); XCTAssertFalse(scope.isCurrent(old))
    }
}
