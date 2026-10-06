import Foundation
import Observation

@MainActor public final class WorkshopPaidProfessionalAppearance {
    fileprivate var started = false, closed = false
    fileprivate var action: WorkshopPaidProfessionalAction?
    public init() {}
    fileprivate func begin() -> Bool { guard !started, !closed else { return false }; started = true; return true }
    fileprivate func revoke() { closed = true; action?.revoke(); action = nil }
}
@MainActor fileprivate final class WorkshopPaidProfessionalAction {
    weak var appearance: WorkshopPaidProfessionalAppearance?
    private var revoked = false, entered = false
    init(_ appearance: WorkshopPaidProfessionalAppearance) { self.appearance = appearance }
    var live: Bool { !revoked && appearance?.closed == false && appearance?.action === self }
    func revoke() { revoked = true }
    func claim() -> Bool { guard live, !entered else { return false }; entered = true; return true }
}

/// The actual screen uses captured one-shot offers. Recovery remains available without a protected
/// body grant. A new creation needs fresh body, generic-draft CAS and professional target reads.
@available(macOS 14.0, *)
@MainActor @Observable public final class WorkshopPaidProfessionalController {
    public enum Phase: Equatable { case idle, loading, history, targets, review, submitting, operation, unavailable, invalidated }
    public typealias Action = @MainActor () async -> Void
    public let reference: WorkshopPaidInstalledTextReference
    public private(set) var phase: Phase = .idle
    public private(set) var issue: WorkshopPaidProfessionalIssue?
    public private(set) var operations: [WorkshopPaidProfessionalOperationReference] = []
    public private(set) var nextOperationCursor: String?
    public private(set) var targets: [WorkshopPaidProfessionalTarget] = []
    public private(set) var nextTargetCursor: Int64?
    public private(set) var selectedTarget: WorkshopPaidProfessionalTarget?
    public private(set) var body: WorkshopPaidInstalledText?
    public private(set) var currentDraft: WorkshopPaidInstallTarget?
    public private(set) var command: WorkshopPaidProfessionalCommand?
    public private(set) var operation: WorkshopPaidProfessionalOperation?
    private let service: any WorkshopPaidProfessionalServing
    private let preparation: WorkshopPaidProfessionalPreparation?
    private let store: WorkshopPaidProfessionalPendingStore
    private let lease: ContentDraftSessionLease
    private var appearance: WorkshopPaidProfessionalAppearance?
    private var lifetime: WorkshopPaidProfessionalLifetime?
    public init(reference: WorkshopPaidInstalledTextReference, service: any WorkshopPaidProfessionalServing,
                preparation: WorkshopPaidProfessionalPreparation? = nil, store: WorkshopPaidProfessionalPendingStore,
                lease: ContentDraftSessionLease) {
        self.reference = reference; self.service = service; self.preparation = preparation; self.store = store; self.lease = lease
    }
    public func invalidate() {
        appearance?.revoke(); appearance = nil; lifetime?.revoke(); lifetime = nil; lease.revoke()
        clearVisible(); phase = .invalidated; issue = .staleSession
    }
    public func close(_ displayed: WorkshopPaidProfessionalAppearance) {
        displayed.revoke(); guard appearance === displayed else { return }
        lifetime?.revoke(); lifetime = nil; appearance = nil; clearVisible()
        if phase != .invalidated { phase = .idle; issue = nil }
        // Durable intent stays until the server returns a matching terminal operation.
    }
    private func clearVisible() {
        body = nil; selectedTarget = nil; currentDraft = nil; targets = []; nextTargetCursor = nil
        operations = []; nextOperationCursor = nil; command = nil; operation = nil
    }
    private func current(_ displayed: WorkshopPaidProfessionalAppearance) -> Bool {
        guard lease.isCurrent else { invalidate(); return false }
        return phase != .invalidated && appearance === displayed && !displayed.closed
    }
    public func appear(_ displayed: WorkshopPaidProfessionalAppearance) -> Action? {
        guard lease.isCurrent, phase != .invalidated, displayed.begin() else { return nil }
        appearance?.revoke(); lifetime?.revoke(); appearance = displayed; clearVisible()
        return offerRecovery(displayed)
    }
    private func offer(_ displayed: WorkshopPaidProfessionalAppearance, phase next: Phase,
                       work: @escaping @MainActor (WorkshopPaidProfessionalLifetime) async throws -> Void) -> Action? {
        guard current(displayed) else { return nil }
        displayed.action?.revoke(); lifetime?.revoke()
        let action = WorkshopPaidProfessionalAction(displayed); displayed.action = action
        let life = WorkshopPaidProfessionalLifetime { [weak self, weak displayed, weak action] in
            guard let self, let displayed, let action else { return false }
            return action.live && self.current(displayed)
        }
        lifetime = life; phase = next; issue = nil
        return { [weak self] in
            guard let self, action.claim(), self.current(displayed) else { return }
            do { try life.check(); try await work(life); try life.check() }
            catch {
                guard action.live, self.current(displayed) else { return }
                self.body = nil; self.selectedTarget = nil; self.currentDraft = nil
                self.issue = (error as? WorkshopPaidProfessionalIssue) ?? .unavailable
                self.phase = self.command == nil ? .unavailable : .operation
            }
        }
    }
    public func offerRecovery(_ displayed: WorkshopPaidProfessionalAppearance) -> Action? {
        offer(displayed, phase: .loading) { [weak self] life in
            guard let self else { return }; self.body = nil; self.selectedTarget = nil; self.currentDraft = nil
            if let pending = try self.store.load() {
                guard pending.matches(self.reference) else { throw WorkshopPaidProfessionalIssue.storageUnavailable }
                self.command = pending; self.operation = nil
                let state = try await self.service.history(command: pending, lifetime: life)
                try life.check(); self.operation = state; self.phase = .operation
            } else {
                self.command = nil; self.operation = nil
                let page = try await self.service.operations(licenseId: self.reference.item.licenseId, before: nil, lifetime: life)
                try life.check(); self.operations = page.items.filter { $0.command.matches(self.reference) }
                self.nextOperationCursor = page.nextBeforeOperationKey; self.phase = .history
            }
        }
    }
    public func offerMoreOperations(_ displayed: WorkshopPaidProfessionalAppearance) -> Action? {
        guard phase == .history, let cursor = nextOperationCursor else { return nil }
        return offer(displayed, phase: .loading) { [weak self] life in
            guard let self else { return }
            let page = try await self.service.operations(licenseId: self.reference.item.licenseId, before: cursor, lifetime: life)
            try life.check(); self.operations += page.items.filter { $0.command.matches(self.reference) }
            self.nextOperationCursor = page.nextBeforeOperationKey; self.phase = .history
        }
    }
    public func offerInspect(_ candidate: WorkshopPaidProfessionalOperationReference, displayed: WorkshopPaidProfessionalAppearance) -> Action? {
        guard phase == .history, operations.contains(where: { $0.operationKey == candidate.operationKey && $0.commandHash == candidate.commandHash }),
              candidate.command.matches(reference) else { return nil }
        return offer(displayed, phase: .loading) { [weak self] life in
            guard let self else { return }
            if let old = try self.store.load(), try old.wireData() != candidate.command.wireData() { throw WorkshopPaidProfessionalIssue.pendingConflict }
            self.command = candidate.command; self.operation = nil
            let state = try await self.service.history(command: candidate.command, lifetime: life)
            try life.check(); self.operation = state; self.phase = .operation
        }
    }
    public func offerRefreshStatus(_ displayed: WorkshopPaidProfessionalAppearance) -> Action? {
        guard phase == .operation, let command else { return nil }
        return offer(displayed, phase: .loading) { [weak self] life in
            guard let self else { return }
            let state = try await self.service.history(command: command, lifetime: life)
            try life.check(); self.operation = state; self.phase = .operation
        }
    }
    public func offerNewReview(_ displayed: WorkshopPaidProfessionalAppearance) -> Action? {
        guard phase == .history, command == nil else { return nil }
        return offer(displayed, phase: .loading) { [weak self] life in
            guard let self else { return }
            guard try self.store.load() == nil, let preparation = self.preparation else { throw WorkshopPaidProfessionalIssue.disabled }
            let body = try await preparation.body(self.reference, lifetime: life)
            try life.check()
            guard body.matches(self.reference), body.originalBusinessType == "TOPIC", body.rights.adaptation == .localAdaptation else { throw WorkshopPaidProfessionalIssue.invalid }
            let page = try await self.service.targets(licenseId: body.licenseID, before: nil, lifetime: life)
            try life.check(); self.body = body; self.targets = page.items; self.nextTargetCursor = page.nextBeforeTopicId; self.phase = .targets
        }
    }
    public func offerMoreTargets(_ displayed: WorkshopPaidProfessionalAppearance) -> Action? {
        guard phase == .targets, let cursor = nextTargetCursor else { return nil }
        return offer(displayed, phase: .loading) { [weak self] life in
            guard let self else { return }
            let page = try await self.service.targets(licenseId: self.reference.item.licenseId, before: cursor, lifetime: life)
            try life.check(); self.targets += page.items; self.nextTargetCursor = page.nextBeforeTopicId; self.phase = .targets
        }
    }
    public func offerSelect(_ selected: WorkshopPaidProfessionalTarget, displayed: WorkshopPaidProfessionalAppearance) -> Action? {
        guard phase == .targets, body != nil, selected.mode != .unresolved, targets.contains(selected) else { return nil }
        return offer(displayed, phase: .loading) { [weak self] life in
            guard let self, let preparation = self.preparation, let body = self.body else { throw WorkshopPaidProfessionalIssue.disabled }
            let current = try await self.service.target(licenseId: body.licenseID, topicId: selected.topicId, lifetime: life)
            try life.check()
            guard current == selected else { throw WorkshopPaidProfessionalIssue.invalid }
            let draft = try await preparation.currentDraft(self.reference, body: body, lifetime: life)
            try life.check(); self.selectedTarget = current; self.currentDraft = draft; self.phase = .review
        }
    }
    /// Called synchronously by the explicit confirmation button, before creating its Task.
    public func offerSubmit(_ displayed: WorkshopPaidProfessionalAppearance, confirmedMode: WorkshopPaidProfessionalTarget.Mode) -> Action? {
        guard current(displayed), phase == .review, let body, let currentDraft, let selectedTarget, let lifetime else { return nil }
        do {
            try service.requireWrite(lifetime: lifetime)
            let value = try WorkshopPaidProfessionalCommand(reference: reference, body: body, currentDraft: currentDraft, target: selectedTarget, confirmedMode: confirmedMode)
            try store.save(value); command = value; operation = nil
            self.body = nil; self.currentDraft = nil; self.selectedTarget = nil
            return offer(displayed, phase: .submitting) { [weak self] life in
                guard let self else { return }
                let value = try await self.service.submit(WorkshopPaidProfessionalConfirmation(command: value, lifetime: life, purpose: .create))
                try life.check(); self.operation = value; self.phase = .operation
            }
        } catch { issue = (error as? WorkshopPaidProfessionalIssue) ?? .storageUnavailable; return nil }
    }
    public func offerCancelPending(_ displayed: WorkshopPaidProfessionalAppearance) -> Action? {
        guard current(displayed), phase == .operation, let command, let lifetime, operation?.state.terminal != true else { return nil }
        do { try service.requireWrite(lifetime: lifetime); try store.save(command) } catch { issue = (error as? WorkshopPaidProfessionalIssue) ?? .storageUnavailable; return nil }
        return offer(displayed, phase: .submitting) { [weak self] life in
            guard let self else { return }
            let result = try await self.service.cancel(WorkshopPaidProfessionalConfirmation(command: command, lifetime: life, purpose: .cancel))
            try life.check(); self.operation = result; self.phase = .operation
        }
    }
    public func offerAcknowledge(_ displayed: WorkshopPaidProfessionalAppearance) -> Action? {
        guard current(displayed), phase == .operation, let operation, operation.state.terminal, let command, operation.matches(command) else { return nil }
        do {
            if try store.load() != nil { try store.acknowledge(operation) }
            self.command = nil; self.operation = nil
            return offerRecovery(displayed)
        } catch { issue = .storageUnavailable; return nil }
    }
}
