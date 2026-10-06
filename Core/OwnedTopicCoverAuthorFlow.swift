import Foundation
import CryptoKit

/// Existing producer consumer. Picked bytes remain local until an explicit captured upload claim.
@MainActor public final class OwnedTopicCoverAuthorFlow {
    public struct Review: Identifiable, Equatable {
        public let id = UUID()
        public let image: RetainedSelectedImage
    }
    public struct UploadClaim {
        public let id = UUID()
        fileprivate let uploadID: UUID, image: RetainedSelectedImage, snapshot: OwnedTopicCoverJournal.Snapshot
    }
    public struct SelectionReview: Identifiable {
        public let id = UUID()
        public let command: OwnedTopicCoverSelectionCommand
        fileprivate let snapshot: OwnedTopicCoverJournal.Snapshot
    }
    public struct SelectionClaim {
        public let id = UUID()
        fileprivate let snapshot: OwnedTopicCoverJournal.Snapshot
    }
    public enum State: Equatable {
        case idle, ready, uploadUnconfirmed, uploadReceiptUnstored, uploaded, selectionUnconfirmed, selectionReceiptUnstored
        case selected(OwnedTopicCoverSelectionReceipt), failed(OwnedTopicCoverFailure), unauthorized, closed
    }
    public let id = UUID(), session: ProjectEditSession, topicID: Int
    public private(set) var state: State = .idle
    public private(set) var current: OwnedTopicCoverCurrent?
    public private(set) var localReview: Review?
    public private(set) var uploadedAsset: OwnedTopicCoverAsset?
    public private(set) var checkedImage: Data?
    public private(set) var checkedAsset: OwnedTopicCoverAsset?
    public private(set) var snapshot: OwnedTopicCoverJournal.Snapshot?
    public private(set) var selectionReview: SelectionReview?
    public private(set) var isWorking = false
    private let source: any OwnedTopicCoverServing
    private let journal: OwnedTopicCoverJournal
    private let parentCurrent: () -> Bool
    private let mayChangeSelection: () -> Bool
    private var requestID: UUID?, claimID: UUID?, pickerID: UUID?
    private var cancelTask: (() -> Void)?
    private var unsavedSelection: OwnedTopicCoverSelectionReceipt?
    private var unsavedUpload: (asset: OwnedTopicCoverAsset, id: UUID, expected: OwnedTopicCoverJournal.Snapshot)?
    public init(session: ProjectEditSession, topicID: Int, source: any OwnedTopicCoverServing, journal: OwnedTopicCoverJournal,
                parentCurrent: @escaping () -> Bool, mayChangeSelection: @escaping () -> Bool) {
        self.session = session; self.topicID = topicID; self.source = source; self.journal = journal
        self.parentCurrent = parentCurrent; self.mayChangeSelection = mayChangeSelection
    }
    public var isCurrent: Bool { state != .closed && parentCurrent() && source.isCurrent(session: session) }
    public var isBusy: Bool { isWorking || claimID != nil || selectionReview != nil || pickerID != nil }
    public var hasUnknownSelection: Bool { snapshot?.currentSelection != nil && snapshot?.currentSelection?.receipt == nil }
    public var hasUnstoredUploadReceipt: Bool { unsavedUpload != nil }
    public var hasUnstoredSelectionReceipt: Bool { unsavedSelection != nil }
    public var hasUnstoredReceipt: Bool { hasUnstoredUploadReceipt || hasUnstoredSelectionReceipt }
    public var canPersistUploadReceipt: Bool { isCurrent && !isWorking && hasUnstoredUploadReceipt }
    public var canPersistSelectionReceipt: Bool { isCurrent && !isWorking && hasUnstoredSelectionReceipt && snapshot != nil }
    public var canReadCurrentDetails: Bool { isCurrent && !isBusy && !hasUnstoredReceipt && source.permits(.readCurrent,session:session) }
    public var canPick: Bool { isCurrent && !isBusy && !hasUnknownSelection && unsavedUpload == nil && unsavedSelection == nil && mayChangeSelection() && current != nil && source.permitsNativePicker(session:session) }
    public func beginPicking() -> UUID? {
        guard canPick else { return nil }; let id = UUID(); pickerID = id; return id
    }
    public func finishPicking(_ image: RetainedSelectedImage?, original: UUID) {
        guard pickerID == original else { return }; pickerID = nil
        guard let image else { return }; setPicked(image)
    }
    public func setPicked(_ image: RetainedSelectedImage) {
        guard canPick else { return }; localReview = .init(image:image); checkedImage = nil; checkedAsset = nil; state = .ready
    }
    public func cancelPicked(_ original: Review) { guard localReview?.id == original.id, !isBusy else { return }; localReview = nil }
    private func execute<T: Sendable>(_ action: @escaping @MainActor () async throws -> T) async throws -> T {
        guard isCurrent, !isWorking else { throw OwnedTopicCoverFailure.changedContext }
        let token = UUID(); requestID = token; isWorking = true
        let task = Task { try await action() }; cancelTask = { task.cancel() }
        defer { if requestID == token { isWorking = false; cancelTask = nil; requestID = nil } }
        let result = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
        guard requestID == token, !task.isCancelled, !Task.isCancelled, isCurrent else { throw OwnedTopicCoverFailure.changedContext }
        return result
    }
    private func failed(_ error: Error) {
        guard isCurrent else { close(); return }
        if error as? APIError == .unauthorized { state = .unauthorized }
        else { state = .failed(error as? OwnedTopicCoverFailure ?? .unavailable) }
    }
    public func load() async {
        guard isCurrent, !isBusy else { return }
        do {
            snapshot = try journal.read(session:session,topicID:topicID)
            if let received = journal.receivedUpload(session:session,topicID:topicID), let snapshot {
                uploadedAsset = received.asset; unsavedUpload = (received.asset,received.id,snapshot)
            }
            unsavedSelection = journal.receivedSelection(session:session,topicID:topicID)
            // Saving an already received receipt does not require another network read.
            // Keep that recovery action visible even when current/author-read is unavailable.
            if unsavedSelection != nil { state = .selectionReceiptUnstored; return }
            if unsavedUpload != nil { state = .uploadReceiptUnstored; return }
            let value = try await execute { [source,topicID,session] in try await source.current(topicID:topicID,session:session) }
            current = value
            if unsavedUpload == nil { uploadedAsset = snapshot?.uploads.last(where: { $0.asset != nil })?.asset }
            if unsavedSelection != nil { state = .selectionReceiptUnstored }
            else if unsavedUpload != nil { state = .uploadReceiptUnstored }
            else { state = hasUnknownSelection ? .selectionUnconfirmed : .ready }
        } catch { failed(error) }
    }
    public func canUpload(_ original: Review) -> Bool {
        isCurrent && !isBusy && !hasUnknownSelection && unsavedUpload == nil && unsavedSelection == nil && mayChangeSelection() && localReview?.id == original.id && source.permits(.upload,session:session)
    }
    /// Persist before the caller schedules its Task. Repeated controls cannot create a second upload.
    public func claimUpload(_ original: Review) -> UploadClaim? {
        guard canUpload(original), let snapshot else { return nil }
        do {
            let digest = SHA256.hash(data:original.image.jpeg).map { String(format:"%02x",$0) }.joined()
            let saved = try journal.beginUpload(localDigest:digest,expected:snapshot,session:session), upload = saved.uploads.last!
            let claim = UploadClaim(uploadID:upload.id,image:original.image,snapshot:saved)
            self.snapshot = saved; localReview = nil; claimID = claim.id; state = .uploadUnconfirmed; return claim
        } catch { failed(error); return nil }
    }
    public func upload(_ original: UploadClaim) async {
        guard claimID == original.id, snapshot == original.snapshot else { return }
        guard isCurrent, mayChangeSelection(), source.permits(.upload,session:session) else { close(); return }
        claimID = nil
        do {
            guard try journal.read(session:session,topicID:topicID) == original.snapshot else { throw OwnedTopicCoverFailure.changedContext }
            let asset = try await execute { [source,session] in try await source.upload(original.image,session:session) }
            journal.rememberUpload(asset,id:original.uploadID,session:session,topicID:topicID)
            uploadedAsset = asset; unsavedUpload = (asset,original.uploadID,original.snapshot)
            persistUploadReceipt()
        } catch {
            guard isCurrent else { close(); return }
            // There is no producer upload-status endpoint. Never turn an uncertain dispatch into an automatic retry.
            state = .uploadUnconfirmed
        }
    }
    public func persistUploadReceipt() {
        guard canPersistUploadReceipt, let pending = unsavedUpload else { return }
        do { snapshot = try journal.recordUpload(pending.asset,uploadID:pending.id,expected:pending.expected,session:session); unsavedUpload = nil; state = .uploaded }
        catch { state = .uploadReceiptUnstored }
    }
    public func readImage(_ asset: OwnedTopicCoverAsset) async {
        guard isCurrent, !isBusy, asset.ownerMemberID == session.accountID,
              asset == uploadedAsset || asset == current?.asset else { return }
        checkedImage = nil; checkedAsset = nil
        do {
            let bytes = try await execute { [source,session] in try await source.content(asset,session:session) }
            checkedImage = bytes; checkedAsset = asset
        } catch { failed(error) }
    }
    public func canReviewSelection(_ asset: OwnedTopicCoverAsset) -> Bool {
        isCurrent && !isBusy && !hasUnknownSelection && unsavedUpload == nil && unsavedSelection == nil && mayChangeSelection() &&
            source.permits(.select,session:session) && asset == checkedAsset && checkedImage != nil && current != nil && snapshot != nil
    }
    public func reviewSelection(_ asset: OwnedTopicCoverAsset) -> SelectionReview? {
        guard canReviewSelection(asset), let current, let snapshot else { return nil }
        let original = SelectionReview(command:.init(current:current,asset:asset),snapshot:snapshot); selectionReview = original; return original
    }
    public func cancelSelection(_ original: SelectionReview) { guard selectionReview?.id == original.id else { return }; selectionReview = nil }
    public func claimSelection(_ original: SelectionReview) -> SelectionClaim? {
        guard isCurrent, mayChangeSelection(), !hasUnstoredReceipt, !isWorking, claimID == nil, selectionReview?.id == original.id,
              source.permits(.select,session:session), original.command.asset == checkedAsset else { return nil }
        do {
            let saved = try journal.beginSelection(original.command,expected:original.snapshot,session:session)
            let claim = SelectionClaim(snapshot:saved); snapshot = saved; selectionReview = nil; claimID = claim.id; state = .selectionUnconfirmed; return claim
        } catch { selectionReview = nil; failed(error); return nil }
    }
    public func select(_ original: SelectionClaim) async {
        guard claimID == original.id, snapshot == original.snapshot else { return }
        guard isCurrent, mayChangeSelection() else { close(); return }; claimID = nil
        await sendSelection(original.snapshot, writing:true)
    }
    public func checkSelection(_ original: OwnedTopicCoverJournal.Snapshot) async {
        guard isCurrent, !isBusy, !hasUnstoredReceipt, snapshot == original else { return }; await sendSelection(original,writing:false)
    }
    public func retrySelection(_ original: OwnedTopicCoverJournal.Snapshot) async {
        guard isCurrent, !isBusy, !hasUnstoredReceipt, hasUnknownSelection, snapshot == original, mayChangeSelection() else { return }
        await sendSelection(original,writing:true)
    }
    private func sendSelection(_ original: OwnedTopicCoverJournal.Snapshot, writing: Bool) async {
        guard isCurrent, !hasUnstoredReceipt, let saved = original.currentSelection, source.permits(writing ? .select : .status,session:session) else { return }
        do {
            guard try journal.read(session:session,topicID:topicID) == original else { throw OwnedTopicCoverFailure.changedContext }
            let receipt = try await execute { [source,session] in
                if writing { return try await source.select(saved.command,session:session) }
                return try await source.status(saved.command,session:session)
            }
            journal.rememberSelection(receipt,session:session); unsavedSelection = receipt
            persistSelectionReceipt()
        } catch { guard isCurrent else { close(); return }; state = .selectionUnconfirmed }
    }
    public func persistSelectionReceipt() {
        guard canPersistSelectionReceipt, let receipt = unsavedSelection, let snapshot else { return }
        do { self.snapshot = try journal.recordSelection(receipt,expected:snapshot,session:session); unsavedSelection = nil; state = .selected(receipt) }
        catch { state = .selectionReceiptUnstored }
    }
    public func close() {
        cancelTask?(); cancelTask = nil; requestID = nil; claimID = nil; pickerID = nil; isWorking = false; state = .closed
        localReview = nil; checkedImage = nil; checkedAsset = nil; selectionReview = nil; uploadedAsset = nil; unsavedUpload = nil; unsavedSelection = nil
    }
}
