import Foundation

/// Author-selected local examples, never player rolls, receipts, scores, or persisted draft values.
public struct TemplateD6Rehearsal: Equatable {
    public struct Sample: Equatable {
        public let pips: [Int]
        public let total: Int
        public let action: String?
    }
    public let diceCount: Int
    public let kicker: String
    public let faces: [String]

    public init(draft: TemplateAdvancedDraft) throws {
        guard draft.enabled("diceRoll"), draft.diceMode == "d6", let fields = draft.value["diceRoll"]?.object,
              fields["mode"] == nil || fields["mode"]?.string == "d6" else {
            throw TemplateAuthoringError.invalidDraft
        }
        // Validate the configured game with the existing contract, without unrelated families
        // blocking a local inspection or rewriting the author's coexisting configuration.
        var isolated = TemplateAdvancedDraft()
        isolated.value["diceRoll"] = .object(fields)
        guard isolated.issues.isEmpty else { throw TemplateAuthoringError.invalidDraft }
        if let rawCount = fields["diceCount"] {
            guard let count = rawCount.integer, (1...2).contains(count) else {
                throw TemplateAuthoringError.invalidDraft
            }
        }
        diceCount = fields["diceCount"]?.integer ?? 1
        kicker = draft.text("diceRoll", "kicker").trimmingCharacters(in: .whitespacesAndNewlines)
        faces = (fields["faces"]?.array ?? []).map { ($0.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
    }
    public func sample(pips: [Int]) throws -> Sample {
        guard pips.count == diceCount, pips.allSatisfy({ (1...6).contains($0) }) else { throw TemplateAuthoringError.invalidDraft }
        return .init(pips: pips, total: pips.reduce(0, +), action: diceCount == 1 ? faces[pips[0] - 1] : nil)
    }
}
