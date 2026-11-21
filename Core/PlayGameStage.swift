import Foundation

/// Story framing for a station game: 「第N站」 with the chapter as a separate small label,
/// the station game's title written once, the station's lead line and its hero image.
/// Read only from the current route read; nothing is invented when a field is missing,
/// so a nil part simply is not shown.
public struct PlayGameStage: Equatable {
    /// Route-wide station number, the same number the station list shows. Nil when the
    /// station has no place on the route (story-only game, free exploration).
    public let ordinal: Int?
    public let stationName: String?
    public let chapterTitle: String?
    public let lead: String?
    /// The game (or station) title, cleaned of route-name prefixes and 「第N关」.
    public let title: String?
    /// Hero image from the station image chain; nil when the host has no route read.
    public let image: PlayStationImage?

    public init(ordinal: Int?, stationName: String?, chapterTitle: String?, lead: String?,
                title: String? = nil, image: PlayStationImage? = nil) {
        let number = ordinal.flatMap { $0 > 0 ? $0 : nil }
        let name = Self.clean(stationName)
        let chapter = Self.clean(chapterTitle)
        self.ordinal = number
        self.stationName = name
        self.lead = Self.leadLine(lead)
        self.title = Self.displayTitle(title) ?? Self.displayTitle(stationName)
        self.image = image
        // The chapter label never repeats the station line.
        self.chapterTitle = number == nil && chapter != nil && chapter == name ? nil : chapter
    }

    /// True when there is anything worth drawing above the game.
    public var isEmpty: Bool { ordinal == nil && stationName == nil && chapterTitle == nil && lead == nil && title == nil }

    /// The small station line when there is no number: the station's own name, unless the
    /// page already shows the same station as its title.
    public func stationLabel(besides pageTitle: String?) -> String? {
        guard ordinal == nil, let name = Self.displayTitle(stationName) else { return nil }
        return Self.sameStation(name, pageTitle) ? nil : name
    }

    /// Stations are numbered across the whole route, never per chapter: places (stations with
    /// coordinates) in route order — `sortId` when every station carries one, otherwise the
    /// order the server returned them. Hidden stations keep their place so numbers never shift
    /// as the route unfolds. Free exploration (mode 2) and stations without a place have no number.
    public static func stationNumber(nodeID: Int, nodes: [PlayNode], mode: Int? = nil) -> Int? {
        guard mode != 2 else { return nil }
        let ordered: [PlayNode]
        if nodes.allSatisfy({ $0.sortID != nil }) {
            ordered = nodes.enumerated().sorted { lhs, rhs in
                let a = lhs.element.sortID ?? 0, b = rhs.element.sortID ?? 0
                return a == b ? lhs.offset < rhs.offset : a < b
            }.map(\.element)
        } else { ordered = nodes }
        return ordered.filter { isPlace($0) }.firstIndex(where: { $0.id == nodeID }).map { $0 + 1 }
    }

    static func isPlace(_ node: PlayNode) -> Bool {
        guard let lat = node.latitude, let lng = node.longitude else { return false }
        return lat != 0 && lng != 0
    }

    public static func resolve(nodeID: Int, nodes: [PlayNode], chapters: [PlayChapter] = [], chapterTitle: String? = nil,
                               mode: Int? = nil, image: PlayStationImage? = nil) -> PlayGameStage? {
        guard let node = nodes.first(where: { $0.id == nodeID }) else { return nil }
        let chapter = clean(chapterTitle) ?? node.chapterID.flatMap { id in chapters.first { $0.id == id }?.name }
        return PlayGameStage(ordinal: stationNumber(nodeID: nodeID, nodes: nodes, mode: mode), stationName: node.name,
                             chapterTitle: chapter, lead: node.hookText, title: node.gameTitle, image: image)
    }

    /// The same framing from a whole route read, with the station image chain as its hero.
    public static func resolve(nodeID: Int, in result: PlayNodesResult, chapterTitle: String? = nil) -> PlayGameStage? {
        guard let node = result.nodes.first(where: { $0.id == nodeID }) else { return nil }
        return resolve(nodeID: nodeID, nodes: result.nodes, chapters: result.chapters, chapterTitle: chapterTitle,
                       mode: result.mode, image: PlayStationImageResolver.station(for: node, in: result))
    }

    /// A title written once: no route-name prefix with 「第N关」, no leading 「第N关」/「模板」/「问答」
    /// label and no leading station number such as 「1 · 」. Cleaning never empties a title.
    public static func displayTitle(_ text: String?) -> String? {
        guard let raw = clean(text) else { return nil }
        var value = raw
        for pattern in [#"^\s*(?:[^·:：]{1,40}?\s*[·:：]\s*)?第\s*\d+\s*关\s*[:：·\-－—\s]\s*"#,
                        #"^\s*(?:第\s*\d+\s*关|模板|问答)\s*[:：·\-－—\s]\s*"#] {
            if let range = value.range(of: pattern, options: .regularExpression) { value.removeSubrange(range) }
        }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { value = raw }
        let unnumbered = value.replacingOccurrences(of: #"^\d+\s*[·.、\-－—:：]\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return unnumbered.isEmpty ? value : unnumbered
    }

    /// Two lines name the same station when one contains the other (a trailing 「（备注）」 aside).
    static func sameStation(_ a: String?, _ b: String?) -> Bool {
        func core(_ text: String?) -> String {
            (displayTitle(text) ?? "").replacingOccurrences(of: #"\s*[（(][^（）()]*[）)]\s*$"#, with: "", options: .regularExpression)
        }
        let x = core(a), y = core(b)
        return !x.isEmpty && !y.isEmpty && (x.contains(y) || y.contains(x))
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
