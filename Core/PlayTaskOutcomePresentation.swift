import Foundation

/// A task-detail projection of current readback. It never interprets a receipt as
/// completion or advances the route, selects a branch, or grants a new operation.
public struct PlayTaskOutcomePresentation: Equatable {
    public enum State: String { case awaitingRead, loading, reviewing, submitting, needsReadback, unknown, failed, completed, pending, locked, unavailable }
    public enum Continuation: String { case none, nextTask, chooseTask, finished, overview }
    public let state: State
    public let continuation: Continuation
    public let nextNodeID: Int?
    public let nextNodeName: String?

    public init(snapshot: PlaySnapshot?, nodeID: Int, phase: String, isCurrentRead: Bool, unresolved: Bool) {
        var state: State = .awaitingRead
        var continuation: Continuation = .none
        var nextNodeID: Int?
        var nextNodeName: String?
        switch phase {
        case "idle": state = .awaitingRead
        case "loading": state = .loading
        case "reviewing": state = .reviewing
        case "submitting": state = .submitting
        case "needsReadback": state = .needsReadback
        default:
            if unresolved || phase == "unknown" { state = .unknown }
            else if phase == "failed" { state = .failed }
            else if phase == "ready", isCurrentRead, let snapshot,
                    snapshot.result.mode == 1,
                    snapshot.availability == .active || snapshot.availability == .completed,
                    let node = snapshot.visibleNodes.first(where: { $0.id == nodeID }) {
                if snapshot.isDone(node) {
                    state = .completed
                    if snapshot.availability == .completed { continuation = .finished }
                    else if snapshot.availability == .active {
                        let choices = snapshot.visibleNodes.filter {
                            $0.id != nodeID && $0.done == false && !snapshot.isDone($0) && !snapshot.isLocked($0)
                        }
                        if choices.count == 1, let next = choices.first {
                            continuation = .nextTask; nextNodeID = next.id; nextNodeName = next.name
                        } else { continuation = choices.count > 1 ? .chooseTask : .overview }
                    } else { continuation = .overview }
                } else if snapshot.isLocked(node) { state = .locked }
                else if node.done == false && snapshot.availability == .active { state = .pending }
                else { state = .unavailable }
            } else { state = .unavailable }
        }
        self.state = state; self.continuation = continuation
        self.nextNodeID = nextNodeID; self.nextNodeName = nextNodeName
    }
}
