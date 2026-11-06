import Foundation
import Observation

/// Select an externally supplied read lease. This owner never issues one or enables a ticket write or attachment.
@MainActor @Observable final class SupportTicketReadSourceSelection {
    private final class WeakClient {
        weak var value: SupportTicketReadReader?
        init(_ value: SupportTicketReadReader) { self.value = value }
    }
    private var selected: SupportTicketReadApproval?
    private var used: Set<UUID> = []
    private var clients: [WeakClient] = []
    private var expirationTask: Task<Void, Never>?
    private(set) var revision = UUID()
    init() {}
    deinit { expirationTask?.cancel() }
    func replace(with value: SupportTicketReadApproval?) throws {
        if let value {
            guard !used.contains(value.revision), value.matches(value.context) else { throw APIError.invalidConfiguration }
        }
        revoke(); selected = value
        guard let value else { return }; used.insert(value.revision)
        let issuance = value.revision, deadline = value.expiresAt
        expirationTask = Task { [weak self] in
            while !Task.isCancelled {
                let remaining = deadline.timeIntervalSinceNow
                if remaining <= 0 {
                    if self?.selected?.revision == issuance { self?.revoke() }
                    return
                }
                do { try await Task.sleep(nanoseconds: UInt64(min(remaining, 3600) * 1_000_000_000)) } catch { return }
                guard self?.selected?.revision == issuance else { return }
            }
        }
    }
    func revoke() {
        selected = nil; expirationTask?.cancel(); expirationTask = nil
        clients.forEach { $0.value?.retire() }; clients.removeAll(); revision = UUID()
    }
    func approval(for context: RuntimeDependencyContext) -> SupportTicketReadApproval? {
        guard let selected, selected.matches(context) else { return nil }; return selected
    }
    func register(_ client: SupportTicketReadReader) {
        clients.removeAll { $0.value == nil }; clients.append(.init(client))
    }
}
@MainActor extension AppCompositionRoot {
    func selectedSupportTicketReadApproval(_ context: RuntimeDependencyContext) -> SupportTicketReadApproval? {
        guard let reviewed, let api = reviewed.regional.apiConfiguration, reviewed.regional.market == context.market,
              api.baseURL.absoluteString.utf8.elementsEqual(context.baseURL.absoluteString.utf8),
              reviewed.storageScope.service.utf8.elementsEqual(context.session.namespace.utf8) else { return nil }
        return supportTicketReadSelection.approval(for: context)
    }
}
