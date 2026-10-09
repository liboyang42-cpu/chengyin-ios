import SwiftUI

/// One player owner per mounted chapter, shared by narration and all real audio blocks.
@MainActor final class ProjectEditorAudioPreviewController: ObservableObject {
    enum Destination: Equatable { case chapterNarration, storyBlock(Data) }
    struct Capture {
        let controllerID: UUID
        let generation: Int
        let destination: Destination
        let incarnation: UUID
        let session: ProjectEditSession?
        let identity: ProjectEditDraftIdentity?
        let revision: Int
        let draftBytes: Data
        let reference: String
        let url: URL
    }
    struct Selection: Identifiable {
        let id = UUID()
        let capture: Capture
        let player: PlatformAudioPlayback?
    }
    let editor: ProjectEditModel
    let chapterID: String
    private let controllerID = UUID()
    private var generation = 0
    @Published private(set) var selection: Selection?
    init(editor: ProjectEditModel, chapterID: String) { self.editor = editor; self.chapterID = chapterID }
    private func reference(_ destination: Destination) -> String? {
        guard let index = ProjectChapterAudio.chapterIndex(chapterID, in: editor.draft) else { return nil }
        let chapter = editor.draft.chapters[index]
        switch destination {
        case .chapterNarration: return ProjectChapterAudio.reference(in: chapter)
        case .storyBlock(let bytes):
            guard let id = String(data: bytes, encoding: .utf8), !id.isEmpty else { return nil }
            let matches = (chapter.blocks ?? []).filter { $0.id == id }
            guard matches.count == 1, let block = matches.first, block.kind == .audio,
                  block.id.utf8.elementsEqual(bytes) else { return nil }
            return block.url
        }
    }
    func capture(_ destination: Destination) -> Capture? {
        guard editor.fullEdit, let reference = reference(destination), !reference.isEmpty, reference.utf8.count <= 8192,
              reference.utf8.allSatisfy({ $0 >= 33 && $0 != 127 }),
              let url = URL(string: reference), url.scheme?.lowercased() == "https", url.host?.isEmpty == false,
              url.user == nil, url.password == nil, url.fragment == nil,
              let bytes = ProjectEditPendingMaterials.exactData(editor.draft) else { return nil }
        return .init(controllerID: controllerID, generation: generation, destination: destination, incarnation: editor.editorIncarnation,
                     session: editor.coordinator.session, identity: editor.coordinator.identity, revision: editor.draftMutationRevision,
                     draftBytes: bytes, reference: reference, url: url)
    }
    func isCurrent(_ capture: Capture) -> Bool {
        guard capture.controllerID == controllerID, capture.generation == generation, editor.fullEdit,
              capture.incarnation == editor.editorIncarnation, capture.session == editor.coordinator.session,
              capture.identity == editor.coordinator.identity, capture.revision == editor.draftMutationRevision,
              ProjectEditPendingMaterials.exactData(editor.draft) == capture.draftBytes,
              let reference = reference(capture.destination) else { return false }
        return reference.utf8.elementsEqual(capture.reference.utf8)
    }
    func select(_ capture: Capture?, makePlayer: (@MainActor () -> PlatformAudioPlayback)?) {
        guard let capture, isCurrent(capture) else { return }
        if let current = selection, isCurrent(current.capture), current.capture.destination == capture.destination,
           current.capture.reference.utf8.elementsEqual(capture.reference.utf8) {
            // Repeated tap pauses/resumes only an already-consented player. Idle still needs the existing review UI.
            if current.player?.state == .playing || current.player?.state == .paused { current.player?.toggle() }
            return
        }
        retire() // Stop/dispose BEFORE creating the next source, including equal URLs with different block IDs.
        guard let current = self.capture(capture.destination) else { return }
        let player = makePlayer?(), next = Selection(capture: current, player: player)
        player?.select(.init(url: current.url, scope: next.id))
        selection = next
    }
    func close(_ original: Selection) {
        guard selection?.id == original.id else { return }; retire()
    }
    func synchronize() { if let selection, !isCurrent(selection.capture) { retire() } }
    func retire() { selection?.player?.dispose(); selection = nil; generation += 1 }
}

@MainActor struct ProjectEditorAudioPreviewEntry: View {
    @ObservedObject var controller: ProjectEditorAudioPreviewController
    @ObservedObject private var editor: ProjectEditModel
    let destination: ProjectEditorAudioPreviewController.Destination
    @Environment(\.projectChapterAudioPlayback) private var makePlayer
    init(controller: ProjectEditorAudioPreviewController, destination: ProjectEditorAudioPreviewController.Destination) {
        self.controller = controller; self.destination = destination; editor = controller.editor
    }
    var body: some View {
        let capture = controller.capture(destination)
        Button { controller.select(capture, makePlayer: makePlayer) } label: {
            Text(destination == .chapterNarration ? "projectEditorAudio.chapter" : "projectEditorAudio.block", tableName: "ProjectEditorAudioPreview")
        }.disabled(capture == nil).accessibilityIdentifier(identifier)
        if capture == nil || makePlayer == nil {
            Text("projectEditorAudio.unavailable", tableName: "ProjectEditorAudioPreview").font(.caption)
        }
        if let original = controller.selection, original.capture.destination == destination, controller.isCurrent(original.capture) {
            Group {
                if let player = original.player {
                    PlatformAudioConsumerView(model: player, source: .init(url: original.capture.url, scope: original.id))
                } else { Text("projectEditorAudio.unavailable", tableName: "ProjectEditorAudioPreview") }
                Button { controller.close(original) } label: { Text("projectEditorAudio.close", tableName: "ProjectEditorAudioPreview") }
            }.id(original.id)
        }
    }
    private var identifier: String {
        switch destination {
        case .chapterNarration: return "projectEditorAudio.chapter"
        case .storyBlock(let id): return "projectEditorAudio.block." + (String(data: id, encoding: .utf8) ?? "")
        }
    }
}

