import Foundation

/// The free-exploration delete action moves whole nodes into the same draft's
/// pending list. City story deletion and pending-material deletion are separate.
public enum ProjectPendingNodeRemoval {
    public struct Receipt {
        public let before: ProjectEditDraft
        public let after: ProjectEditDraft
        public let nodeIDs: [String]
    }
    public static func moving(_ ids: [String], chapterID: String, in draft: ProjectEditDraft) throws -> Receipt {
        try ProjectEditPendingMaterials.validateIDs(draft)
        guard draft.product == .freeExplore, !ids.isEmpty, Set(ids).count == ids.count,
              let index = draft.chapters.firstIndex(where: { $0.id == chapterID }),
              draft.chapters[index].blocks == nil,
              draft.chapters[index].preserved["opening"] != .bool(true),
              draft.chapters[index].preserved["ending"] == nil || draft.chapters[index].preserved["ending"] == .null,
              draft.preserved["routeMode"] == nil || draft.preserved["routeMode"] == .null || draft.preserved["routeMode"] == .string("LINEAR"),
              draft.preserved["routeGraphJson"] == nil || draft.preserved["routeGraphJson"] == .null || draft.preserved["routeGraphJson"] == .string("") else {
            throw ProjectEditError.invalidDraft
        }
        let selected = Set(ids), nodes = draft.chapters[index].nodes.filter { selected.contains($0.id) }
        guard nodes.count == ids.count else { throw ProjectEditError.staleConfirmation }
        var next = draft
        next.chapters[index].nodes.removeAll { selected.contains($0.id) }
        next.pendingMaterials = (draft.pendingMaterials ?? []) + nodes.map { .init(node: $0, kind: .node) }
        try ProjectEditPendingMaterials.validateIDs(next)
        return .init(before: draft, after: next, nodeIDs: nodes.map(\.id))
    }
    public static func restoring(_ receipt: Receipt, in current: ProjectEditDraft) throws -> ProjectEditDraft {
        guard let expected = ProjectEditPendingMaterials.exactData(receipt.after),
              let actual = ProjectEditPendingMaterials.exactData(current), actual == expected,
              current.product == .freeExplore, receipt.before.product == current.product,
              receipt.before.owner == current.owner,
              receipt.before.baseRevision.utf8.elementsEqual(current.baseRevision.utf8) else {
            throw ProjectEditError.staleConfirmation
        }
        try ProjectEditPendingMaterials.validateIDs(receipt.before)
        return receipt.before
    }
    public static func combining(_ previous: Receipt, with next: Receipt) throws -> Receipt {
        guard let expected = ProjectEditPendingMaterials.exactData(previous.after),
              ProjectEditPendingMaterials.exactData(next.before) == expected,
              Set(previous.nodeIDs).isDisjoint(with: next.nodeIDs) else { throw ProjectEditError.staleConfirmation }
        return .init(before: previous.before, after: next.after, nodeIDs: previous.nodeIDs + next.nodeIDs)
    }
}
