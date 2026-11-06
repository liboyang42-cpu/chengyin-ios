import Foundation

/// Explicit host selection only. Storing a configuration does not issue its endpoint or target grants.
@MainActor final class MerchantMarketingConsentSourceSelection {
    private final class WeakOwner {
        weak var coordinator: AccountComplianceCoordinator?
        init(_ coordinator: AccountComplianceCoordinator) { self.coordinator = coordinator }
    }
    private var selected: MerchantMarketingConsentRuntimeConfiguration?
    private var usedIssuances: Set<UUID> = []
    private var owners: [WeakOwner] = []
    init() {}
    func replace(with configuration: MerchantMarketingConsentRuntimeConfiguration?) throws {
        if let configuration, usedIssuances.contains(configuration.issuanceID) { throw APIError.invalidConfiguration }
        selected = nil
        retire()
        selected = configuration
        if let configuration { usedIssuances.insert(configuration.issuanceID) }
    }
    func revoke() { selected = nil; retire() }
    func approval(for context: RuntimeDependencyContext) -> MerchantMarketingConsentOriginalApproval? {
        selected?.approval(for: context)
    }
    func register(_ coordinator: AccountComplianceCoordinator) {
        owners.removeAll { $0.coordinator == nil }
        if !owners.contains(where: { $0.coordinator === coordinator }) { owners.append(.init(coordinator)) }
    }
    private func retire() {
        owners.forEach { $0.coordinator?.retireMarketingSource() }
        owners.removeAll { $0.coordinator == nil }
    }
}

@MainActor extension AppCompositionRoot {
    func selectedMerchantMarketingConsentApproval(_ context: RuntimeDependencyContext) -> MerchantMarketingConsentOriginalApproval? {
        guard let reviewed, let api = reviewed.regional.apiConfiguration, reviewed.regional.market == context.market,
              api.baseURL.absoluteString.utf8.elementsEqual(context.baseURL.absoluteString.utf8),
              reviewed.storageScope.service.utf8.elementsEqual(context.session.namespace.utf8) else { return nil }
        return merchantMarketingConsentSelection.approval(for: context)
    }
}
