import Foundation

/// Owns the real permission-bound tasks and original confirmations for one captured author presentation.
@MainActor public final class ApprovedTopicReviewFlow {
    public enum State: Equatable {
        case idle, loading, ready(ApprovedTopicReviewCapture), sending, unconfirmed, known(ApprovedTopicReviewReceipt)
        case failed(ApprovedTopicReleaseError), unauthorized, closed
    }
    public enum ObservationState: Equatable { case notRequested, loading, ready(ApprovedTopicReviewObservation), failed, unauthorized }
    public private(set) var observation: ObservationState = .notRequested
    public struct Confirmation: Identifiable {
        public let id = UUID()
        public let capture: ApprovedTopicReviewCapture
        fileprivate let snapshot: ApprovedTopicReviewJournal.Snapshot
    }
    public struct Claim {
        public let id = UUID()
        fileprivate let snapshot: ApprovedTopicReviewJournal.Snapshot
    }
    public let id = UUID()
    public let origin: ApprovedTopicReleaseReadTarget
    public let session: ProjectEditSession
    public private(set) var state: State = .idle
    public private(set) var snapshot: ApprovedTopicReviewJournal.Snapshot?
    public private(set) var confirmation: Confirmation?
    private let source: any ApprovedTopicReviewServing
    private let journal: ApprovedTopicReviewJournal
    private let stillCurrent: () -> Bool
    private var requestID: UUID?, claimID: UUID?
    private var readTask: Task<ApprovedTopicReviewCapture, Error>?
    private var writeTask: Task<ApprovedTopicReviewReceipt, Error>?
    private var observationTask: Task<ApprovedTopicReviewObservation, Error>?
    public init(origin: ApprovedTopicReleaseReadTarget, session: ProjectEditSession, source: any ApprovedTopicReviewServing,
                journal: ApprovedTopicReviewJournal, stillCurrent: @escaping () -> Bool) {
        self.origin = origin; self.session = session; self.source = source; self.journal = journal; self.stillCurrent = stillCurrent
    }
    public var isCurrent: Bool { state != .closed && origin.ownerKey == session.ownerKey && stillCurrent() && source.isCurrent(session: session) }
    private var isBusy: Bool { readTask != nil || writeTask != nil || observationTask != nil || claimID != nil || confirmation != nil }
    public var canReadStatus: Bool { isCurrent && !isBusy && source.canReadStatus(session: session) && snapshot?.current != nil }
    public var canRetryExact: Bool { (snapshot?.current?.capture.coverBindingAllowsReview ?? true) && isCurrent && !isBusy && source.canSubmit(session: session) && snapshot?.current?.receipt == nil && snapshot?.current != nil }
    public var canObserve: Bool { isCurrent && !isBusy && snapshot?.current?.receipt != nil && (source as? any ApprovedTopicReviewObserving)?.canObserve(session: session) == true }
    public var isReceiptForThisSubmission: Bool { snapshot?.current?.originOperationID == origin.operationID }
    private func restoreState() {
        if let receipt = snapshot?.current?.receipt { state = .known(receipt) }
        else { state = snapshot?.current == nil ? .idle : .unconfirmed }
    }
    public func load() async {
        guard !isBusy, isCurrent else { return }
        observation = .notRequested
        do {
            snapshot = try journal.read(session: session, topicID: origin.topicID)
            if let current = snapshot?.current, current.receipt == nil || current.originOperationID == origin.operationID { restoreState(); return }
        } catch { state = .failed(.persistenceUnavailable); return }
        guard source.canPrepare(session: session) else { state = .failed(.notConfigured); return }
        let request = UUID(); requestID = request; state = .loading
        let task = Task { [source, origin, session] in try await source.prepare(origin, session: session) }; readTask = task
        defer { if requestID == request { requestID = nil; readTask = nil } }
        do {
            let captured = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
            guard requestID == request else { return }
            guard !Task.isCancelled, !task.isCancelled, isCurrent else { close(); return }
            state = .ready(captured)
        } catch {
            guard requestID == request else { return }
            guard !Task.isCancelled, !task.isCancelled, isCurrent else { close(); return }
            if error as? APIError == .unauthorized { state = .unauthorized }
            else { state = .failed(error as? ApprovedTopicReleaseError ?? .unavailable) }
        }
    }
    public func canConfirm(_ capture: ApprovedTopicReviewCapture) -> Bool {
        guard capture.coverBindingAllowsReview, isCurrent, !isBusy, source.canSubmit(session: session), case .ready(let current) = state, current == capture, let snapshot else { return false }
        return journal.canBegin(capture, origin: origin, expected: snapshot)
    }
    public func review(_ capture: ApprovedTopicReviewCapture) -> Confirmation? {
        guard canConfirm(capture), let snapshot else { return nil }
        let original = Confirmation(capture: capture, snapshot: snapshot); confirmation = original; return original
    }
    public func cancel(_ original: Confirmation) {
        guard confirmation?.id == original.id else { return }; confirmation = nil
        if isCurrent { state = .ready(original.capture) } else { close() }
    }
    /// Synchronous persistence is completed before a queued Task receives permission to dispatch.
    public func claim(_ original: Confirmation) -> Claim? {
        guard original.capture.coverBindingAllowsReview, confirmation?.id == original.id, isCurrent, source.canSubmit(session: session), readTask == nil, writeTask == nil, claimID == nil else { return nil }
        do {
            let saved = try journal.begin(original.capture, origin: origin, expected: original.snapshot, session: session)
            let claim = Claim(snapshot: saved); snapshot = saved; confirmation = nil; claimID = claim.id; state = .unconfirmed; return claim
        } catch { confirmation = nil; state = .failed(.persistenceUnavailable); return nil }
    }
    public func submit(_ original: Claim) async {
        guard claimID == original.id, snapshot == original.snapshot, readTask == nil, writeTask == nil else { return }
        guard isCurrent, source.canSubmit(session: session) else { close(); return }
        claimID = nil; await send(original.snapshot, mutation: true)
    }
    public func check(_ original: ApprovedTopicReviewJournal.Snapshot) async {
        guard canReadStatus, snapshot == original else { return }; await send(original, mutation: false)
    }
    public func retryExact(_ original: ApprovedTopicReviewJournal.Snapshot) async {
        guard canRetryExact, snapshot == original else { return }; await send(original, mutation: true)
    }
    public func observeCurrent(_ original: ApprovedTopicReviewJournal.Snapshot) async {
        guard canObserve, snapshot == original, let record = original.current, let observer = source as? any ApprovedTopicReviewObserving else { return }
        do { guard try journal.read(session: session, topicID: origin.topicID) == original else { throw ApprovedTopicReleaseError.changedContext } }
        catch { observation = .failed; return }
        let request = UUID(); requestID = request; observation = .loading
        let task = Task { [session] in try await observer.observe(record, session: session) }; observationTask = task
        defer { if requestID == request { requestID = nil; observationTask = nil } }
        do {
            let value = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
            guard requestID == request else { return }
            guard !Task.isCancelled, !task.isCancelled, isCurrent else { close(); return }
            guard snapshot == original, try journal.read(session: session, topicID: origin.topicID) == original else { observation = .failed; return }
            observation = .ready(value)
        } catch {
            guard requestID == request else { return }
            guard !Task.isCancelled, !task.isCancelled, isCurrent else { close(); return }
            observation = error as? APIError == .unauthorized ? .unauthorized : .failed
        }
    }
    private func send(_ original: ApprovedTopicReviewJournal.Snapshot, mutation: Bool) async {
        guard isCurrent, readTask == nil, writeTask == nil, observationTask == nil, claimID == nil, confirmation == nil, let record = original.current else { return }
        guard mutation ? source.canSubmit(session: session) : source.canReadStatus(session: session) else { return }
        do { guard try journal.read(session: session, topicID: origin.topicID) == original else { throw ApprovedTopicReleaseError.changedContext } }
        catch { state = .failed(.persistenceUnavailable); return }
        observation = .notRequested
        guard !mutation || record.capture.coverBindingAllowsReview else { return }
        let request = UUID(); requestID = request; state = .sending
        let task = Task { [source, session] in
            if mutation { return try await source.submit(record, session: session) }
            return try await source.status(record, session: session)
        }; writeTask = task
        defer { if requestID == request { requestID = nil; writeTask = nil } }
        do {
            let receipt = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
            guard requestID == request else { return }
            guard !Task.isCancelled, !task.isCancelled, isCurrent else { close(); return }
            snapshot = try journal.record(receipt, expected: original, session: session); restoreState()
        } catch {
            guard requestID == request else { return }
            guard !Task.isCancelled, !task.isCancelled, isCurrent else { close(); return }
            state = .unconfirmed
        }
    }
    public func close() {
        readTask?.cancel(); writeTask?.cancel(); observationTask?.cancel(); readTask = nil; writeTask = nil; observationTask = nil; observation = .notRequested; requestID = nil; claimID = nil; confirmation = nil; state = .closed
    }
}
