import Foundation

/// F03 letter pool: one pure selection model shared by the hangman pool mode and
/// the TYPE question letter pool. It only arranges server-provided candidate
/// characters into server-shaped slots; it never knows, derives or checks an answer.
/// Separator and prefilled slots are display-only and never consume a candidate.
public struct LetterPoolState: Equatable {
    public enum SlotKind: Equatable { case separator, prefilled, fillable }
    public struct Slot: Equatable, Identifiable {
        /// Server slot index (hangman `i`) or the 0-based answer position for a question.
        public let id: Int
        public let kind: SlotKind
        /// Fixed display text for separator/prefilled slots.
        public let fixedText: String?
        /// Candidate index in `pool` currently placed in this slot.
        public fileprivate(set) var poolIndex: Int?
        /// A server-filled character that is no longer in the visible pool (for
        /// example after a revealed letter). It stays visible but is never sent again.
        public fileprivate(set) var carried: String?
        public var isFillable: Bool { kind == .fillable }
        public init(id: Int, kind: SlotKind, fixedText: String? = nil, poolIndex: Int? = nil, carried: String? = nil) {
            self.id = id; self.kind = kind; self.fixedText = fixedText; self.poolIndex = poolIndex; self.carried = carried
        }
    }

    /// Visible candidates in server order. Duplicates are separate candidates.
    public let pool: [String]
    public private(set) var slots: [Slot]

    public init(pool: [String], slots: [Slot]) {
        self.pool = pool; self.slots = slots
    }

    /// Hangman pool mode. Existing FILLED slots (kept by the server after a wrong
    /// answer or reveal) are matched to unused candidates with the same character.
    public init?(hangman projection: PlayHangmanProjection) {
        guard projection.inputMode == .pool else { return nil }
        var built: [Slot] = []
        for slot in projection.slots {
            switch slot.kind {
            case .separator: built.append(.init(id: slot.index, kind: .separator, fixedText: slot.character, poolIndex: nil, carried: nil))
            case .prefilled: built.append(.init(id: slot.index, kind: .prefilled, fixedText: slot.character, poolIndex: nil, carried: nil))
            case .filled, .blank: built.append(.init(id: slot.index, kind: .fillable, fixedText: nil, poolIndex: nil, carried: nil))
            }
        }
        self.init(pool: projection.pool, slots: built)
        for slot in projection.slots where slot.kind == .filled {
            guard let character = slot.character, let position = slots.firstIndex(where: { $0.id == slot.index }) else { continue }
            if let candidate = firstUnused(character) { slots[position].poolIndex = candidate }
            else { slots[position].carried = character }
        }
    }

    /// TYPE question letter pool: `answerLength` empty fillable slots.
    public init?(question pool: PlayQuestionLetterPool) {
        guard pool.answerLength > 0 else { return nil }
        self.init(pool: pool.chars, slots: (0..<pool.answerLength).map { Slot(id: $0, kind: .fillable, fixedText: nil, poolIndex: nil, carried: nil) })
    }

    public var usedPoolIndexes: Set<Int> { Set(slots.compactMap(\.poolIndex)) }
    public func isUsed(_ poolIndex: Int) -> Bool { slots.contains { $0.poolIndex == poolIndex } }
    public func text(of slot: Slot) -> String? {
        if let fixed = slot.fixedText { return fixed }
        if let index = slot.poolIndex, pool.indices.contains(index) { return pool[index] }
        return slot.carried
    }
    public var fillableSlots: [Slot] { slots.filter(\.isFillable) }
    public var isEmpty: Bool { fillableSlots.allSatisfy { $0.poolIndex == nil && $0.carried == nil } }
    public var isComplete: Bool { !fillableSlots.isEmpty && fillableSlots.allSatisfy { $0.poolIndex != nil || $0.carried != nil } }
    /// True when at least one candidate was placed locally (carried server fills alone are not a draft).
    public var hasPlacedCandidates: Bool { slots.contains { $0.poolIndex != nil } }

    /// Tapping a candidate fills the first empty fillable slot. Used candidates and
    /// a full answer row are ignored.
    @discardableResult public mutating func pick(_ poolIndex: Int) -> Bool {
        guard pool.indices.contains(poolIndex), !isUsed(poolIndex),
              let position = slots.firstIndex(where: { $0.isFillable && $0.poolIndex == nil && $0.carried == nil }) else { return false }
        slots[position].poolIndex = poolIndex
        return true
    }
    /// Tapping a filled slot returns its candidate to the pool. Separator and
    /// prefilled slots are not tappable.
    @discardableResult public mutating func clear(slotID: Int) -> Bool {
        guard let position = slots.firstIndex(where: { $0.id == slotID }), slots[position].isFillable,
              slots[position].poolIndex != nil || slots[position].carried != nil else { return false }
        slots[position].poolIndex = nil; slots[position].carried = nil
        return true
    }
    public mutating func clearAll() {
        for position in slots.indices where slots[position].isFillable {
            slots[position].poolIndex = nil; slots[position].carried = nil
        }
    }

    /// SUBMIT_HANGMAN payload: `{"slots":{"<index>":"<char>"}}` for locally placed
    /// candidates. Carried server fills stay on the server and are not resent.
    public var hangmanPayload: [String: PlayWireValue] {
        var slotsPayload: [String: PlayWireValue] = [:]
        for slot in slots where slot.isFillable {
            if let index = slot.poolIndex, pool.indices.contains(index) { slotsPayload[String(slot.id)] = .string(pool[index]) }
        }
        return ["slots": .object(slotsPayload)]
    }
    /// SUBMIT_QA payload: picked characters concatenated in slot order.
    public var questionPayload: [String: PlayWireValue] { ["input": .string(joinedInput)] }
    public var joinedInput: String { fillableSlots.compactMap { text(of: $0) }.joined() }

    /// Keep a previous draft's characters when the server sends a new projection
    /// (refresh, POOL_TRIM, wrong answer). Characters whose candidate is gone are dropped.
    public func rebased(keeping previous: LetterPoolState) -> LetterPoolState {
        var next = self
        for old in previous.slots where old.isFillable {
            guard let character = previous.text(of: old), old.carried == nil,
                  let position = next.slots.firstIndex(where: { $0.id == old.id && $0.isFillable }),
                  next.slots[position].poolIndex == nil, next.slots[position].carried == nil,
                  let candidate = next.firstUnused(character) else { continue }
            next.slots[position].poolIndex = candidate
        }
        return next
    }

    /// True when `characters` can be taken from `pool`, counting duplicates.
    public static func fits(_ characters: [String], in pool: [String]) -> Bool {
        var left: [String: Int] = [:]
        for item in pool { left[item, default: 0] += 1 }
        for character in characters {
            guard let count = left[character], count > 0 else { return false }
            left[character] = count - 1
        }
        return true
    }

    private func firstUnused(_ character: String) -> Int? {
        let used = usedPoolIndexes
        return pool.indices.first { !used.contains($0) && pool[$0] == character }
    }
}

/// `playKit.qa.letterPool` from the runtime session view (TYPE questions only).
public struct PlayQuestionLetterPool: Equatable {
    public static let maximumCharacters = 30
    public let chars: [String]
    public let answerLength: Int
    /// Decoys removed by POOL_TRIM hints (0 when none).
    public let removed: Int
    /// Returns nil when the question has no letter pool; throws on a malformed one.
    public init?(question segment: PlayWireValue) throws {
        let raw = segment["letterPool"]
        guard raw != .null else { return nil }
        guard (segment["mode"].text ?? "TYPE").uppercased() == "TYPE" else { return nil }
        guard raw.object != nil, let rows = raw["chars"].array, !rows.isEmpty, rows.count <= Self.maximumCharacters,
              let length = raw["answerLength"].integer, length > 0, length <= rows.count else { throw PlayExperienceError.malformed }
        let values = rows.compactMap(\.text)
        guard values.count == rows.count, values.allSatisfy({ $0.unicodeScalars.count == 1 }) else { throw PlayExperienceError.malformed }
        if raw["removed"] != .null { guard let removed = raw["removed"].integer, removed >= 0 else { throw PlayExperienceError.malformed } }
        chars = values; answerLength = length; removed = raw["removed"].integer ?? 0
    }
}
