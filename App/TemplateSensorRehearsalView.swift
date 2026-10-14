import SwiftUI
import Combine

@MainActor final class TemplateSensorRehearsalController: ObservableObject {
    private let model: TemplateAuthoringModel
    let game: TemplateAdvancedGame
    private var observation: AnyCancellable?
    private var owner: TemplateAuthoringSession?
    private var identity: TemplateAuthoringIdentity?
    private var source: Data?
    private var metadata = UUID(), media = UUID(), generation = UUID()
    private var active = false, sceneActive = false
    private(set) var isVisible = false
    @Published private var state: TemplateSensorRehearsal?
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
    var visibleState: TemplateSensorRehearsal? { hasLease ? state : nil }
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
              let next = TemplateSensorRehearsal(model.draft.advanced, game: game) else { return }
        owner = model.coordinator.session; identity = model.coordinator.identity
        metadata = model.metadataGeneration; media = model.mediaReviewGeneration
        self.source = source; state = next; active = true
    }
    func retire() {
        generation = UUID(); active = false; source = nil; state = nil; formID = UUID()
    }
    func advanceAction() -> (Double, Double, Double) -> Void {
        let stamp = generation
        return { [weak self] bearing, accuracy, peak in
            guard let self, self.generation == stamp, self.hasLease, var next = self.state,
                  next.advance(bearing: bearing, accuracy: accuracy, peak: peak) else { return }
            self.generation = UUID(); self.state = next
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

@MainActor struct TemplateSensorRehearsalView: View {
    @ObservedObject var model: TemplateAuthoringModel
    @StateObject private var controller: TemplateSensorRehearsalController
    @Environment(\.scenePhase) private var scenePhase
    init(model: TemplateAuthoringModel, game: TemplateAdvancedGame) {
        self.model = model; _controller = StateObject(wrappedValue: .init(model: model, game: game))
    }
    var body: some View {
        Form {
            Section { sensorText("boundary"); sensorText("virtualTime").font(.footnote) }
            if let state = controller.visibleState {
                TemplateSensorRehearsalInputs(state: state, advance: controller.advanceAction())
                    .id(controller.formID)
                Section {
                    sensorText("feedback." + state.feedback.rawValue).accessibilityIdentifier("templateSensor.feedback")
                    ProgressView(value: state.heldSeconds, total: state.duration)
                    LabeledContent { Text(verbatim: String(format: "%.1f / %.1f", state.heldSeconds, state.duration)) }
                        label: { sensorText("held") }
                    Button(action: controller.resetAction()) { sensorText("retry") }
                        .accessibilityIdentifier("templateSensor.retry")
                }
            } else {
                Section {
                    sensorText("unavailable")
                    Button { controller.reload() } label: { sensorText("reload") }
                        .disabled(!controller.canReload)
                }
            }
        }
        .navigationTitle(sensorText("title"))
        .privacySensitive()
        .onAppear { controller.viewAppeared(sceneIsActive: scenePhase == .active) }
        .onDisappear { controller.viewDisappeared() }
        .onChange(of: scenePhase) { _, phase in controller.sceneChanged(isActive: phase == .active) }
    }
}
@MainActor private struct TemplateSensorRehearsalInputs: View {
    let state: TemplateSensorRehearsal
    let advance: (Double, Double, Double) -> Void
    @State private var bearing = 0.0
    @State private var accuracy = 0.0
    @State private var peak = 0.1
    var body: some View {
        Section {
            if !state.title.isEmpty { Text(verbatim: state.title).font(.headline) }
            if state.game == .compass {
                LabeledContent { Text(verbatim: "\(Int(state.targetBearing))° ± \(Int(state.tolerance))°") }
                    label: { sensorText("target") }
                LabeledContent { Text(verbatim: "\(Int(bearing))°") } label: { sensorText("bearing") }
                Slider(value: $bearing, in: 0...359, step: 1) { sensorText("bearing") }
                    .accessibilityIdentifier("templateSensor.bearing")
                LabeledContent { Text(verbatim: "\(Int(accuracy))°") } label: { sensorText("accuracy") }
                Slider(value: $accuracy, in: 0...180, step: 1) { sensorText("accuracy") }
                    .accessibilityIdentifier("templateSensor.accuracy")
            } else {
                sensorText("baseline").font(.footnote)
                LabeledContent { Text(verbatim: String(format: "%.2f", state.loudThreshold)) }
                    label: { sensorText("threshold") }
                LabeledContent { Text(verbatim: String(format: "%.2f", peak)) } label: { sensorText("peak") }
                Slider(value: $peak, in: 0...1, step: 0.01) { sensorText("peak") }
                    .accessibilityIdentifier("templateSensor.peak")
            }
            Button { advance(bearing, accuracy, peak) } label: { sensorText("advance") }
                .disabled(state.finished).accessibilityIdentifier("templateSensor.advance")
        }
    }
}
private func sensorText(_ key: String) -> Text {
    Text(LocalizedStringKey("templateSensor." + key), tableName: "TemplateSensorRehearsal")
}
