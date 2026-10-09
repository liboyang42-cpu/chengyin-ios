import SwiftUI

/// A real chapter destination. It never inserts or identifies a story block.
@MainActor final class ProjectChapterAudioPresentation: ObservableObject {
    struct Opening {
        let controllerID: UUID
        let generation: Int
        let lease: ProjectEditStarterController.Lease
        let revision: Int
        let bytes: Data
        let target: ProjectStoryAudioTarget
        let source: any ProjectStoryAudioUploading
        let journal: ProjectStoryAudioJournal
        let chapterName: String
        let savedReference: String
    }
    struct Presentation: Identifiable {
        let opening: Opening
        let flow: ProjectStoryAudioFlow
        var id: UUID { flow.id }
    }
    let editor: ProjectEditModel
    let chapterID: String
    @Published private(set) var presentation: Presentation?
    private let controllerID = UUID()
    private var generation = 0
    private var applied: (targetID: UUID, revision: Int, bytes: Data)?
    init(editor: ProjectEditModel, chapterID: String) { self.editor = editor; self.chapterID = chapterID }
    func capture() -> Opening? {
        guard presentation == nil, let lease = editor.captureStarterLease(),
              let index = ProjectChapterAudio.chapterIndex(chapterID, in: editor.draft),
              let source = editor.coordinator.storyAudioSource, source.isCurrent(session: lease.session),
              let parentJournal = editor.coordinator.storyAudioJournal,
              let bytes = ProjectEditPendingMaterials.exactData(editor.draft),
              let target = try? ProjectStoryAudioTarget(chapterNarrationIn: editor.draft, identity: lease.identity,
                                                        session: lease.session, chapterID: chapterID) else { return nil }
        return .init(controllerID: controllerID, generation: generation, lease: lease, revision: editor.draftMutationRevision, bytes: bytes,
                     target: target, source: source, journal: parentJournal.chapterNarrationJournal(),
                     chapterName: editor.draft.chapters[index].name,
                     savedReference: ProjectChapterAudio.reference(in: editor.draft.chapters[index]) ?? "")
    }
    func isCurrent(_ opening: Opening) -> Bool {
        guard opening.controllerID == controllerID, opening.generation == generation, editor.isCurrentStarterLease(opening.lease),
              ProjectChapterAudio.chapterIndex(chapterID, in: editor.draft) != nil,
              opening.target.kind == .chapterNarration, opening.target.chapterID.utf8.elementsEqual(chapterID.utf8),
              let source = editor.coordinator.storyAudioSource, ObjectIdentifier(source) == ObjectIdentifier(opening.source),
              editor.coordinator.storyAudioJournal?.chapterNarrationJournal() === opening.journal,
              source.isCurrent(session: opening.lease.session) else { return false }
        let expected = applied?.targetID == opening.target.id ? applied : nil
        return editor.draftMutationRevision == (expected?.revision ?? opening.revision) &&
            ProjectEditPendingMaterials.exactData(editor.draft) == (expected?.bytes ?? opening.bytes)
    }
    func open(_ opening: Opening) {
        guard presentation == nil, isCurrent(opening),
              opening.target.matches(editor.draft, identity: opening.lease.identity, session: opening.lease.session) else { return }
        applied = nil
        let flow = ProjectStoryAudioFlow(target: opening.target, session: opening.lease.session, identity: opening.lease.identity,
            source: opening.source, journal: opening.journal, currentDraft: { [weak self] in self?.editor.draft },
            parentCurrent: { [weak self] in self?.isCurrent(opening) == true })
        presentation = .init(opening: opening, flow: flow)
    }
    func apply(_ original: Presentation) {
        guard presentation?.id == original.id, isCurrent(original.opening), let next = original.flow.draftForApply() else { return }
        guard editor.persistLocalChange(next, lease: original.opening.lease) else { original.flow.localSaveFailed(); return }
        guard presentation?.id == original.id, editor.isCurrentStarterLease(original.opening.lease),
              let bytes = ProjectEditPendingMaterials.exactData(next), ProjectEditPendingMaterials.exactData(editor.draft) == bytes else {
            close(original); return
        }
        applied = (original.opening.target.id, editor.draftMutationRevision, bytes)
        original.flow.didSaveAppliedDraft()
        if original.flow.state == .applied { close(original) }
    }
    func close(_ original: Presentation) {
        original.flow.close()
        guard presentation?.id == original.id else { return }
        presentation = nil; applied = nil; generation += 1
    }
    func retire() { if let presentation { close(presentation) } else { generation += 1; applied = nil } }
    func binding(_ original: Presentation?) -> Binding<Presentation?> {
        .init(get: { guard let original, self.presentation?.id == original.id, self.isCurrent(original.opening) else { return nil }; return original },
              set: { if $0 == nil, let original { self.close(original) } })
    }
}

private struct ProjectChapterAudioPlaybackKey: EnvironmentKey {
    static let defaultValue: (@MainActor () -> PlatformAudioPlayback)? = nil
}
extension EnvironmentValues {
    var projectChapterAudioPlayback: (@MainActor () -> PlatformAudioPlayback)? {
        get { self[ProjectChapterAudioPlaybackKey.self] }
        set { self[ProjectChapterAudioPlaybackKey.self] = newValue }
    }
}

