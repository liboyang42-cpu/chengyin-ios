import Foundation

/// Author-local comparison against the current draft, not a gameplay judge.
/// This value is never a PlayAdvancedState, a completion receipt or a network payload.
public struct TemplateReasoningRehearsal: Equatable {
    public enum Result: String, Equatable { case ready, matched, missed, invalid }
    public let game: TemplateAdvancedGame
    public let segment: PlayWireValue
    private let expected: [String: PlayWireValue]
    public private(set) var result: Result = .ready
    public var canSubmit: Bool { result == .ready }
    public var action: String {
        switch game { case .sort: return "SUBMIT_SORT"; case .match: return "SUBMIT_MATCH"; default: return "SUBMIT_CLASSIFY" }
    }

    public init?(_ original: TemplateAdvancedDraft, game: TemplateAdvancedGame) {
        guard game.isReasoning, original.enabled(game.section), original.miniGameIssues(game).isEmpty else { return nil }
        // Use the existing editor normalization. Sort order and paired rows are the
        // actual authoring source; stale imported answerOrder/pairs are not another truth.
        var draft = original
        draft.normalizeMiniGame(game)
        guard let publicSource = try? draft.miniPreviewSegment(game) else { return nil }
        let fields = draft.value[game.section]?.object ?? [:]
        func wire(_ value: TemplateAuthoringJSON?) -> PlayWireValue? {
            guard let value, let data = try? JSONEncoder().encode(value) else { return nil }
            return try? JSONDecoder().decode(PlayWireValue.self, from: data)
        }
        let expected: [String: PlayWireValue]
        switch game {
        case .sort:
            guard let answer = wire(fields["answerOrder"]) else { return nil }
            expected = ["order": answer]
        case .match:
            guard let answer = wire(fields["pairs"]) else { return nil }
            expected = ["pairs": answer]
        case .classify:
            guard let answer = wire(fields["answer"]) else { return nil }
            expected = ["placement": answer]
        default: return nil
        }
        // Render only the controls' allowlisted text fields. No answers, imported
        // status, media fetches, rewards or unknown extensions enter the form.
        var presentation: [String: PlayWireValue] = ["prompt": publicSource["prompt"]]
        let rowFields = game == .sort ? ["items"] : game == .match ? ["left", "right"] : ["items", "bins"]
        for field in rowFields {
            var rows = (publicSource[field].array ?? []).map { row in
                PlayWireValue.object(["id": row["id"], "label": row["label"]])
            }
            // Reproducible practice arrangement, deliberately different from the
            // authored answer order. Production shuffling still belongs to the server.
            if game == .sort, rows.count > 1 { rows.append(rows.removeFirst()) }
            if game == .match && field == "right" { rows.reverse() }
            presentation[field] = .array(rows)
        }
        let segment = PlayWireValue.object(presentation)
        let action = game == .sort ? "SUBMIT_SORT" : game == .match ? "SUBMIT_MATCH" : "SUBMIT_CLASSIFY"
        guard (try? PlayKitInputContract.validate(kind: game.section, action: action, payload: expected, segment: segment)) != nil else { return nil }
        self.game = game; self.segment = segment; self.expected = expected
    }

    /// One local comparison per form lifetime. Reset starts another isolated try.
    @discardableResult public mutating func submit(action: String, payload: [String: PlayWireValue]) -> Bool {
        guard canSubmit else { return false }
        guard action == self.action,
              (try? PlayKitInputContract.validate(kind: game.section, action: action, payload: payload, segment: segment)) != nil else {
            result = .invalid; return true
        }
        if game == .match {
            // Pair row order is presentation only. The exact one-to-one mapping matters.
            result = Self.pairMap(payload["pairs"]) == Self.pairMap(expected["pairs"]) ? .matched : .missed
        } else {
            result = payload == expected ? .matched : .missed
        }
        return true
    }
    public mutating func reset() { result = .ready }
    private static func pairMap(_ value: PlayWireValue?) -> [String: String] {
        var result: [String: String] = [:]
        for pair in value?.array ?? [] {
            if let row = pair.array, row.count == 2, let left = row[0].text, let right = row[1].text { result[left] = right }
        }
        return result
    }
}
