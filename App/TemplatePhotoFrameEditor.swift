import SwiftUI
import Combine

@MainActor final class TemplatePhotoFrameController: ObservableObject {
    struct Request: Identifiable, Equatable { let id = UUID(); let url: URL; let reference: Data }
    enum PreviewState: Equatable { case idle, loading, ready, failed }
    private let model: TemplateAuthoringModel
    private let session: TemplateAuthoringSession?
    private let identity: TemplateAuthoringIdentity
    private var mediaGeneration = UUID(), actionGeneration = UUID(), textGeneration = UUID()
    private var writing = false
    private var publicationObservation: AnyCancellable?, draftObservation: AnyCancellable?
    @Published private var active = false
    @Published private var configuration: TemplatePhotoFrameConfiguration
    @Published private var request: Request?
    @Published private(set) var previewState: PreviewState = .idle
    @Published private(set) var needsReload = false
    init(model: TemplateAuthoringModel) {
        self.model = model; session = model.coordinator.session; identity = model.coordinator.identity
        configuration = .init(model.draft.advanced); reload()
        publicationObservation = model.objectWillChange.sink { [weak self] _ in
            guard let self else { return }; self.actionGeneration = UUID()
            if !self.writing && (!self.canReload || !self.model.canEdit || self.mediaGeneration != self.model.mediaReviewGeneration) { self.suspend() }
        }
        // Parent onChange(draft) performs another review-only changed(). Keep the loaded
        // frame through that refresh, while actual external draft emissions retire it.
        draftObservation = model.$draft.dropFirst().sink { [weak self] _ in
            guard let self, !self.writing else { return }; self.suspend()
        }
    }
    var canReload: Bool { model.canReadStoryDraft && session != nil && model.coordinator.session == session && model.coordinator.identity == identity }
    private var hasLease: Bool { active && canReload && mediaGeneration == model.mediaReviewGeneration && configuration.isCurrent(model.draft.advanced) }
    var canEdit: Bool { hasLease && model.canEdit && configuration.canEdit }
    var isSupported: Bool { hasLease && configuration.isSupported }
    var canClear: Bool { canEdit && configuration.canClear }
    var canAdjustOpacity: Bool { canEdit && configuration.canAdjustOpacity }
    var canLoad: Bool { canEdit && configuration.previewURL != nil }
    var reference: String { hasLease ? configuration.reference : "" }
    var opacity: Double { hasLease ? configuration.opacity : 40 }
    var scene: Request? { guard let request, isCurrent(request) else { return nil }; return request }
    var issues: [TemplateCreatorIssue] { hasLease ? model.draft.advanced.creatorIssues(.photoCheck).filter { ["frameUrl", "frameOpacity"].contains($0.path) } : [] }
    func reload() {
        actionGeneration = UUID(); textGeneration = UUID(); clearPreview()
        guard canReload else { active = false; needsReload = true; return }
        configuration = .init(model.draft.advanced); mediaGeneration = model.mediaReviewGeneration; active = true; needsReload = false
    }
    func retire() { active = false; actionGeneration = UUID(); textGeneration = UUID(); clearPreview() }
    func suspend() { retire(); needsReload = true }
    private func clearPreview() { request = nil; previewState = .idle }
    private func isCurrent(_ candidate: Request) -> Bool { canEdit && request?.id == candidate.id && Data(configuration.reference.utf8) == candidate.reference }
    func loadAction() -> () -> Void {
        let stamp = actionGeneration, metadata = model.metadataGeneration, snapshot = configuration
        return { [weak self] in
            guard let self, self.canLoad, self.actionGeneration == stamp, self.model.metadataGeneration == metadata,
                  snapshot.isCurrent(self.model.draft.advanced), let url = snapshot.previewURL else { return }
            self.actionGeneration = UUID(); self.clearPreview(); self.request = .init(url: url, reference: Data(snapshot.reference.utf8)); self.previewState = .loading
        }
    }
    func imageReady(_ candidate: Request) { guard isCurrent(candidate) else { return }; previewState = .ready }
    func imageFailed(_ candidate: Request) { guard isCurrent(candidate) else { return }; previewState = .failed }
    func clearAction() -> () -> Void {
        let stamp = actionGeneration, metadata = model.metadataGeneration, snapshot = configuration
        return { [weak self] in
            guard let self, self.canClear, self.actionGeneration == stamp, self.model.metadataGeneration == metadata,
                  let next = snapshot.applying(.clear, to: self.model.draft.advanced) else { return }
            self.textGeneration = UUID(); self.apply(next)
        }
    }
    func referenceInput() -> Binding<String> {
        let stamp = textGeneration
        return .init(get: { [weak self] in guard let self, self.hasLease, self.textGeneration == stamp else { return "" }; return self.configuration.reference }, set: { [weak self] text in
            guard let self, self.canEdit, self.textGeneration == stamp, let next = self.configuration.applying(.reference(text), to: self.model.draft.advanced) else { return }
            self.apply(next)
        })
    }
    func opacityInput() -> Binding<Double> {
        let stamp = textGeneration, reference = Data(configuration.reference.utf8)
        return .init(get: { [weak self] in guard let self, self.hasLease, self.textGeneration == stamp, Data(self.configuration.reference.utf8) == reference else { return 40 }; return self.configuration.opacity }, set: { [weak self] value in
            guard let self, self.canAdjustOpacity, self.textGeneration == stamp, Data(self.configuration.reference.utf8) == reference,
                  let next = self.configuration.applying(.opacity(value), to: self.model.draft.advanced) else { return }
            self.apply(next)
        })
    }
    private func apply(_ next: TemplateAdvancedDraft) {
        let updated = TemplatePhotoFrameConfiguration(next)
        actionGeneration = UUID(); writing = true; defer { writing = false }
        if Data(updated.reference.utf8) != Data(configuration.reference.utf8) { clearPreview(); model.mediaReferencesWillChange() }
        configuration = updated
        if !updated.isCurrent(model.draft.advanced) { model.draft.advanced = next; model.changed() }
    }
}

@MainActor struct TemplatePhotoFrameEditor: View {
    @ObservedObject var model: TemplateAuthoringModel
    @StateObject private var editor: TemplatePhotoFrameController
    @Environment(\.scenePhase) private var scenePhase
    init(model: TemplateAuthoringModel) { self.model = model; _editor = StateObject(wrappedValue: .init(model: model)) }
    var body: some View {
        Form {
            Section {
                Text("templateFrame.instructions").font(.callout)
                if editor.needsReload {
                    Text("templateFrame.changed").font(.caption)
                    Button("templateFrame.reload") { editor.reload() }.disabled(!editor.canReload)
                } else if !editor.isSupported { Text("templateFrame.unsupported").font(.caption) }
            }
            Section("creator.field.frameUrl") {
                TextField("creator.field.frameUrl", text: editor.referenceInput(), axis: .vertical).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    .accessibilityIdentifier("creator.frame.reference")
                Text("templateFrame.addressHint").font(.caption)
                Button("templateFrame.clear", role: .destructive, action: editor.clearAction()).disabled(!editor.canClear).accessibilityIdentifier("creator.frame.clear")
            }.disabled(!editor.canEdit)
            if editor.isSupported && !editor.reference.isEmpty {
                Section("creator.field.frameOpacity") {
                    Slider(value: editor.opacityInput(), in: 0...100, step: 5).disabled(!editor.canAdjustOpacity).accessibilityLabel("creator.field.frameOpacity").accessibilityIdentifier("creator.frame.opacity")
                    Text("templateFrame.opacity \(Int(editor.opacity))").font(.caption)
                }
            }
            Section("templateFrame.preview") {
                Button("templateFrame.load", systemImage: "photo", action: editor.loadAction()).disabled(!editor.canLoad).accessibilityIdentifier("creator.frame.load")
                if !editor.canLoad { Text("templateFrame.previewUnavailable").font(.caption) }
                if let request = editor.scene { preview(request).id(request.id) }
            }
            if !editor.issues.isEmpty {
                Section("templateAuthor.validationTitle") {
                    ForEach(Array(editor.issues.enumerated()), id: \.offset) { _, issue in VStack(alignment: .leading) { Text(LocalizedStringKey(issue.labelKey)); Text(verbatim: issue.path).font(.caption) } }
                }
            }
        }.navigationTitle("templateFrame.title").onAppear { editor.reload() }.onDisappear { editor.retire() }
            .onChange(of: model.canEdit) { _, value in if !value { editor.suspend() } }
            .onChange(of: scenePhase) { _, phase in if phase != .active { editor.suspend() } }
    }
    private func preview(_ request: TemplatePhotoFrameController.Request) -> some View {
        AsyncImage(url: request.url) { phase in
            if let image = phase.image {
                VStack(alignment: .leading) {
                    ZStack {
                        HStack(spacing: 0) { Color.white; Color.gray }
                        image.resizable().scaledToFit().opacity(editor.opacity / 100)
                    }.frame(height: 240).clipped().onAppear { editor.imageReady(request) }
                        .accessibilityLabel("templateFrame.preview").accessibilityIdentifier("creator.frame.canvas")
                    Text("templateFrame.backgroundHint").font(.caption)
                }
            } else if phase.error != nil { Text("templateFrame.loadFailed").onAppear { editor.imageFailed(request) } }
            else { ProgressView().accessibilityLabel("templateFrame.loading") }
        }
    }
}
