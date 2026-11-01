import Foundation

/// One read of topicRouteSessionMapper.selectActionByAction.
/// Passed into the existing route page read. This type does not mint originalRequestID.
/// Does not insert a route action. No controller path was found, so this reader does not send.
public struct OriginalActionReader: Equatable {
    public private(set) var appeared = false
    public var queries: Int { gate.queries }
    public let writes = 0
    public let sends = 0
    /// Absent. This mapper has no controller path, so the send stays stopped.
    public let httpPath: String? = nil
    private let gate: Gate

    public init(selectActionByAction: ((Int64, Int64, String) -> RouteActionOriginalRow?)?) {
        gate = Gate(query: selectActionByAction)
    }

    /// Visible only. Does not ask the original query and does not write.
    public mutating func appear() {
        appeared = true
    }

    /// Closure for the existing RouteActionPageRead.shownRow.
    /// Nil when the original query port is absent, so the page stays WAITING_SOURCE and does not send.
    public var selectAction: ((Int64, Int64, String) -> RouteActionOriginalRow?)? {
        gate.selectAction
    }

    public static func == (lhs: OriginalActionReader, rhs: OriginalActionReader) -> Bool {
        lhs.appeared == rhs.appeared
            && lhs.queries == rhs.queries
            && lhs.writes == rhs.writes
            && lhs.sends == rhs.sends
            && lhs.httpPath == rhs.httpPath
    }

    private final class Gate {
        private let query: ((Int64, Int64, String) -> RouteActionOriginalRow?)?
        private(set) var queries = 0

        init(query: ((Int64, Int64, String) -> RouteActionOriginalRow?)?) {
            self.query = query
        }

        var selectAction: ((Int64, Int64, String) -> RouteActionOriginalRow?)? {
            guard let query else { return nil }
            return { sessionID, memberID, actionID in
                self.read(sessionID: sessionID, memberID: memberID, actionID: actionID, query: query)
            }
        }

        private func read(
            sessionID: Int64,
            memberID: Int64,
            actionID: String,
            query: (Int64, Int64, String) -> RouteActionOriginalRow?
        ) -> RouteActionOriginalRow? {
            let trimmed = actionID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard sessionID > 0, memberID > 0, !trimmed.isEmpty else { return nil }
            queries += 1
            guard let row = query(sessionID, memberID, trimmed) else { return nil }
            guard row.actionID == trimmed else { return nil }
            if let rowSession = row.sessionID, rowSession != sessionID { return nil }
            if let rowMember = row.memberID, rowMember != memberID { return nil }
            return row
        }
    }
}
