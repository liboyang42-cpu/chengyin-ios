import Foundation

/// Server-projected question and whole-answer receipt only. No answer or per-row
/// correctness is retained. Timeline order and opaque IDs are part of the question.
public struct PlayCompareQuestion: Equatable {
    public struct Item: Equatable, Identifiable {
        public let id: String; public let time: String; public let text: String
    }
    public struct Side: Equatable {
        public let label: String; public let items: [Item]
    }
    public let prompt: String; public let left: Side; public let right: Side
    public let maxAttempts: Int; public let attempts: Int; public let remainingAttempts: Int?
    public let finished: Bool; public let passed: Bool; public let lastCorrect: Bool
    public let lastMarked: [String]
    public var items: [Item] { left.items + right.items }
    public var knownIDs: Set<String> { Set(items.map(\.id)) }
    public init(_ segment: PlayWireValue) throws {
        func text(_ value: PlayWireValue, limit: Int) throws -> String {
            guard let text = value.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf16.count <= limit else { throw PlayExperienceError.malformed }
            return text
        }
        var known = Set<String>()
        func side(_ raw: PlayWireValue) throws -> Side {
            let label = try text(raw["label"], limit: 20)
            guard let rows = raw["items"].array, (2...20).contains(rows.count) else { throw PlayExperienceError.malformed }
            let items = try rows.map { row -> Item in
                let id = try text(row["id"], limit: 32)
                guard id.range(of: "^[A-Za-z0-9_-]{1,32}$", options: .regularExpression) != nil, known.insert(id).inserted else { throw PlayExperienceError.malformed }
                return Item(id: id, time: try text(row["time"], limit: 16), text: try text(row["text"], limit: 200))
            }
            return Side(label: label, items: items)
        }
        prompt = try text(segment["prompt"], limit: 200)
        left = try side(segment["left"]); right = try side(segment["right"])
        guard let cap = segment["maxAttempts"].integer, (0...10).contains(cap),
              let attempts = segment["attempts"].integer, attempts >= 0,
              let finished = segment["finished"].bool, let passed = segment["passed"].bool,
              let correct = segment["lastCorrect"].bool, let marked = segment["lastMarked"].array else { throw PlayExperienceError.malformed }
        let ids = marked.compactMap(\.text)
        guard ids.count == marked.count, Set(ids).count == ids.count, Set(ids).isSubset(of: known), !passed || finished else { throw PlayExperienceError.malformed }
        if cap > 0 {
            guard let remaining = segment["remainingAttempts"].integer, remaining == max(0, cap - attempts) else { throw PlayExperienceError.malformed }
            remainingAttempts = remaining
        } else {
            guard segment["remainingAttempts"] == .null else { throw PlayExperienceError.malformed }
            remainingAttempts = nil
        }
        maxAttempts = cap; self.attempts = attempts; self.finished = finished; self.passed = passed
        lastCorrect = correct; lastMarked = ids
    }
    /// Empty selections are valid submissions. A correct answer is never guessed here.
    public func payload(marked: [String]) throws -> [String: PlayWireValue] {
        guard !finished, Set(marked).count == marked.count, Set(marked).isSubset(of: knownIDs) else { throw PlayExperienceError.invalidAction }
        return ["marked": .array(marked.map(PlayWireValue.string))]
    }
    public func validate(_ payload: [String: PlayWireValue]) throws {
        guard Set(payload.keys) == ["marked"], let rows = payload["marked"]?.array else { throw PlayExperienceError.invalidAction }
        let ids = rows.compactMap(\.text)
        guard ids.count == rows.count else { throw PlayExperienceError.invalidAction }
        _ = try self.payload(marked: ids)
    }
}

/// A draft cannot silently rebase onto a changed session/version. Refreshing the
/// receipt is explicit and does not send an action or mutate readiness/rewards.
public struct PlayCompareSelection: Equatable {
    public private(set) var revision: String?
    public private(set) var marked = Set<String>()
    public init() {}
    public mutating func restore(_ question: PlayCompareQuestion, revision: String) {
        self.revision = revision; marked = Set(question.lastMarked)
    }
    public mutating func toggle(_ id: String, question: PlayCompareQuestion, revision: String) {
        guard self.revision == revision, !question.finished, question.knownIDs.contains(id) else { return }
        if marked.contains(id) { marked.remove(id) } else { marked.insert(id) }
    }
    public func payload(_ question: PlayCompareQuestion, revision: String) throws -> [String: PlayWireValue] {
        guard self.revision == revision else { throw PlayExperienceError.staleSession }
        return try question.payload(marked: question.items.map(\.id).filter { marked.contains($0) })
    }
}
