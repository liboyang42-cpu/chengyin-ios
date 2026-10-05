import SwiftUI

/// Mount only for source-backed, unlocked topic/chapter audio. Owner creates a fresh model per view identity.
@MainActor struct PlatformAudioConsumerView: View {
    @Bindable var model: PlatformAudioPlayback
    let source: PlatformMediaSource?
    @Environment(\.scenePhase) private var scenePhase
    @State private var review = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("platform.audio.title", systemImage: "speaker.wave.2")
            Text(LocalizedStringKey("platform.audio." + String(describing: model.state))).accessibilityIdentifier("platform.audio.state")
            if model.state == .loading { ProgressView("platform.audio.loading") }
            Button(model.state == .playing ? "platform.audio.pause" : "platform.audio.play") {
                if model.state == .playing || model.state == .paused { model.toggle() } else { review = true }
            }.disabled(model.state == .gated || model.state == .disposed || model.state == .loading)
                .accessibilityIdentifier("platform.audio.toggle")
            Text("platform.audio.boundary").font(.footnote)
        }
        .confirmationDialog("platform.audio.review", isPresented: $review, titleVisibility: .visible) {
            Button("platform.audio.allow") { model.approveSelectedMedia(); model.toggle() }
            Button("platform.cancel", role: .cancel) {}
        } message: { Text(verbatim: source?.url.host ?? "") }
        .onAppear { model.select(source) }
        .onChange(of: source) { _, next in review = false; model.select(next) }
        .onChange(of: scenePhase) { _, next in if next != .active { review = false; model.suspend() } }
        .onDisappear { review = false; model.dispose() }
    }
}
@MainActor struct PlatformExternalMapButton: View {
    @Bindable var model: PlatformExternalMaps
    let destination: PlatformMapDestination
    /// Account/region scope: changing it clears a pending review and stale operation results.
    let scope: UUID
    @State private var review = false
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("platform.map.open") { review = true }.disabled(model.state == .gated || model.state == .opening)
                .accessibilityIdentifier("platform.map.open")
            Text(LocalizedStringKey("platform.map." + String(describing: model.state))).font(.footnote)
                .accessibilityIdentifier("platform.map.state")
            if model.state == .launchFailed || model.state == .copyFailed || model.state == .noCoordinates {
                Button("platform.map.copy") { model.copySelectedAddress() }.accessibilityIdentifier("platform.map.copy")
            }
        }
        .confirmationDialog("platform.map.review", isPresented: $review, titleVisibility: .visible) {
            Button("platform.map.open") { let selected = destination; Task { await model.openReviewedDestination(selected) } }
            Button("platform.cancel", role: .cancel) {}
        } message: { Text(verbatim: destination.copyText) }
        .onAppear { model.select(destination) }
        .onChange(of: destination) { _, next in review = false; model.select(next) }
        .onChange(of: scope) { _, _ in review = false; model.select(destination) }
        .onChange(of: scenePhase) { _, next in if next != .active { review = false; model.invalidate() } else { model.select(destination) } }
        .onDisappear { review = false; model.invalidate() }
    }
}

/// Additive host seam: a nil factory keeps application defaults dormant. Re-entry creates a fresh player.
@MainActor struct PlatformAudioHost: View {
    let rawURL: String?
    let scope: UUID
    var makeModel: (@MainActor () -> PlatformAudioPlayback)? = nil
    @State private var model: PlatformAudioPlayback?
    private var source: PlatformMediaSource? {
        guard let rawURL, let url = URL(string: rawURL.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return PlatformMediaSource(url: url, scope: scope)
    }
    var body: some View {
        Group {
            if let model { PlatformAudioConsumerView(model: model, source: source) }
            else if rawURL?.isEmpty == false { Label("platform.audio.gated", systemImage: "speaker.slash") }
        }
        .onAppear { if model == nil { model = makeModel?() } }
        .onChange(of: scope) { _, _ in model?.dispose(); model = makeModel?() }
        .onDisappear { model?.dispose(); model = nil }
    }
}
@MainActor struct PlatformExternalMapHost: View {
    let destination: PlatformMapDestination
    let scope: UUID
    var makeModel: (@MainActor () -> PlatformExternalMaps)? = nil
    @State private var model: PlatformExternalMaps?
    var body: some View {
        Group {
            if let model { PlatformExternalMapButton(model: model, destination: destination, scope: scope) }
            else { Label("platform.map.gated", systemImage: "map") }
        }
        .onAppear { if model == nil { model = makeModel?() } }
        .onChange(of: scope) { _, _ in model?.invalidate(); model = makeModel?() }
        .onDisappear { model?.invalidate(); model = nil }
    }
}

/// Source chapter narration and node guide share ONE player, so selecting one stops the other.
/// Parent supplies a fresh authoritative snapshot projection, never a retained chapter object.
@MainActor struct PlatformChapterAudioHost: View {
    let selection: PlatformChapterAudioSelection?
    let scope: UUID
    var makeModel: (@MainActor () -> PlatformAudioPlayback)? = nil
    @State private var guide = false
    private var selectedURL: String? { guide ? selection?.guideURL : selection?.narrationURL }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let selection, selection.narrationURL != nil || selection.guideURL != nil {
                Picker("platform.audio.source", selection: $guide) {
                    if selection.narrationURL != nil { Text("platform.audio.narration").tag(false) }
                    if selection.guideURL != nil { Text("platform.audio.guide").tag(true) }
                }.accessibilityIdentifier("platform.audio.source")
                PlatformAudioHost(rawURL: selectedURL, scope: scope, makeModel: makeModel)
            }
        }
        .onAppear { guide = selection?.narrationURL == nil }
        .onChange(of: selection) { _, next in guide = next?.narrationURL == nil }
    }
}
