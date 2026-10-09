import SwiftUI

/// These controls only replace the existing featured pair in a still-current local draft.
@MainActor struct MerchantFeaturedClearControl: View {
    @ObservedObject var model: MerchantOperationsViewModel
    let source: MerchantStoreDecor
    private let baseline: MerchantStoreDecor?
    private let scope: UUID
    private let identity: UUID
    init(model: MerchantOperationsViewModel, source: MerchantStoreDecor) {
        self.model = model; self.source = source
        let owner = model.coordinator
        scope = owner.reader.scope; identity = owner.draftIdentity
        if case .decor(let value) = owner.baseline { baseline = value } else { baseline = nil }
    }
    private var isCurrent: Bool {
        let owner = model.coordinator
        guard let baseline else { return false }
        return owner.isCurrent && !owner.isBusy && !owner.isLocked && owner.confirmation == nil
            && owner.reader.scope == scope && owner.draftIdentity == identity
            && owner.baseline == .decor(baseline) && owner.draft == .decor(source)
    }
    private var isCleared: Bool { source.featuredType == 0 && source.featuredID == nil }
    private var canRestore: Bool {
        guard let baseline else { return false }
        return source.featuredType != baseline.featuredType || source.featuredID != baseline.featuredID
    }
    var body: some View {
        if isCleared {
            Text("merchant.featuredClear.inDraft").font(.footnote).foregroundStyle(.secondary)
                .accessibilityIdentifier("merchant.featuredClear.inDraft")
        } else if source.featuredType != nil || source.featuredID != nil {
            Button("merchant.featuredClear.clear", role: .destructive) { clear() }
                .disabled(!isCurrent).accessibilityIdentifier("merchant.featuredClear.clear")
        }
        if canRestore {
            Button("merchant.featuredClear.restore") { restore() }
                .disabled(!isCurrent).accessibilityIdentifier("merchant.featuredClear.restore")
        }
    }
    @discardableResult func clear() -> Bool {
        guard isCurrent, !isCleared, source.featuredType != nil || source.featuredID != nil else { return false }
        var edited = source; edited.featuredType = 0; edited.featuredID = nil
        model.edit(.decor(edited)); return model.coordinator.draft == .decor(edited)
    }
    @discardableResult func restore() -> Bool {
        guard isCurrent, canRestore, let baseline else { return false }
        var edited = source; edited.featuredType = baseline.featuredType; edited.featuredID = baseline.featuredID
        model.edit(.decor(edited)); return model.coordinator.draft == .decor(edited)
    }
}
