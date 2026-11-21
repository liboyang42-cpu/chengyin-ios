import Foundation

/// Story framing for a station game: 「第N站 · 站名」, its chapter and the station's
/// lead line. Read only from the current route read; nothing is invented when a
/// field is missing, so a nil part simply is not shown.
public struct PlayGameStage: Equatable {
    public let ordinal: Int?
    public let stationName: String?
    public let chapterTitle: String?
    public let lead: String?

    public init(ordinal: Int?, stationName: String?, chapterTitle: String?, lead: String?) {
        self.ordinal = ordinal.flatMap { $0 > 0 ? $0 : nil }
        self.stationName = Self.clean(stationName)
        self.chapterTitle = Self.clean(chapterTitle)
        self.lead = Self.leadLine(lead)
    }

    /// True when there is anything worth drawing above the game.
    public var isEmpty: Bool { ordinal == nil && stationName == nil && chapterTitle == nil && lead == nil }

    /// Stations are numbered in route order: `sortId` when every station carries
    /// one, otherwise the order the server returned them. Hidden stations keep their
    /// place so numbers never shift as the route unfolds.
    public static func resolve(nodeID: Int, nodes: [PlayNode], chapters: [PlayChapter] = [], chapterTitle: String? = nil) -> PlayGameStage? {
        guard let node = nodes.first(where: { $0.id == nodeID }) else { return nil }
        let ordered: [PlayNode]
        if nodes.allSatisfy({ $0.sortID != nil }) {
            ordered = nodes.enumerated().sorted { lhs, rhs in
                let a = lhs.element.sortID ?? 0, b = rhs.element.sortID ?? 0
                return a == b ? lhs.offset < rhs.offset : a < b
            }.map(\.element)
        } else { ordered = nodes }
        let ordinal = ordered.firstIndex(where: { $0.id == nodeID }).map { $0 + 1 }
        let chapter = clean(chapterTitle) ?? node.chapterID.flatMap { id in chapters.first { $0.id == id }?.name }
        return PlayGameStage(ordinal: ordinal, stationName: node.name, chapterTitle: chapter, lead: node.hookText)
    }

    /// The first non-empty line, trimmed. A lead is one sentence of story, not a page.
    static func leadLine(_ text: String?) -> String? {
        guard let text else { return nil }
        return text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    static func clean(_ text: String?) -> String? {
        guard let value = text?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}

/// What the story says once the server has answered. It mirrors the result block's
/// existing authority rules exactly; only the wording is chosen here.
public enum PlayGameOutcome: String, Equatable {
    case passed, notPassed, recorded, noVerdict

    public static func resolve(_ projection: PlayKitScreenProjection) -> PlayGameOutcome? {
        if projection.kind == .photoCheck, projection.segment["degraded"].bool == true { return .noVerdict }
        if PlayKitNoRightAnswer.applies(kind: projection.kind, segment: projection.segment), projection.reportedPass != nil { return .recorded }
        if let passed = projection.reportedPass { return passed ? .passed : .notPassed }
        return projection.complete ? .recorded : nil
    }

    /// Localization key for the story-voice line.
    public var key: String { "playkit.story." + rawValue }

    /// A miss while the game is still open invites another try instead of closing the scene.
    public func key(open: Bool) -> String { self == .notPassed && open ? "playkit.story.tryAgain" : key }

    /// The continue-story action belongs to a finished game only: a terminal
    /// server state with nothing still in flight.
    public static func showsContinue(complete: Bool, pending: Bool, phase: String) -> Bool {
        complete && !pending && phase == "ready"
    }
}

/// A number with its unit right beside it: 「120 米」 / "120 m". Whole numbers drop
/// the decimal; others keep at most two places. No unit means the bare number.
public enum PlayGameNumber {
    public static func text(_ value: Double, unit: String?, locale: Locale = .current) -> String {
        guard value.isFinite else { return "—" }
        let number = value.formatted(.number.precision(.fractionLength(0...2)).locale(locale))
        guard let unit = unit?.trimmingCharacters(in: .whitespacesAndNewlines), !unit.isEmpty else { return number }
        return number + " " + unit
    }
}

/// Lines drawn between paired match items, by row index. Pairs that point at an
/// unknown row are skipped rather than drawn to a guessed place.
public struct PlayGameMatchLine: Equatable, Hashable {
    public let left: Int
    public let right: Int
    public init(left: Int, right: Int) { self.left = left; self.right = right }

    public static func lines(left: [String], right: [String], placement: [String: String]) -> [PlayGameMatchLine] {
        left.enumerated().compactMap { index, id in
            guard let target = placement[id], let column = right.firstIndex(of: target) else { return nil }
            return PlayGameMatchLine(left: index, right: column)
        }
    }
}
