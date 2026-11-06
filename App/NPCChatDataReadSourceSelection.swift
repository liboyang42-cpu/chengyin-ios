import Foundation
import Observation

/// Select an externally supplied read lease. This owner never issues one or enables chat, consent or deletion.
@MainActor @Observable final class NPCChatDataReadSourceSelection {
    private final class WeakClient {
        weak var value: NPCChatDataReader?
        init(_ value: NPCChatDataReader) { self.value = value }
    }
    private var selected: NPCChatDataReadApproval?
    private var used: Set<UUID> = []
    private var clients: [WeakClient] = []
    private var expirationTask: Task<Void, Never>?
    private(set) var revision = UUID()
    init() {}
    deinit { expirationTask?.cancel() }
    func replace(with value: NPCChatDataReadApproval?) throws {
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
    func approval(for context: RuntimeDependencyContext) -> NPCChatDataReadApproval? {
        guard let selected, selected.matches(context) else { return nil }; return selected
    }
    func register(_ client: NPCChatDataReader) {
        clients.removeAll { $0.value == nil }; clients.append(.init(client))
    }
}
@MainActor extension AppCompositionRoot {
    func selectedNPCChatDataReadApproval(_ context: RuntimeDependencyContext) -> NPCChatDataReadApproval? {
        guard let reviewed, let api = reviewed.regional.apiConfiguration, reviewed.regional.market == context.market,
              api.baseURL.absoluteString.utf8.elementsEqual(context.baseURL.absoluteString.utf8),
              reviewed.storageScope.service.utf8.elementsEqual(context.session.namespace.utf8) else { return nil }
        return npcChatDataReadSelection.approval(for: context)
    }
}
