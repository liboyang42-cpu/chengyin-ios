import Foundation
import CryptoKit

/// A foreground-only discard review. Its fingerprints never persist or transmit
/// knowledge text, and invalid fields need not pass save validation to be protected.
@MainActor struct MerchantNPCKnowledgeDismissal {
    enum Decision: Equatable { case close, confirm, blocked }
    struct Review: Identifiable, Equatable {
        let id = UUID()
        fileprivate let owner: ObjectIdentifier
        fileprivate let scope: MerchantNPCKnowledgeDraftCoordinator.Scope
        fileprivate let revision: Int
        fileprivate let draftFingerprint: Data
        fileprivate let savedFingerprint: Data
    }
    private(set) var review: Review?

    static func requiresConfirmation(_ model: MerchantNPCKnowledgeDraftModel) -> Bool {
        guard model.coordinator.canEdit else { return false }
        return model.coordinator.isDirty ||
            fingerprint(model.coordinator.draft) != fingerprint(model.coordinator.savedDraft ?? .init())
    }
    static func blocksInteractiveDismissal(_ model: MerchantNPCKnowledgeDraftModel) -> Bool {
        guard model.coordinator.isCurrent else { return false }
        return model.coordinator.phase == .saving || requiresConfirmation(model)
    }
    mutating func prepare(_ model: MerchantNPCKnowledgeDraftModel, isActive: Bool) -> Decision {
        review = nil
        guard isActive else { return .blocked }
        // Revocation/unavailable contexts must be allowed to close immediately.
        guard model.coordinator.isCurrent else { return .close }
        guard model.coordinator.phase != .saving else { return .blocked }
        guard Self.requiresConfirmation(model), let scope = model.coordinator.scope else { return .close }
        review = .init(owner: ObjectIdentifier(model), scope: scope, revision: model.revision,
                       draftFingerprint: Self.fingerprint(model.coordinator.draft),
                       savedFingerprint: Self.fingerprint(model.coordinator.savedDraft ?? .init()))
        return .confirm
    }
    mutating func keepEditing() { review = nil }
    mutating func discard(_ captured: Review, model: MerchantNPCKnowledgeDraftModel, isActive: Bool) -> Bool {
        let pending = review; review = nil
        guard isActive, pending == captured, captured.owner == ObjectIdentifier(model),
              captured.scope == model.coordinator.scope, captured.revision == model.revision,
              model.coordinator.canEdit, Self.requiresConfirmation(model),
              captured.draftFingerprint == Self.fingerprint(model.coordinator.draft),
              captured.savedFingerprint == Self.fingerprint(model.coordinator.savedDraft ?? .init()) else { return false }
        model.cancel()
        return true
    }

    /// Length-delimited UTF-8 fields preserve canonical Unicode differences, row
    /// identity/order and invalid/empty input. No validated JSON or server hash.
    static func fingerprint(_ draft: MerchantNPCKnowledgeDraft) -> Data {
        var hash = SHA256()
        func append(_ raw: String) {
            let bytes = Data(raw.utf8)
            hash.update(data: Data("\(bytes.count):".utf8)); hash.update(data: bytes)
        }
        append("products"); append(String(draft.products.count))
        for row in draft.products { append(row.id.uuidString); append(row.name); append(row.priceMinor); append(row.currency) }
        append("hours"); append(String(draft.hours.count))
        for row in draft.hours { append(row.id.uuidString); append(String(row.day)); append(row.opens); append(row.closes); append(row.timeZone) }
        append("promotions"); append(String(draft.promotions.count))
        for row in draft.promotions { append(row.id.uuidString); append(row.title); append(row.startsAt); append(row.endsAt) }
        append("faq"); append(String(draft.faq.count))
        for row in draft.faq { append(row.id.uuidString); append(row.question); append(row.answer) }
        append("neverSay"); append(String(draft.neverSay.count))
        for row in draft.neverSay { append(row.id.uuidString); append(row.text) }
        return Data(hash.finalize())
    }
}
