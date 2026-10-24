import SwiftUI
import UIKit
import Combine

/// Owns only the whole editor's Back decision. It cannot publish or clear an operation journal.
@MainActor final class ProjectEditExitController: ObservableObject {
    enum Reason: String { case saveFailed, memoryOnly }
    fileprivate struct Snapshot: Equatable {
        let session: ProjectEditSession?
        let identity: ProjectEditDraftIdentity?
        let incarnation: UUID
        let draftRevision: Int
        let bytes: Data?
        let state: ProjectEditCoordinator.State
        let canEdit: Bool
        let hasRestore: Bool
    }
    fileprivate struct Capture: Equatable { let generation: UUID; let snapshot: Snapshot }
    struct Review: Identifiable {
        let id = UUID()
        let reason: Reason
        fileprivate let capture: Capture
    }
    let model: ProjectEditModel
    private let overlaysOpen: () -> Bool
    private let requiresNativeRoot: Bool
    private weak var root: UIViewController?
    private var visible = false, active = false
    private var generation = UUID()
    private var observation: AnyCancellable?
    @Published private(set) var review: Review?
    @Published private var attachmentRevision = 0
    init(model: ProjectEditModel, overlaysOpen: @escaping () -> Bool = { false }, requiresNativeRoot: Bool = false) {
        self.model = model; self.overlaysOpen = overlaysOpen; self.requiresNativeRoot = requiresNativeRoot
        observation = model.objectWillChange.sink { [weak self] _ in self?.invalidateReview() }
    }
    private var nativeUncovered: Bool {
        guard let root else { return !requiresNativeRoot }
        var next: UIViewController? = root
        while let value = next {
            if value.presentedViewController != nil || value.isBeingDismissed || value.isMovingFromParent { return false }
            next = value.parent
        }
        return root.parent != nil && root.viewIfLoaded?.window != nil
    }
    private var canNavigate: Bool {
        visible && active && nativeUncovered && !overlaysOpen() && model.ownsVisit && !model.busy &&
            model.confirmation == nil && model.coordinator.confirmation == nil && model.coordinator.state != .submitting
    }
    var canRequestBack: Bool { canNavigate && review == nil }
    private func snapshot() -> Snapshot {
        .init(session: model.coordinator.session, identity: model.coordinator.identity,
              incarnation: model.editorIncarnation, draftRevision: model.draftMutationRevision,
              bytes: ProjectEditPendingMaterials.exactData(model.draft), state: model.coordinator.state,
              canEdit: model.canEdit, hasRestore: model.hasRestore)
    }
    private func capture() -> Capture { .init(generation: generation, snapshot: snapshot()) }
    private func current(_ capture: Capture) -> Bool { canNavigate && self.capture() == capture }
    private func current(_ original: Review) -> Bool { review?.id == original.id && current(original.capture) }
    func attach(_ controller: UIViewController) { root = controller; attachmentRevision += 1 }
    func detach(_ controller: UIViewController) { guard root === controller else { return }; root = nil; disappear() }
    func appear(active: Bool) {
        if !visible || self.active != active { invalidateReview() }
        visible = true; self.active = active
    }
    func disappear() { visible = false; active = false; invalidateReview() }
    func sceneChanged(active: Bool) { self.active = visible && active; if !self.active { invalidateReview() } }
    func overlayChanged() { invalidateReview() }
    private func invalidateReview() { generation = UUID(); review = nil }
    func backAction(_ dismiss: @escaping () -> Void) -> () -> Void {
        let original = capture()
        return { [weak self] in guard let self, self.canRequestBack, self.current(original) else { return }; self.inspect(dismiss) }
    }
    private func inspect(_ dismiss: () -> Void) {
        guard canRequestBack else { return }
        // Locked/terminal/restore screens are not editable; leaving never rewrites their durable material.
        guard model.canEdit else { finish(dismiss); return }
        if model.coordinator.session == nil {
            let draft = ProjectEditPendingMaterials.exactData(model.draft)
            let baseline = model.coordinator.snapshot.flatMap { ProjectEditPendingMaterials.exactData($0.draft) }
            if let draft, let baseline, draft == baseline { finish(dismiss) }
            else { review = .init(reason: .memoryOnly, capture: capture()) }
            return
        }
        let before = snapshot()
        let saved = model.saveLocalForExit()
        // Saving may publish a status revision; account, draft bytes and owner must still be identical.
        guard canNavigate, nativeUncovered, snapshot() == before else { return }
        if saved { finish(dismiss) }
        else { review = .init(reason: .saveFailed, capture: capture()) }
    }
    func continueAction(_ original: Review) -> () -> Void {
        { [weak self] in guard let self, self.current(original) else { return }; self.invalidateReview() }
    }
    func leaveAction(_ original: Review, dismiss: @escaping () -> Void) -> () -> Void {
        { [weak self] in guard let self, self.current(original) else { return }; self.finish(dismiss) }
    }
    func retryAction(_ original: Review, dismiss: @escaping () -> Void) -> () -> Void {
        { [weak self] in
            guard let self, original.reason == .saveFailed, self.current(original) else { return }
            self.invalidateReview(); self.inspect(dismiss)
        }
    }
    private func finish(_ dismiss: () -> Void) {
        guard canNavigate else { return }
        model.confirmLocalExit(); disappear(); dismiss()
    }
}

@MainActor struct ProjectEditExitGuard: ViewModifier {
    @StateObject private var owner: ProjectEditExitController
    private let overlaysOpen: () -> Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    init(model: ProjectEditModel, overlaysOpen: @escaping () -> Bool) {
        self.overlaysOpen = overlaysOpen
        _owner = StateObject(wrappedValue: .init(model: model, overlaysOpen: overlaysOpen, requiresNativeRoot: true))
    }
    func body(content: Content) -> some View {
        content.disabled(owner.review != nil).navigationBarBackButtonHidden(true).interactiveDismissDisabled(true)
            .toolbar { ToolbarItem(placement: .topBarLeading) {
                Button(action: owner.backAction { dismiss() }) {
                    Label { Text("back", tableName: "ProjectEditExitGuard") } icon: { Image(systemName: "chevron.backward") }
                }.disabled(!owner.canRequestBack).accessibilityIdentifier("projectEditExit.back")
            } }
            .background { ProjectEditExitRootAnchor(owner: owner).frame(width: 0, height: 0) }
            .safeAreaInset(edge: .bottom) {
                if let original = owner.review {
                    ProjectEditExitReviewBar(owner: owner, original: original, leave: { dismiss() }).id(original.id)
                }
            }
            .onAppear { owner.appear(active: scenePhase == .active) }
            .onDisappear { owner.disappear() }
            .onChange(of: scenePhase) { _, phase in owner.sceneChanged(active: phase == .active) }
            .onChange(of: overlaysOpen()) { _, _ in owner.overlayChanged() }
    }
}

/// An in-page confirmation keeps repeated failed retries visible without modal re-presentation races.
@MainActor private struct ProjectEditExitReviewBar: View {
    @ObservedObject var owner: ProjectEditExitController
    let original: ProjectEditExitController.Review
    let leave: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("title", tableName: "ProjectEditExitGuard").font(.headline)
            Text(LocalizedStringKey(original.reason.rawValue), tableName: "ProjectEditExitGuard")
                .accessibilityIdentifier("projectEditExit.reason")
            HStack {
                Button(action: owner.continueAction(original)) { Text("continue", tableName: "ProjectEditExitGuard") }
                    .accessibilityIdentifier("projectEditExit.continue")
                if original.reason == .saveFailed {
                    Button(action: owner.retryAction(original, dismiss: leave)) { Text("retry", tableName: "ProjectEditExitGuard") }
                        .accessibilityIdentifier("projectEditExit.retry")
                }
                Button(role: .destructive, action: owner.leaveAction(original, dismiss: leave)) { Text("leave", tableName: "ProjectEditExitGuard") }
                    .accessibilityIdentifier("projectEditExit.leave")
            }.buttonStyle(.bordered)
        }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.regularMaterial)
    }
}

/// A native container check also fences sheets owned by nested editor sections.
@MainActor private struct ProjectEditExitRootAnchor: UIViewControllerRepresentable {
    let owner: ProjectEditExitController
    func makeUIViewController(context: Context) -> ProjectEditExitRootController { .init(owner: owner) }
    func updateUIViewController(_ controller: ProjectEditExitRootController, context: Context) {}
    static func dismantleUIViewController(_ controller: ProjectEditExitRootController, coordinator: ()) { controller.owner?.detach(controller) }
}
@MainActor private final class ProjectEditExitRootController: UIViewController {
    weak var owner: ProjectEditExitController?
    init(owner: ProjectEditExitController) { self.owner = owner; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { return nil }
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); owner?.attach(self) }
}
