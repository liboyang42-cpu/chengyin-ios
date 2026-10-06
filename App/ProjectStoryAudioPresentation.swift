import SwiftUI

@MainActor final class ProjectStoryAudioPresentation: ObservableObject {
    struct Insertion {
        let lease: ProjectEditStarterController.Lease
        let topology: Int
        let gapRevision: Int
        let gap: ProjectStoryMediaGap
    }
    struct LocalBlock {
        let lease: ProjectEditStarterController.Lease
        let topology: Int
        let gapRevision: Int
        let target: ProjectStoryAudioTarget
    }
    struct Opening {
        let block: LocalBlock
        let source: any ProjectStoryAudioUploading
        let journal: ProjectStoryAudioJournal
        let chapterName: String
        let savedReference: String
        let savedFilename: String?
    }
    struct Presentation: Identifiable {
        let opening: Opening
        let flow: ProjectStoryAudioFlow
        var id: UUID { flow.id }
    }
    @Published private(set) var presentation: Presentation?
    private var appliedGapRevision: (targetID: UUID, revision: Int)?
    private let editor: ProjectEditModel
    private let host: ProjectStoryMediaChapterHost
    init(editor: ProjectEditModel, host: ProjectStoryMediaChapterHost = .ordinary) {
        self.editor = editor; self.host = host
    }
    func captureInsertion(chapterID: String, before blockID: String?) -> Insertion? {
        guard presentation == nil, host.allows(editor: editor, chapterID: chapterID), let lease = editor.captureStarterLease(),
              let gap = try? ProjectStoryMediaGap(draft: editor.draft, identity: lease.identity, session: lease.session, chapterID: chapterID, before: blockID) else { return nil }
        return .init(lease: lease, topology: editor.storyTopologyRevision, gapRevision: editor.storyGapRevision, gap: gap)
    }
    /// Commit the blank block before any document picker. Cancelling selection keeps this exact gap.
    @discardableResult func insertEmpty(chapterID: String, captured original: Insertion) -> String? {
        guard chapterID == original.gap.chapterID, presentation == nil, host.allows(editor: editor, chapterID: original.gap.chapterID),
              editor.isCurrentStarterLease(original.lease), editor.storyTopologyRevision == original.topology,
              editor.storyGapRevision == original.gapRevision else { return nil }
        let block = ProjectEditBlock(kind: .audio)
        guard let next = try? original.gap.inserting(block, into: editor.draft, identity: original.lease.identity, session: original.lease.session),
              editor.persistLocalChange(next, lease: original.lease) else { return nil }
        return block.id
    }
    func captureBlock(chapterID: String, blockID: String) -> LocalBlock? {
        guard host.allows(editor: editor, chapterID: chapterID), let lease = editor.captureStarterLease(),
              let target = try? ProjectStoryAudioTarget(draft: editor.draft, identity: lease.identity, session: lease.session, chapterID: chapterID, blockID: blockID) else { return nil }
        return .init(lease: lease, topology: editor.storyTopologyRevision, gapRevision: editor.storyGapRevision, target: target)
    }
    func capture(chapterID: String, blockID: String) -> Opening? {
        guard presentation == nil, let local = captureBlock(chapterID: chapterID, blockID: blockID),
              let source = editor.coordinator.storyAudioSource, source.isCurrent(session: local.lease.session),
              let journal = editor.coordinator.storyAudioJournal,
              let chapter = editor.draft.chapters.first(where: { $0.id == chapterID }),
              let block = chapter.blocks?.first(where: { $0.id == blockID }) else { return nil }
        let filename = block.localAudio.flatMap { $0.reference.utf8.elementsEqual(block.url.utf8) ? $0.filename : nil }
        return .init(block: local, source: source, journal: journal, chapterName: chapter.name, savedReference: block.url, savedFilename: filename)
    }
    private func owns(_ original: LocalBlock) -> Bool {
        let expectedGap = appliedGapRevision?.targetID == original.target.id ? appliedGapRevision?.revision : nil
        return host.allows(editor: editor, chapterID: original.target.chapterID) && editor.isCurrentStarterLease(original.lease) && editor.storyTopologyRevision == original.topology &&
            editor.storyGapRevision == (expectedGap ?? original.gapRevision) &&
            editor.draft.chapters.first(where: { $0.id == original.target.chapterID })?.blocks?.contains(where: {
                $0.id == original.target.blockID && $0.kind == .audio
            }) == true
    }
    func isCurrent(_ original: Opening) -> Bool {
        guard owns(original.block), let source = editor.coordinator.storyAudioSource,
              ObjectIdentifier(source) == ObjectIdentifier(original.source), editor.coordinator.storyAudioJournal === original.journal else { return false }
        return source.isCurrent(session: original.block.lease.session)
    }
    func open(_ original: Opening) {
        guard presentation == nil, isCurrent(original),
              original.block.target.matches(editor.draft, identity: original.block.lease.identity, session: original.block.lease.session) else { return }
        appliedGapRevision = nil
        let flow = ProjectStoryAudioFlow(target: original.block.target, session: original.block.lease.session, identity: original.block.lease.identity,
            source: original.source, journal: original.journal, currentDraft: { [weak self] in self?.editor.draft },
            parentCurrent: { [weak self] in self?.isCurrent(original) == true })
        presentation = .init(opening: original, flow: flow)
    }
    func apply(_ original: Presentation) {
        guard presentation?.id == original.id, isCurrent(original.opening), let next = original.flow.draftForApply() else { return }
        guard editor.persistLocalChange(next, lease: original.opening.block.lease) else { original.flow.localSaveFailed(); return }
        guard presentation?.id == original.id, host.allows(editor: editor, chapterID: original.opening.block.target.chapterID),
              editor.isCurrentStarterLease(original.opening.block.lease),
              let expected = ProjectEditPendingMaterials.exactData(next), ProjectEditPendingMaterials.exactData(editor.draft) == expected else { close(original); return }
        appliedGapRevision = (original.opening.block.target.id, editor.storyGapRevision)
        original.flow.didSaveAppliedDraft()
        if original.flow.state == .applied { close(original) }
    }
    /// Existing Mini action: keep a real empty audio block after a cancelled document picker.
    @discardableResult func insertEmpty(chapterID: String, lease: ProjectEditStarterController.Lease?, topology: Int, draftHash: String?) -> String? {
        guard host.allows(editor: editor, chapterID: chapterID), let lease, editor.isCurrentStarterLease(lease), editor.storyTopologyRevision == topology,
              let raw = ProjectEditPendingMaterials.exactData(editor.draft), ProjectStoryImageTarget.hash(raw) == draftHash,
              let index = editor.draft.chapters.firstIndex(where: { $0.id == chapterID }),
              ProjectEditStarterPolicy.usesStoryEditor(product: editor.draft.product, chapter: editor.draft.chapters[index]),
              let count = editor.draft.chapters[index].blocks?.count, count < 200 else { return nil }
        let audio = ProjectEditBlock(kind: .audio); var next = editor.draft; next.chapters[index].blocks?.append(audio)
        guard editor.persistLocalChange(next, lease: lease) else { return nil }; return audio.id
    }
    func remove(_ original: LocalBlock) {
        guard owns(original), original.target.matches(editor.draft, identity: original.lease.identity, session: original.lease.session),
              let index = editor.draft.chapters.firstIndex(where: { $0.id == original.target.chapterID }) else { return }
        var next = editor.draft; next.chapters[index].blocks?.removeAll { $0.id == original.target.blockID && $0.kind == .audio }
        _ = editor.persistLocalChange(next, lease: original.lease)
    }
    func close(_ original: Presentation) {
        original.flow.close(); guard presentation?.id == original.id else { return }; presentation = nil; appliedGapRevision = nil
    }
    func binding(_ original: Presentation?) -> Binding<Presentation?> {
        .init(get: { guard let original, self.presentation?.id == original.id, self.isCurrent(original.opening) else { return nil }; return original },
              set: { value in if value == nil, let original { self.close(original) } })
    }
}
