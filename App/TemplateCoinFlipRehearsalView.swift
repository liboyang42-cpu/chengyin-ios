import SwiftUI
import Combine

@MainActor final class TemplateCoinFlipRehearsalController: ObservableObject {
    private let model: TemplateAuthoringModel
    let mode: TemplateCoinFlipRehearsal.Mode
    private(set) var isVisible = false
    private var sceneActive = false
    private var owner: TemplateAuthoringSession?
    private var identity: TemplateAuthoringIdentity?
    private var source: Data?
    private var metadata = UUID(), media = UUID(), generation = UUID()
    private var active = false
    private var observation: AnyCancellable?
    @Published private var state: TemplateCoinFlipRehearsal?
    init(model: TemplateAuthoringModel, mode: TemplateCoinFlipRehearsal.Mode) {
        self.model = model; self.mode = mode
        observation = model.objectWillChange.sink { [weak self] _ in self?.retire() }
    }
    var canReload: Bool { isVisible && sceneActive && model.canReadStoryDraft && model.canEdit && !model.busy && model.review == nil }
    private var hasLease: Bool {
        active && canReload && owner != nil && owner == model.coordinator.session &&
        identity == model.coordinator.identity && metadata == model.metadataGeneration && media == model.mediaReviewGeneration &&
        source != nil && source == TemplateSamplePreview.snapshot(model.draft)
    }
    var visibleState: TemplateCoinFlipRehearsal? { hasLease ? state : nil }
    // NavigationStack can retain this destination while another page is on top.
    func viewAppeared(sceneIsActive: Bool) {
        isVisible = true; sceneActive = sceneIsActive
        guard sceneActive else { retire(); return }
        // Repeated visible appearance must preserve a current local run or presentation.
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
              let next = TemplateCoinFlipRehearsal(model.draft.advanced, mode: mode) else { return }
        owner = model.coordinator.session; identity = model.coordinator.identity
        metadata = model.metadataGeneration; media = model.mediaReviewGeneration
        self.source = source; state = next; active = true
    }
    func retire() { generation = UUID(); active = false; state = nil; source = nil }
    var selection: Binding<TemplateCoinFlipRehearsal.Face> {
        let stamp = generation
        return .init(get: { [weak self] in
            guard let self, self.generation == stamp else { return .heads }
            return self.visibleState?.selection ?? .heads
        }, set: { [weak self] face in
            guard let self, self.hasLease, self.generation == stamp, var next = self.state else { return }
            self.generation = UUID(); next.select(face); self.state = next
        })
    }
    func showAction() -> () -> Void {
        let stamp = generation
        return { [weak self] in
            guard let self, self.hasLease, self.generation == stamp, var next = self.state else { return }
            self.generation = UUID(); next.showSelectedResult(); self.state = next
        }
    }
    func resetAction() -> () -> Void {
        let stamp = generation
        return { [weak self] in
            guard let self, self.hasLease, self.generation == stamp, var next = self.state else { return }
            self.generation = UUID(); next.reset(); self.state = next
        }
    }
    func closeAction(_ dismiss: @escaping () -> Void) -> () -> Void {
        let stamp = generation
        return { [weak self] in
            guard let self, self.generation == stamp else { return }
            self.retire(); dismiss()
        }
    }
}

@MainActor struct TemplateCoinFlipRehearsalView: View {
    @ObservedObject var model: TemplateAuthoringModel
    @StateObject private var controller: TemplateCoinFlipRehearsalController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    init(model: TemplateAuthoringModel, mode: TemplateCoinFlipRehearsal.Mode) {
        self.model = model; _controller = StateObject(wrappedValue: .init(model: model, mode: mode))
    }
    var body: some View {
        Form {
            Section {
                Text("templateCoin.localOnly").font(.callout)
                Text("templateCoin.deterministic").font(.footnote).foregroundStyle(.secondary)
                if controller.mode == .sourceExample { Text("templateCoin.exampleOnly").font(.footnote) }
            }
            if let state = controller.visibleState {
                Section {
                    Text(verbatim: state.kicker).font(.title2).accessibilityIdentifier("templateCoin.kicker")
                    side(state.heads, key: "templateCoin.heads")
                    side(state.tails, key: "templateCoin.tails")
                }
                Section("templateCoin.chooseFace") {
                    Picker("templateCoin.chooseFace", selection: controller.selection) {
                        ForEach(TemplateCoinFlipRehearsal.Face.allCases) { face in Text(LocalizedStringKey(face.labelKey)).tag(face) }
                    }.pickerStyle(.segmented).accessibilityIdentifier("templateCoin.selection")
                    if state.result == nil {
                        Button("templateCoin.show", action: controller.showAction()).accessibilityIdentifier("templateCoin.show")
                    } else {
                        Button("templateCoin.again", action: controller.showAction()).accessibilityIdentifier("templateCoin.again")
                    }
                }
                if let result = state.result {
                    Section("templateCoin.result") {
                        Text(LocalizedStringKey(result.face.labelKey)).font(.caption)
                        Text(verbatim: result.side.label).font(.largeTitle).accessibilityIdentifier("templateCoin.result.label")
                        if result.side.action.isEmpty { Text("templateCoin.emptyAction") }
                        else { Text(verbatim: result.side.action).accessibilityIdentifier("templateCoin.result.action") }
                    }
                }
                Button("creator.reset", action: controller.resetAction()).accessibilityIdentifier("templateCoin.reset")
            } else {
                Section {
                    Text("templateCoin.unavailable")
                    Button("templateCoin.reload") { controller.reload() }.disabled(!controller.canReload)
                        .accessibilityIdentifier("templateCoin.reload")
                }
            }
        }.navigationTitle("templateCoin.rehearse").privacySensitive()
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("templateAuthor.close", action: controller.closeAction { dismiss() }).accessibilityIdentifier("templateCoin.close")
            } }
            .onAppear { controller.viewAppeared(sceneIsActive: scenePhase == .active) }
            .onDisappear { controller.viewDisappeared() }
            .onChange(of: scenePhase) { _, phase in controller.sceneChanged(isActive: phase == .active) }
    }
    private func side(_ side: TemplateCoinFlipRehearsal.Side, key: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(key)).font(.caption)
            Text(verbatim: side.label).font(.headline)
            if side.action.isEmpty { Text("templateCoin.emptyAction").foregroundStyle(.secondary) }
            else { Text(verbatim: side.action) }
        }
    }
}
