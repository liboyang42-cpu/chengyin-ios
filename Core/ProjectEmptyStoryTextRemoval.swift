import Foundation

/// An exact ordinary paragraph target. Rich/source-bearing blocks are retained.
/// Removal is an explicit editing-completion action, never an input side effect.
public struct ProjectEmptyStoryTextRemoval {
    public enum Reason: String { case identity, unsupported }
    public let chapterID: String, blockID: String
    public private(set) var reason: Reason?
    public private(set) var content = ""
    private var bytes: Data?
    private var chapterIndex = 0, blockIndex = 0
    public static func supports(_ block: ProjectEditBlock) -> Bool {
        block.kind == .text && block.nodeID.isEmpty && block.url.isEmpty && block.localAudio == nil &&
        (block.sourceFields == nil || block.sourceFields?.isEmpty == true)
    }
    public init(draft: ProjectEditDraft, chapterID: String, blockID: String) {
        self.chapterID = chapterID; self.blockID = blockID
        // Reject both exact duplicates and canonical aliases used by existing UI
        // identity. Select the actual target using UTF-8 identity only.
        let chapters = draft.chapters.indices.filter { draft.chapters[$0].id == chapterID }
        guard !chapterID.isEmpty, !blockID.isEmpty, chapters.count == 1, let ci = chapters.first,
              draft.chapters[ci].id.utf8.elementsEqual(chapterID.utf8),
              draft.chapters.flatMap({ $0.blocks ?? [] }).filter({ $0.id == blockID }).count == 1,
              let blocks = draft.chapters[ci].blocks,
              let bi = blocks.firstIndex(where: { $0.id.utf8.elementsEqual(blockID.utf8) }),
              let bytes = ProjectEditPendingMaterials.exactData(draft) else { reason = .identity; return }
        content = blocks[bi].content
        guard draft.chapters[ci].schemaVersion == 1, Self.supports(blocks[bi]) else { reason = .unsupported; return }
        self.bytes = bytes; chapterIndex = ci; blockIndex = bi
    }
    /// ECMAScript String.trim WhiteSpace + LineTerminator scalar set. This is not
    /// Foundation's whitespace set and does not trim or normalize stored text.
    public static func isEmptyAfterECMAScriptTrim(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 0x0009...0x000D, 0x0020, 0x00A0, 0x1680, 0x2000...0x200A,
                 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF: return true
            default: return false
            }
        }
    }
    public var isEmpty: Bool { Self.isEmptyAfterECMAScriptTrim(content) }
    public func isCurrent(in draft: ProjectEditDraft) -> Bool {
        reason == nil && bytes != nil && ProjectEditPendingMaterials.exactData(draft) == bytes
    }
    public func replacingContent(with text: String, in draft: ProjectEditDraft) throws -> ProjectEditDraft {
        guard isCurrent(in: draft) else { throw ProjectEditError.staleConfirmation }
        guard !content.utf8.elementsEqual(text.utf8) else { return draft }
        var next = draft; next.chapters[chapterIndex].blocks?[blockIndex].content = text; return next
    }
    public func removingIfEmpty(in draft: ProjectEditDraft) throws -> ProjectEditDraft {
        guard isCurrent(in: draft) else { throw ProjectEditError.staleConfirmation }
        guard isEmpty else { return draft }
        var next = draft; next.chapters[chapterIndex].blocks?.remove(at: blockIndex)
        // No neighboring merge, node mutation or description reconstruction.
        // Existing story serialization owns the derived wire description.
        return next
    }
}
