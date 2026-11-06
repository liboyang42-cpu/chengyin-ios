import Foundation
import Observation

@MainActor struct MemberIdentityAvatarAccess {
    let sourceRevision: () -> UUID?
    let makeReader: () -> MemberIdentityAvatarReader?
}
/// No issuer or origin defaults. Reinstallation cannot resurrect a spent issuance.
@MainActor @Observable final class MemberIdentityAvatarSourceSelection {
    private var selected: MemberIdentityAvatarApproval?
    private var used: Set<UUID> = []
    private var timer: Task<Void, Never>?
    deinit { timer?.cancel() }
    func replace(with value: MemberIdentityAvatarApproval?) throws {
        if let value {
            guard !used.contains(value.revision), value.matches(value.context) else { throw APIError.invalidConfiguration }
        }
        revoke(); selected = value
        guard let value else { return }; used.insert(value.revision)
        let issuance = value.revision, deadline = value.clientDeadline
        timer = Task { [weak self] in
            do { try await ContinuousClock().sleep(until: deadline) } catch { return }
            guard !Task.isCancelled, self?.selected?.revision == issuance else { return }; self?.revoke()
        }
    }
    func revoke() { let value = selected; selected = nil; timer?.cancel(); timer = nil; value?.revoke() }
    func approval(for context: RuntimeDependencyContext) -> MemberIdentityAvatarApproval? {
        guard let value = selected, value.matches(context) else { return nil }; return value
    }
}
@MainActor extension AppCompositionRoot {
    func selectedMemberIdentityAvatarApproval(_ context: RuntimeDependencyContext) -> MemberIdentityAvatarApproval? {
        guard let reviewed, let api = reviewed.regional.apiConfiguration, reviewed.regional.market == context.market,
              api.baseURL.absoluteString.utf8.elementsEqual(context.baseURL.absoluteString.utf8),
              reviewed.storageScope.service.utf8.elementsEqual(context.session.namespace.utf8) else { return nil }
        return memberIdentityAvatarSelection.approval(for: context)
    }
}
@MainActor final class MemberIdentityAvatarLifetime {
    private final class WeakClient {
        weak var value: MemberIdentityAvatarReader?
        init(_ value: MemberIdentityAvatarReader) { self.value = value }
    }
    private var clients: [WeakClient] = []
    func register(_ reader: MemberIdentityAvatarReader) { clients.removeAll { $0.value == nil }; clients.append(.init(reader)) }
    func retireAll() { let values = clients; clients.removeAll(); values.forEach { $0.value?.retire() } }
}
