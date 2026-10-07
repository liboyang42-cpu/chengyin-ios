import Foundation

/// Owns the real permission-bound tasks and original confirmations for one captured author presentation.
@MainActor public final class ApprovedTopicReviewFlow {
    public enum State: Equatable {
        case selectingSources(SourceSelectionPresentation)
        case idle, loading, ready(ApprovedTopicReviewCapture), sending, unconfirmed, known(ApprovedTopicReviewReceipt)
        case failed(ApprovedTopicReleaseError), unauthorized, closed
    }
    public struct SourceSelectionPresentation: Equatable, Identifiable {
        public let id = UUID()
        public let choices: ApprovedMerchantReviewChoices
    }
    public struct SourceCaptureClaim {
        public let id = UUID()
        fileprivate let presentation: SourceSelectionPresentation
        fileprivate let selected: [ApprovedMerchantReviewSource]
    }
    public private(set) var selectedSources: [Int: ApprovedMerchantReviewSource] = [:]
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
    private var sourcesTask: Task<ApprovedMerchantReviewChoices, Error>?
    private var readTask: Task<ApprovedTopicReviewCapture, Error>?
    private var writeTask: Task<ApprovedTopicReviewReceipt, Error>?
    private var observationTask: Task<ApprovedTopicReviewObservation, Error>?
    public init(origin: ApprovedTopicReleaseReadTarget, session: ProjectEditSession, source: any ApprovedTopicReviewServing,
                journal: ApprovedTopicReviewJournal, stillCurrent: @escaping () -> Bool) {
        self.origin = origin; self.session = session; self.source = source; self.journal = journal; self.stillCurrent = stillCurrent
    }
    public var isCurrent: Bool { state != .closed && origin.ownerKey == session.ownerKey && stillCurrent() && source.isCurrent(session: session) }
    private var isBusy: Bool { sourcesTask != nil || readTask != nil || writeTask != nil || observationTask != nil || claimID != nil || confirmation != nil }
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
        selectedSources = [:]
        if let chooser = source as? any ApprovedTopicReviewSourceChoosing, chooser.canReadSources(session: session) {
            let request = UUID(); requestID = request; state = .loading
            let task = Task { [origin, session] in try await chooser.sources(origin, session: session) }; sourcesTask = task
            defer { if requestID == request { requestID = nil; sourcesTask = nil } }
            do {
                let choices = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
                guard requestID == request else { return }
                guard !Task.isCancelled, !task.isCancelled, isCurrent, chooser.canReadSources(session: session) else { close(); return }
                if !choices.groups.isEmpty { state = .selectingSources(.init(choices: choices)); return }
                sourcesTask = nil; requestID = nil
            } catch {
                guard requestID == request else { return }
                guard !Task.isCancelled, !task.isCancelled, isCurrent else { close(); return }
                state = error as? APIError == .unauthorized ? .unauthorized : .failed(error as? ApprovedTopicReleaseError ?? .unavailable); return
            }
        }
        await captureSelections([], choices: nil)
    }
    public func selectSource(_ choice: ApprovedMerchantReviewChoices.Choice, from original: SourceSelectionPresentation) -> Bool {
        guard isCurrent, !isBusy, case .selectingSources(let current) = state, current == original,
              (source as? any ApprovedTopicReviewSourceChoosing)?.canReadSources(session: session) == true,
              original.choices.groups.contains(where: { $0.confirmations.contains(choice) }) else { return false }
        selectedSources[choice.selection.memberTemplateID] = choice.selection; return true
    }
    public func canCaptureSources(_ original: SourceSelectionPresentation) -> Bool {
        guard isCurrent, !isBusy, source.canPrepare(session: session), case .selectingSources(let current) = state, current == original,
              (source as? any ApprovedTopicReviewSourceChoosing)?.canReadSources(session: session) == true else { return false }
        return original.choices.groups.allSatisfy { group in group.confirmations.contains { $0.selection == selectedSources[group.memberTemplateID] } }
    }
    /// Captured synchronously by the real button, so a queued task cannot choose a later presentation.
    public func claimSourceCapture(_ original: SourceSelectionPresentation) -> SourceCaptureClaim? {
        guard canCaptureSources(original) else { return nil }
        let claim = SourceCaptureClaim(presentation: original, selected: selectedSources.values.sorted { $0.memberTemplateID < $1.memberTemplateID })
        claimID = claim.id; return claim
    }
    public func captureSources(_ original: SourceCaptureClaim) async {
        guard claimID == original.id, case .selectingSources(let current) = state, current == original.presentation else { return }
        guard isCurrent, source.canPrepare(session: session),
              (source as? any ApprovedTopicReviewSourceChoosing)?.canReadSources(session: session) == true else { close(); return }
        claimID = nil; await captureSelections(original.selected, choices: original.presentation.choices)
    }
    private func captureSelections(_ selections: [ApprovedMerchantReviewSource], choices: ApprovedMerchantReviewChoices?) async {
        guard source.canPrepare(session: session) else { state = .failed(.notConfigured); return }
        let request = UUID(); requestID = request; state = .loading
        let task = Task { [source, origin, session] in
            if let chooser = source as? any ApprovedTopicReviewSourceChoosing { return try await chooser.prepare(origin, selections: selections, session: session) }
            guard selections.isEmpty else { throw ApprovedTopicReleaseError.notConfigured }
            return try await source.prepare(origin, session: session)
        }; readTask = task
        defer { if requestID == request { requestID = nil; readTask = nil } }
        do {
            let captured = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
            guard requestID == request else { return }
            guard !Task.isCancelled, !task.isCancelled, isCurrent else { close(); return }
            guard captured.selectedMerchantSources == selections else { state = .failed(.changedReview); return }
            if let choices {
                guard captured.observedAuditTaskVersion == choices.observedAuditTaskVersion, captured.sourceConfigVersion == choices.sourceConfigVersion else { state = .failed(.changedReview); return }
            }
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
        sourcesTask?.cancel(); sourcesTask = nil; selectedSources = [:]; readTask?.cancel(); writeTask?.cancel(); observationTask?.cancel(); readTask = nil; writeTask = nil; observationTask = nil; observation = .notRequested; requestID = nil; claimID = nil; confirmation = nil; state = .closed
    }
}
