import SwiftUI

@MainActor final class MerchantStoreFieldSession: ObservableObject, Identifiable {
    let id = UUID()
    private weak var document: MerchantOperationsViewModel?
    private let scope: UUID, identity: UUID
    private let revision: Int
    private let original: MerchantOperationsDraft, baseline: MerchantOperationsDraft
    private let presentationIsCurrent: () -> Bool
    @Published private(set) var buffer: MerchantStoreFieldDraft
    @Published private(set) var asksDiscard = false
    @Published private(set) var consumed = false
    init?(document: MerchantOperationsViewModel, field: MerchantStoreTextField, presentationIsCurrent: @escaping () -> Bool = { true }) {
        let c = document.coordinator
        guard Self.canOpen(document, field: field), let original = c.draft, let baseline = c.baseline,
              let buffer = MerchantStoreFieldDraft(field: field, source: original) else { return nil }
        self.document = document; scope = c.reader.scope; identity = c.draftIdentity; revision = document.revision
        self.original = original; self.baseline = baseline; self.buffer = buffer; self.presentationIsCurrent = presentationIsCurrent
    }
    static func canOpen(_ document: MerchantOperationsViewModel, field: MerchantStoreTextField) -> Bool {
        let c = document.coordinator
        guard c.reader.isConfigured, c.reader.isAuthenticated, c.isCurrent, !c.isBusy, !c.isLocked, c.confirmation == nil,
              let draft = c.draft, let baseline = c.baseline, draft.destination == c.destination,
              baseline.destination == c.destination, field.value(in: draft) != nil, field.value(in: baseline) != nil else { return false }
        return true
    }
    var isCurrent: Bool {
        guard !consumed, presentationIsCurrent(), let document, document.revision == revision,
              Self.canOpen(document, field: buffer.field) else { return false }
        let c = document.coordinator
        guard c.reader.scope == scope, c.draftIdentity == identity, let draft = c.draft, let baseline = c.baseline else { return false }
        return MerchantStoreFieldDraft.sameDraft(draft, original) && MerchantStoreFieldDraft.sameDraft(baseline, self.baseline)
    }
    var canApply: Bool { isCurrent && !asksDiscard && buffer.issueKey == nil }
    @discardableResult func update(_ raw: String) -> Bool {
        guard isCurrent, !asksDiscard else { return false }; buffer.value = raw; return true
    }
    @discardableResult func requestClose() -> Bool {
        guard isCurrent else { cancel(); return true }
        if buffer.isDirty { asksDiscard = true; return false }; cancel(); return true
    }
    func keepEditing() { guard isCurrent, asksDiscard else { return }; asksDiscard = false }
    func cancel() { consumed = true; asksDiscard = false; buffer.value = "" }
    @discardableResult func discard() -> Bool {
        guard isCurrent, asksDiscard else { return false }; cancel(); return true
    }
    @discardableResult func apply() -> Bool {
        guard canApply, let document, let next = try? buffer.applying(to: original) else { return false }
        let changed = buffer.isDirty; cancel()
        if changed { document.edit(next) }
        guard let current = document.coordinator.draft else { return false }
        return MerchantStoreFieldDraft.sameDraft(current, next)
    }
}

@MainActor final class MerchantStoreFieldPresentation: ObservableObject {
    @Published private(set) var session: MerchantStoreFieldSession?
    @Published private(set) var generation: UInt64 = 0
    private(set) var active = false
    private(set) var isVisible = false
    func viewAppeared(sceneIsActive: Bool) {
        isVisible = true
        sceneChanged(isActive: sceneIsActive)
    }
    func viewDisappeared() {
        isVisible = false
        deactivate()
    }
    func sceneChanged(isActive: Bool) {
        if isVisible && isActive { activate() } else { deactivate() }
    }
    func activate() { guard !active else { return }; active = true; generation &+= 1 }
    func invalidate() { generation &+= 1; session?.cancel(); session = nil }
    func deactivate() { active = false; invalidate() }
    func close(_ id: UUID) { guard session?.id == id else { return }; invalidate() }
    func open(permit: UInt64, document: MerchantOperationsViewModel, field: MerchantStoreTextField) {
        guard active, generation == permit, session == nil else { return }
        let captured = generation
        session = .init(document: document, field: field, presentationIsCurrent: { [weak self] in
            guard let self else { return false }; return self.active && self.generation == captured
        })
    }
    func presentationBinding() -> Binding<MerchantStoreFieldSession?> {
        let shownID = session?.id
        return Binding(get: { [weak self] in
            guard let self, self.session?.id == shownID else { return nil }; return self.session
        }, set: { [weak self] value in if value == nil, let shownID { self?.close(shownID) } })
    }
}
