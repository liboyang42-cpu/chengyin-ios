import Foundation

/// Native local-envelope representation of mini's pending material. The full node retains
/// local identity, raw text, duration and all gameplay metadata; this is not a wire schema.
public struct ProjectEditPendingMaterial: Identifiable, Codable, Equatable {
    public enum Kind: String, Codable { case node, place }
    public var kind: Kind
    public var node: ProjectEditNode
    public var id: String { node.id }
    public init(node: ProjectEditNode, kind: Kind = .node) { self.node = node; self.kind = kind }
}

public enum ProjectEditPendingMaterials {
    public static func exactData<T: Encodable>(_ value: T) -> Data? {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(value)
    }
    public static func canSave(_ node: ProjectEditNode) -> Bool {
        !node.id.isEmpty && !node.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && node.nodeTime >= 0
    }
    static func validateIDs(_ draft: ProjectEditDraft) throws {
        let chapters = draft.chapters.map(\.id)
        let ids = draft.chapters.flatMap { $0.nodes.map(\.id) } + (draft.pendingMaterials ?? []).map(\.id)
        guard Set(chapters).count == chapters.count, Set(ids).count == ids.count,
              !ids.contains(where: \.isEmpty) else { throw ProjectEditError.invalidDraft }
    }
    public static func saving(_ node: ProjectEditNode, replacing existingID: String? = nil,
                              kind: ProjectEditPendingMaterial.Kind = .node, in draft: ProjectEditDraft) throws -> ProjectEditDraft {
        try validateIDs(draft); guard canSave(node) else { throw ProjectEditError.invalidDraft }
        var copy = draft, rows = draft.pendingMaterials ?? []
        if let existingID {
            guard node.id == existingID, let index = rows.firstIndex(where: { $0.id == existingID }) else { throw ProjectEditError.staleConfirmation }
            rows[index].node = node // Keep the original material kind and all node metadata.
        } else {
            guard !rows.contains(where: { $0.id == node.id }), !draft.chapters.contains(where: { $0.nodes.contains(where: { $0.id == node.id }) }) else { throw ProjectEditError.invalidDraft }
            rows.append(.init(node: node, kind: kind))
        }
        copy.pendingMaterials = rows; return copy
    }
    public static func removing(_ id: String, from draft: ProjectEditDraft) throws -> ProjectEditDraft {
        try validateIDs(draft); guard draft.pendingMaterials?.contains(where: { $0.id == id }) == true else { throw ProjectEditError.staleConfirmation }
        var copy = draft; copy.pendingMaterials?.removeAll { $0.id == id }; return copy
    }
    public static func materializingStory(chapterID: String, in draft: ProjectEditDraft) throws -> ProjectEditDraft {
        try validateIDs(draft)
        guard draft.product == .city, let index = draft.chapters.firstIndex(where: { $0.id == chapterID }),
              draft.chapters[index].preserved["opening"] != .bool(true), draft.chapters[index].preserved["ending"]?.object == nil,
              draft.chapters[index].schemaVersion == 1, draft.chapters[index].required == 1 else { throw ProjectEditError.invalidDraft }
        var copy = draft
        if copy.chapters[index].blocks == nil {
            let chapter = copy.chapters[index]
            copy.chapters[index].blocks = [.init(kind: .text, content: chapter.description)] + chapter.nodes.map { .init(kind: .node, nodeID: $0.id) }
        }
        return copy
    }
    public static func arranging(_ id: String, into chapterID: String, before blockID: String? = nil,
                                 expectedBlocks: [String]? = nil, in draft: ProjectEditDraft) throws -> ProjectEditDraft {
        try validateIDs(draft)
        guard let material = draft.pendingMaterials?.first(where: { $0.id == id }),
              ProjectEditStarterPolicy.canAddFormalNode(material.node),
              let index = draft.chapters.firstIndex(where: { $0.id == chapterID }),
              draft.chapters[index].preserved["opening"] != .bool(true), draft.chapters[index].preserved["ending"]?.object == nil else { throw ProjectEditError.invalidDraft }
        var copy = draft
        if draft.product == .city {
            guard draft.chapters[index].hasRealStory, draft.chapters[index].schemaVersion == 1, draft.chapters[index].required == 1, var blocks = draft.chapters[index].blocks,
                  blocks.count < 200, let expectedBlocks, blocks.map(\.id) == expectedBlocks else { throw ProjectEditError.storyRequired }
            let insertion: Int
            if let blockID { guard let found = blocks.firstIndex(where: { $0.id == blockID }) else { throw ProjectEditError.staleConfirmation }; insertion = found }
            else { insertion = blocks.count }
            blocks.insert(.init(kind: .node, nodeID: material.id), at: insertion); copy.chapters[index].blocks = blocks
        } else {
            // A stored future/legacy flow cannot be silently flattened into the free-node list.
            guard draft.chapters[index].blocks == nil, blockID == nil, expectedBlocks == nil else { throw ProjectEditError.invalidDraft }
        }
        copy.chapters[index].nodes.append(material.node)
        copy.pendingMaterials?.removeAll { $0.id == id }
        return copy
    }
}
