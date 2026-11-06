import SwiftUI

/// Host-owned capabilities. These only hide UI; the existing service still authorizes every request.
enum InvoiceLaunchUIAction: Hashable { case apply, saveTitle, deleteTitle, cancel }

@MainActor final class InvoiceLaunchPresentation: ObservableObject {
    let coordinator: InvoiceLaunchCoordinator
    private let isCurrent: () -> Bool
    private let permits: (InvoiceLaunchUIAction) -> Bool
    @Published private(set) var overview: InvoiceLaunchOverview?
    @Published private(set) var detail: InvoiceLaunchApplication?
    @Published private(set) var busy = false
    @Published private(set) var issue: String?
    @Published private(set) var unresolved = false
    @Published private(set) var identityRevision = UUID()
    private var generation: UUID { identityRevision }
    private var detailIntent = UUID()
    private var idleWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    private func wakeIdleWaiters() {
        let waiters = Array(idleWaiters.values)
        idleWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }
    private func finishOperation() {
        busy = false
        wakeIdleWaiters()
    }
    private func waitForDetailTurn(visit: UUID, intent: UUID) async {
        while busy && generation == visit && detailIntent == intent && !Task.isCancelled {
            let id = UUID()
            await withTaskCancellationHandler {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    if Task.isCancelled { continuation.resume() }
                    else { idleWaiters[id] = continuation }
                }
            } onCancel: {
                Task { @MainActor [weak self] in
                    self?.idleWaiters.removeValue(forKey: id)?.resume()
                }
            }
        }
    }

    init(coordinator: InvoiceLaunchCoordinator, isCurrent: @escaping () -> Bool,
         permits: @escaping (InvoiceLaunchUIAction) -> Bool = { _ in false }) {
        self.coordinator = coordinator; self.isCurrent = isCurrent; self.permits = permits
    }

    func allows(_ action: InvoiceLaunchUIAction) -> Bool {
        isCurrent() && permits(action) && overview != nil && !busy && !unresolved && issue == nil
    }

    /// The host calls this for account, realm, epoch, role or grant changes; it never clears the journal.
    func invalidate() {
        identityRevision = UUID(); detailIntent = UUID()
        wakeIdleWaiters()
        overview = nil; detail = nil; issue = nil; unresolved = false
        // An outstanding request retains serialization until its own defer runs.
    }

    func refresh() async {
        guard !busy else { return }
        guard isCurrent() else { invalidate(); issue = "session"; return }
        let visit = generation
        busy = true; issue = nil
        defer { finishOperation() }
        do {
            // Recover before admitting another intent. Recovery is read-only and never resends a write.
            if try coordinator.store.load() != nil {
                do { _ = try await coordinator.recover() }
                catch { guard accept(visit) else { return } }
            }
            let result = try await coordinator.overview()
            guard accept(visit) else { return }
            overview = result; unresolved = result.pending != nil
        } catch { fail(error, visit: visit) }
    }

    func loadDetail(_ id: Int64) async {
        guard !Task.isCancelled else { return }
        guard isCurrent() else { invalidate(); issue = "session"; return }
        let visit = generation, intent = UUID()
        detailIntent = intent; detail = nil
        // A newer navigation retires queued reads but never overlaps an active operation.
        wakeIdleWaiters()
        await waitForDetailTurn(visit: visit, intent: intent)
        guard detailIntent == intent, generation == visit, !Task.isCancelled else { return }
        guard accept(visit) else { return }
        busy = true; issue = nil
        defer { finishOperation() }
        do {
            let result = try await coordinator.service.detail(id: id)
            guard detailIntent == intent, accept(visit) else { return }
            detail = result
        } catch {
            guard detailIntent == intent else { return }
            fail(error, visit: visit)
        }
    }

    func apply(titleID: Int64, orderIDs: [Int64]) async -> Bool {
        await perform(.apply) {
            let command = try InvoiceLaunchApply(titleId: titleID, orderIds: orderIDs)
            _ = try await self.coordinator.apply(command)
        }
    }
    func save(_ draft: InvoiceLaunchTitleDraft) async -> Bool {
        await perform(.saveTitle) { _ = try await self.coordinator.saveTitle(draft) }
    }
    func delete(_ id: Int64) async -> Bool {
        await perform(.deleteTitle) { try await self.coordinator.deleteTitle(id: id) }
    }
    func cancel(_ id: Int64) async -> Bool {
        await perform(.cancel) { _ = try await self.coordinator.cancel(id: id) }
    }

    private func perform(_ action: InvoiceLaunchUIAction, operation: () async throws -> Void) async -> Bool {
        guard allows(action) else { return false }
        let visit = generation
        busy = true; issue = nil
        defer { finishOperation() }
        do {
            // The coordinator persists the original request before sending. No UI retry creates a second intent.
            try await operation()
            guard accept(visit) else { return false }
            detail = nil
            do {
                let result = try await coordinator.overview()
                guard accept(visit) else { return false }
                overview = result; unresolved = result.pending != nil
            } catch { fail(error, visit: visit) }
            // The mutation was confirmed even if refreshing the list subsequently failed.
            return generation == visit && isCurrent()
        } catch { fail(error, visit: visit); return false }
    }

    private func accept(_ visit: UUID) -> Bool {
        guard generation == visit, isCurrent() else {
            if generation == visit { invalidate(); issue = "session" }
            return false
        }
        // Cancellation belongs to this view task, not to the retained account
        // presentation. Discard its result without retiring a newer queued detail.
        return !Task.isCancelled
    }
    private func fail(_ error: Error, visit: UUID) {
        guard accept(visit) else { return }
        overview = nil; detail = nil
        do { unresolved = try coordinator.store.load() != nil }
        catch { unresolved = true }
        switch error as? InvoiceLaunchIssue {
        case .staleSession, .unauthorized: invalidate(); issue = "session"
        case .disabled: issue = "unavailable"
        case .outcomeUnknown, .originalReadUnavailable, .pendingConflict: unresolved = true; issue = "unknown"
        case .storageUnavailable: unresolved = true; issue = "storage"
        case .invalid, .rejected: issue = "notSaved"
        default: issue = "loadFailed"
        }
    }
}

func invoiceText(_ key: String) -> Text { Text(LocalizedStringKey(key), tableName: "InvoiceLaunchUI") }
func invoiceAmount(_ value: Decimal, locale: Locale) -> String {
    let formatter = NumberFormatter(); formatter.locale = locale; formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 2; formatter.maximumFractionDigits = 2
    return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "—"
}
func invoiceTime(_ time: InvoiceLaunchTime?, locale: Locale) -> String {
    switch time {
    case .text(let value): return value
    case .epochMilliseconds(let value):
        let formatter = DateFormatter(); formatter.locale = locale
        formatter.dateStyle = .medium; formatter.timeStyle = .short
        return formatter.string(from: Date(timeIntervalSince1970: Double(value) / 1000))
    case nil: return "—"
    }
}

@MainActor struct InvoiceLaunchStateSection: View {
    @ObservedObject var model: InvoiceLaunchPresentation
    var retry: (() async -> Void)? = nil
    var body: some View {
        if model.unresolved {
            Section {
                invoiceText("unknown").accessibilityIdentifier("invoice.pending")
                Button { Task { await model.refresh() } } label: { invoiceText("checkResult") }
                    .disabled(model.busy).accessibilityIdentifier("invoice.recover")
            }
        }
        if let issue = model.issue {
            ContentUnavailableView {
                Label { invoiceText(issue) } icon: { Image(systemName: "exclamationmark.circle") }
            } actions: {
                Button { Task { if let retry { await retry() } else { await model.refresh() } } } label: { invoiceText("retry") }
                    .disabled(model.busy)
            }
        } else if model.busy {
            ProgressView().frame(maxWidth: .infinity).accessibilityLabel(invoiceText("loading"))
        }
    }
}
