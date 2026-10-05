import Foundation

/// Template-only ownership. This conveys no permission to select, read or upload media.
public struct TemplateAuthoringMediaOwner: Equatable {
    public let session: TemplateAuthoringSession
    public let draft: TemplateAuthoringIdentity
    public init(session: TemplateAuthoringSession, draft: TemplateAuthoringIdentity) {
        self.session = session; self.draft = draft
    }
}

public enum TemplateAuthoringMediaField: Equatable {
    case questionImage, questionAudio
    case optionImage(TemplateChoiceOptionMedia.Letter)
    case optionAudio(TemplateChoiceOptionMedia.Letter)
    case storyBeatImage(beatID: UUID)
    case narration
}

/// A slot is not an array index or a reference string. Duplicate references get distinct slots.
/// Preserve this ID while a loaded editor moves a slot; mint a new ID for a new attachment.
public struct TemplateAuthoringMediaSlot: Equatable, Identifiable {
    public let id: UUID
    public let field: TemplateAuthoringMediaField
    public init(field: TemplateAuthoringMediaField, id: UUID = UUID()) {
        self.id = id; self.field = field
    }
}

/// Capture from visibleTargets when an action is created, not when its delayed closure runs.
/// Its immutable owner, editor incarnation, field/slot and revision fence stale initiations.
public struct TemplateAuthoringMediaTargetIdentity: Equatable {
    public let owner: TemplateAuthoringMediaOwner
    public let editorID: UUID
    public let slot: TemplateAuthoringMediaSlot
    public let slotRevision: UUID
    fileprivate init(owner: TemplateAuthoringMediaOwner, editorID: UUID,
                     slot: TemplateAuthoringMediaSlot, slotRevision: UUID) {
        self.owner = owner; self.editorID = editorID; self.slot = slot; self.slotRevision = slotRevision
    }
}

/// In-memory callback identity only, never an upload receipt or a durable recovery key.
/// Deliberately not Codable: story wire rows do not retain their loaded editor UUIDs.
public struct TemplateAuthoringMediaSelectionIdentity: Equatable {
    public let owner: TemplateAuthoringMediaOwner
    public let editorID: UUID
    public let slot: TemplateAuthoringMediaSlot
    public let slotRevision: UUID
    public let selectionID: UUID
    public var target: TemplateAuthoringMediaTargetIdentity {
        .init(owner: owner, editorID: editorID, slot: slot, slotRevision: slotRevision)
    }
    fileprivate init(owner: TemplateAuthoringMediaOwner, editorID: UUID,
                     slot: TemplateAuthoringMediaSlot, slotRevision: UUID, selectionID: UUID) {
        self.owner = owner; self.editorID = editorID; self.slot = slot
        self.slotRevision = slotRevision; self.selectionID = selectionID
    }
}

/// Dormant identity seam. It has no picker, media bytes, transport, journal, origin or grant.
/// Future hosts must announce reference edits and topology changes before handling callbacks,
/// and reset on restore/discard/reload, even when the persisted draftID is unchanged.
/// Retire immediately on editor dismissal or any ownership transition. Polling currentOwner
/// cannot detect an unobserved A -> B -> A transition; a future host must report that event.
/// This scope cannot authorize an upload or resolve an uncertain upload after relaunch.
@MainActor public final class TemplateAuthoringMediaIdentityScope {
    public enum Failure: Error, Equatable { case staleOwner, staleTarget, invalidSlots, missingSlot }
    public enum ReferenceChange { case cleared, replaced }
    public enum ResetReason { case restored, discarded, editorReloaded, ownerChanged }
    private struct Entry {
        let slot: TemplateAuthoringMediaSlot
        var revision = UUID()
        var selectionID: UUID?
    }
    private let currentOwner: () -> TemplateAuthoringMediaOwner?
    private var owner: TemplateAuthoringMediaOwner
    private var editorID = UUID()
    private var entries: [Entry]
    private var retired = false

    public init(owner: TemplateAuthoringMediaOwner, slots: [TemplateAuthoringMediaSlot],
                currentOwner: @escaping () -> TemplateAuthoringMediaOwner?) throws {
        try Self.validate(slots)
        guard currentOwner() == owner else { throw Failure.staleOwner }
        self.owner = owner; self.entries = slots.map { Entry(slot: $0) }; self.currentOwner = currentOwner
    }

    public var visibleSlots: [TemplateAuthoringMediaSlot] {
        hasCurrentOwner() ? entries.map(\.slot) : []
    }

    /// Bind each action to this value before asynchronous work or delayed closure execution.
    /// Refresh actions after a lifecycle/reference/topology event; never reacquire a target
    /// by UUID inside an already-created action to make its stale initiation appear current.
    public var visibleTargets: [TemplateAuthoringMediaTargetIdentity] {
        guard hasCurrentOwner() else { return [] }
        return entries.map { .init(owner: owner, editorID: editorID, slot: $0.slot, slotRevision: $0.revision) }
    }

    /// Reserves a callback identity, without accessing a device or opening a picker.
    /// A newer selection for this same slot invalidates the preceding selection immediately.
    public func beginSelection(target: TemplateAuthoringMediaTargetIdentity) throws -> TemplateAuthoringMediaSelectionIdentity {
        guard hasCurrentOwner() else { throw Failure.staleOwner }
        guard target.owner == owner, target.editorID == editorID,
              let index = entries.firstIndex(where: { $0.slot == target.slot && $0.revision == target.slotRevision }) else {
            throw Failure.staleTarget
        }
        let selectionID = UUID(); entries[index].selectionID = selectionID
        return .init(owner: target.owner, editorID: target.editorID, slot: target.slot,
                     slotRevision: target.slotRevision, selectionID: selectionID)
    }

    public func isCurrent(_ identity: TemplateAuthoringMediaSelectionIdentity) -> Bool {
        guard hasCurrentOwner(), identity.owner == owner, identity.editorID == editorID,
              let entry = entries.first(where: { $0.slot == identity.slot }) else { return false }
        return entry.revision == identity.slotRevision && entry.selectionID == identity.selectionID
    }

    /// Consumes the identity once and retires its target revision so queued starts also expire.
    /// Success asserts freshness only, not media or upload validity.
    /// A future host must consume immediately before its same-MainActor reference mutation,
    /// without an intervening await. This method does not perform that mutation.
    @discardableResult public func finishSelection(_ identity: TemplateAuthoringMediaSelectionIdentity) -> Bool {
        guard isCurrent(identity), let index = entries.firstIndex(where: { $0.slot == identity.slot }) else { return false }
        entries[index].selectionID = nil; entries[index].revision = UUID()
        return true
    }

    /// Cancels only this selection. A late cancellation cannot cancel a newer selection.
    @discardableResult public func cancelSelection(_ identity: TemplateAuthoringMediaSelectionIdentity) -> Bool {
        finishSelection(identity)
    }

    /// Explicit clear/replacement invalidates even when the reference text happens to be equal.
    public func referenceDidChange(slotID: UUID, reason: ReferenceChange) throws {
        guard hasCurrentOwner() else { throw Failure.staleOwner }
        guard let index = entries.firstIndex(where: { $0.slot.id == slotID }) else { throw Failure.missingSlot }
        entries[index].revision = UUID(); entries[index].selectionID = nil
    }

    /// Keep stable IDs during moves. Any topology change conservatively cancels all pending
    /// selections, including those on slots whose array position did not change. This also
    /// fences an image slot when another beat is moved past it. A no-op retains selections.
    /// For a structural edit not represented in this list (such as moving an empty story
    /// beat), call topologyDidChange as well. Invalid input retires the scope, failing closed.
    /// Deleted slots disappear; reintroducing a deleted ID cannot revive a prior selection.
    public func synchronizeSlots(_ slots: [TemplateAuthoringMediaSlot]) throws {
        guard hasCurrentOwner() else { throw Failure.staleOwner }
        do { try Self.validate(slots) }
        catch { retire(); throw error }
        guard slots != entries.map(\.slot) else { return }
        entries = slots.map { Entry(slot: $0) }
    }

    /// Report structural edits even when the flattened media-slot list is unchanged.
    /// Keep the slots, but invalidate every pending callback and advance every revision.
    public func topologyDidChange() throws {
        guard hasCurrentOwner() else { throw Failure.staleOwner }
        entries = entries.map { Entry(slot: $0.slot) }
    }

    /// Explicitly close this editor lease before publishing an ownership or lifecycle change.
    public func retire() {
        retired = true; editorID = UUID(); entries = []
    }

    public func reset(owner: TemplateAuthoringMediaOwner, slots: [TemplateAuthoringMediaSlot],
                      reason: ResetReason) throws {
        // Retire the old lifetime even if a malformed replacement fails validation.
        retire()
        try Self.validate(slots)
        guard currentOwner() == owner else { throw Failure.staleOwner }
        self.owner = owner; entries = slots.map { Entry(slot: $0) }; retired = false
    }

    private func hasCurrentOwner() -> Bool {
        guard !retired else { return false }
        guard currentOwner() == owner else {
            // Observing an owner change permanently retires this lifetime, including A → B → A.
            retire(); return false
        }
        return true
    }

    private static func validate(_ slots: [TemplateAuthoringMediaSlot]) throws {
        guard Set(slots.map(\.id)).count == slots.count else { throw Failure.invalidSlots }
        for (index, slot) in slots.enumerated() {
            if case .storyBeatImage = slot.field { continue }
            guard !slots.prefix(index).contains(where: { $0.field == slot.field }) else { throw Failure.invalidSlots }
        }
    }
}
