import SwiftUI

@MainActor final class ProjectEditPendingController: ObservableObject {
    struct Target: Equatable {
        let lease: ProjectEditStarterController.Lease
        let materialID: String
        let materialRevision: Int
        let bytes: Data
    }
    struct NewChapterTarget {
        let material: Target
        let chapters: Data
    }
    struct Destination: Identifiable, Equatable {
        enum Kind: Equatable { case edit, remove, story(chapterID: String) }
        let id = UUID()
        let target: Target
        let kind: Kind
    }
    struct Slot {
        let destination: Destination
        let chapterID: String
        let beforeBlockID: String?
        let blocks: [String]
        let topologyRevision: Int
    }
    let model: ProjectEditModel
    @Published private(set) var destination: Destination?
    @Published private(set) var candidate = ProjectEditNode() {
        didSet { candidateRevision += 1 }
    }
    private(set) var candidateRevision = 0
    @Published private(set) var saveUnconfirmed = false
    @Published private(set) var actionUnavailable = false
    init(model: ProjectEditModel) { self.model = model }
    func capture(_ id: String) -> Target? {
        guard let lease = model.captureStarterLease(), let row = model.draft.pendingMaterials?.first(where: { $0.id == id }),
              let bytes = ProjectEditPendingMaterials.exactData(row) else { return nil }
        return .init(lease: lease, materialID: id, materialRevision: model.materialRevision, bytes: bytes)
    }
    func isCurrent(_ target: Target) -> Bool { capture(target.materialID) == target }
    func isCurrent(_ value: Destination) -> Bool {
        guard destination?.id == value.id, destination?.target == value.target, isCurrent(value.target) else { return false }
        if case .story(let id) = value.kind {
            guard model.draft.product == .city, let chapter = model.draft.chapters.first(where: { $0.id == id }),
                  chapter.preserved["opening"] != .bool(true), chapter.preserved["ending"]?.object == nil else { return false }
        }
        return true
    }
    func open(_ target: Target?, kind: Destination.Kind = .edit) {
        guard let target, isCurrent(target) else { return }
        if let destination, isCurrent(destination) { return }
        guard let row = model.draft.pendingMaterials?.first(where: { $0.id == target.materialID }) else { return }
        candidate = row.node; saveUnconfirmed = false; actionUnavailable = false
        destination = .init(target: target, kind: kind)
    }
    func node(for value: Destination) -> Binding<ProjectEditNode> {
        Binding(get: { self.isCurrent(value) ? self.candidate : .init() }, set: { next in
            guard self.isCurrent(value), value.kind == .edit, next.id == value.target.materialID else { return }
            self.candidate = next
        })
    }
    func canSave(_ value: Destination) -> Bool { isCurrent(value) && value.kind == .edit && ProjectEditPendingMaterials.canSave(candidate) }
    func save(_ value: Destination) {
        guard canSave(value), let next = try? ProjectEditPendingMaterials.saving(candidate, replacing: value.target.materialID, in: model.draft) else { return }
        guard model.persistLocalChange(next, lease: value.target.lease) else { saveUnconfirmed = true; return }
        close(value)
    }
    func remove(_ value: Destination) {
        guard isCurrent(value), value.kind == .remove,
              let next = try? ProjectEditPendingMaterials.removing(value.target.materialID, from: model.draft) else { return }
        guard model.persistLocalChange(next, lease: value.target.lease) else { saveUnconfirmed = true; return }
        close(value)
    }
    func captureNewChapter(_ id: String) -> NewChapterTarget? {
        guard let material = capture(id), let chapters = ProjectEditPendingMaterials.exactData(model.draft.chapters) else { return nil }
        return .init(material: material, chapters: chapters)
    }
    func createChapter(_ target: NewChapterTarget?, name: String) {
        guard let target, isCurrent(target.material),
              ProjectEditPendingMaterials.exactData(model.draft.chapters) == target.chapters,
              let material = model.draft.pendingMaterials?.first(where: { $0.id == target.material.materialID }) else { return }
        if let destination, isCurrent(destination) { return }
        if !ProjectEditStarterPolicy.canAddFormalNode(material.node) { open(target.material); return }
        guard let result = try? ProjectEditPendingChapter.create(for: material.id, name: name, in: model.draft) else { actionUnavailable = true; return }
        guard model.persistLocalChange(result.draft, lease: target.material.lease) else { saveUnconfirmed = true; return }
        saveUnconfirmed = false; actionUnavailable = false
        if model.draft.product == .city, let fresh = capture(material.id) {
            open(fresh, kind: .story(chapterID: result.chapterID))
        }
    }
    func chooseChapter(_ id: String, target: Target?) {
        guard let target, isCurrent(target), let row = model.draft.pendingMaterials?.first(where: { $0.id == target.materialID }) else { return }
        if let destination, isCurrent(destination) { return }
        if !ProjectEditStarterPolicy.canAddFormalNode(row.node) { open(target); return }
        if model.draft.product == .city {
            guard let next = try? ProjectEditPendingMaterials.materializingStory(chapterID: id, in: model.draft) else { actionUnavailable = true; return }
            guard model.persistLocalChange(next, lease: target.lease) else { saveUnconfirmed = true; return }
            guard let fresh = capture(target.materialID) else { return }
            open(fresh, kind: .story(chapterID: id))
        } else {
            guard let next = try? ProjectEditPendingMaterials.arranging(target.materialID, into: id, in: model.draft) else { actionUnavailable = true; return }
            guard model.persistLocalChange(next, lease: target.lease) else { saveUnconfirmed = true; return }
            actionUnavailable = false; saveUnconfirmed = false
        }
    }
    func storyChapter(_ value: Destination) -> Binding<ProjectEditChapter> {
        Binding(get: {
            guard self.isCurrent(value), case .story(let id) = value.kind else { return .init() }
            return self.model.chapter(id).wrappedValue
        }, set: { next in
            guard self.isCurrent(value), case .story(let id) = value.kind, next.id == id else { return }
            self.model.chapter(id).wrappedValue = next
        })
    }
    func slot(_ value: Destination, before blockID: String?) -> Slot? {
        guard isCurrent(value), case .story(let id) = value.kind, let blocks = storyChapter(value).wrappedValue.blocks else { return nil }
        return .init(destination: value, chapterID: id, beforeBlockID: blockID, blocks: blocks.map(\.id), topologyRevision: model.storyTopologyRevision)
    }
    func canInsert(_ value: Destination) -> Bool { isCurrent(value) && storyChapter(value).wrappedValue.hasRealStory && (storyChapter(value).wrappedValue.blocks?.count ?? 200) < 200 }
    func insert(_ slot: Slot?) {
        guard let slot, isCurrent(slot.destination), slot.topologyRevision == model.storyTopologyRevision,
              let next = try? ProjectEditPendingMaterials.arranging(slot.destination.target.materialID, into: slot.chapterID,
                before: slot.beforeBlockID, expectedBlocks: slot.blocks, in: model.draft) else { return }
        guard model.persistLocalChange(next, lease: slot.destination.target.lease) else { saveUnconfirmed = true; return }
        close(slot.destination)
    }
    func close(_ value: Destination) {
        // Successful commit rotates material revision; closure still owns its original presentation ID.
        guard destination?.id == value.id, destination?.target == value.target else { return }
        destination = nil; candidate = .init(); saveUnconfirmed = false; actionUnavailable = false
    }
    func retire() { destination = nil; candidate = .init(); saveUnconfirmed = false; actionUnavailable = false }
}
