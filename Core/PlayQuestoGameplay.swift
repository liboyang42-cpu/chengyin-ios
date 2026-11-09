import Foundation

// New gameplay player contracts (spec UG-01/02/03/04/10, §十一). Sources on
// integrate/questo-ui-20261110: HangmanGameplay.projection/judge,
// AccusationTemplateSupport.publicView, AccusationOutcomePolicy.Verdict,
// AdvancedGamePublicProjection (qa.options img/alt) and G3 clueTransform.
// The client never judges, never stores an answer, and never slices an answer string.

// MARK: - UG-01 Hangman

/// `state.hangman` public projection / SUBMIT_HANGMAN receipt.
public struct PlayHangmanProjection: Equatable {
    public enum SlotKind: Equatable { case separator, prefilled, filled, blank }
    public struct Slot: Equatable, Identifiable {
        public let index: Int
        public let kind: SlotKind
        /// Present for separator/prefilled/filled. Blank slots carry no character.
        public let character: String?
        public var id: Int { index }
        public var editable: Bool { kind == .blank || kind == .filled }
    }
    public enum Verdict: Equatable { case correct, wrong }
    public let length: Int
    public let blankCount: Int
    public let caseSensitive: Bool
    public let solved: Bool
    public let slots: [Slot]
    public let display: String
    /// Only on a submission receipt.
    public let verdict: Verdict?
    /// Only after a correct verdict. Never present while unsolved.
    public let answerText: String?

    public init(raw: PlayWireValue) throws {
        guard let length = raw["length"].integer, length > 0, let blanks = raw["blankCount"].integer, blanks >= 0,
              let solved = raw["solved"].bool, let rows = raw["slots"].array, rows.count == length,
              let display = raw["display"].text else { throw PlayExperienceError.malformed }
        var slots: [Slot] = []
        for (offset, row) in rows.enumerated() {
            guard row["i"].integer == offset, let kind = row["kind"].text else { throw PlayExperienceError.malformed }
            let ch = row["ch"].text
            let parsed: SlotKind
            switch kind {
            case "SEPARATOR": parsed = .separator
            case "PREFILLED": parsed = .prefilled
            case "FILLED": parsed = .filled
            case "BLANK": parsed = .blank
            default: throw PlayExperienceError.malformed
            }
            // One user-perceived character per slot (CJK and supplementary-plane characters included).
            guard parsed == .blank ? ch == nil : (ch.map({ $0.count == 1 }) ?? false) else { throw PlayExperienceError.malformed }
            slots.append(Slot(index: offset, kind: parsed, character: ch))
        }
        self.length = length; blankCount = blanks; caseSensitive = raw["caseSensitive"].bool == true
        self.solved = solved; self.slots = slots; self.display = display
        switch raw["verdict"].text ?? "" {
        case "CORRECT": verdict = .correct
        case "WRONG": verdict = .wrong
        case "": verdict = nil
        default: throw PlayExperienceError.malformed
        }
        answerText = solved || verdict == .correct ? raw["answerText"].text : nil
    }

    /// Payload `{slots:{"i":"ch"}}` for the blanks the player filled cell by cell. Only blank
    /// (or previously filled) slots may be sent; one character each. Server judges.
    public func slotPayload(_ entries: [Int: String]) throws -> [String: PlayWireValue] {
        guard !solved, !entries.isEmpty else { throw PlayExperienceError.invalidAction }
        var map: [String: PlayWireValue] = [:]
        for (index, value) in entries {
            guard slots.indices.contains(index), slots[index].editable, value.count == 1 else { throw PlayExperienceError.invalidAction }
            map[String(index)] = .string(value)
        }
        return ["slots": .object(map)]
    }
    /// Payload `{input:"..."}`: blanks in order, or the whole word. The server rebuilds spacing.
    public func inputPayload(_ text: String) throws -> [String: PlayWireValue] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !solved, !trimmed.isEmpty, trimmed.count <= 256 else { throw PlayExperienceError.invalidAction }
        return ["input": .string(trimmed)]
    }
}

// MARK: - UG-02 Image options

/// One `qa.options[]` row from the public projection. `correct` and secret feedback never arrive.
public struct PlayChoiceOption: Equatable, Identifiable {
    public let id: String
    public let label: String
    /// Only an https URL or a site path that the server already resolved. Anything else
    /// (http, //host, data:, backslash, raw `media-asset:` ref) is dropped: text only, never a broken image.
    public let imageURL: URL?
    public let alt: String?
    public init(raw: PlayWireValue, baseURL: URL?) throws {
        guard let id = raw["id"].text ?? raw["id"].integer.map({ String($0) }), !id.isEmpty,
              let label = raw["label"].text ?? raw["t"].text else { throw PlayExperienceError.malformed }
        self.id = id; self.label = label
        let alt = raw["alt"].text?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.alt = alt?.isEmpty == false ? alt : nil
        imageURL = raw["img"].text.flatMap { Self.safeImage($0, baseURL: baseURL) }
    }
    static func safeImage(_ raw: String, baseURL: URL?) -> URL? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains("\\"), !value.hasPrefix("//") else { return nil }
        if value.hasPrefix("/") {
            guard let baseURL, let url = URL(string: value, relativeTo: baseURL)?.absoluteURL, url.scheme == "https" else { return nil }
            return url
        }
        guard let components = URLComponents(string: value), components.scheme == "https",
              components.host?.isEmpty == false, components.user == nil, components.password == nil else { return nil }
        return components.url
    }
    /// VoiceOver reads text first; the image is never the only information.
    public var accessibilityLabel: String { alt.map { label + "，" + $0 } ?? label }
}

// MARK: - UG-03 / UG-04 Accusation

public struct PlayAccusationView: Equatable {
    public struct Testimony: Equatable, Identifiable { public let key: String; public let text: String; public var id: String { key } }
    public struct Suspect: Equatable, Identifiable {
        public let id: String
        /// Equals the QA option label (single source of truth on the server).
        public let name: String
        public let identity: String?
        public let avatarURL: URL?
        /// Only testimony the player has already obtained; the server filters, never the client.
        public let testimony: [Testimony]
    }
    public let enabled: Bool
    public let suspects: [Suspect]
    public let corkboardURL: URL?
    public let corkboardAlt: String?
    /// Author intro screens, shown verbatim in order. Shape is author-defined text or {text,img}.
    public let introTexts: [String]
    public let earlyAccuseAllowed: Bool

    public init(raw: PlayWireValue, baseURL: URL?) throws {
        guard let enabled = raw["enabled"].bool else { throw PlayExperienceError.malformed }
        self.enabled = enabled
        var seen = Set<String>()
        suspects = try (raw["suspects"].array ?? []).map { row in
            guard let id = row["id"].text, !id.isEmpty, seen.insert(id).inserted, let name = row["name"].text else { throw PlayExperienceError.malformed }
            let avatar: URL?
            if let text = row["avatar"].text { avatar = PlayChoiceOption.safeImage(text, baseURL: baseURL) }
            else { avatar = row["avatar"]["img"].text.flatMap { PlayChoiceOption.safeImage($0, baseURL: baseURL) } }
            let testimony = (row["testimony"].array ?? []).compactMap { item -> Testimony? in
                guard let key = item["key"].text, let text = item["text"].text, !text.isEmpty else { return nil }
                return Testimony(key: key, text: text)
            }
            return Suspect(id: id, name: name, identity: row["identity"].text, avatarURL: avatar, testimony: testimony)
        }
        let board = raw["corkboardImage"]
        if let text = board.text { corkboardURL = PlayChoiceOption.safeImage(text, baseURL: baseURL); corkboardAlt = nil }
        else { corkboardURL = board["img"].text.flatMap { PlayChoiceOption.safeImage($0, baseURL: baseURL) }; corkboardAlt = board["alt"].text }
        introTexts = (raw["introScreens"].array ?? []).compactMap { $0.text ?? $0["text"].text }
        earlyAccuseAllowed = raw["earlyAccuse"]["allowed"].bool == true
    }
}

/// Server verdict of one confirmed accusation. Choosing and re-choosing never reaches here.
public struct PlayAccusationOutcome: Equatable {
    /// UG-04: three ending facts plus "continue investigating", "refused" and "still confirming".
    public enum Ending: Equatable {
        /// 正常结案
        case solved
        /// 提前结案 — not a failure and not "caught the culprit".
        case closedEarly
        /// 指认失败 (no chances left)
        case failed
        /// Wrong, chances remain: spoiler-free feedback, keep investigating.
        case keepInvestigating
        /// REFUSED: no chance consumed; show the reason only.
        case refused(String?)
        /// The server could not decide (progress unreadable) or the write result is unknown: 结算确认中.
        case confirming
    }
    public let ending: Ending
    /// Author ending copy, delivered only after the verdict. Never invented locally.
    public let screenText: String?

    /// Reads the advanced view's `accusation` object: `result` {verdict,correct,early,canRetry,terminal}
    /// and `screen` (author win/lose copy, present only after the server decided). REFUSED never
    /// lands in state (the server rolls back and answers an error), so it arrives via `refused(_:)`.
    public init(accusation raw: PlayWireValue) {
        let result = raw["result"]
        let early = result["early"].bool == true
        switch result["verdict"].text ?? "" {
        case "CORRECT": ending = early ? .closedEarly : .solved
        case "WRONG": ending = result["canRetry"].bool == true ? .keepInvestigating : .failed
        case "FAILED": ending = .failed
        case "REFUSED": ending = .refused(nil)
        default: ending = .confirming // no result yet, or an unrecognised value: never guess an ending
        }
        let screen = raw["screen"]
        switch ending {
        case .solved, .closedEarly, .failed: screenText = screen.text ?? screen["text"].text
        default: screenText = nil
        }
    }
    /// Server refusal message, mirrored verbatim. No chance was consumed.
    public init(refused message: String?) { ending = .refused(message); screenText = nil }
    /// True once a recorded result exists; until then the view shows only the choose/confirm flow.
    public static func decided(_ raw: PlayWireValue) -> Bool { raw["result"]["verdict"].text != nil }
    /// Write result unknown (timeout): 结算确认中 until the original receipt is read back.
    public static var confirming: PlayAccusationOutcome { PlayAccusationOutcome(accusation: .null) }
    /// Success animation and reward copy are allowed only for a normal solved ending.
    public var celebrates: Bool { ending == .solved }
}

// MARK: - UG-10 Clue transform

/// Server already sends the transformed question text. MIRROR flips only the text layer;
/// REVERSE renders the server string as-is (never reversed again). Unknown → plain text.
public enum PlayClueTransform: Equatable {
    case standard, mirror, reverse
    public init(raw: PlayWireValue) {
        switch raw["mode"].text ?? raw.text ?? "" {
        case "MIRROR": self = .mirror
        case "REVERSE": self = .reverse
        default: self = .standard
        }
    }
    public var mirrorsText: Bool { self == .mirror }
}
