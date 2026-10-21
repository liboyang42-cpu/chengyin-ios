import Foundation

/// Purchased-version upgrade draft loop. Trusted comparison in, explicit confirm, one local file, restore on reopen.
/// Does not change the purchased version, a published release, or a running session, and does not contact the network.
@MainActor public final class WorkshopUpgradeFlow {
    private let store: WorkshopUpgradeDraftStore
    private var generation: UUID?
    private var openLicenseId: String?
    public init(store: WorkshopUpgradeDraftStore) { self.store = store }
    public func begin(item: WorkshopPurchasedItem) throws -> UUID {
        try store.checkLease()
        guard item.status != .revoked else { throw WorkshopUpgradeDraftIssue.revoked }
        let id = UUID()
        generation = id
        openLicenseId = item.licenseId
        return id
    }
    public func cancel() {
        generation = nil
        openLicenseId = nil
    }
    public func commit(item: WorkshopPurchasedItem, presentation: WorkshopModUpgradePresentation, confirmedByBuyer: Bool, requestId: String, generation: UUID) throws -> WorkshopUpgradeDraftReceipt {
        guard self.generation == generation, openLicenseId == item.licenseId else { throw WorkshopUpgradeDraftIssue.stalePresentation }
        guard item.status != .revoked else { throw WorkshopUpgradeDraftIssue.revoked }
        let pinnedVersion = item.purchasedVersionId
        let pinnedHash = item.contentHash
        let term = try WorkshopPurchasedUseTerm(item)
        let request = try WorkshopUpgradeDraftRequest(term: term, preview: presentation.preview, confirmedByBuyer: confirmedByBuyer, requestId: requestId)
        let receipt = try store.save(item: item, presentation: presentation, request: request)
        guard receipt.persisted, receipt.licenseId == item.licenseId, receipt.moduleId == item.moduleId, receipt.fromVersionId == pinnedVersion, receipt.fromContentHash == pinnedHash, item.purchasedVersionId == pinnedVersion, item.contentHash == pinnedHash else { throw WorkshopUpgradeDraftIssue.saveFailed }
        return receipt
    }
    public func restore(item: WorkshopPurchasedItem) throws -> WorkshopUpgradeDraftReceipt? {
        guard let record = try store.load(item: item) else { return nil }
        let receipt = record.makeReceipt()
        guard receipt.persisted, receipt.fromVersionId == item.purchasedVersionId, receipt.fromContentHash == item.contentHash else { return nil }
        return receipt
    }
}
