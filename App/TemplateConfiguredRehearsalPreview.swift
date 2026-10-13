import SwiftUI
import Combine

/// One normal preview sheet owns the immutable source and its local navigation.
/// The five destinations retain their existing author-only behavior and lifecycle.
@MainActor final class TemplateConfiguredRehearsalPreviewController: ObservableObject {
    enum Route: String, Hashable { case coin, d6, reaction, countdown, stopwatch, legacyQuestion }
    struct Destination: Hashable { let id = UUID(); let route: Route }
    let draft: TemplateAuthoringDraft
    private let model: TemplateAuthoringModel
    private let owner: TemplateAuthoringSession?
    private let identity: TemplateAuthoringIdentity
    private let source: Data?
    private let metadata: UUID, media: UUID
    private var observation: AnyCancellable?
    private var generation = UUID(), sceneActive = false, retired = false, didClose = false
    private(set) var isVisible = false
    @Published private var active = false
    @Published private(set) var path: [Destination] = []

    init(model: TemplateAuthoringModel) {
        self.model = model; draft = model.draft
        owner = model.coordinator.session; identity = model.coordinator.identity
        source = TemplateSamplePreview.snapshot(model.draft)
        metadata = model.metadataGeneration; media = model.mediaReviewGeneration
        observation = model.objectWillChange.sink { [weak self] _ in self?.retire() }
    }
    var isCurrent: Bool {
        active && !retired && !didClose && isVisible && sceneActive &&
        owner != nil && owner == model.coordinator.session && identity == model.coordinator.identity &&
        model.canEdit && !model.busy && model.review == nil &&
        metadata == model.metadataGeneration && media == model.mediaReviewGeneration &&
        source != nil && source == TemplateSamplePreview.snapshot(model.draft)
    }
    func viewAppeared(sceneIsActive: Bool) {
        isVisible = true; sceneActive = sceneIsActive
        guard !retired && !didClose && sceneActive else { return }
        // A repeated appearance must not rotate a live route or dismiss a child.
        if !active { generation = UUID(); active = true }
    }
    func viewDisappeared() { isVisible = false; retire() }
    func sceneChanged(isActive: Bool) {
        sceneActive = isActive
        if !isActive { retire() }
        // A backgrounded/hidden snapshot is never revived by a foreground callback.
    }
    private func retire() {
        generation = UUID(); retired = true; active = false; path = []
    }
    func route(for game: TemplateAdvancedGame) -> Route? {
        switch game {
        case .coin: return .coin
        case .dice: return draft.advanced.diceMode == "d6" ? .d6 : nil
        case .react: return .reaction
        case .countdown: return .countdown
        case .stopwatch: return .stopwatch
        default: return nil
        }
    }
    func currentModel(for destination: Destination) -> TemplateAuthoringModel? {
        guard path == [destination] else { return nil }
        return sourceModel(for: destination.route)
    }
    private func sourceModel(for route: Route) -> TemplateAuthoringModel? {
        guard isCurrent else { return nil }
        let game: TemplateAdvancedGame, supported: Bool
        switch route {
        case .legacyQuestion:
            let rehearsal = TemplateLegacyQuestionRehearsal(draft)
            return rehearsal.isAvailable && rehearsal.isConfigured ? model : nil
        case .coin:
            game = .coin; supported = TemplateCoinFlipRehearsal(draft.advanced, mode: .currentConfiguration) != nil
        case .d6:
            game = .dice; supported = draft.advanced.diceMode == "d6" && (try? TemplateD6Rehearsal(draft: draft.advanced)) != nil
        case .reaction:
            game = .react; supported = TemplateReactionRehearsal(draft.advanced, mode: .currentConfiguration) != nil
        case .countdown:
            game = .countdown; supported = TemplateTimerRehearsal(draft.advanced, kind: .countdown, mode: .currentConfiguration) != nil
        case .stopwatch:
            game = .stopwatch; supported = TemplateTimerRehearsal(draft.advanced, kind: .stopwatch, mode: .currentConfiguration) != nil
        }
        guard supported && draft.advanced.enabled(game.section) else { return nil }
        return model
    }
    var offersLegacyQuestion: Bool { isCurrent && TemplateLegacyQuestionRehearsal(draft).isAvailable }
    var canOpenLegacyQuestion: Bool { path.isEmpty && sourceModel(for: .legacyQuestion) != nil }
    func openLegacyQuestionAction() -> () -> Void {
        let stamp = generation
        return { [weak self] in
            guard let self, self.generation == stamp, self.canOpenLegacyQuestion else { return }
            self.generation = UUID(); self.path = [.init(route: .legacyQuestion)]
        }
    }
    func canOpen(_ game: TemplateAdvancedGame) -> Bool {
        guard path.isEmpty, let route = route(for: game) else { return false }
        return sourceModel(for: route) != nil
    }
    func openAction(_ game: TemplateAdvancedGame) -> () -> Void {
        let stamp = generation
        return { [weak self] in
            guard let self, self.generation == stamp, self.canOpen(game), let route = self.route(for: game) else { return }
            self.generation = UUID(); self.path = [.init(route: route)]
        }
    }
    var navigationPath: Binding<[Destination]> {
        let stamp = generation, expected = path
        return .init(get: { [weak self] in
            guard let self, self.isCurrent, self.generation == stamp, self.path == expected else { return [] }
            return expected
        }, set: { [weak self] value in
            guard let self, self.isCurrent, self.generation == stamp, self.path == expected,
                  !expected.isEmpty, value.isEmpty else { return }
            self.generation = UUID(); self.path = []
        })
    }
    func closeAction(_ dismiss: @escaping () -> Void) -> () -> Void {
        let stamp = generation
        return { [weak self] in
            guard let self, self.generation == stamp, self.isVisible, self.sceneActive, !self.didClose else { return }
            self.didClose = true; self.retire(); dismiss()
        }
    }
}

private struct TemplateConfiguredRehearsalPreviewKey: EnvironmentKey {
    static let defaultValue: TemplateConfiguredRehearsalPreviewController? = nil
}
extension EnvironmentValues {
    var templateConfiguredRehearsals: TemplateConfiguredRehearsalPreviewController? {
        get { self[TemplateConfiguredRehearsalPreviewKey.self] }
        set { self[TemplateConfiguredRehearsalPreviewKey.self] = newValue }
    }
}

/// Lifecycle belongs to the sheet's outer NavigationStack, not its pushed content.
@MainActor struct TemplateConfiguredRehearsalPreview<Content: View>: View {
    @StateObject private var controller: TemplateConfiguredRehearsalPreviewController
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    private let content: Content
    init(model: TemplateAuthoringModel, @ViewBuilder content: () -> Content) {
        _controller = StateObject(wrappedValue: .init(model: model)); self.content = content()
    }
    init(controller: TemplateConfiguredRehearsalPreviewController, @ViewBuilder content: () -> Content) {
        _controller = StateObject(wrappedValue: controller); self.content = content()
    }
    var body: some View {
        NavigationStack(path: controller.navigationPath) {
            Group {
                if controller.isCurrent {
                    content.environment(\.templateConfiguredRehearsals, controller)
                } else {
                    VStack(spacing: 16) {
                        Text("templateConfiguredRehearsal.changed", tableName: "TemplateConfiguredRehearsal")
                        Button(action: controller.closeAction { dismiss() }) { Text("templateAuthor.close") }
                    }.accessibilityIdentifier("templateConfiguredRehearsal.changed")
                }
            }
            .navigationDestination(for: TemplateConfiguredRehearsalPreviewController.Destination.self) { destination in
                TemplateConfiguredRehearsalDestination(controller: controller, destination: destination)
            }
        }
        .onAppear { controller.viewAppeared(sceneIsActive: scenePhase == .active) }
        .onDisappear { controller.viewDisappeared() }
        .onChange(of: scenePhase) { _, phase in controller.sceneChanged(isActive: phase == .active) }
        .privacySensitive()
    }
}

@MainActor private struct TemplateConfiguredRehearsalDestination: View {
    @ObservedObject var controller: TemplateConfiguredRehearsalPreviewController
    let destination: TemplateConfiguredRehearsalPreviewController.Destination
    var body: some View {
        if let model = controller.currentModel(for: destination) {
            switch destination.route {
            case .legacyQuestion: TemplateLegacyQuestionRehearsalView(model: model)
            case .coin: TemplateCoinFlipRehearsalView(model: model, mode: .currentConfiguration)
            case .d6: TemplateD6RehearsalView(model: model)
            case .reaction: TemplateReactionRehearsalView(model: model, mode: .currentConfiguration)
            case .countdown: TemplateTimerRehearsalView(model: model, kind: .countdown, mode: .currentConfiguration)
            case .stopwatch: TemplateTimerRehearsalView(model: model, kind: .stopwatch, mode: .currentConfiguration)
            }
        } else {
            Text("templateConfiguredRehearsal.changed", tableName: "TemplateConfiguredRehearsal")
        }
    }
}

/// Lazy summary rows observe the stable owner; they never own a sheet or a route.
@MainActor struct TemplateConfiguredRehearsalPreviewButton: View {
    @ObservedObject var controller: TemplateConfiguredRehearsalPreviewController
    let game: TemplateAdvancedGame
    var body: some View {
        Button(action: controller.openAction(game)) {
            Text("templateConfiguredRehearsal.open", tableName: "TemplateConfiguredRehearsal")
        }.disabled(!controller.canOpen(game))
            .accessibilityIdentifier("templateConfiguredRehearsal.open." + game.rawValue)
    }
}

@MainActor struct TemplateConfiguredRehearsalCloseButton: View {
    @ObservedObject var controller: TemplateConfiguredRehearsalPreviewController
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Button("templateAuthor.close", action: controller.closeAction { dismiss() })
    }
}

/// The normal text/choice preview reuses the complete existing local attempt page.
@MainActor struct TemplateConfiguredLegacyRehearsalPreviewButton: View {
    @ObservedObject var controller: TemplateConfiguredRehearsalPreviewController
    var body: some View {
        Button("templateLegacyQuiz.title", action: controller.openLegacyQuestionAction())
            .disabled(!controller.canOpenLegacyQuestion)
            .accessibilityIdentifier("templateConfiguredRehearsal.open.legacyQuestion")
    }
}
