import SwiftUI

@MainActor final class ProjectEditStarterController: ObservableObject {
    struct Lease: Equatable {
        let session: ProjectEditSession
        let identity: ProjectEditDraftIdentity
        let product: ProjectEditProduct
        let owner: ProjectEditOwner
        let baseRevision: [UInt8]
        let incarnation: UUID
        let structureRevision: Int
    }
    struct Destination: Identifiable, Equatable {
        let id = UUID()
        let lease: Lease
        let chapterID: String
        let kind: ProjectEditStarterPolicy.Destination
        let opening: Bool
    }
    let model: ProjectEditModel
    @Published private(set) var destination: Destination?
    @Published private(set) var candidate = ProjectEditNode() {
        didSet { candidateRevision += 1 }
    }
    private(set) var candidateRevision = 0
    @Published private(set) var saveUnconfirmed = false
    init(model: ProjectEditModel) { self.model = model }

    func createChapter(lease: Lease?, name: String) {
        guard let lease, model.isCurrentStarterLease(lease) else { return }
        if let destination, isCurrent(destination) { return }
        destination = nil; candidate = .init(); saveUnconfirmed = false
        let hadChapters = !model.draft.chapters.isEmpty
        let chapter = ProjectEditStarterPolicy.chapter(name: name, product: lease.product)
        model.draft.chapters.append(chapter); model.changed()
        guard let current = model.captureStarterLease(),
              let kind = ProjectEditStarterPolicy.destination(product: current.product, chapter: chapter, hadChapters: hadChapters) else { return }
        destination = .init(lease: current, chapterID: chapter.id, kind: kind, opening: false)
    }
    func isCurrent(_ value: Destination) -> Bool {
        destination?.id == value.id && destination?.lease == value.lease && model.isCurrentStarterChapter(value)
    }
    func node(for value: Destination) -> Binding<ProjectEditNode> {
        Binding(get: { self.isCurrent(value) && value.kind == .firstNode ? self.candidate : .init() }, set: { next in
            guard self.isCurrent(value), value.kind == .firstNode, next.id == self.candidate.id else { return }
            self.candidate = next
        })
    }
    func canFinish(_ value: Destination) -> Bool {
        isCurrent(value) && value.kind == .firstNode && ProjectEditPendingMaterials.canSave(candidate)
    }
    func willSaveToPending(_ value: Destination) -> Bool {
        isCurrent(value) && value.kind == .firstNode && !ProjectEditStarterPolicy.canAddFormalNode(candidate)
    }
    func finish(_ value: Destination) {
        guard canFinish(value), let index = model.draft.chapters.firstIndex(where: { $0.id == value.chapterID }),
              model.draft.chapters[index].nodes.isEmpty, model.draft.chapters[index].blocks == nil,
              (model.draft.chapters[index].preserved["ending"] == nil || model.draft.chapters[index].preserved["ending"] == .null) else { return }
        // Chapters and pending materials share the same saved draft envelope.
        var next = model.draft
        if ProjectEditStarterPolicy.canAddFormalNode(candidate) { next.chapters[index].nodes.append(candidate) }
        else {
            guard let staged = try? ProjectEditPendingMaterials.saving(candidate, in: next) else { return }
            next = staged
        }
        guard model.persistLocalChange(next, lease: value.lease) else { saveUnconfirmed = true; return }
        close(value)
    }
    func close(_ value: Destination) {
        guard destination?.id == value.id, destination?.lease == value.lease else { return }
        destination = nil; candidate = .init(); saveUnconfirmed = false; model.invalidateStarterLease()
    }
    func retire() { destination = nil; candidate = .init(); saveUnconfirmed = false; model.invalidateStarterLease() }
}

@MainActor extension ProjectEditModel {
    func captureStarterLease() -> ProjectEditStarterController.Lease? {
        guard fullEdit, let session = coordinator.session, let identity = coordinator.identity,
              let baseline = coordinator.snapshot, baseline.draft.product == draft.product,
              baseline.draft.owner == draft.owner,
              baseline.draft.baseRevision.utf8.elementsEqual(draft.baseRevision.utf8) else { return nil }
        return .init(session: session, identity: identity, product: draft.product, owner: draft.owner,
                     baseRevision: Array(draft.baseRevision.utf8), incarnation: editorIncarnation, structureRevision: structureRevision)
    }
    func isCurrentStarterLease(_ lease: ProjectEditStarterController.Lease) -> Bool { captureStarterLease() == lease }
    func isCurrentStarterChapter(_ value: ProjectEditStarterController.Destination) -> Bool {
        guard isCurrentStarterLease(value.lease), let chapter = draft.chapters.first(where: { $0.id == value.chapterID }),
              (chapter.preserved["opening"] == .bool(true)) == value.opening else { return false }
        switch value.kind {
        case .story: return ProjectEditStarterPolicy.usesStoryEditor(product: draft.product, chapter: chapter)
        case .firstNode: return draft.product == .freeExplore && !value.opening && chapter.blocks == nil && chapter.nodes.isEmpty && (chapter.preserved["ending"] == nil || chapter.preserved["ending"] == .null)
        }
    }
    func starterChapter(_ value: ProjectEditStarterController.Destination) -> Binding<ProjectEditChapter> {
        Binding(get: { self.isCurrentStarterChapter(value) ? self.chapter(value.chapterID).wrappedValue : .init() }, set: { next in
            guard self.isCurrentStarterChapter(value), next.id == value.chapterID else { return }
            self.chapter(value.chapterID).wrappedValue = next
        })
    }
}
