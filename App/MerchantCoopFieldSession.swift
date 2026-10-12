import SwiftUI

@MainActor final class MerchantCoopFieldSession: ObservableObject, Identifiable {
    let id = UUID()
    private weak var document: MerchantOperationsViewModel?
    private let scope: UUID
    private let identity: UUID
    private let revision: Int
    private let original: MerchantCoopSettings
    private let baseline: MerchantCoopSettings
    @Published private(set) var buffer: MerchantCoopFieldDraft
    @Published private(set) var asksDiscard = false
    @Published private(set) var consumed = false
    init?(document: MerchantOperationsViewModel, field: MerchantCoopField) {
        let c = document.coordinator
        guard Self.canOpen(document), case .cooperation(let value) = c.draft,
              case .cooperation(let baseline) = c.baseline else { return nil }
        self.document = document; scope = c.reader.scope; identity = c.draftIdentity
        revision = document.revision; original = value; self.baseline = baseline
        buffer = .init(field: field, settings: value)
    }
    static func canOpen(_ document: MerchantOperationsViewModel) -> Bool {
        let c = document.coordinator
        guard c.destination == .cooperation, c.reader.isConfigured, c.reader.isAuthenticated,
              c.isCurrent, !c.isBusy, !c.isLocked, c.confirmation == nil,
              case .cooperation = c.draft, case .cooperation = c.baseline else { return false }
        return true
    }
    var isCurrent: Bool {
        guard !consumed, let document, Self.canOpen(document), document.revision == revision else { return false }
        let c = document.coordinator
        guard c.reader.scope == scope, c.draftIdentity == identity,
              case .cooperation(let value) = c.draft, case .cooperation(let base) = c.baseline else { return false }
        return MerchantCoopFieldDraft.sameValues(value, original) && MerchantCoopFieldDraft.sameValues(base, baseline)
    }
    var canApply: Bool { isCurrent && !asksDiscard && buffer.issueKey == nil }
    @discardableResult func update(_ text: String) -> Bool {
        guard isCurrent, !asksDiscard else { return false }
        buffer.value = text; return true
    }
    /// true means this unchanged field may close; false keeps the dirty input for a decision.
    @discardableResult func requestClose() -> Bool {
        guard isCurrent else { cancel(); return true }
        if buffer.isDirty { asksDiscard = true; return false }
        cancel(); return true
    }
    func keepEditing() { guard isCurrent, asksDiscard else { return }; asksDiscard = false }
    func cancel() { consumed = true; asksDiscard = false; buffer.value = "" }
    @discardableResult func discard() -> Bool {
        guard isCurrent, asksDiscard else { return false }
        cancel(); return true
    }
    @discardableResult func apply() -> Bool {
        guard canApply, let document, let next = try? buffer.applying(to: original) else { return false }
        let changed = buffer.isDirty
        // Consume before notifying the owner; old Apply/Close/Discard cannot run twice.
        cancel()
        if changed { document.edit(.cooperation(next)) }
        guard case .cooperation(let applied) = document.coordinator.draft else { return false }
        return MerchantCoopFieldDraft.sameValues(applied, next)
    }
}
