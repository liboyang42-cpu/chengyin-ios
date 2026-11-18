import Foundation

/// `playKit.hangman` from the advanced runtime session view. Blank slots carry
/// only a placeholder; the answer never reaches the client.
public struct PlayHangmanProjection: Equatable {
    public enum InputMode: String, Equatable { case keyboard, pool }
    public enum SlotKind: String, Equatable { case separator = "SEPARATOR", prefilled = "PREFILLED", filled = "FILLED", blank = "BLANK" }
    public struct Slot: Equatable, Identifiable {
        public let index: Int
        public let kind: SlotKind
        public let character: String?
        public var id: Int { index }
        /// Only BLANK and FILLED slots take input. Separators and prefilled characters are fixed.
        public var isFillable: Bool { kind == .blank || kind == .filled }
    }
    public static let maximumPool = 30
    public let length: Int
    public let blankCount: Int
    public let caseSensitive: Bool
    public let solved: Bool
    public let slots: [Slot]
    public let display: String
    public let inputMode: InputMode
    /// Visible candidates in server order (already shuffled for the run, trimmed decoys absent).
    public let pool: [String]
    /// Decoys removed by POOL_TRIM hints (0 when none).
    public let poolRemoved: Int

    public init(_ segment: PlayWireValue) throws {
        guard segment.object != nil, let rows = segment["slots"].array, !rows.isEmpty else { throw PlayExperienceError.malformed }
        var parsed: [Slot] = []
        for (position, row) in rows.enumerated() {
            guard let index = row["i"].integer, index == position,
                  let rawKind = row["kind"].text, let kind = SlotKind(rawValue: rawKind) else { throw PlayExperienceError.malformed }
            let character = row["ch"].text
            switch kind {
            case .separator, .prefilled, .filled:
                guard let character, character.unicodeScalars.count == 1 else { throw PlayExperienceError.malformed }
            case .blank:
                guard row["ch"] == .null else { throw PlayExperienceError.malformed }
            }
            parsed.append(.init(index: index, kind: kind, character: character))
        }
        guard parsed.contains(where: \.isFillable) else { throw PlayExperienceError.malformed }
        if segment["length"] != .null { guard segment["length"].integer == parsed.count else { throw PlayExperienceError.malformed } }
        slots = parsed; length = parsed.count
        blankCount = segment["blankCount"].integer ?? parsed.filter(\.isFillable).count
        caseSensitive = segment["caseSensitive"].bool == true
        solved = segment["solved"].bool == true
        display = segment["display"].text ?? ""
        switch segment["inputMode"] {
        case .null: inputMode = .keyboard
        case .string(let value):
            guard let mode = InputMode(rawValue: value) else { throw PlayExperienceError.malformed }
            inputMode = mode
        default: throw PlayExperienceError.malformed
        }
        if inputMode == .pool {
            guard let candidates = segment["pool"].array, candidates.count <= Self.maximumPool else { throw PlayExperienceError.malformed }
            let values = candidates.compactMap(\.text)
            guard values.count == candidates.count, values.allSatisfy({ $0.unicodeScalars.count == 1 }) else { throw PlayExperienceError.malformed }
            pool = values
            if segment["poolRemoved"] != .null {
                guard let removed = segment["poolRemoved"].integer, removed >= 0 else { throw PlayExperienceError.malformed }
                poolRemoved = removed
            } else { poolRemoved = 0 }
        } else { pool = []; poolRemoved = 0 }
    }

    public var fillableSlots: [Slot] { slots.filter(\.isFillable) }

    /// Keyboard mode: typed characters fill BLANK/FILLED slots in order, matching the
    /// mini-program's hidden-input distribution. Returns nil until every slot is covered.
    public func keyboardPayload(_ typed: String) -> [String: PlayWireValue]? {
        let characters = typed.filter { !$0.isWhitespace }.map(String.init)
        let targets = fillableSlots
        guard characters.count == targets.count, characters.allSatisfy({ $0.unicodeScalars.count == 1 }) else { return nil }
        var payload: [String: PlayWireValue] = [:]
        for (slot, character) in zip(targets, characters) { payload[String(slot.index)] = .string(character) }
        return ["slots": .object(payload)]
    }
    /// Keyboard mode starts from the characters the server kept in FILLED slots.
    public var keyboardDraft: String {
        var result = ""
        for slot in fillableSlots {
            guard slot.kind == .filled, let character = slot.character else { break }
            result += character
        }
        return result
    }

    /// Exact SUBMIT_HANGMAN payload contract: indices of BLANK/FILLED slots only, one
    /// character each; every slot ends up filled; pool mode may only use visible candidates.
    public func validate(_ payload: [String: PlayWireValue]) throws {
        guard Set(payload.keys) == ["slots"], let submitted = payload["slots"]?.object, !submitted.isEmpty else { throw PlayExperienceError.invalidAction }
        let fillable = Dictionary(uniqueKeysWithValues: fillableSlots.map { ($0.index, $0) })
        var used: [String] = []
        for (key, value) in submitted {
            guard let index = Int(key), String(index) == key, fillable[index] != nil,
                  let character = value.text, character.unicodeScalars.count == 1 else { throw PlayExperienceError.invalidAction }
            used.append(character)
        }
        guard fillableSlots.allSatisfy({ submitted[String($0.index)] != nil || $0.kind == .filled }) else { throw PlayExperienceError.invalidAction }
        if inputMode == .pool, !LetterPoolState.fits(used, in: pool) { throw PlayExperienceError.invalidAction }
    }
}

/// Capability keys this client renders for the F03/F05 features, in the server's
/// `ContentCapabilityRequirements` naming (`game.<section lowercased>`, `area.feature`).
/// Declaring a list at start is an all-or-nothing contract on the server: a supplied
/// declaration must cover every required key of the frozen content, so this catalogue
/// is not sent until the complete native capability list is reviewed.
public enum PlayClientCapabilities {
    public static let version = 1
    public static let letterPoolAndRoleViews: [String] = ["game.hangman", "hangman.pool", "qa.letterPool", "role.views"]
    public static func declaration(_ keys: [String]) -> String {
        keys.sorted().map { $0 + "@" + String(version) }.joined(separator: ",")
    }
}
