import Foundation

/// First-party construction only: reviewed scope, reads, explicit apply grant and legal approval are independent inputs.
@MainActor final class AccountDeregistrationOriginalConfigurationSource {
    private final class WeakCoordinator {
        weak var value: AccountComplianceCoordinator?
        init(_ value: AccountComplianceCoordinator) { self.value = value }
    }
    private var selected: AccountDeregistrationOriginalApproval?
    private var usedIssuances = Set<UUID>()
    private var owners: [WeakCoordinator] = []
    init(approval: AccountDeregistrationOriginalApproval? = nil) throws { try replace(with: approval) }
    func replace(with approval: AccountDeregistrationOriginalApproval?) throws {
        if let approval, usedIssuances.contains(approval.issuanceID) { throw APIError.invalidConfiguration }
        selected = nil; retire(); selected = approval
        if let approval { usedIssuances.insert(approval.issuanceID) }
    }
    /// Revocation immediately clears UI, frozen confirmation and SMS memory; it never erases durable UUIDs.
    func revoke() { selected = nil; retire() }
    private func retire() { owners.forEach { $0.value?.invalidate() }; owners.removeAll { $0.value == nil } }
    func register(_ coordinator: AccountComplianceCoordinator) {
        owners.removeAll { $0.value == nil }
        if !owners.contains(where: { $0.value === coordinator }) { owners.append(.init(coordinator)) }
    }
    func approval(for context: RuntimeDependencyContext) -> AccountDeregistrationOriginalApproval? {
        guard let selected, selected.matches(context) else { return nil }; return selected
    }
}
@MainActor extension AppCompositionRoot {
    func selectedAccountDeregistrationOriginalApproval(_ context: RuntimeDependencyContext) -> AccountDeregistrationOriginalApproval? {
        guard let reviewed, let api = reviewed.regional.apiConfiguration, reviewed.regional.market == context.market,
              api.baseURL.absoluteString.utf8.elementsEqual(context.baseURL.absoluteString.utf8),
              reviewed.storageScope.service.utf8.elementsEqual(context.session.namespace.utf8) else { return nil }
        return reviewed.accountDeregistrationOriginalSource?.approval(for: context)
    }
}
