import Foundation

@MainActor public final class IMVoiceCoordinator {
    public enum State: Equatable {
        case empty, draft(IMVoiceClip), uploading, unknown, held, rejected, ready(IMVoiceReference), closed
    }
    /// Read projection only; the original IMExpanded journal remains the sole send ledger.
    public enum OriginalSendState: Equatable {
        case unchecked, reading, notFound, unknown, found(MessagingMessage)
    }
    private var sendState: OriginalSendState = .unchecked
    public var originalSendState: OriginalSendState { isCurrent ? sendState : .unchecked }
    public let scope: IMScope
    public let expanded: IMExpandedCoordinator
    public let service: IMVoiceService
    private let journal: IMVoiceJournal
    private let stillCurrent: () -> Bool
    private var pending: IMVoiceJournal.Pending?
    private var state: State = .empty
    public static let consumptionRetiredNotification = Notification.Name("IMVoiceOriginalConsumptionRetired")
    private var consumptionRetired = false
    private var generation = UUID()
    public var onChange: (() -> Void)?
    public var isCurrent: Bool { !consumptionRetired && stillCurrent() && service.identity == scope.identity && expanded.isCurrent }
    public var visibleState: State { isCurrent ? state : .closed }
    public var canUpload: Bool { isCurrent && service.uploadEnabled }
    public var canRecover: Bool { isCurrent && service.receiptEnabled && pending != nil && state != .uploading }
    public var canRecoverOriginalSend: Bool {
        guard isCurrent, pending != nil, expanded.writer.canRecoverVoice,
              state != .uploading, sendState != .reading else { return false }
        switch expanded.visibleState {
        case .outcomeUnknown(.send(let intent)), .rejected(.send(let intent)): return isOriginal(intent)
        case .acknowledged(.sent(let message)):
            return IMVoiceReference.read(message)?.uploadRequestID == pending?.requestID || canRecover
        case .idle, .acknowledged: return canRecover
        default: return false
        }
    }
    public init(scope: IMScope, expanded: IMExpandedCoordinator, service: IMVoiceService, journal: IMVoiceJournal,
                stillCurrent: @escaping () -> Bool) {
        self.scope = scope; self.expanded = expanded; self.service = service; self.journal = journal; self.stillCurrent = stillCurrent
        do { pending = try journal.restore(current: scope); if pending != nil { state = .unknown } }
        catch { state = .closed }
    }
    public func select(_ clip: IMVoiceClip) throws {
        guard isCurrent, pending == nil else { throw IMVoiceFailure.unknown }
        try clip.validate(); state = .draft(clip); onChange?()
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
        sendState = .unchecked; state = .uploading; onChange?()
        do {
            let receipt = try await service.upload(pending, scope: scope)
            guard isCurrent, generation == stamp, !Task.isCancelled else { return }
            apply(receipt)
        } catch { if isCurrent, generation == stamp { handleFailure(error) } }
        onChange?()
    }
    public func recover() async {
        guard canRecover, let pending, let operation = journal.beginOperation() else { return }
        let stamp = generation
        defer { finishOperation(operation, generation: stamp) }
        sendState = .unchecked; state = .uploading; onChange?()
        do {
            let receipt = try await service.recover(pending, scope: scope)
            guard isCurrent, generation == stamp, !Task.isCancelled else { return }
            apply(receipt)
        } catch { if isCurrent, generation == stamp { handleFailure(error) } }
        onChange?()
    }
    private func apply(_ receipt: IMVoiceUploadReceipt) {
        if receipt.ready, let reference = receipt.reference { state = .ready(reference) }
        else if receipt.state == "UPLOADED", receipt.reviewState == "REJECTED" { state = .rejected }
        else if receipt.state == "UPLOADED", receipt.reviewState == "HOLD" { state = .held }
        else { state = .unknown }
    }
    /// Re-entry may have only the upload sidecar after the original send ACK settled its
    /// journal. Read the SAME clientMessageID through the existing original reader; never
    /// infer success from history or issue a send merely to discover an old result.
    public func recoverOriginalSend() async {
        guard canRecoverOriginalSend else { return }
        let stamp = generation, previous = expanded.visibleState
        let reference: IMVoiceReference
        switch previous {
        case .outcomeUnknown(.send(let intent)), .rejected(.send(let intent)):
            // The original message ledger already carries its exact typed reference. Its
            // read permission must not inherit the separate upload/attachment write grant.
            guard isOriginal(intent), case .voice(let original) = intent.payload else { return }
            reference = original
        case .acknowledged(.sent(let message)) where IMVoiceReference.read(message)?.uploadRequestID == pending?.requestID:
            guard let original = IMVoiceReference.read(message) else { return }
            reference = original
        case .idle, .acknowledged:
            await recover()
            guard case .ready(let original) = state else { return }
            reference = original
        default: return
        }
        guard isCurrent, generation == stamp, !Task.isCancelled,
              let pending, expanded.visibleState == previous,
              let operation = journal.beginOperation() else { return }
        defer { finishOperation(operation, generation: stamp) }
        sendState = .reading; onChange?()
        do {
            guard try journal.restore(current: scope) == pending else { throw IMVoiceFailure.unknown }
            let intent = try IMOutgoingIntent(scope: scope, payload: .voice(reference), clientMessageID: pending.clientMessageID)
            let message = try await expanded.writer.recoverVoice(intent, expectedIdentity: scope.identity)
            guard isCurrent, generation == stamp, !Task.isCancelled,
                  self.pending == pending, expanded.visibleState == previous else { return }
            if let message {
                guard message.conversationID == scope.conversationID, message.senderID == scope.identity.accountID,
                      IMVoiceReference.read(message) == reference else { throw IMVoiceFailure.invalid }
                switch previous {
                case .outcomeUnknown, .rejected:
                    // Only the original coordinator can settle its own pending message ledger.
                    // Its fresh read must also confirm; the sidecar must not stand in for it.
                    await expanded.recoverVoice()
                    guard isCurrent, generation == stamp, !Task.isCancelled else { return }
                    guard case .acknowledged(.sent(let acknowledged)) = expanded.visibleState,
                          acknowledged == message else { state = .unknown; sendState = .unknown; onChange?(); return }
                default: break
                }
                sendState = .found(message)
            } else {
                // A prior original ACK is not undone by an absent current read projection.
                if case .acknowledged(.sent(let prior)) = previous,
                   IMVoiceReference.read(prior)?.uploadRequestID == pending.requestID { sendState = .unknown }
                else { sendState = .notFound }
            }
        } catch { if isCurrent, generation == stamp { handleFailure(error) } }
        onChange?()
    }
    /// Fresh original AUDIO + message reads precede the existing sender's explicit review.
    public func reviewSend() async {
        guard isCurrent, expanded.writer.canSendVoice, canRecoverOriginalSend else { return }
        let stamp = generation
        await recoverOriginalSend()
        guard isCurrent, generation == stamp, !Task.isCancelled, sendState == .notFound,
              let pending, case .ready(let reference) = state else { return }
        switch expanded.visibleState { case .idle, .acknowledged: break; default: return }
        do { _ = expanded.review(.send(try IMOutgoingIntent(scope: scope, payload: .voice(reference), clientMessageID: pending.clientMessageID))) }
        catch { state = .closed; onChange?() }
    }
    /// User-confirmed retry is permitted only after a fresh NOT_FOUND for this exact key.
    public func retryOriginalSend() async {
        guard canRecoverOriginalSend, expanded.writer.canSendVoice else { return }
        let stamp = generation
        await recoverOriginalSend()
        guard isCurrent, generation == stamp, !Task.isCancelled, sendState == .notFound else { return }
        switch expanded.visibleState {
        case .outcomeUnknown(.send(let intent)), .rejected(.send(let intent)):
            guard isOriginal(intent) else { return }
            await expanded.retryUnchanged()
        default: return
        }
    }
    public func recoverAndFinishAcknowledged() async {
        let stamp = generation
        await recoverOriginalSend()
        guard isCurrent, generation == stamp, !Task.isCancelled else { return }
        finishAcknowledged()
    }
    public func finishAcknowledged() {
        // Only a receipt looked up by the sidecar's exact clientMessageID may clear it.
        // A generic expanded ACK containing the same upload reference is not that proof.
        guard isCurrent, let pending, case .found(let message) = sendState,
              message.conversationID == scope.conversationID, message.senderID == scope.identity.accountID,
              IMVoiceReference.read(message)?.uploadRequestID == pending.requestID else { return }
        let finishExpanded: Bool
        switch expanded.visibleState {
        case .idle: finishExpanded = false
        case .acknowledged(.sent(let acknowledged)):
            finishExpanded = acknowledged.id == message.id && IMVoiceReference.read(acknowledged) == IMVoiceReference.read(message)
        case .acknowledged: finishExpanded = false
        default: return
        }
        do {
            try journal.settle(pending, current: scope)
            self.pending = nil; state = .empty; sendState = .unchecked
            if finishExpanded { expanded.finishVoiceResult() }
        } catch { state = .closed }; onChange?()
    }
    private func isOriginal(_ intent: IMOutgoingIntent) -> Bool {
        guard let pending, intent.scope == scope, intent.clientMessageID == pending.clientMessageID,
              case .voice(let reference) = intent.payload else { return false }
        return reference.uploadRequestID == pending.requestID
    }
    public func discardRejected() {
        guard isCurrent, case .rejected = state, let pending else { return }
        // A definitive AUDIO rejection is not an ambiguous upload or pending send.
        switch expanded.visibleState { case .idle, .acknowledged: break; default: return }
        do { try journal.settle(pending, current: scope); self.pending = nil; state = .empty }
        catch { state = .closed }; onChange?()
    }
    public func retireConsumption() {
        consumptionRetired = true; generation = UUID(); state = .closed; sendState = .unchecked
        NotificationCenter.default.post(name: Self.consumptionRetiredNotification, object: self); onChange?()
    }
    /// Presentation cancellation cannot decide the outcome of the original upload.
    /// Keep its protected bytes and both identities available for explicit readback.
    public func invalidate() {
        generation = UUID(); sendState = .unchecked
        if state == .uploading { state = .unknown }
        if case .reviewing(.send(let intent)) = expanded.visibleState, isOriginal(intent) { expanded.cancelReview() }
        onChange?()
    }
    private func finishOperation(_ operation: UUID, generation stamp: UUID) {
        // This token may release only its own original operation, never a newer owner's lock.
        journal.endOperation(operation)
        guard generation == stamp else { return }
        if state == .uploading { state = .unknown }
        if sendState == .reading { sendState = .unknown }
        onChange?()
    }
    private func handleFailure(_ error: Error) {
        state = .unknown; sendState = .unknown
        if let failure = error as? MessagingReadFailure,
           failure.isUnauthorized || failure.isForbidden || failure.isClosed {
            // Clear visible private projections; durable ambiguous requests are not discarded.
            retireConsumption()
        }
    }
}
