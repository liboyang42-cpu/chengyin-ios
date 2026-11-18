import Foundation

/// F01 hint ladder: author-ordered levels (direction, key step, answer) plus a
/// separate skip. Order, cost and content are server decisions; this file only
/// projects the server view and never derives a hint or an answer locally.
public enum PlayHelpScope: Hashable {
    /// Topic-route run (`/api/play/help`).
    case run(runID: Int, nodeID: Int)
    /// Advanced game session (`/api/play/help/advanced`), same rules.
    case advanced(sessionID: Int, nodeID: Int)

    public var nodeID: Int {
        switch self { case .run(_, let node), .advanced(_, let node): return node }
    }
    var ownerID: Int {
        switch self { case .run(let owner, _), .advanced(let owner, _): return owner }
    }
    var isValid: Bool { ownerID > 0 && nodeID > 0 }
    var basePath: String {
        switch self { case .run: return "api/play/help"; case .advanced: return "api/play/help/advanced" }
    }
    var ownerField: String {
        switch self { case .run: return "runId"; case .advanced: return "sessionId" }
    }
}

public enum PlayHelpRowState: String, Equatable {
    /// Already unlocked: re-reading is free.
    case review
    /// The previous level is not unlocked yet; the server would refuse it too.
    case gated
    case free
    case cost
    case unavailable
}

public struct PlayHelpRow: Equatable, Identifiable {
    public let level: Int
    public let type: String
    public let state: PlayHelpRowState
    public let cost: Int
    public var id: Int { level }
    public var isAnswer: Bool { type == "ANSWER" }
    public var canRequest: Bool { state == .review || state == .free || state == .cost }
}

/// Projection of GET `/api/play/help`. Hint rows keep the author order; the
/// skip level is kept apart so the panel can place it on the last row.
public struct PlayHelpView: Equatable {
    public static let renderableTypes: Set<String> = ["TEXT", "IMAGE", "LETTER", "DIGIT", "ANSWER"]
    public let enabled: Bool
    public let rows: [PlayHelpRow]
    public let skipLevel: Int?
    /// Nil means unknown (old run), never zero.
    public let remainingFreeUses: Int?

    public init(_ raw: PlayWireValue) throws {
        guard raw.object != nil else { throw PlayExperienceError.malformed }
        guard raw["enabled"].bool == true, let layers = raw["layers"].array else {
            enabled = false; rows = []; skipLevel = nil; remainingFreeUses = nil; return
        }
        var projected: [PlayHelpRow] = []
        var skip: Int?
        var previousUnlocked = true
        var seen = Set<Int>()
        for layer in layers {
            guard let level = layer["level"].integer, level > 0, seen.insert(level).inserted else { continue }
            let type = layer["type"].text ?? ""
            if type == "SKIP" {
                if layer["usable"].bool == true { skip = level }
                continue
            }
            let usable = Self.renderableTypes.contains(type) && layer["usable"].bool == true
            let unlocked = layer["unlocked"].bool == true
            let cost: Int? = layer["costPoints"].integer.flatMap { $0 >= 0 ? $0 : nil }
            let state: PlayHelpRowState
            if usable && unlocked { state = .review }
            else if usable && !previousUnlocked { state = .gated }
            else if usable && (layer["free"].bool == true || cost == 0) { state = .free }
            else if usable, let cost, cost > 0 { state = .cost }
            else { state = .unavailable }
            projected.append(PlayHelpRow(level: level, type: type, state: state, cost: state == .cost ? (cost ?? 0) : 0))
            previousUnlocked = unlocked
        }
        rows = projected
        skipLevel = skip
        enabled = !projected.isEmpty || skip != nil
        remainingFreeUses = raw["remainingFreeUses"].integer.flatMap { $0 >= 0 ? $0 : nil }
    }
}

/// POST `/use` receipt. The content is exactly what the server approved.
public struct PlayHelpUseReceipt: Equatable {
    public let level: Int
    public let type: String
    public let content: String
    public let alreadyUnlocked: Bool
    public let chargedPoints: Int

    public init(_ raw: PlayWireValue, expectedLevel: Int) throws {
        guard let level = raw["level"].integer, level == expectedLevel,
              let type = raw["type"].text, let content = raw["content"].text, !content.isEmpty else {
            throw PlayExperienceError.malformed
        }
        self.level = level; self.type = type; self.content = content
        alreadyUnlocked = raw["alreadyUnlocked"].bool == true
        chargedPoints = max(0, raw["chargedPoints"].integer ?? 0)
    }
}

/// POST `/skip` receipt: zero score, assisted completion, the story continues.
public struct PlayHelpSkipReceipt: Equatable {
    public let score: Int?
    public let completionMode: String?

    public init(_ raw: PlayWireValue) throws {
        guard raw["skipped"].bool == true else { throw PlayExperienceError.malformed }
        score = raw["score"].integer
        completionMode = raw["completionMode"].text
    }
}

/// One request id per (scope, operation, level) until a definitive answer.
/// A lost response is retried with the same id, so the server replays the
/// original result and never charges or skips twice.
public struct PlayHelpRequestLedger: Equatable {
    private var pending: [String: String] = [:]
    public init() {}

    static func key(_ scope: PlayHelpScope, operation: String, level: Int) -> String {
        "\(scope.basePath)|\(scope.ownerID)|\(scope.nodeID)|\(operation)|\(level)"
    }
    public static func newRequestID() -> String {
        "h" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }
    public mutating func requestID(_ scope: PlayHelpScope, operation: String, level: Int,
                                   make: () -> String = PlayHelpRequestLedger.newRequestID) -> String {
        let key = Self.key(scope, operation: operation, level: level)
        if let existing = pending[key] { return existing }
        let fresh = make(); pending[key] = fresh; return fresh
    }
    public func pendingID(_ scope: PlayHelpScope, operation: String, level: Int) -> String? {
        pending[Self.key(scope, operation: operation, level: level)]
    }
    public mutating func settle(_ scope: PlayHelpScope, operation: String, level: Int) {
        pending.removeValue(forKey: Self.key(scope, operation: operation, level: level))
    }
}
