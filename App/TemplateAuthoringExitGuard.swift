import SwiftUI
import Combine

@MainActor final class TemplateAuthoringExitController: ObservableObject {
    fileprivate struct Capture: Equatable {
        let generation: UUID
        let owner: TemplateAuthoringSession?
        let identity: TemplateAuthoringIdentity
        let metadata: UUID
        let media: UUID
        let draft: Data?
        let state: TemplateAuthoringCoordinator.State
        let restore: TemplateAuthoringRestore
    }
    struct Review: Identifiable {
        let id = UUID()
        let status: TemplateAuthoringExitDecision.Status
        fileprivate let capture: Capture
    }
    private let model: TemplateAuthoringModel
    private let overlaysOpen: () -> Bool
    private var generation = UUID()
    private var active = false
    private var observation: AnyCancellable?
    @Published private(set) var review: Review?
    init(model: TemplateAuthoringModel, overlaysOpen: @escaping () -> Bool = { false }) {
        self.model = model; self.overlaysOpen = overlaysOpen
        observation = model.objectWillChange.sink { [weak self] _ in
            guard let self else { return }; self.generation = UUID(); self.review = nil
        }
    }
    private var canNavigate: Bool { !overlaysOpen() && !model.busy && model.review == nil && model.coordinator.review == nil && model.coordinator.state != .submitting }
    var canRequestBack: Bool { active && canNavigate && review == nil }
    private func capture() -> Capture {
        .init(generation: generation, owner: model.coordinator.session, identity: model.coordinator.identity,
              metadata: model.metadataGeneration, media: model.mediaReviewGeneration,
              draft: TemplateAuthoringExitDecision.snapshot(model.draft), state: model.coordinator.state, restore: model.coordinator.restore)
    }
    private func current(_ original: Capture) -> Bool { active && canNavigate && capture() == original }
    private func current(_ original: Review) -> Bool { review?.id == original.id && current(original.capture) }
    func activate() { generation = UUID(); review = nil; active = true }
    func retire() { generation = UUID(); review = nil; active = false }
    func overlayChanged() { generation = UUID(); review = nil }
    func backAction(_ dismiss: @escaping () -> Void) -> () -> Void {
        let original = capture()
        return { [weak self] in guard let self, self.current(original), self.review == nil else { return }; self.inspect(dismiss) }
    }
    private func inspect(_ dismiss: @escaping () -> Void) {
        guard active, canNavigate else { return }
        // Restore/terminal/no-session screens cannot edit; retain their existing ability to leave.
        guard model.canEdit else { finish(dismiss); return }
        let original = capture(), checkpoint = model.coordinator.localCheckpointForExit()
        guard current(original) else { return }
        let decision = TemplateAuthoringExitDecision(draft: model.draft, checkpoint: checkpoint)
        if decision.status == .clean { finish(dismiss) }
        else { generation = UUID(); review = .init(status: decision.status, capture: capture()) }
    }
    func leaveAction(_ original: Review, dismiss: @escaping () -> Void) -> () -> Void {
        { [weak self] in guard let self, self.current(original) else { return }; self.finish(dismiss) }
    }
    func cancelAction(_ original: Review) -> () -> Void {
        { [weak self] in guard let self, self.current(original) else { return }; self.generation = UUID(); self.review = nil }
    }
    func retryAction(_ original: Review, dismiss: @escaping () -> Void) -> () -> Void {
        { [weak self] in
            guard let self, self.current(original), original.status == .unverified else { return }
            self.generation = UUID(); self.review = nil; self.inspect(dismiss)
        }
    }
    func presentationBinding() -> Binding<Bool> {
        let original = review
        return .init(get: { [weak self] in self?.review != nil }, set: { [weak self] shown in
            guard !shown, let self, let original else { return }; self.cancelAction(original)()
        })
    }
    private func finish(_ dismiss: () -> Void) { retire(); dismiss() }
}

/// Owns only the editor's normal Back route; existing preview/media/review sheets stay above it.
@MainActor struct TemplateAuthoringExitGuard: ViewModifier {
    @StateObject private var controller: TemplateAuthoringExitController
    private let overlaysOpen: () -> Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    init(model: TemplateAuthoringModel, overlaysOpen: @escaping () -> Bool) {
        self.overlaysOpen = overlaysOpen
        _controller = StateObject(wrappedValue: .init(model: model, overlaysOpen: overlaysOpen))
    }
    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(true)
            .interactiveDismissDisabled(true)
            .toolbar { ToolbarItem(placement: .topBarLeading) {
                Button(action: controller.backAction { dismiss() }) {
                    Label { Text("templateAuthorExit.back", tableName: "CreatorExitGuard") } icon: { Image(systemName: "chevron.backward") }
                }
                    .disabled(!controller.canRequestBack).accessibilityIdentifier("templateAuthorExit.back")
            } }
            .confirmationDialog(Text("templateAuthorExit.title", tableName: "CreatorExitGuard"), isPresented: controller.presentationBinding(), titleVisibility: .visible) {
                if let review = controller.review {
                    Button(role: .destructive, action: controller.leaveAction(review) { dismiss() }) { Text("templateAuthorExit.leave", tableName: "CreatorExitGuard") }
                        .accessibilityIdentifier("templateAuthorExit.leave")
                    if review.status == .unverified {
                        Button(action: controller.retryAction(review) { dismiss() }) { Text("templateAuthorExit.retry", tableName: "CreatorExitGuard") }.accessibilityIdentifier("templateAuthorExit.retry")
                    }
                    Button(role: .cancel, action: controller.cancelAction(review)) { Text("templateAuthorExit.continue", tableName: "CreatorExitGuard") }.accessibilityIdentifier("templateAuthorExit.continue")
                }
            } message: {
                Text(LocalizedStringKey(controller.review?.status == .unverified ? "templateAuthorExit.unverified" : "templateAuthorExit.unsaved"), tableName: "CreatorExitGuard")
            }
            .onChange(of: overlaysOpen()) { _, _ in controller.overlayChanged() }
            .onAppear { controller.activate() }
            .onDisappear { controller.retire() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { controller.activate() } else { controller.retire() } }
    }
}
