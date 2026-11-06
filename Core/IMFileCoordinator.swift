import Foundation

@MainActor public final class IMFileCoordinator {
    public enum State: Equatable {
        case empty, draft(IMFileSelection), uploading, unknown, held, rejected, ready(IMFileReference), closed
    }
    public let scope: IMScope
    public let expanded: IMExpandedCoordinator
    public let service: IMFileService
    private let journal: IMFileJournal
    private let stillCurrent: () -> Bool
    private var pending: IMFileJournal.Pending?
    private var state: State = .empty
    public static let consumptionRetiredNotification = Notification.Name("IMFileOriginalConsumptionRetired")
    private var consumptionRetired = false
    private var generation = UUID()
    public var onChange: (() -> Void)?
    public var isCurrent: Bool { !consumptionRetired && stillCurrent() && service.identity == scope.identity && expanded.isCurrent }
    public var visibleState: State { isCurrent ? state : .closed }
    public var canUpload: Bool { isCurrent && service.uploadEnabled }
    public var canRecover: Bool { isCurrent && service.receiptEnabled && pending != nil && state != .uploading }
    public init(scope: IMScope, expanded: IMExpandedCoordinator, service: IMFileService, journal: IMFileJournal,
                stillCurrent: @escaping () -> Bool) {
        self.scope = scope; self.expanded = expanded; self.service = service; self.journal = journal; self.stillCurrent = stillCurrent
        do { pending = try journal.restore(current: scope); if pending != nil { state = .unknown } }
        catch { state = .closed }
    }
    public func select(_ clip: IMFileSelection) throws {
        guard isCurrent, pending == nil else { throw IMFileFailure.unknown }
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
        defer { journal.endOperation(operation) }
        let stamp = generation; state = .uploading; onChange?()
        do {
            let receipt = try await service.upload(pending, scope: scope)
            guard isCurrent, generation == stamp, !Task.isCancelled else { return }
            apply(receipt)
        } catch { if isCurrent, generation == stamp { state = .unknown } }
        onChange?()
    }
    public func recover() async {
        guard canRecover, let pending, let operation = journal.beginOperation() else { return }
        defer { journal.endOperation(operation) }
        let stamp = generation; state = .uploading; onChange?()
        do {
            let receipt = try await service.recover(pending, scope: scope)
            guard isCurrent, generation == stamp, !Task.isCancelled else { return }
            apply(receipt)
        } catch { if isCurrent, generation == stamp { state = .unknown } }
        onChange?()
    }
    public func retryScan() async {
        guard isCurrent, service.scanEnabled, let pending, state != .uploading, let operation = journal.beginOperation() else { return }
        defer { journal.endOperation(operation) }
        let stamp = generation; state = .uploading; onChange?()
        do {
            let result = try await service.scan(pending, scope: scope)
            guard isCurrent, generation == stamp, !Task.isCancelled else { return }; apply(result)
        } catch { if isCurrent, generation == stamp { state = .unknown } }
        onChange?()
    }
    private func apply(_ receipt: IMFileUploadReceipt) {
        if receipt.ready, let reference = receipt.reference { state = .ready(reference) }
        else if receipt.scanState == "INFECTED" || receipt.reviewState == "REJECTED" { state = .rejected }
        else if receipt.state == "UPLOADED", receipt.reviewState == "HOLD" { state = .held }
        else { state = .unknown }
    }
    /// Fresh read of the same original FILE decision, then the existing sender's review.
    /// Sidecar retains the SAME message key across a crash after send acknowledgement.
    public func reviewSend() async {
        guard isCurrent, expanded.writer.canSendFile, pending != nil else { return }
        await recover()
        guard isCurrent, let pending, case .ready(let reference) = state else { return }
        do { _ = expanded.review(.send(try IMOutgoingIntent(scope: scope, payload: .file(reference), clientMessageID: pending.clientMessageID))) }
        catch { state = .closed; onChange?() }
    }
    public func finishAcknowledged() {
        guard isCurrent, let pending, case .acknowledged(.sent(let message)) = expanded.visibleState,
              let reference = IMFileReference.read(message), reference.uploadRequestID == pending.requestID else { return }
        do { try journal.settle(pending, current: scope); self.pending = nil; state = .empty; expanded.finishFileResult() }
        catch { state = .closed }; onChange?()
    }
    public func discardRejected() {
        guard isCurrent, case .rejected = state, let pending else { return }
        // A definitive FILE rejection is not an ambiguous upload or pending send.
        switch expanded.visibleState { case .idle, .acknowledged: break; default: return }
        do { try journal.settle(pending, current: scope); self.pending = nil; state = .empty }
        catch { state = .closed }; onChange?()
    }
    public func retireConsumption() { consumptionRetired = true; generation = UUID(); NotificationCenter.default.post(name: Self.consumptionRetiredNotification, object: self); onChange?() }
    /// Presentation retirement cannot settle an in-flight original upload/read/scan.
    /// Keep the journal and lease untouched; expose explicit same-request recovery on return.
    public func invalidate() {
        generation = UUID()
        if state == .uploading { state = .unknown }
        onChange?()
    }
}
