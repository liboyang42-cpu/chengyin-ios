import SwiftUI
import Combine

@MainActor final class TemplateSampleBrowserController: ObservableObject {
    struct Presentation: Identifiable {
        let id = UUID()
        let sample: TemplateSamplePreview
        let source: Data
        let metadata: UUID
        let media: UUID
    }
    private let model: TemplateAuthoringModel
    private var owner: TemplateAuthoringSession?
    private var identity: TemplateAuthoringIdentity?
    private var generation = UUID(), active = false
    private(set) var isVisible = false
    private var sceneActive = false
    private var observations: [AnyCancellable] = []
    @Published private(set) var presentation: Presentation?
    @Published private(set) var unavailable = false
    init(model: TemplateAuthoringModel) {
        self.model = model
        observations.append(model.objectWillChange.sink { [weak self] _ in
            // Retire before the new model value arrives; the sheet observes this controller.
            self?.close()
        })
        observations.append(model.$draft.dropFirst().sink { [weak self] draft in
            guard let self, let current = self.presentation else { return }
            if current.source != TemplateSamplePreview.snapshot(draft) { self.close() }
        })
        observations.append(Publishers.CombineLatest(model.$busy, model.$review).dropFirst().sink { [weak self] value in
            if value.0 || value.1 != nil { self?.close() }
        })
    }
    var canBrowse: Bool {
        isVisible && sceneActive && active && model.canEdit && !model.busy && model.review == nil && owner != nil &&
        owner == model.coordinator.session && identity == model.coordinator.identity
    }
    var visiblePresentation: Presentation? {
        guard canBrowse, let current = presentation,
              current.source == TemplateSamplePreview.snapshot(model.draft),
              current.metadata == model.metadataGeneration, current.media == model.mediaReviewGeneration else { return nil }
        return current
    }
    // A retained NavigationStack parent may receive scene/media events while hidden.
    // Visibility belongs to this whole destination, never to its lazy rows or owned sheet.
    func viewAppeared(sceneIsActive: Bool) {
        isVisible = true; sceneActive = sceneIsActive
        guard sceneActive else { retire(); return }
        // A repeated visible appearance must not close an already presented sample sheet.
        if !active { reload() }
    }
    func viewDisappeared() { isVisible = false; retire() }
    func sceneChanged(isActive: Bool) {
        let becameActive = !sceneActive && isActive
        sceneActive = isActive
        guard isVisible && sceneActive else { retire(); return }
        if becameActive || !active { reload() }
    }
    func mediaChanged(sceneIsActive: Bool) {
        sceneActive = sceneIsActive
        reload() // The reload guard keeps a hidden or inactive destination retired.
    }
    func reload() {
        guard isVisible && sceneActive else { retire(); return }
        close(); owner = model.coordinator.session; identity = model.coordinator.identity
        active = model.canReadStoryDraft; unavailable = false
    }
    func retire() { close(); active = false }
    func openAction(_ choice: TemplateSamplePreview.Choice) -> () -> Void {
        let token = generation, source = TemplateSamplePreview.snapshot(model.draft)
        let metadata = model.metadataGeneration, media = model.mediaReviewGeneration
        return { [weak self] in
            guard let self, self.canBrowse, self.presentation == nil, self.generation == token,
                  metadata == self.model.metadataGeneration, media == self.model.mediaReviewGeneration,
                  let source, source == TemplateSamplePreview.snapshot(self.model.draft) else { return }
            self.generation = UUID()
            guard let sample = TemplateSamplePreview(self.model.draft.advanced, choice: choice) else { self.unavailable = true; return }
            self.unavailable = false; self.presentation = .init(sample: sample, source: source, metadata: metadata, media: media)
        }
    }
    func close(expected: UUID? = nil) {
        if let expected, presentation?.id != expected { return }
        generation = UUID(); presentation = nil
    }
    func closeAction(_ id: UUID) -> () -> Void { { [weak self] in self?.close(expected: id) } }
    var presentationBinding: Binding<Presentation?> {
        let expected = presentation?.id
        return .init(get: { [weak self] in
            guard let self, let expected, let current = self.visiblePresentation,
                  current.id == expected else { return nil }
            return current
        }, set: { [weak self] value in
            if value == nil, let expected { self?.close(expected: expected) }
        })
    }
}

@MainActor struct TemplateSampleBrowserView: View {
    @ObservedObject var model: TemplateAuthoringModel
    @StateObject private var controller: TemplateSampleBrowserController
    @Environment(\.scenePhase) private var scenePhase
    init(model: TemplateAuthoringModel) {
        self.model = model; _controller = StateObject(wrappedValue: .init(model: model))
    }
    var body: some View {
        Form {
            Section {
                NavigationLink("templateSampleCoverage.open") { TemplateAdditionalSampleBrowserView(model: model) }
                    .accessibilityIdentifier("templateSampleCoverage.open")
            }
            Section { Text("templateSamples.scope"); Text("templateSamples.configureScope").font(.footnote).foregroundStyle(.secondary) }
            if controller.unavailable { Section { Text("templateSamples.unavailable") } }
            ForEach(TemplateSamplePreview.Group.allCases) { group in
                Section(LocalizedStringKey(group.labelKey)) {
                    ForEach(TemplateSamplePreview.Choice.allCases.filter { $0.group == group }) { choice in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(LocalizedStringKey(choice.labelKey)).font(.headline)
                            HStack {
                                Button("templateSamples.preview", action: controller.openAction(choice))
                                    .disabled(!controller.canBrowse || controller.presentation != nil)
                                    .accessibilityIdentifier("templateSamples.preview." + choice.rawValue)
                                Spacer()
                                NavigationLink("templateSamples.configure") { TemplateCreatorConfigurationView(model: model, family: choice.family) }
                                    .disabled(!controller.canBrowse)
                                    .accessibilityIdentifier("templateSamples.configure." + choice.rawValue)
                            }.buttonStyle(.borderless)
                        }
                    }
                }
            }
        }.navigationTitle("templateSamples.open")
            .sheet(item: controller.presentationBinding) { item in
                NavigationStack { TemplateSamplePresentationView(controller: controller, presentationID: item.id) }
            }
            .onAppear { controller.viewAppeared(sceneIsActive: scenePhase == .active) }
            .onDisappear { controller.viewDisappeared() }
            .onChange(of: model.mediaReviewGeneration) { _, _ in
                controller.mediaChanged(sceneIsActive: scenePhase == .active)
            }
            .onChange(of: scenePhase) { _, phase in controller.sceneChanged(isActive: phase == .active) }
    }
}

@MainActor private struct TemplateSamplePresentationView: View {
    @ObservedObject var controller: TemplateSampleBrowserController
    let presentationID: UUID
    var body: some View {
        Group {
            if let item = controller.visiblePresentation, item.id == presentationID {
                VStack(spacing: 8) {
                    Text("templateSamples.previewScope").font(.footnote).padding(.horizontal)
                    Text("templateSamples.filled \(item.sample.filledFields.count)").font(.caption)
                    TemplateCreatorRehearsalView(draft: item.sample.draft, family: item.sample.choice.family)
                        .id(item.id)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("templateAuthor.close", action: controller.closeAction(presentationID))
                    .accessibilityIdentifier("templateSamples.close")
            }
        }
        .onDisappear { controller.close(expected: presentationID) }
        .privacySensitive()
    }
}
