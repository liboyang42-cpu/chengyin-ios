import Foundation

public struct ProjectEditConfirmation: Identifiable, Equatable {
    public let id: UUID
    public let draft: ProjectEditDraft
    public let payload: [String: ProjectEditJSON]
    fileprivate let session: ProjectEditSession?
    fileprivate let baseline: ProjectEditSnapshot
}
/// AppSession must retain one coordinator per editor target. Persistent pending intent is
/// written BEFORE submit and survives navigation, same-account reauth, and process restart.
@MainActor public final class ProjectEditCoordinator {
    public enum State: Equatable { case idle, loading, reviewing, submitting, simulated, acknowledged, unknown, rejected, notSent, blocked }
    private let service: any ProjectEditServing
    private let store: ProjectEditLocalStore
    private let currentSession: () -> ProjectEditSession?
    private var capturedSession: ProjectEditSession?
    private var generation = 0
    private let initial: ProjectEditSnapshot
    public private(set) var identity: ProjectEditDraftIdentity?
    public private(set) var snapshot: ProjectEditSnapshot?
    public private(set) var confirmation: ProjectEditConfirmation?
    public private(set) var pending: ProjectEditPending?
    public private(set) var restore: ProjectEditRestore = .missing
    public private(set) var state: State = .idle
    public private(set) var messageKey: String?
    public private(set) var issues: [ProjectEditIssue] = []
    public var session: ProjectEditSession? { currentSession() }
    public var isBusy: Bool { [.loading, .reviewing, .submitting].contains(state) }
    public var isLocked: Bool { (pending != nil && pending?.completedTopicID == nil) || state == .unknown }
    public var canSubmit: Bool { canSimulate || service.authority == .approved }
    public var canSimulate: Bool {
        #if DEBUG
        return service.authority == .synthetic
        #else
        return false
        #endif
    }
    public init(initial: ProjectEditSnapshot, service: any ProjectEditServing, store: ProjectEditLocalStore, currentSession: @escaping () -> ProjectEditSession?) {
        self.initial = initial; self.service = service; self.store = store; self.currentSession = currentSession
    }
    public func synchronizeSession() {
        guard capturedSession != currentSession() else { return }
        generation += 1; capturedSession = currentSession(); snapshot = nil; confirmation = nil
        pending = nil; identity = nil; restore = .missing; issues = []; state = .idle; messageKey = nil
    }
    private func active(_ session: ProjectEditSession, _ stamp: Int) -> Bool { currentSession() == session && generation == stamp && !Task.isCancelled }
    public func load() async {
        synchronizeSession()
        guard !isBusy, state != .simulated, state != .acknowledged else { return }
        guard let session = capturedSession else {
            if initial.topicID == nil { var blank = ProjectEditDraft(product: initial.draft.product); blank.owner = initial.draft.owner; snapshot = .init(draft: blank); state = .idle }
            messageKey = "projectEdit.signIn"; return
        }
        generation += 1; let stamp = generation; state = .loading; confirmation = nil; issues = []
        do {
            let baseline: ProjectEditSnapshot
            if let id = initial.topicID {
                guard service.authority != .disabled else { throw ProjectEditError.notConfigured }
                let value = try await service.preflight(topicID: id, session: session)
                guard active(session, stamp) else { return }
                guard let remote = value.snapshot, remote.topicID == id, remote.draft.owner == initial.draft.owner else { throw ProjectEditError.invalidContract }
                baseline = remote
            } else { baseline = initial }
            let target: ProjectEditDraftIdentity
            if let id = baseline.topicID { target = try .init(topicID: id) }
            else { target = try store.activeIdentity(session: session, product: baseline.draft.product, owner: baseline.draft.owner) ?? ProjectEditDraftIdentity() }
            guard active(session, stamp) else { return }
            identity = target; snapshot = baseline
            pending = try store.pending(session: session, identity: target)
            restore = store.load(session: session, identity: target, baseline: baseline.draft)
            state = pending == nil ? .idle : (pending?.completedTopicID == nil ? .unknown : (pending?.serverAcknowledged == true ? .acknowledged : .simulated))
            messageKey = pending == nil ? (canSimulate ? "projectEdit.fixtureNotice" : "projectEdit.unconfigured") : (pending?.completedTopicID == nil ? "projectEdit.unknown" : (pending?.serverAcknowledged == true ? "projectEdit.acknowledged" : "projectEdit.simulated"))
        } catch {
            guard active(session, stamp) else { return }
            state = .blocked; messageKey = error as? ProjectEditError == .notConfigured ? "projectEdit.unconfigured" : "projectEdit.loadFailed"
        }
    }
    public func restoredDraft() -> ProjectEditDraft? {
        guard !isBusy, !isLocked, capturedSession == currentSession(), let baseline = snapshot,
              case .ready(let envelope) = restore else { return nil }
        guard baseline.scope != .whitelist || envelope.draft.whitelistLockedFieldsEqual(to: baseline.draft) else {
            messageKey = "projectEdit.lockedFields"; return nil
        }
        restore = .missing; var draft = envelope.draft
        if baseline.topicID != nil { draft.publishToCreative = false }
        return draft
    }
    public func discardLocalDraft() {
        guard !isBusy, !isLocked, let session = capturedSession, session == currentSession(), let identity else { return }
        do { try store.remove(session: session, identity: identity); restore = .missing; messageKey = "projectEdit.localRemoved" }
        catch { messageKey = "projectEdit.localFailed" }
    }
    public func saveLocal(_ draft: ProjectEditDraft) {
        guard !isBusy, !isLocked, state != .blocked, state != .simulated, state != .acknowledged, let session = capturedSession, session == currentSession(), let identity,
              let baseline = snapshot, baseline.draft.product == draft.product, baseline.draft.owner == draft.owner,
              baseline.scope != .whitelist || draft.whitelistLockedFieldsEqual(to: baseline.draft) else { return }
        // Never overwrite an unreviewed saved draft/conflict with the blank baseline.
        guard case .missing = restore else { return }
        do { try store.save(draft, session: session, identity: identity); messageKey = "projectEdit.localSaved" }
        catch { messageKey = "projectEdit.localFailed" }
    }
    public func prepare(_ draft: ProjectEditDraft) {
        synchronizeSession(); confirmation = nil
        guard !isBusy, !isLocked, state != .blocked, state != .simulated, state != .acknowledged, capturedSession == currentSession(), let baseline = snapshot else { return }
        let session = capturedSession
        issues = ProjectEditValidation.issues(draft, scope: baseline.scope)
        guard issues.isEmpty else { messageKey = "projectEdit.invalid"; return }
        guard draft.product == baseline.draft.product, draft.owner == baseline.draft.owner,
              draft.baseRevision == baseline.draft.baseRevision,
              baseline.scope != .whitelist || draft.whitelistLockedFieldsEqual(to: baseline.draft) else {
            messageKey = "projectEdit.lockedFields"; return
        }
        do {
            let payload = try ProjectEditContract.payload(draft, topicID: baseline.topicID, scope: baseline.scope)
            confirmation = .init(id: UUID(), draft: draft, payload: payload, session: session, baseline: baseline)
            messageKey = canSimulate ? "projectEdit.fixtureNotice" : "projectEdit.unconfigured"
        } catch { messageKey = "projectEdit.invalid" }
    }
    public func cancelReview() { confirmation = nil }
    public func leaveScreen() { generation += 1; confirmation = nil; if state != .simulated && state != .acknowledged { state = isLocked ? .unknown : .idle } }
    public func confirm(_ value: ProjectEditConfirmation) async {
        synchronizeSession()
        guard !isBusy, !isLocked, confirmation == value, currentSession() == value.session else { return }
        guard let session = value.session, let identity else { messageKey = "projectEdit.signIn"; confirmation = nil; return }
        guard canSubmit else { messageKey = "projectEdit.unconfigured"; confirmation = nil; return }
        generation += 1; let stamp = generation
        state = .reviewing; confirmation = nil
        do {
            let check = try await service.preflight(topicID: value.baseline.topicID, session: session)
            guard active(session, stamp) else { return }
            if value.baseline.topicID == nil {
                guard check.capability.allowsCreate else { state = .blocked; messageKey = "projectEdit.capabilityBlocked"; return }
            } else {
                guard check.snapshot == value.baseline else { state = .blocked; messageKey = "projectEdit.revisionConflict"; return }
            }
            if let existing = try store.pending(session: session, identity: identity) {
                pending = existing; state = .unknown; messageKey = "projectEdit.unknown"; return
            }
            // Persist the active new-draft pointer as well as the intent, so a fresh
            // coordinator can discover an uncertain create even without UI autosave.
            try store.save(value.draft, session: session, identity: identity)
            let operation = ProjectEditPending(operationID: value.id, ownerKey: session.ownerKey, identity: identity, payload: value.payload, baseline: value.baseline)
            try store.savePending(operation, session: session)
            pending = operation; state = .submitting
            let outcome = await service.submit(operation, session: session)
            // The persisted lock is intentionally retained if the user or navigation changed.
            guard active(session, stamp) else { return }
            apply(outcome, operation: operation, session: session)
        } catch {
            guard active(session, stamp) else { return }
            state = pending == nil ? .blocked : .unknown
            messageKey = pending == nil ? "projectEdit.preflightFailed" : "projectEdit.unknown"
        }
    }
    private func apply(_ result: ProjectEditWriteOutcome, operation: ProjectEditPending, session: ProjectEditSession) {
        switch result {
        case .simulatedReceipt(let operationID, let topicID):
            guard operationID == operation.operationID, topicID > 0,
                  operation.identity.topicID == nil || operation.identity.topicID == topicID else { state = .unknown; messageKey = "projectEdit.unknown"; return }
            do {
                var completed = operation; completed.completedTopicID = topicID
                try store.savePending(completed, session: session)
                pending = completed; state = .simulated; messageKey = "projectEdit.simulated"
            } catch { state = .unknown; messageKey = "projectEdit.unknown" }
        case .acknowledged(let operationID, let topicID):
            guard operationID == operation.operationID, topicID > 0,
                  operation.identity.topicID == nil || operation.identity.topicID == topicID else { state = .unknown; messageKey = "projectEdit.unknown"; return }
            do {
                var completed = operation; completed.completedTopicID = topicID; completed.serverAcknowledged = true
                try store.savePending(completed, session: session)
                pending = completed; state = .acknowledged; messageKey = "projectEdit.acknowledged"
            } catch { state = .unknown; messageKey = "projectEdit.unknown" }
        case .rejected, .notSent:
            do {
                try store.clearPending(session: session, identity: operation.identity); pending = nil
                state = result == .rejected ? .rejected : .notSent
                messageKey = result == .rejected ? "projectEdit.rejected" : "projectEdit.notSent"
            } catch { state = .unknown; messageKey = "projectEdit.unknown" }
        case .unknown: state = .unknown; messageKey = "projectEdit.unknown"
        }
    }
    public func checkOutcome() async {
        synchronizeSession()
        guard !isBusy, let session = capturedSession, let pending, canSimulate else { return }
        generation += 1; let stamp = generation; state = .reviewing
        do {
            let receipt = try await service.terminalReceipt(operationID: pending.operationID, session: session)
            guard active(session, stamp) else { return }
            if let receipt { apply(receipt, operation: pending, session: session) }
            else { state = .unknown; messageKey = "projectEdit.unknown" }
        } catch {
            guard active(session, stamp) else { return }; state = .unknown; messageKey = "projectEdit.unknown"
        }
    }
}
