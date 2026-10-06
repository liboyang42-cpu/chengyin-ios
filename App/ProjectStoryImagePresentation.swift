import SwiftUI

@MainActor final class ProjectStoryImagePresentation: ObservableObject {
    struct Opening {
        let lease: ProjectEditStarterController.Lease
        let target: ProjectStoryImageTarget
        let recoveryOnly: ProjectStoryImageJournal.Entry?
        let source: any ProjectStoryImageUploading
        let journal: ProjectStoryImageJournal
        let chapterName: String
        let savedReference: String?
        let storyTopologyRevision: Int
        let storyGapRevision: Int
    }
    struct Presentation: Identifiable {
        let opening: Opening
        let flow: ProjectStoryImageFlow
        var id: UUID { flow.id }
    }
    @Published private(set) var presentation: Presentation?
    private let editor: ProjectEditModel
    private var appliedTopology: (openingID: UUID, revision: Int, gapRevision: Int)?
    private let host: ProjectStoryMediaChapterHost
    init(editor: ProjectEditModel, host: ProjectStoryMediaChapterHost = .ordinary) {
        self.editor = editor; self.host = host
    }
    func capture(chapterID: String, replacing blockID: String? = nil, insertingBefore anchorID: String? = nil) -> Opening? {
        guard host.allows(editor: editor, chapterID: chapterID), presentation == nil, let lease = editor.captureStarterLease(),
              let source = editor.coordinator.storyImageSource, source.isCurrent(session: lease.session),
              let journal = editor.coordinator.storyImageJournal,
              let chapter = editor.draft.chapters.first(where: { $0.id == chapterID }), blockID == nil || anchorID == nil else { return nil }
        let fresh = try? ProjectStoryImageTarget(draft: editor.draft, identity: lease.identity, session: lease.session, chapterID: chapterID, replacing: blockID, insertingBefore: anchorID)
        var recovery: ProjectStoryImageJournal.Entry?
        // Capacity never grants a new insertion. Only an exact durable, unapplied receipt
        // for the already-saved postimage may reopen as a receipt-only presentation.
        if fresh == nil, blockID == nil, chapter.blocks?.count == 200,
           let saved = try? journal.read(session: lease.session, identity: lease.identity) {
            let action: ProjectStoryImageTarget.Action = anchorID.map(ProjectStoryImageTarget.Action.insertBefore) ?? .append
            let matches = saved.entries.filter { entry in
                guard !entry.applied, entry.target.chapterID == chapterID, entry.target.action == action,
                      let receipt = entry.receipt, receipt.reference.utf16.count <= 500,
                      source.permitsReference(receipt.reference, session: lease.session) else { return false }
                return entry.target.hasAppliedReference(receipt, in: editor.draft, identity: lease.identity, session: lease.session)
            }
            if matches.count == 1 { recovery = matches[0] }
        }
        guard let target = fresh ?? recovery?.target else { return nil }
        return .init(lease: lease, target: target, recoveryOnly: recovery, source: source, journal: journal, chapterName: chapter.name,
                     savedReference: blockID.flatMap { id in chapter.blocks?.first(where: { $0.id == id })?.url },
                     storyTopologyRevision: editor.storyTopologyRevision, storyGapRevision: editor.storyGapRevision)
    }
    func isCurrent(_ original: Opening) -> Bool {
        guard ownsContext(original) else { return false }
        let expected = appliedTopology?.openingID == original.target.id ? appliedTopology?.revision : nil
        let expectedGap = appliedTopology?.openingID == original.target.id ? appliedTopology?.gapRevision : nil
        return editor.storyTopologyRevision == (expected ?? original.storyTopologyRevision) &&
            editor.storyGapRevision == (expectedGap ?? original.storyGapRevision)
    }
    private func ownsContext(_ original: Opening) -> Bool {
        guard host.allows(editor: editor, chapterID: original.target.chapterID), editor.isCurrentStarterLease(original.lease), editor.editorIncarnation == original.lease.incarnation,
              editor.coordinator.session == original.lease.session, editor.coordinator.identity == original.lease.identity,
              let source = editor.coordinator.storyImageSource, ObjectIdentifier(source) == ObjectIdentifier(original.source),
              editor.coordinator.storyImageJournal === original.journal,
              let chapter = editor.draft.chapters.first(where: { $0.id == original.target.chapterID }),
              ProjectEditStarterPolicy.usesStoryEditor(product: editor.draft.product, chapter: chapter) else { return false }
        return source.isCurrent(session: original.lease.session)
    }
    func open(_ original: Opening) {
        guard presentation == nil, isCurrent(original), editor.isCurrentStarterLease(original.lease) else { return }
        if let recovery = original.recoveryOnly {
            guard editor.draft.chapters.first(where: { $0.id == original.target.chapterID })?.blocks?.count == 200,
                  recovery.target == original.target, !recovery.applied, let receipt = recovery.receipt,
                  let saved = try? original.journal.read(session: original.lease.session, identity: original.lease.identity),
                  saved.entries.contains(recovery), original.source.permitsReference(receipt.reference, session: original.lease.session),
                  original.target.hasAppliedReference(receipt, in: editor.draft, identity: original.lease.identity, session: original.lease.session) else { return }
        } else {
            guard original.target.matches(editor.draft, identity: original.lease.identity, session: original.lease.session) else { return }
        }
        appliedTopology = nil
        let flow = ProjectStoryImageFlow(target: original.target, session: original.lease.session, identity: original.lease.identity,
            source: original.source, journal: original.journal, recoveryOnly: original.recoveryOnly, currentDraft: { [weak self] in self?.editor.draft },
            parentCurrent: { [weak self] in self?.isCurrent(original) == true })
        presentation = .init(opening: original, flow: flow)
    }
    func apply(_ original: Presentation) {
        guard presentation?.id == original.id, isCurrent(original.opening),
              let next = original.flow.draftForApply() else { return }
        guard editor.persistLocalChange(next, lease: original.opening.lease) else { original.flow.localSaveFailed(); return }
        // Only this synchronous, exact successful draft save may advance the presentation's
        // topology. An external reorder/delete/restore, including ABA, cannot borrow it.
        guard presentation?.id == original.id, ownsContext(original.opening),
              let expected = ProjectEditPendingMaterials.exactData(next),
              ProjectEditPendingMaterials.exactData(editor.draft) == expected else { close(original); return }
        appliedTopology = (original.opening.target.id, editor.storyTopologyRevision, editor.storyGapRevision)
        original.flow.didSaveAppliedDraft()
        if original.flow.state == .applied { close(original) }
    }
    func close(_ original: Presentation) {
        original.flow.close()
        guard presentation?.id == original.id else { return }
        presentation = nil; appliedTopology = nil
    }
    func binding(_ original: Presentation?) -> Binding<Presentation?> {
        .init(get: {
            guard let original, self.presentation?.id == original.id, self.isCurrent(original.opening) else { return nil }; return original
        }, set: { next in if next == nil, let original { self.close(original) } })
    }
}
