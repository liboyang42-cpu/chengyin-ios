import Foundation

/// Read-only presentation of an existing authoritative snapshot. No completion commands,
/// inferred totals, local success flags, timers or provider access live in this projection.
public struct PlayTaskSummaryPresentation: Equatable {
    public let completed: Int?
    public let total: Int?
    public let currentNodeID: Int?
    public init(snapshot: PlaySnapshot) {
        let done = snapshot.displayedDoneCount
        if let count = snapshot.result.total, count > 0, let done, (0...count).contains(done) {
            completed = done; total = count
        } else { completed = nil; total = nil }
        let candidates = snapshot.visibleNodes.filter { !snapshot.isDone($0) && !snapshot.isLocked($0) && $0.done == false }
        // Multiple playable branches remain a choice; their order is not an authoritative current task.
        currentNodeID = snapshot.result.mode != 2 && snapshot.availability == .active && candidates.count == 1 ? candidates.first?.id : nil
    }
    public var fraction: Double? {
        guard let completed, let total else { return nil }
        return Double(completed) / Double(total)
    }
}

public enum PlayTaskStatusPresentation: String, Equatable {
    case completed, locked, awaitingVerification, available, unknown
    public init(node: PlayNode, snapshot: PlaySnapshot) {
        if snapshot.isDone(node) { self = .completed }
        else if snapshot.isLocked(node) { self = .locked }
        else if snapshot.result.mode == 2 && node.selfReported == true { self = .awaitingVerification }
        else if node.done == false && snapshot.availability == .active { self = .available }
        else { self = .unknown }
    }
    public var labelKey: String { "referenceTask.status." + rawValue }
    public var symbol: String {
        switch self {
        case .completed: return "checkmark.circle"
        case .locked: return "lock"
        case .awaitingVerification: return "clock"
        case .available: return "circle"
        case .unknown: return "questionmark.circle"
        }
    }
}

extension PlayTaskStatusPresentation {
    /// CG-07-P2-2: a completed node that was skipped, revealed, done at the desk or at an
    /// alternate station reads as that completion, not as an ordinary solve.
    public func labelKey(completionMode: String?) -> String {
        if self == .completed, let mode = PlayCompletionModePresentation(raw: completionMode), mode.isAssisted { return mode.labelKey }
        return labelKey
    }
}

/// CG-01-P2-7: one evidence card per finished station that carries solved-feedback text,
/// in server order. Unfinished or locked stations never show their card early.
public struct PlayEvidenceCard: Equatable, Identifiable {
    public let id: Int
    public let name: String?
    public let text: String
}
/// CG-01-P2-6 / CG-02-P2-11: this player's own photo for a finished station.
public struct PlayRunPhoto: Equatable, Identifiable {
    public let id: Int
    public let name: String?
    public let url: String
}
public enum PlayRunKeepsakes {
    private static func finished(_ snapshot: PlaySnapshot) -> [PlayNode] {
        snapshot.visibleNodes.filter { snapshot.isDone($0) && !snapshot.isLocked($0) }
    }
    public static func evidenceCards(in snapshot: PlaySnapshot) -> [PlayEvidenceCard] {
        finished(snapshot).compactMap { node in node.feedbackText.map { PlayEvidenceCard(id: node.id, name: node.name, text: $0) } }
    }
    public static func photos(in snapshot: PlaySnapshot) -> [PlayRunPhoto] {
        finished(snapshot).compactMap { node in node.photoURL.map { PlayRunPhoto(id: node.id, name: node.name, url: $0) } }
    }
}
