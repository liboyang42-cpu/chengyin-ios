import Foundation

/// Changes only the value of an existing HAS_TAG predicate on a real voice block.
public enum ProjectStoryConditionChoice {
    public struct Target {
        public let chapterID: String, blockID: String, blockBytes: Data
        public init(draft: ProjectEditDraft, chapterID: String, blockID: String) throws {
            guard let (ci, bi) = ProjectStoryConditionChoice.indices(draft, chapterID: chapterID, blockID: blockID),
                  let block = draft.chapters[ci].blocks?[bi], block.sourceFields?["when"]?.object?["op"] == .string("HAS_TAG"),
                  let bytes = ProjectEditPendingMaterials.exactData(block) else { throw ProjectEditError.invalidDraft }
            self.chapterID = chapterID; self.blockID = blockID; blockBytes = bytes
        }
    }
    private static func indices(_ draft: ProjectEditDraft, chapterID: String, blockID: String) -> (Int, Int)? {
        guard draft.product == .city, !chapterID.isEmpty, !blockID.isEmpty else { return nil }
        let chapters = draft.chapters.indices.filter { draft.chapters[$0].id == chapterID }
        guard chapters.count == 1, let ci = chapters.first, draft.chapters[ci].id.utf8.elementsEqual(chapterID.utf8),
              let blocks = draft.chapters[ci].blocks else { return nil }
        let matches = blocks.indices.filter { blocks[$0].id == blockID }
        guard matches.count == 1, let bi = matches.first, blocks[bi].id.utf8.elementsEqual(blockID.utf8), blocks[bi].kind == .voice else { return nil }
        return (ci, bi)
    }
    public static func currentValue(_ target: Target, in draft: ProjectEditDraft) -> ProjectEditJSON? {
        guard let (ci, bi) = indices(draft, chapterID: target.chapterID, blockID: target.blockID) else { return nil }
        return draft.chapters[ci].blocks?[bi].sourceFields?["when"]?.object?["value"]
    }
    public static func applying(_ choice: ProjectEndingConditionChoices.Choice, to draft: ProjectEditDraft, target: Target) throws -> ProjectEditDraft {
        guard let (ci, bi) = indices(draft, chapterID: target.chapterID, blockID: target.blockID),
              let block = draft.chapters[ci].blocks?[bi], ProjectEditPendingMaterials.exactData(block) == target.blockBytes,
              var condition = block.sourceFields?["when"]?.object, condition["op"] == .string("HAS_TAG"),
              ProjectEndingConditionChoices.choices(in: draft, operation: "HAS_TAG").contains(where: {
                  $0.id == choice.id && ProjectEditPendingMaterials.exactData($0.value) == ProjectEditPendingMaterials.exactData(choice.value)
              }) else { throw ProjectEditError.invalidDraft }
        if condition["value"].flatMap({ ProjectEditPendingMaterials.exactData($0) }) == ProjectEditPendingMaterials.exactData(choice.value) { return draft }
        condition["value"] = choice.value
        var next = draft; next.chapters[ci].blocks?[bi].setField("when", .object(condition)); return next
    }
}
