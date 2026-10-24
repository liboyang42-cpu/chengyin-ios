import SwiftUI
import Combine

@MainActor final class TemplateReasoningRehearsalController: ObservableObject {
    private let model: TemplateAuthoringModel
    let game: TemplateAdvancedGame
    private var observation: AnyCancellable?
    private var owner: TemplateAuthoringSession?
    private var identity: TemplateAuthoringIdentity?
    private var source: Data?
    private var metadata = UUID(), media = UUID(), generation = UUID()
    private var active = false, sceneActive = false
    private(set) var isVisible = false
    @Published private var state: TemplateReasoningRehearsal?
    @Published private(set) var formID = UUID()

    init(model: TemplateAuthoringModel, game: TemplateAdvancedGame) {
        self.model = model; self.game = game
        observation = model.objectWillChange.sink { [weak self] _ in self?.retire() }
    }
    var canReload: Bool { isVisible && sceneActive && model.canReadStoryDraft && model.canEdit && !model.busy && model.review == nil }
    private var hasLease: Bool {
        active && canReload && owner != nil && owner == model.coordinator.session && identity == model.coordinator.identity &&
        metadata == model.metadataGeneration && media == model.mediaReviewGeneration &&
        source != nil && source == TemplateSamplePreview.snapshot(model.draft)
    }
    var visibleState: TemplateReasoningRehearsal? { hasLease ? state : nil }
    func viewAppeared(sceneIsActive: Bool) {
        isVisible = true; sceneActive = sceneIsActive
        guard sceneActive else { retire(); return }
        if !active { reload() }
    }
    func viewDisappeared() { isVisible = false; retire() }
    func sceneChanged(isActive: Bool) {
        let becameActive = !sceneActive && isActive
        sceneActive = isActive
        guard isVisible && sceneActive else { retire(); return }
        if becameActive || !active { reload() }
    }
    func reload() {
        retire()
        guard canReload, let source = TemplateSamplePreview.snapshot(model.draft),
              let next = TemplateReasoningRehearsal(model.draft.advanced, game: game) else { return }
        owner = model.coordinator.session; identity = model.coordinator.identity
        metadata = model.metadataGeneration; media = model.mediaReviewGeneration
        self.source = source; state = next; active = true
    }
    func retire() {
        generation = UUID(); active = false; source = nil; state = nil; formID = UUID()
    }
    func submitAction() -> PlayKitReviewRequest {
        let stamp = generation
        return { [weak self] action, payload, _ in
            guard let self, self.generation == stamp, self.hasLease, var next = self.state,
                  next.submit(action: action, payload: payload) else { return }
            self.generation = UUID(); self.state = next
            // Deliberately never invoke the runtime's completion callback.
        }
    }
    func resetAction() -> () -> Void {
        let stamp = generation
        return { [weak self] in
            guard let self, self.generation == stamp, self.hasLease, var next = self.state else { return }
            self.generation = UUID(); next.reset(); self.state = next; self.formID = UUID()
        }
    }
}

@MainActor struct TemplateReasoningRehearsalView: View {
    @ObservedObject var model: TemplateAuthoringModel
    @StateObject private var controller: TemplateReasoningRehearsalController
    @Environment(\.scenePhase) private var scenePhase
    init(model: TemplateAuthoringModel, game: TemplateAdvancedGame) {
        self.model = model; _controller = StateObject(wrappedValue: .init(model: model, game: game))
    }
    var body: some View {
        Form {
            Section {
                Text("templateReasoning.localOnly", tableName: "TemplateReasoningRehearsal").font(.callout)
                Text("templateReasoning.lifecycle", tableName: "TemplateReasoningRehearsal").font(.footnote).foregroundStyle(.secondary)
            }
            if let state = controller.visibleState, let kind = PlayKitScreenKind(rawValue: state.game.section) {
                Section {
                    Text(verbatim: state.segment["prompt"].text ?? "").font(.title2)
                    PlayKitReasoningForm(kind: kind, segment: state.segment, enabled: state.canSubmit,
                        onDirty: {}, requestReview: controller.submitAction())
                        .id(controller.formID)
                }
                if state.result != .ready {
                    Section {
                        Text("templateReasoning.result", tableName: "TemplateReasoningRehearsal").font(.headline)
                        Text(LocalizedStringKey("templateReasoning." + state.result.rawValue), tableName: "TemplateReasoningRehearsal")
                            .accessibilityIdentifier("templateReasoning.result")
                    }
                }
                Button(action: controller.resetAction()) {
                    Text("templateReasoning.retry", tableName: "TemplateReasoningRehearsal")
                }.accessibilityIdentifier("templateReasoning.retry")
            } else {
                Section {
                    Text("templateReasoning.unavailable", tableName: "TemplateReasoningRehearsal")
                    Button(action: { controller.reload() }) {
                        Text("templateReasoning.reload", tableName: "TemplateReasoningRehearsal")
                    }.disabled(!controller.canReload).accessibilityIdentifier("templateReasoning.reload")
                }
            }
        }
        .navigationTitle(Text("templateReasoning.title", tableName: "TemplateReasoningRehearsal"))
        .privacySensitive()
        .onAppear { controller.viewAppeared(sceneIsActive: scenePhase == .active) }
        .onDisappear { controller.viewDisappeared() }
        .onChange(of: scenePhase) { _, phase in controller.sceneChanged(isActive: phase == .active) }
    }
}
