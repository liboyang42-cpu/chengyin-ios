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
        currentNodeID = snapshot.availability == .active && candidates.count == 1 ? candidates.first?.id : nil
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
