import SwiftUI
import Combine

@MainActor final class TemplateD6RehearsalController: ObservableObject {
    private let model: TemplateAuthoringModel
    private var session: TemplateAuthoringSession?
    private var identity: TemplateAuthoringIdentity?
    private var metadataGeneration = UUID()
    private var mediaGeneration = UUID()
    private var generation = UUID()
    private var observation: AnyCancellable?
    @Published private var active = false
    @Published private var configuration: TemplateD6Rehearsal?
    @Published private var pips: [Int] = []
    @Published private var lastSample: TemplateD6Rehearsal.Sample?

    init(model: TemplateAuthoringModel) {
        self.model = model
        observation = model.objectWillChange.sink { [weak self] _ in self?.retire() }
    }
    private var hasLease: Bool {
        active && model.canReadStoryDraft && model.canEdit && model.coordinator.session == session &&
            model.coordinator.identity == identity && model.metadataGeneration == metadataGeneration &&
            model.mediaReviewGeneration == mediaGeneration
    }
    var visibleConfiguration: TemplateD6Rehearsal? { hasLease ? configuration : nil }
    var visibleSample: TemplateD6Rehearsal.Sample? { hasLease ? lastSample : nil }
    var selectedPips: [Int] { hasLease ? pips : [] }
    var canReload: Bool { model.canEdit && (try? TemplateD6Rehearsal(draft: model.draft.advanced)) != nil }

    func reload() {
        retire()
        guard model.canEdit, let configuration = try? TemplateD6Rehearsal(draft: model.draft.advanced) else { return }
        session = model.coordinator.session; identity = model.coordinator.identity
        metadataGeneration = model.metadataGeneration; mediaGeneration = model.mediaReviewGeneration
        self.configuration = configuration; pips = Array(repeating: 1, count: configuration.diceCount)
        active = true
    }
    func retire() {
        generation = UUID(); active = false
        configuration = nil; pips = []; lastSample = nil
    }
    func pip(_ index: Int) -> Binding<Int> {
        let stamp = generation
        return .init(get: { [weak self] in
            guard let self, self.hasLease, self.generation == stamp, self.pips.indices.contains(index) else { return 1 }
            return self.pips[index]
        }, set: { [weak self] value in
            guard let self, self.hasLease, self.generation == stamp, self.pips.indices.contains(index), (1...6).contains(value) else { return }
            guard self.pips[index] != value else { return }
            self.lastSample = nil; self.pips[index] = value
        })
    }
    func sampleAction() -> () -> Void {
        let stamp = generation, values = pips
        return { [weak self] in
            guard let self, self.hasLease, self.generation == stamp, self.pips == values, let configuration = self.configuration else { return }
            self.lastSample = try? configuration.sample(pips: values)
        }
    }
    func resetAction() -> () -> Void {
        let stamp = generation
        return { [weak self] in
            guard let self, self.hasLease, self.generation == stamp, let configuration = self.configuration else { return }
            self.generation = UUID(); self.lastSample = nil; self.pips = Array(repeating: 1, count: configuration.diceCount)
        }
    }
}

@MainActor struct TemplateD6RehearsalView: View {
    @ObservedObject var model: TemplateAuthoringModel
    @StateObject private var controller: TemplateD6RehearsalController
    init(model: TemplateAuthoringModel) {
        self.model = model; _controller = StateObject(wrappedValue: .init(model: model))
    }
    var body: some View {
        Form {
            Section { Text("templateD6.sampleOnly").font(.callout).accessibilityIdentifier("templateD6.boundary") }
            if let configuration = controller.visibleConfiguration {
                Section("templateD6.configuration") {
                    if !configuration.kicker.isEmpty { Text(verbatim: configuration.kicker) }
                    Text(LocalizedStringKey(configuration.diceCount == 1 ? "templateD6.oneDie" : "templateD6.twoDice"))
                    if configuration.diceCount == 2 { Text("templateD6.sumOnly").font(.caption).foregroundStyle(.secondary) }
                }
                Section("templateD6.exampleValues") {
                    ForEach(0..<configuration.diceCount, id: \.self) { index in
                        Picker(selection: controller.pip(index)) {
                            ForEach(1...6, id: \.self) { value in Text(verbatim: String(value)).tag(value) }
                        } label: { Text("templateD6.dieNumber \(index + 1)") }
                            .accessibilityIdentifier("templateD6.pip.\(index)")
                    }
                    Button("templateD6.showSample", action: controller.sampleAction())
                        .accessibilityIdentifier("templateD6.showSample")
                }
                if let sample = controller.visibleSample {
                    Section("templateD6.sampleResult") {
                        HStack {
                            ForEach(Array(sample.pips.enumerated()), id: \.offset) { _, value in
                                Image(systemName: "die.face.\(value).fill").font(.system(size: 48))
                                    .accessibilityLabel(Text(verbatim: String(value)))
                            }
                        }
                        LabeledContent("playkit.dice.total", value: String(sample.total)).accessibilityIdentifier("templateD6.total")
                        if let action = sample.action { Text(verbatim: action).accessibilityIdentifier("templateD6.action") }
                        else { Text("templateD6.sumOnly").font(.caption) }
                    }
                }
                Button("creator.reset", action: controller.resetAction()).accessibilityIdentifier("templateD6.reset")
            } else {
                Section {
                    Text("templateD6.configurationChanged").accessibilityIdentifier("templateD6.unavailable")
                    Button("templateD6.reload") { controller.reload() }.disabled(!controller.canReload)
                        .accessibilityIdentifier("templateD6.reload")
                }
            }
        }.navigationTitle("templateD6.preview").privacySensitive()
            .onAppear { controller.reload() }
            .onDisappear { controller.retire() }
    }
}
