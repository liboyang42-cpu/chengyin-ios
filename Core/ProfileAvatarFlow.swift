import Foundation

/// One avatar selection/review/upload/staging flow. It never saves the profile.
@MainActor public final class ProfileAvatarFlow {
    public struct Review: Identifiable { public let id = UUID(); public let image: RetainedSelectedImage }
    public enum State: Equatable { case ready, uploading, uploaded, staged, unknown, failed, closed }
    public let id = UUID()
    public let target: ProfileAvatarTarget
    public private(set) var state: State = .ready
    public private(set) var review: Review?
    public private(set) var receipt: ProfileAvatarUploadReceipt?
    private let source: ProfileAvatarUploadClient
    private let journal: (any ProfileAvatarJournaling)?
    private let currentSnapshot: () -> ProfileEditSnapshot?
    private let currentDraft: () -> ProfileEditDraft?
    private let currentRevision: () -> UInt64
    private let ownerCurrent: () -> Bool
    private let apply: (ProfileAvatarReplacement) -> Void
    private var attemptID: UUID?
    private var pickerID: UUID?
    private var task: Task<ProfileAvatarUploadReceipt, Error>?
    private var key: ProfileAvatarJournalKey { .init(scope: target.scope) }
    public init(target: ProfileAvatarTarget, source: ProfileAvatarUploadClient, journal: (any ProfileAvatarJournaling)? = nil,
                currentSnapshot: @escaping () -> ProfileEditSnapshot?, currentDraft: @escaping () -> ProfileEditDraft?,
                currentRevision: @escaping () -> UInt64, ownerCurrent: @escaping () -> Bool,
                apply: @escaping (ProfileAvatarReplacement) -> Void) {
        self.target = target; self.source = source; self.journal = journal
        self.currentSnapshot = currentSnapshot; self.currentDraft = currentDraft; self.currentRevision = currentRevision
        self.ownerCurrent = ownerCurrent; self.apply = apply
        do {
            guard let journal else { state = .unknown; return }
            if let old = try journal.entry(for: .init(scope: target.scope)), !old.phase.permitsNewSelection { state = .unknown }
        } catch { state = .unknown }
    }
    public var ownsTarget: Bool {
        guard state != .closed, ownerCurrent(), source.isCurrent(target.scope), let snapshot = currentSnapshot(), let draft = currentDraft() else { return false }
        return target.matches(snapshot: snapshot, draft: draft, revision: currentRevision())
    }
    public var canSelect: Bool {
        guard (state == .ready || state == .failed), task == nil, pickerID == nil, receipt == nil,
              ownsTarget, source.permitsPicker(target.scope), let journal else { return false }
        do { return try journal.entry(for: key)?.phase.permitsNewSelection ?? true } catch { return false }
    }
    public var isPicking: Bool { pickerID != nil }
    public func beginPicking() -> UUID? { guard canSelect else { return nil }; let id = UUID(); pickerID = id; return id }
    public func endPicking(_ id: UUID) { if pickerID == id { pickerID = nil } }
    public func prepare(_ image: RetainedSelectedImage) {
        guard canSelect, image.width == image.height else { return }
        review = .init(image: image); state = .ready
    }
    public func cancelReview(_ value: Review) { if review?.id == value.id, task == nil { review = nil } }
    public func confirm(_ value: Review) async {
        guard ownsTarget, canSelect, review?.id == value.id, let journal else { return }
        let attempt = UUID(), digest = ProfileAvatarExact.hash(value.image.jpeg)
        do { try journal.begin(key: key, attemptID: attempt, targetID: target.id, selectedDigest: digest) }
        catch { state = .unknown; return }
        guard ownsTarget, review?.id == value.id else { state = .unknown; return }
        attemptID = attempt; review = nil; state = .uploading
        let pending = Task { [source, target, weak self] in
            try await source.upload(value.image, target: target, attemptID: attempt) { self?.ownsTarget == true }
        }
        task = pending
        do {
            let received = try await withTaskCancellationHandler(operation: { try await pending.value }, onCancel: { pending.cancel() })
            guard !Task.isCancelled, !pending.isCancelled, state != .closed, ownsTarget,
                  received.id == attempt, received.target == target, received.selectedDigest == digest,
                  source.permitsReference(received.reference, scope: target.scope) else { if state != .closed { state = .unknown }; return }
            // Keep the accepted receipt even if acknowledgment persistence fails.
            receipt = received
            try journal.record(key: key, attemptID: attempt, phase: .acknowledged)
            state = .uploaded; task = nil
        } catch {
            task = nil
            if error as? ProfileAvatarFailure == .notSent || error as? ProfileAvatarFailure == .rejected {
                do { try journal.record(key: key, attemptID: attempt, phase: .rejected); if state != .closed { state = .failed } }
                catch { if state != .closed { state = .unknown } }
            } else if state != .closed { state = .unknown }
        }
    }
    public var canStage: Bool {
        guard state == .uploaded, task == nil, ownsTarget, let receipt, receipt.id == attemptID,
              receipt.target == target, source.permitsReference(receipt.reference, scope: target.scope), let journal else { return false }
        return (try? journal.entry(for: key))?.phase == .acknowledged
    }
    public func stage() {
        guard canStage, let receipt, let journal else { return }
        do {
            try journal.record(key: key, attemptID: receipt.id, phase: .stageReserved)
            // Storage callbacks are synchronous but still recheck every attachment fence.
            guard ownsTarget, self.receipt == receipt, source.permitsReference(receipt.reference, scope: target.scope) else { state = .unknown; return }
            let source = source, scope = target.scope, key = key, owner = ownerCurrent
            let replacement = receipt.stage {
                guard owner(), source.permitsReference(receipt.reference, scope: scope),
                      let entry = try? journal.entry(for: key) else { return false }
                return entry.attemptID == receipt.id && entry.targetID == receipt.target.id &&
                    entry.selectedDigest == receipt.selectedDigest && entry.phase == .locallyStaged
            }
            apply(replacement) // Synchronous, nonfallible, after all owner/draft checks.
            guard currentDraft()?.avatarReplacement == replacement else { state = .unknown; return }
            try journal.record(key: key, attemptID: receipt.id, phase: .locallyStaged)
            state = .staged
        } catch { state = .unknown }
    }
    public func close() {
        task?.cancel(); task = nil; pickerID = nil; review = nil; receipt = nil
        state = .closed // Never reset/remove a durable pending or uncertain attempt.
    }
}
