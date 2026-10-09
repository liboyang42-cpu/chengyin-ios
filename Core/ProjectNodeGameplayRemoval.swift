import Foundation

/// Removes one ordinary place node's template association, never the template itself.
public enum ProjectNodeGameplayRemoval {
    public static func index(chapterID: String, nodeID: String, in draft: ProjectEditDraft) -> (chapter: Int, node: Int)? {
        guard !chapterID.isEmpty, !nodeID.isEmpty else { return nil }
        switch draft.preserved["routeMode"] { case nil, .null?, .string("LINEAR")?: break; default: return nil }
        switch draft.preserved["routeGraphJson"] {
        case nil, .null?: break
        case .string(let raw)?: guard raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        default: return nil
        }
        let chapters = draft.chapters.indices.filter { draft.chapters[$0].id == chapterID }
        guard chapters.count == 1, let ci = chapters.first, draft.chapters[ci].id.utf8.elementsEqual(chapterID.utf8) else { return nil }
        let chapter = draft.chapters[ci]
        guard chapter.preserved["opening"] == nil || chapter.preserved["opening"] == .null || chapter.preserved["opening"] == .bool(false),
              chapter.preserved["ending"] == nil || chapter.preserved["ending"] == .null,
              draft.chapters.flatMap(\.nodes).filter({ $0.id == nodeID }).count == 1 else { return nil }
        let nodes = chapter.nodes.indices.filter { chapter.nodes[$0].id == nodeID }
        guard nodes.count == 1, let ni = nodes.first, chapter.nodes[ni].id.utf8.elementsEqual(nodeID.utf8) else { return nil }
        let blocks = (chapter.blocks ?? []).filter { $0.kind == .node && $0.nodeID == nodeID }
        guard blocks.count <= 1, blocks.allSatisfy({
            $0.nodeID.utf8.elementsEqual(nodeID.utf8) && ($0.sourceFields?["locationRequired"] == nil || $0.sourceFields?["locationRequired"] == .bool(true))
        }), chapter.nodes[ni].localMetadata["_storyGame"] == nil || chapter.nodes[ni].localMetadata["_storyGame"] == .null || chapter.nodes[ni].localMetadata["_storyGame"] == .bool(false) else { return nil }
        return (ci, ni)
    }
    public static func clearing(chapterID: String, nodeID: String, in draft: ProjectEditDraft) throws -> ProjectEditDraft {
        guard let index = index(chapterID: chapterID, nodeID: nodeID, in: draft) else { throw ProjectEditError.invalidDraft }
        guard (draft.chapters[index.chapter].nodes[index.node].templateID ?? 0) > 0 else { return draft }
        var next = draft
        next.chapters[index.chapter].nodes[index.node].templateID = nil
        // Only these actual mini companion fields belong to the explicit unbind action.
        if next.chapters[index.chapter].nodes[index.node].localMetadata["templateId"] != nil { next.chapters[index.chapter].nodes[index.node].localMetadata["templateId"] = .number(0) }
        if next.chapters[index.chapter].nodes[index.node].localMetadata["templateInfo"] != nil { next.chapters[index.chapter].nodes[index.node].localMetadata["templateInfo"] = .object([:]) }
        if next.chapters[index.chapter].nodes[index.node].localMetadata["templateName"] != nil { next.chapters[index.chapter].nodes[index.node].localMetadata["templateName"] = .string("") }
        return next
    }
}
