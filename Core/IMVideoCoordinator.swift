import Foundation

@MainActor public final class IMVideoCoordinator {
    public enum State: Equatable {
        case empty, draft(IMVideoSelection), uploading, unknown, held, rejected, ready(IMVideoReference), closed
    }
    public let scope: IMScope
    public let expanded: IMExpandedCoordinator
    public let service: IMVideoService
    private let journal: IMVideoJournal
    private let stillCurrent: () -> Bool
    private var pending: IMVideoJournal.Pending?
    public private(set) var selectionPolicy: IMVideoPolicy?
    private var state: State = .empty
    public static let consumptionRetiredNotification = Notification.Name("IMVideoOriginalConsumptionRetired")
    private var consumptionRetired = false
    private var generation = UUID()
    public var onChange: (() -> Void)?
    public var isCurrent: Bool { !consumptionRetired && stillCurrent() && service.identity == scope.identity && expanded.isCurrent }
    public var visibleState: State { isCurrent ? state : .closed }
    public var canUpload: Bool { isCurrent && service.uploadEnabled }
    public var canRecover: Bool { isCurrent && service.receiptEnabled && pending != nil && state != .uploading }
    public init(scope: IMScope, expanded: IMExpandedCoordinator, service: IMVideoService, journal: IMVideoJournal,
                stillCurrent: @escaping () -> Bool) {
        self.scope = scope; self.expanded = expanded; self.service = service; self.journal = journal; self.stillCurrent = stillCurrent
        do { pending = try journal.restore(current: scope); if pending != nil { state = .unknown } }
        catch { state = .closed }
    }
    public func loadPolicy() async {
        guard isCurrent, service.policyEnabled else { return }
        let stamp = generation
        do { let value = try await service.policy(scope: scope); guard isCurrent, generation == stamp, !Task.isCancelled else { return }; selectionPolicy = value }
        catch { if isCurrent, generation == stamp { selectionPolicy = nil } }
        onChange?()
    }
    public func select(_ clip: IMVideoSelection) throws {
        guard isCurrent, pending == nil else { throw IMVideoFailure.unknown }
        guard selectionPolicy == clip.policy else { throw IMVideoFailure.invalid }
        state = .draft(clip); onChange?()
    }
    public func discardDraft() {
        guard pending == nil else { return }; generation = UUID(); state = .empty; onChange?()
    }
    /// Explicit upload confirmation. Neither restoration nor recording calls this.
    public func confirmUpload() async {
        guard isCurrent, service.uploadEnabled, case .draft(let clip) = state else { return }
        do { pending = try journal.reserve(clip, current: scope) }
        catch { state = .closed; onChange?(); return }
        await uploadUnchanged()
    }
    /// Explicit same-key retry only; NOT_FOUND never rotates either original request identity.
    public func uploadUnchanged() async {
        guard isCurrent, service.uploadEnabled, let pending, state != .uploading,
              let operation = journal.beginOperation() else { return }
        let stamp = generation
        defer { finishOperation(operation, generation: stamp) }
        state = .uploading; onChange?()
        do {
            let receipt = try await service.upload(pending, scope: scope)
            guard isCurrent, generation == stamp, !Task.isCancelled else { return }
            apply(receipt)
        } catch { if isCurrent, generation == stamp { state = .unknown } }
        onChange?()
    }
    public func recover() async {
        guard canRecover, let pending, let operation = journal.beginOperation() else { return }
        let stamp = generation
        defer { finishOperation(operation, generation: stamp) }
        state = .uploading; onChange?()
        do {
            let receipt = try await service.recover(pending, scope: scope)
            guard isCurrent, generation == stamp, !Task.isCancelled else { return }
            apply(receipt)
        } catch { if isCurrent, generation == stamp { state = .unknown } }
        onChange?()
    }
    private func apply(_ receipt: IMVideoUploadReceipt) {
        if receipt.ready, let reference = receipt.reference { state = .ready(reference) }
        else if receipt.videoReviewState == "REJECTED" || receipt.coverReviewState == "REJECTED" { state = .rejected }
        else if receipt.state == "UPLOADED", receipt.videoReviewState == "HOLD" || receipt.coverReviewState == "HOLD" { state = .held }
        else { state = .unknown }
    }
    /// Fresh read of the same original VIDEO decision, then the existing sender's review.
    /// Sidecar retains the SAME message key across a crash after send acknowledgement.
    public func reviewSend() async {
        guard isCurrent, expanded.writer.canSendVideo, pending != nil else { return }
        await recover()
        guard isCurrent, let pending, case .ready(let reference) = state else { return }
        do { _ = expanded.review(.send(try IMOutgoingIntent(scope: scope, payload: .video(reference), clientMessageID: pending.clientMessageID))) }
        catch { state = .closed; onChange?() }
    }
    public func finishAcknowledged() {
        guard isCurrent, let pending, case .acknowledged(.sent(let message)) = expanded.visibleState,
              let reference = IMVideoReference.read(message), reference.uploadRequestID == pending.requestID else { return }
        do { try journal.settle(pending, current: scope); self.pending = nil; state = .empty; expanded.finishVideoResult() }
        catch { state = .closed }; onChange?()
    }
    public func discardRejected() {
        guard isCurrent, case .rejected = state, let pending else { return }
        // A definitive VIDEO rejection is not an ambiguous upload or pending send.
        switch expanded.visibleState { case .idle, .acknowledged: break; default: return }
        do { try journal.settle(pending, current: scope); self.pending = nil; state = .empty }
        catch { state = .closed }; onChange?()
    }
    public func retireConsumption() { consumptionRetired = true; generation = UUID(); NotificationCenter.default.post(name: Self.consumptionRetiredNotification, object: self); onChange?() }
    /// Dropping a presentation does not prove that the original upload failed.
    /// Keep both request identities and protected bytes; re-entry only exposes explicit recovery.
    public func invalidate() {
        generation = UUID()
        if state == .uploading { state = .unknown }
        onChange?()
    }
    private func finishOperation(_ operation: UUID, generation stamp: UUID) {
        journal.endOperation(operation)
        // Cancellation may discard a successful response without reaching catch. Never leave
        // that original pending request permanently busy, or accept an obsolete completion.
        if generation == stamp, state == .uploading {
            state = .unknown
            onChange?()
        }
    }
}
