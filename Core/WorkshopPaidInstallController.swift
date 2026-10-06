import Foundation
import Observation

/// One actual modal presentation, never revived by a cached View or queued onAppear.
@MainActor public final class WorkshopPaidInstallAppearance {
    private var started = false
    private(set) var closed = false
    fileprivate var action: WorkshopPaidInstallAction?
    public init() {}
    fileprivate func begin() -> Bool { guard !started, !closed else { return false }; started = true; return true }
    fileprivate func revoke() { closed = true; action?.revoke(); action = nil }
}
@MainActor fileprivate final class WorkshopPaidInstallAction {
    weak var appearance: WorkshopPaidInstallAppearance?
    private var revoked = false, entered = false
    init(_ appearance: WorkshopPaidInstallAppearance) { self.appearance = appearance }
    var live: Bool { !revoked && appearance?.closed == false && appearance?.action === self }
    func revoke() { revoked = true }
    func claim() -> Bool { guard live, !entered else { return false }; entered = true; return true }
}
@available(macOS 14.0, *)
@MainActor @Observable public final class WorkshopPaidInstallController {
    public enum Phase: Equatable { case idle, loading, ready, confirming, submitting, installed, invalidated, failed }
    public typealias Action = @MainActor () async -> Void
    public let identity = UUID()
    public let item: WorkshopPurchasedItem
    public private(set) var phase: Phase = .idle
    public private(set) var targets: [WorkshopPaidInstallTarget] = []
    public private(set) var history: [WorkshopPaidInstallOutcome] = []
    public private(set) var nextTargetCursor: Int64?
    public private(set) var nextHistoryCursor: String?
    public private(set) var target: WorkshopPaidInstallTarget?
    public private(set) var region: String?
    public private(set) var commercialUse = false
    public private(set) var confirmation: WorkshopPaidInstallCommand?
    public private(set) var pending: WorkshopPaidInstallCommand?
    public private(set) var outcome: WorkshopPaidInstallOutcome?
    public private(set) var issue: WorkshopPaidInstallIssue?
    public private(set) var targetIssue: WorkshopPaidInstallIssue?
    private let service: any WorkshopPaidInstallServing
    private let lease: ContentDraftSessionLease
    private let store: WorkshopPaidInstallPendingStore
    private var appearance: WorkshopPaidInstallAppearance?
    private var lifetime: WorkshopPaidInstallLifetime?
    public init(item: WorkshopPurchasedItem, service: any WorkshopPaidInstallServing, lease: ContentDraftSessionLease, store: WorkshopPaidInstallPendingStore) {
        self.item = item; self.service = service; self.lease = lease; self.store = store
    }
    public func invalidate() {
        guard phase != .invalidated else { return }
        appearance?.revoke(); appearance = nil; lifetime?.revoke(); lifetime = nil; lease.revoke()
        targets = []; history = []; target = nil; region = nil; confirmation = nil; pending = nil; outcome = nil
        nextTargetCursor = nil; nextHistoryCursor = nil; phase = .invalidated; issue = .staleSession
        // Do not delete the original owner-scoped durable pending record on identity replacement.
    }
    private func current(_ displayed: WorkshopPaidInstallAppearance) -> Bool {
        guard lease.isCurrent else { invalidate(); return false }
        return phase != .invalidated && appearance === displayed && !displayed.closed
    }
    public func appear(_ displayed: WorkshopPaidInstallAppearance) -> Action? {
        guard lease.isCurrent, phase != .invalidated, displayed.begin() else { return nil }
        appearance?.revoke(); lifetime?.revoke(); appearance = displayed
        return offerLoad(displayed)
    }
    public func close(_ displayed: WorkshopPaidInstallAppearance) {
        displayed.revoke(); guard appearance === displayed else { return }
        lifetime?.revoke(); lifetime = nil; appearance = nil
        target = nil; region = nil; confirmation = nil; targets = []; history = []; nextTargetCursor = nil; nextHistoryCursor = nil
        if phase != .invalidated { phase = .idle }; issue = nil; targetIssue = nil
        // A submitted operation may already be committed. Back never clears pending or reports failure.
    }
    private func offer(_ displayed: WorkshopPaidInstallAppearance) -> (WorkshopPaidInstallAction, WorkshopPaidInstallLifetime)? {
        guard current(displayed), phase != .submitting else { return nil }
        displayed.action?.revoke(); lifetime?.revoke()
        let action = WorkshopPaidInstallAction(displayed); displayed.action = action
        let life = WorkshopPaidInstallLifetime { [weak self, weak displayed, weak action] in
            guard let self, let displayed, let action else { return false }
            return self.current(displayed) && action.live
        }
        lifetime = life; return (action, life)
    }
    public func offerLoad(_ displayed: WorkshopPaidInstallAppearance, beforeTarget: Int64? = nil, beforeHistory: String? = nil) -> Action? {
        guard beforeTarget == nil || beforeTarget == nextTargetCursor, beforeHistory == nil || beforeHistory == nextHistoryCursor,
              let (action, life) = offer(displayed) else { return nil }
        confirmation = nil; target = nil; region = nil; phase = .loading
        return { [weak self] in
            guard let self, action.claim(), self.current(displayed) else { return }
            self.phase = .loading; self.issue = nil; self.targetIssue = nil
            do {
                self.pending = try self.store.load()
                guard self.pending?.belongs(to: self.item) != false else { throw WorkshopPaidInstallIssue.storageUnavailable }
                let history = try await self.service.history(licenseId: self.item.licenseId, before: beforeHistory, lifetime: life)
                try life.check(); guard history.items.allSatisfy({ $0.command?.belongs(to: self.item) == true }) else { throw WorkshopPaidInstallIssue.malformed }
                self.history = history.items; self.nextHistoryCursor = history.nextBeforeCommandKey
                if let pending = self.pending {
                    let status = try await self.service.status(command: pending, lifetime: life); try life.check(); try self.accept(status, expected: pending)
                }
                if self.item.status == .active {
                    do {
                        let targets = try await self.service.targets(licenseId: self.item.licenseId, before: beforeTarget, lifetime: life); try life.check()
                        self.targets = targets.items; self.nextTargetCursor = targets.nextBeforeDraftId
                    } catch { try life.check(); self.targets = []; self.nextTargetCursor = nil; self.targetIssue = (error as? WorkshopPaidInstallIssue) ?? .unavailable }
                }
                try life.check(); self.phase = self.outcome?.state == .installed ? .installed : .ready
            } catch {
                guard action.live, self.current(displayed) else { return }
                self.issue = (error as? WorkshopPaidInstallIssue) ?? .unavailable; self.phase = .failed
            }
        }
    }
    public func select(_ target: WorkshopPaidInstallTarget?, appearance displayed: WorkshopPaidInstallAppearance) {
        guard current(displayed), phase == .ready || phase == .installed, pending == nil,
              target == nil || targets.contains(where: { $0.id == target?.id && $0 == target }) else { return }
        confirmation = nil; self.target = target; region = nil; commercialUse = false
    }
    public func chooseRegion(_ region: String?, appearance displayed: WorkshopPaidInstallAppearance) {
        guard current(displayed), phase == .ready || phase == .installed, pending == nil,
              region == nil || item.allowedRegions.contains(where: { WorkshopPaidInstallWire.same($0, region!) }) else { return }
        confirmation = nil; self.region = region
    }
    public func chooseCommercialUse(_ commercial: Bool, appearance displayed: WorkshopPaidInstallAppearance) {
        guard current(displayed), phase == .ready || phase == .installed, pending == nil, !commercial || item.commercialUse == .allowed else { return }
        confirmation = nil; commercialUse = commercial
    }
    public func review(appearance displayed: WorkshopPaidInstallAppearance) {
        guard current(displayed), phase == .ready || phase == .installed, pending == nil, let target, let region else { return }
        do { confirmation = try WorkshopPaidInstallCommand(item: item, target: target, region: region, commercialUse: commercialUse); phase = .confirming; issue = nil }
        catch { issue = .invalid }
    }
    public func reviewRecovery(_ receipt: WorkshopPaidInstallOutcome? = nil, appearance displayed: WorkshopPaidInstallAppearance) {
        guard current(displayed), phase != .submitting, phase != .loading else { return }
        let command: WorkshopPaidInstallCommand?
        if let receipt {
            guard !receipt.state.terminal, receipt.state != .notFound,
                  history.contains(where: { $0.id == receipt.id && $0 == receipt }) else { return }
            command = receipt.command
        } else { command = pending }
        guard let command, command.belongs(to: item), pending == nil || (try? pending?.wireData()) == (try? command.wireData()) else { return }
        confirmation = command; phase = .confirming; issue = nil
    }
    public func cancelReview(appearance displayed: WorkshopPaidInstallAppearance) {
        guard current(displayed), phase == .confirming else { return }; confirmation = nil; phase = .ready
    }
    public func offerSubmit(_ displayed: WorkshopPaidInstallAppearance, command expected: WorkshopPaidInstallCommand) -> Action? {
        guard current(displayed), phase == .confirming, let confirmation, confirmation.id == expected.id,
              (try? confirmation.wireData()) == (try? expected.wireData()), let (action, life) = offer(displayed) else { return nil }
        do { try store.save(confirmation); pending = confirmation }
        catch { issue = (error as? WorkshopPaidInstallIssue) ?? .storageUnavailable; return nil }
        // Synchronous one-use claim and phase change precede Task creation. Double taps offer nothing.
        self.confirmation = nil; outcome = nil; phase = .submitting; issue = nil
        let consent = WorkshopPaidInstallConfirmation(command: confirmation, lifetime: life)
        return { [weak self] in
            guard let self, action.claim(), self.current(displayed) else { return }
            do { let value = try await self.service.submit(consent); try life.check(); try self.accept(value, expected: confirmation); self.phase = .installed }
            catch {
                guard action.live, self.current(displayed) else { return }
                self.issue = (error as? WorkshopPaidInstallIssue) ?? .outcomeUnknown; self.phase = .ready
            }
        }
    }
    public func offerStatus(_ displayed: WorkshopPaidInstallAppearance) -> Action? {
        guard let pending, let (action, life) = offer(displayed) else { return nil }
        return { [weak self] in
            guard let self, action.claim(), self.current(displayed) else { return }
            self.phase = .loading; self.issue = nil
            do { let value = try await self.service.status(command: pending, lifetime: life); try life.check(); try self.accept(value, expected: pending); self.phase = value.state == .installed ? .installed : .ready }
            catch { guard action.live, self.current(displayed) else { return }; self.issue = (error as? WorkshopPaidInstallIssue) ?? .unavailable; self.phase = .ready }
        }
    }
    private func accept(_ value: WorkshopPaidInstallOutcome, expected: WorkshopPaidInstallCommand) throws {
        guard value.matches(expected), expected.belongs(to: item) else { throw WorkshopPaidInstallIssue.malformed }
        outcome = value
        if value.state.terminal { try store.acknowledge(value); pending = nil }
        // NOT_FOUND never erases a saved UUID: an older request may still be committing its command.
    }
    /// Synchronous entry capture while the actual install/history presentation is still live.
    /// A delayed button callback after Back cannot mint a protected-read presentation.
    public func installedTextReference(_ receipt: WorkshopPaidInstallOutcome, appearance displayed: WorkshopPaidInstallAppearance) -> WorkshopPaidInstalledTextReference? {
        guard current(displayed), phase == .ready || phase == .installed,
              receipt.state == .installed, outcome == receipt || history.contains(receipt) else { return nil }
        return try? WorkshopPaidInstalledTextReference(item: item, receipt: receipt)
    }
}
