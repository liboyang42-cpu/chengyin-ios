import Foundation

public enum InvoiceLaunchRecovery: Equatable {
    /// Entity facts, not a receipt attributing the write to a particular request.
    case none, application(InvoiceLaunchApplication), title(InvoiceLaunchTitle), titleAbsent(Int64)
    case titleSaved(InvoiceLaunchTitleReceipt)
}

/// Main-actor serialization plus the shared durable journal prevents double taps and
/// restarts from dispatching a second write. Construct one per account/realm, retain
/// it across appearances, and revoke its service on every session transition.
@MainActor public final class InvoiceLaunchCoordinator {
    public let service: InvoiceLaunchService
    public let store: InvoiceLaunchPendingStore
    private var busy = false
    public init(service: InvoiceLaunchService, store: InvoiceLaunchPendingStore) throws {
        guard service.session.ownerKey == store.ownerKey else { throw InvoiceLaunchIssue.invalid }
        self.service = service; self.store = store
    }
    private func begin(mutation: Bool) throws {
        guard !busy else { throw InvoiceLaunchIssue.pendingConflict }
        try service.check(mutation: mutation); busy = true
    }
    /// Fetch actual server eligibility and history; no local quote, eligibility,
    /// invoice-file inference or write is performed when the entry refreshes.
    public func overview() async throws -> InvoiceLaunchOverview {
        try begin(mutation: false); defer { busy = false }
        let titles = try await service.titles()
        let orders = try await service.eligibleOrders()
        let applications = try await service.applications()
        let pending = try store.load(); try service.check()
        return InvoiceLaunchOverview(titles: titles, eligibleOrders: orders,
                                     applications: applications, pending: pending)
    }
    public func apply(_ command: InvoiceLaunchApply) async throws -> InvoiceLaunchApplication {
        try command.validate(); try begin(mutation: true); defer { busy = false }
        var pending = InvoiceLaunchPending(kind: .apply, apply: command, originalApplicationReceipt: service.usesOriginalReceipts ? true : nil)
        try store.save(pending)
        let response = try await dispatch(pending) { try await service.apply(command) }
        return try await readback {
            try service.check()
            guard pending.originalApplicationReceipt != true || response.requestId == command.requestId else { throw InvoiceLaunchIssue.outcomeUnknown }
            pending = try store.checkpoint(pending, applicationID: response.id)
            let result = try await service.detail(id: response.id)
            guard (pending.originalApplicationReceipt != true || result.requestId == command.requestId), result.matches(command), result.applicationNo == response.applicationNo else { throw InvoiceLaunchIssue.outcomeUnknown }
            try service.check(); try store.clear(pending); return result
        }
    }
    public func saveTitle(_ draft: InvoiceLaunchTitleDraft) async throws -> InvoiceLaunchTitle {
        try begin(mutation: true); defer { busy = false }
        var pending = InvoiceLaunchPending(kind: .saveTitle, targetID: draft.id,
            titleRequestID: service.usesOriginalReceipts ? UUID().uuidString : nil)
        try store.save(pending)
        if let request = pending.titleRequestID {
            let receipt = try await dispatch(pending) { try await service.saveTitleWithRequest(draft, requestId: request) }
            return try await readback {
                try service.check()
                pending = try store.checkpointTitle(pending, acknowledgedTitleID: receipt.titleId)
                let titles = try await service.titles()
                guard let title = titles.first(where: { $0.id == receipt.titleId }) else { throw InvoiceLaunchIssue.outcomeUnknown }
                try service.check(); try store.clear(pending); return title
            }
        }
        let response = try await dispatch(pending) { try await service.saveTitle(draft) }
        return try await readback {
            try service.check()
            pending = try store.checkpointTitle(pending, acknowledgedTitleID: response.id)
            let titles = try await service.titles()
            guard titles.contains(response) else { throw InvoiceLaunchIssue.outcomeUnknown }
            try service.check(); try store.clear(pending); return response
        }
    }
    public func deleteTitle(id: Int64) async throws {
        guard id > 0 else { throw InvoiceLaunchIssue.invalid }
        try begin(mutation: true); defer { busy = false }
        let pending = InvoiceLaunchPending(kind: .deleteTitle, targetID: id)
        try store.save(pending)
        try await dispatch(pending) { try await service.deleteTitle(id: id) }
        try await readback {
            let titles = try await service.titles()
            guard !titles.contains(where: { $0.id == id }) else { throw InvoiceLaunchIssue.outcomeUnknown }
            try service.check(); try store.clear(pending)
        }
    }
    public func cancel(id: Int64) async throws -> InvoiceLaunchApplication {
        guard id > 0 else { throw InvoiceLaunchIssue.invalid }
        try begin(mutation: true); defer { busy = false }
        let pending = InvoiceLaunchPending(kind: .cancel, targetID: id)
        try store.save(pending)
        _ = try await dispatch(pending) { try await service.cancel(id: id) }
        return try await readback {
            let result = try await service.detail(id: id)
            guard result.status == .cancelled else { throw InvoiceLaunchIssue.outcomeUnknown }
            try service.check(); try store.clear(pending); return result
        }
    }
    /// Recovery never invokes a mutation, never generates a requestId, and never
    /// guesses an application from eligible orders or list/title/amount similarity.
    public func recover() async throws -> InvoiceLaunchRecovery {
        try begin(mutation: false); defer { busy = false }
        guard let pending = try store.load() else { return .none }
        switch pending.kind {
        case .apply:
            if (service.usesOriginalReceipts || pending.originalApplicationReceipt == true), let command = pending.apply {
                return try await readback {
                    let result = try await service.originalApplication(requestId: command.requestId)
                    guard result.matches(command), pending.applicationID == nil || pending.applicationID == result.id else { throw InvoiceLaunchIssue.outcomeUnknown }
                    try service.check(); try store.clear(pending); return .application(result)
                }
            }
            guard let id = pending.applicationID, let command = pending.apply else { throw InvoiceLaunchIssue.originalReadUnavailable }
            return try await readback {
                let result = try await service.detail(id: id)
                guard result.matches(command) else { throw InvoiceLaunchIssue.outcomeUnknown }
                try service.check(); try store.clear(pending); return .application(result)
            }
        case .cancel:
            guard let id = pending.targetID else { throw InvoiceLaunchIssue.storageUnavailable }
            return try await readback {
                let result = try await service.detail(id: id)
                guard result.status == .cancelled else { throw InvoiceLaunchIssue.outcomeUnknown }
                try service.check(); try store.clear(pending); return .application(result)
            }
        case .deleteTitle:
            guard let id = pending.targetID else { throw InvoiceLaunchIssue.storageUnavailable }
            return try await readback {
                let titles = try await service.titles()
                guard !titles.contains(where: { $0.id == id }) else { throw InvoiceLaunchIssue.outcomeUnknown }
                // Frozen selectTitlesByMember is a complete, unpaginated active-title
                // list; absence proves the original target is no longer active. It
                // does not prove which delete call caused that fact.
                try service.check(); try store.clear(pending); return .titleAbsent(id)
            }
        case .saveTitle:
            if let request = pending.titleRequestID {
                return try await readback {
                    let receipt = try await service.titleReceipt(requestId: request, targetID: pending.targetID)
                    guard pending.acknowledgedTitleID == nil || pending.acknowledgedTitleID == receipt.titleId else { throw InvoiceLaunchIssue.outcomeUnknown }
                    // Exact original receipt is sufficient even if the title was subsequently deleted.
                    try service.check(); try store.clear(pending); return .titleSaved(receipt)
                }
            }
            // A received success can durably identify the original saved entity.
            // A transport-unknown save has no such evidence: neither matching an
            // existing title nor replaying legacy save can confirm that request.
            guard let id = pending.acknowledgedTitleID else { throw InvoiceLaunchIssue.originalReadUnavailable }
            return try await readback {
                let titles = try await service.titles()
                guard let title = titles.first(where: { $0.id == id }) else { throw InvoiceLaunchIssue.outcomeUnknown }
                try service.check(); try store.clear(pending); return .title(title)
            }
        }
    }
    private func readback<T>(_ operation: () async throws -> T) async throws -> T {
        do { return try await operation() }
        catch {
            // Once a write has succeeded or become unknown, a later read error
            // must never look like a definitive rollback to the host. Keep the
            // original journal; storage failures remain explicit and visible.
            switch error as? InvoiceLaunchIssue {
            case .storageUnavailable: throw InvoiceLaunchIssue.storageUnavailable
            case .pendingConflict: throw InvoiceLaunchIssue.pendingConflict
            default: throw InvoiceLaunchIssue.outcomeUnknown
            }
        }
    }
    private func dispatch<T>(_ pending: InvoiceLaunchPending, operation: () async throws -> T) async throws -> T {
        do { return try await operation() }
        catch {
            // Only a coded rollback from the mutation permits a fresh intent.
            // A later readback rejection leaves the persisted operation intact.
            if case InvoiceLaunchIssue.rejected = error {
                try service.check(); try store.clear(pending)
            }
            throw error
        }
    }
}
