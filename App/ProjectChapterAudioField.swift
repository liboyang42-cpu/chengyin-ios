import SwiftUI

@MainActor final class ProjectChapterAudioController: ObservableObject {
    struct Capture {
        let controllerID: UUID
        let generation: Int
        let incarnation: UUID
        let session: ProjectEditSession?
        let identity: ProjectEditDraftIdentity?
        let revision: Int
        let bytes: Data
        let reference: String
    }
    struct Confirmation: Identifiable { let id = UUID(); let capture: Capture }
    let model: ProjectEditModel
    let chapterID: String
    private let controllerID = UUID()
    private var generation = 0
    @Published private(set) var confirmation: Confirmation?
    init(model: ProjectEditModel, chapterID: String) { self.model = model; self.chapterID = chapterID }
    var chapter: ProjectEditChapter? {
        ProjectChapterAudio.chapterIndex(chapterID, in: model.draft).map { model.draft.chapters[$0] }
    }
    func capture() -> Capture? {
        guard model.fullEdit, let chapter, let reference = ProjectChapterAudio.reference(in: chapter), !reference.isEmpty,
              let bytes = ProjectEditPendingMaterials.exactData(model.draft) else { return nil }
        return .init(controllerID: controllerID, generation: generation, incarnation: model.editorIncarnation,
                     session: model.coordinator.session, identity: model.coordinator.identity,
                     revision: model.draftMutationRevision, bytes: bytes, reference: reference)
    }
    func isCurrent(_ capture: Capture) -> Bool {
        guard capture.controllerID == controllerID, capture.generation == generation, model.fullEdit,
              capture.incarnation == model.editorIncarnation, capture.session == model.coordinator.session,
              capture.identity == model.coordinator.identity, capture.revision == model.draftMutationRevision,
              ProjectEditPendingMaterials.exactData(model.draft) == capture.bytes, let chapter,
              let reference = ProjectChapterAudio.reference(in: chapter) else { return false }
        return reference.utf8.elementsEqual(capture.reference.utf8)
    }
    func open(_ capture: Capture?) {
        guard let capture, isCurrent(capture), confirmation == nil else { return }
        confirmation = .init(capture: capture)
    }
    func clear(_ original: Confirmation) {
        guard confirmation?.id == original.id, isCurrent(original.capture),
              let next = try? ProjectChapterAudio.clearing(chapterID: chapterID, in: model.draft) else { return }
        if ProjectEditPendingMaterials.exactData(next) != original.capture.bytes { model.draft = next }
        close(original)
    }
    func close(_ original: Confirmation) {
        guard confirmation?.id == original.id else { return }
        confirmation = nil; generation += 1
    }
    func retire() { confirmation = nil; generation += 1 }
    func binding(_ original: Confirmation?) -> Binding<Bool> {
        .init(get: { original.map { self.confirmation?.id == $0.id && self.isCurrent($0.capture) } ?? false },
              set: { if !$0, let original { self.close(original) } })
    }
}

@MainActor struct ProjectChapterAudioField: View {
    @ObservedObject private var model: ProjectEditModel
    let preview: ProjectEditorAudioPreviewController
    @StateObject private var controller: ProjectChapterAudioController
    @StateObject private var uploads: ProjectChapterAudioPresentation
    init(model: ProjectEditModel, chapterID: String, preview: ProjectEditorAudioPreviewController) {
        self.preview = preview
        self.model = model; _controller = StateObject(wrappedValue: .init(model: model, chapterID: chapterID))
        _uploads = StateObject(wrappedValue: .init(editor: model, chapterID: chapterID))
    }
    var body: some View {
        let capture = controller.capture(), original = controller.confirmation
        let opening = uploads.capture(), upload = uploads.presentation
        Section {
            if let chapter = controller.chapter {
                if let reference = ProjectChapterAudio.reference(in: chapter), !reference.isEmpty {
                    // Verbatim text only: no Link, detector, fetch or implicit playback of legacy URLs.
                    Text(verbatim: reference).textSelection(.enabled).accessibilityIdentifier("projectChapterAudio.reference")
                    if !ProjectChapterAudio.fitsWire(reference) {
                        Text("projectChapterAudio.tooLong", tableName: "ProjectChapterAudio").font(.caption)
                    }
                    ProjectEditorAudioPreviewEntry(controller: preview, destination: .chapterNarration)
                    Button(role: .destructive) { guard uploads.presentation == nil else { return }; preview.retire(); controller.open(capture) } label: {
                        Text("projectChapterAudio.clear", tableName: "ProjectChapterAudio")
                    }.disabled(capture == nil).accessibilityIdentifier("projectChapterAudio.clear")
                } else if ProjectChapterAudio.isUnsupported(in: chapter) {
                    Text("projectChapterAudio.unsupported", tableName: "ProjectChapterAudio")
                } else { Text("projectChapterAudio.empty", tableName: "ProjectChapterAudio") }
                Button {
                    guard let opening, controller.confirmation == nil else { return }; preview.retire(); uploads.open(opening)
                } label: { Text("projectChapterAudio.replace", tableName: "ProjectChapterAudio") }
                    .disabled(opening == nil).accessibilityIdentifier("projectChapterAudio.replace")
                if opening == nil && upload == nil {
                    Text("projectChapterAudio.uploadUnavailable", tableName: "ProjectChapterAudio").font(.caption)
                }
                Text("projectChapterAudio.scope", tableName: "ProjectChapterAudio").font(.caption).foregroundStyle(.secondary)
            }
        } header: { Text("projectChapterAudio.title", tableName: "ProjectChapterAudio") }
        .confirmationDialog(Text("projectChapterAudio.clearTitle", tableName: "ProjectChapterAudio"),
                            isPresented: controller.binding(original), titleVisibility: .visible) {
            if let original {
                Button(role: .destructive) { controller.clear(original) } label: {
                    Text("projectChapterAudio.clear", tableName: "ProjectChapterAudio")
                }
                Button("action.cancel", role: .cancel) { controller.close(original) }
            }
        } message: { Text("projectChapterAudio.clearMessage", tableName: "ProjectChapterAudio") }
        .sheet(item: uploads.binding(upload)) { original in
            ProjectChapterAudioAuthorView(original: original, picker: model.storyAudioPicker?(), apply: { uploads.apply($0) }, close: { uploads.close(original) })
        }
        .onChange(of: model.editorIncarnation) { _, _ in controller.retire(); uploads.retire() }
        .onDisappear { controller.retire(); uploads.retire() }
    }
}
