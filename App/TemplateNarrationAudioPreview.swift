import Combine
import SwiftUI

/// Read-only ownership for the existing platform player. No URL fetcher or draft writer.
@MainActor final class TemplateNarrationAudioPreviewController: ObservableObject {
    struct Capture {
        let controllerID: UUID
        let generation: Int
        let modelGeneration: UUID
        let mediaGeneration: UUID
        let session: TemplateAuthoringSession?
        let identity: TemplateAuthoringIdentity
        let referenceBytes: Data
        let url: URL
    }
    struct Selection: Identifiable {
        let id = UUID()
        let capture: Capture
        let player: PlatformAudioPlayback
    }
    let model: TemplateAuthoringModel
    private let controllerID = UUID()
    private var generation = 0
    private var observation: AnyCancellable?
    @Published private(set) var isActive = false
    @Published private(set) var selection: Selection?

    init(model: TemplateAuthoringModel) {
        self.model = model
        // Published edits notify synchronously before replacement. This stops a pending
        // download/player even for clear, same-value reload and A -> B -> A edits.
        observation = model.objectWillChange.sink { [weak self] _ in self?.retire() }
    }
    func activate() {
        guard !isActive else { return }
        generation += 1; isActive = true
    }
    func capture() -> Capture? {
        guard isActive, model.canEdit, model.draft.voiceEnabled,
              let reference = model.draft.audioUrl, !reference.isEmpty, reference.utf8.count <= 8192,
              reference.utf8.allSatisfy({ $0 >= 33 && $0 != 127 }),
              let url = URL(string: reference), url.scheme?.lowercased() == "https", url.host?.isEmpty == false,
              url.user == nil, url.password == nil, url.fragment == nil else { return nil }
        return .init(controllerID: controllerID, generation: generation,
                     modelGeneration: model.metadataGeneration, mediaGeneration: model.mediaReviewGeneration,
                     session: model.coordinator.session, identity: model.coordinator.identity,
                     referenceBytes: Data(reference.utf8), url: url)
    }
    func isCurrent(_ capture: Capture) -> Bool {
        isActive && model.canEdit && model.draft.voiceEnabled && capture.controllerID == controllerID &&
            capture.generation == generation && capture.modelGeneration == model.metadataGeneration &&
            capture.mediaGeneration == model.mediaReviewGeneration && capture.session == model.coordinator.session &&
            capture.identity == model.coordinator.identity && model.draft.audioUrl.map({ Data($0.utf8) }) == capture.referenceBytes
    }
    func select(_ capture: Capture?, makePlayer: (@MainActor () -> PlatformAudioPlayback)?) {
        guard let capture, isCurrent(capture) else { return }
        if let selection, isCurrent(selection.capture) {
            // The existing consumer has already obtained consent before these states.
            if selection.player.state == .playing || selection.player.state == .paused { selection.player.toggle() }
            return
        }
        guard let makePlayer else { return }
        retire()
        guard let current = self.capture() else { return }
        let player = makePlayer(), selected = Selection(capture: current, player: player)
        player.select(.init(url: current.url, scope: selected.id))
        // Selection only. The existing PlatformAudioConsumerView owns URL review/play.
        selection = selected
    }
    func close(_ original: Selection) {
        guard selection?.id == original.id else { return }
        retire()
    }
    func synchronize() {
        if let selection, !isCurrent(selection.capture) { retire() }
    }
    func retire() {
        generation += 1
        selection?.player.dispose()
        selection = nil
    }
    func deactivate() { retire(); isActive = false }
}

@MainActor struct TemplateNarrationAudioPreviewEntry: View {
    @ObservedObject var model: TemplateAuthoringModel
    @StateObject private var controller: TemplateNarrationAudioPreviewController
    @Environment(\.projectChapterAudioPlayback) private var makePlayer
    @Environment(\.scenePhase) private var scenePhase
    init(model: TemplateAuthoringModel) {
        self.model = model
        _controller = StateObject(wrappedValue: .init(model: model))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            let capture = controller.capture()
            Button("templateNarration.preview") { controller.select(capture, makePlayer: makePlayer) }
                .disabled(capture == nil || makePlayer == nil)
                .accessibilityIdentifier("templateNarration.preview")
            if capture == nil || makePlayer == nil {
                Text("templateNarration.previewUnavailable").font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("templateNarration.previewUnavailable")
            }
            if let selected = controller.selection, controller.isCurrent(selected.capture) {
                Group {
                    PlatformAudioConsumerView(model: selected.player,
                        source: .init(url: selected.capture.url, scope: selected.id))
                    Button("templateNarration.closePreview") { controller.close(selected) }
                        .accessibilityIdentifier("templateNarration.closePreview")
                }.id(selected.id)
            }
        }.buttonStyle(.borderless)
            .onAppear { if scenePhase == .active { controller.activate() } }
            .onDisappear { controller.deactivate() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { controller.activate() } else { controller.deactivate() }
            }
            .onChange(of: model.canEdit) { _, _ in controller.synchronize() }
    }
}
