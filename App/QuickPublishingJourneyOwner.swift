import SwiftUI
import UIKit

/// One normal quick-draft journey; child results belong to a concrete original draft.
@MainActor final class QuickPublishingJourneyOwner: ObservableObject {
    fileprivate struct Source: Equatable {
        let account: PublishingSession?
        let context: UUID
        let draftID: UUID
        let revision: UInt64
        let bytes: Data?
    }
    enum Kind: Equatable { case ai, place(UUID) }
    struct Presentation: Identifiable {
        let id = UUID()
        let kind: Kind
        let product: ProjectEditProduct
        let client: (any PublishingAIDraftServing)?
        fileprivate let source: Source
    }
    @Published private(set) var draft = QuickPublishDraft()
    @Published private(set) var draftID = UUID()
    @Published private(set) var presentation: Presentation?
    @Published private(set) var problem = false
    @Published private(set) var storageMessage = ""
    @Published private var revision: UInt64 = 0
    private var account: PublishingSession?
    private var context = UUID()
    @Published private var visible = false
    @Published private var active = false
    @Published private var covered = false
    private var wasBound = false
    private func source() -> Source {
        .init(account: account, context: context, draftID: draftID, revision: revision,
              bytes: ProjectEditPendingMaterials.exactData(draft))
    }
    private var live: Bool { active && (visible || covered) && wasBound }
    var canEdit: Bool { live && visible && presentation == nil }
    private func current(_ original: Source) -> Bool { live && original.bytes != nil && original == source() }
    func bind(account: PublishingSession?) {
        guard !wasBound || self.account != account else { return }
        wasBound = true; self.account = account; context = UUID(); revision &+= 1
        presentation = nil; draft = .init(); draftID = UUID(); problem = false; storageMessage = ""
    }
    func appear(active: Bool) { visible = true; covered = false; self.active = active; if !active { retireCallbacks() } }
    func parentAppeared() { visible = true; covered = false }
    func parentDisappeared(departing: Bool, coveredByPresentation: Bool) {
        guard !departing, coveredByPresentation, presentation != nil, active else { disappear(); return }
        visible = false; covered = true
    }
    func disappear() { visible = false; covered = false; active = false; retireCallbacks() }
    func setActive(_ value: Bool) { active = value; if !value { retireCallbacks() } }
    private func retireCallbacks() { context = UUID(); revision &+= 1; presentation = nil; covered = false }
    private func replace(_ value: QuickPublishDraft, identity: UUID? = nil) {
        retireCallbacks(); draft = value; draftID = identity ?? UUID(); problem = false; storageMessage = ""
    }
    func draftBinding() -> Binding<QuickPublishDraft> {
        let capturedContext = context, capturedDraft = draftID
        return .init(get: { [weak self] in
            guard let self, self.context == capturedContext, self.draftID == capturedDraft else { return .init() }; return self.draft
        }, set: { [weak self] value in
            guard let self, self.canEdit, self.context == capturedContext, self.draftID == capturedDraft else { return }
            self.draft = value; self.revision &+= 1; self.problem = false
        })
    }
    func addNodeAction() -> () -> Void {
        let original = source()
        return { [weak self] in guard let self, self.canEdit, self.current(original) else { return }
            self.draft.nodes.append(.init()); self.revision &+= 1; self.problem = false
        }
    }
    func removeNodeAction(_ id: UUID) -> () -> Void {
        let original = source()
        return { [weak self] in guard let self, self.canEdit, self.current(original), self.draft.nodes.filter({ $0.id == id }).count == 1 else { return }
            self.draft.nodes.removeAll { $0.id == id }; self.revision &+= 1; self.problem = false
        }
    }
    func openAIAction(makeClient: (() -> any PublishingAIDraftServing)?) -> () -> Void {
        let original = source()
        return { [weak self] in guard let self, self.canEdit, self.current(original) else { return }
            let client = makeClient?()
            self.presentation = .init(kind: .ai, product: self.draft.product,
                                      client: client?.session == self.account ? client : nil, source: original)
        }
    }
    func openPlaceAction(_ id: UUID) -> () -> Void {
        let original = source()
        return { [weak self] in guard let self, self.canEdit, self.current(original), self.draft.nodes.filter({ $0.id == id }).count == 1 else { return }
            self.presentation = .init(kind: .place(id), product: self.draft.product, client: nil, source: original)
        }
    }
    func isCurrent(_ original: Presentation) -> Bool { presentation?.id == original.id && current(original.source) }
    func presentationBinding(_ original: Presentation) -> Binding<Presentation?> {
        .init(get: { [weak self] in self?.isCurrent(original) == true ? original : nil }, set: { [weak self] value in
            if value == nil { self?.cancel(original) }
        })
    }
    func cancel(_ original: Presentation) {
        guard presentation?.id == original.id else { return }; presentation = nil; revision &+= 1
    }
    @discardableResult func adopt(_ value: QuickPublishDraft, from original: Presentation) -> Bool {
        guard original.kind == .ai, isCurrent(original), let account = original.source.account,
              original.client?.session == account, value.product == original.product,
              !value.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !value.nodes.isEmpty, value.nodes.count <= 3,
              Set(value.nodes.map(\.id)).count == value.nodes.count,
              value.nodes.allSatisfy({ $0.confirmedPlace == nil && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { return false }
        replace(value); return true
    }
    @discardableResult func confirm(_ place: PublishingPlace, from original: Presentation) -> Bool {
        guard case .place(let id) = original.kind, isCurrent(original),
              draft.nodes.filter({ $0.id == id }).count == 1,
              let index = draft.nodes.firstIndex(where: { $0.id == id }) else { return false }
        presentation = nil; draft.nodes[index].confirmedPlace = place; revision &+= 1; problem = false; return true
    }
    func saveAction(store: PublishingDraftStore?) -> () -> Void {
        let original = source()
        return { [weak self] in
            guard let self, self.canEdit, self.current(original), let account = self.account, let store else { return }
            do { try store.saveActive(PublishingLocalDraft(session: account, identity: self.draftID, quick: self.draft), session: account)
                guard self.current(original) else { return }; self.storageMessage = "publishModes.savedLocal"
            } catch { guard self.current(original) else { return }; self.storageMessage = "publishModes.storageFailed" }
        }
    }
    func restoreAction(store: PublishingDraftStore?) -> () -> Void {
        let original = source()
        return { [weak self] in
            guard let self, self.canEdit, self.current(original), let account = self.account, let store else { return }
            do {
                let saved = try store.loadActive(activity: false, session: account)
                guard self.current(original) else { return }
                if let saved, let quick = saved.quick { self.replace(quick, identity: saved.identity); self.storageMessage = "publishModes.restoredLocal" }
                else { self.storageMessage = "publishModes.noSavedLocal" }
            } catch { guard self.current(original) else { return }; self.storageMessage = "publishModes.storageFailed" }
        }
    }
    func handoffAction(_ open: @escaping (ProjectEditDraft) -> Void) -> () -> Void {
        let original = source()
        return { [weak self] in
            guard let self, self.canEdit, self.current(original) else { return }
            do {
                let value = try self.draft.professionalSeed()
                guard self.current(original) else { return }
                self.retireCallbacks(); self.problem = false; open(value)
            } catch { self.problem = true }
        }
    }
}

/// A concrete modal owns its original node or AI draft; no completion reads a global selection.
@MainActor struct QuickPublishingJourneyPresenter: View {
    @ObservedObject var owner: QuickPublishingJourneyOwner
    let original: QuickPublishingJourneyOwner.Presentation
    let placeSearch: (any PublishingPlaceSearching)?
    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .sheet(item: owner.presentationBinding(original)) { shown in
                if owner.isCurrent(shown) {
                    switch shown.kind {
                    case .ai:
                        PublishingAIDraftSheet(client: shown.client, product: shown.product) { value in _ = owner.adopt(value, from: shown) }
                    case .place:
                        PublishingPlacePicker(provider: placeSearch) { value in _ = owner.confirm(value, from: shown) }
                    }
                }
            }
    }
}

@MainActor struct QuickPublishingJourneyLifetime: UIViewControllerRepresentable {
    let owner: QuickPublishingJourneyOwner
    func makeUIViewController(context: Context) -> QuickPublishingJourneyLifetimeController { .init(owner: owner) }
    func updateUIViewController(_ controller: QuickPublishingJourneyLifetimeController, context: Context) {}
    static func dismantleUIViewController(_ controller: QuickPublishingJourneyLifetimeController, coordinator: ()) { controller.owner?.disappear() }
}
@MainActor final class QuickPublishingJourneyLifetimeController: UIViewController {
    weak var owner: QuickPublishingJourneyOwner?
    private var departing = false
    init(owner: QuickPublishingJourneyOwner) { self.owner = owner; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { return nil }
    private var ancestry: [UIViewController] {
        var result: [UIViewController] = [], next: UIViewController? = self
        while let value = next { result.append(value); next = value.parent }; return result
    }
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); departing = false; owner?.parentAppeared() }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); departing = ancestry.contains { $0.isMovingFromParent || $0.isBeingDismissed } }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated); let source = ancestry
        owner?.parentDisappeared(departing: departing || source.contains { $0.isMovingFromParent || $0.isBeingDismissed } || parent == nil,
                                 coveredByPresentation: source.contains { $0.presentedViewController != nil })
    }
}
