import Foundation

/// The route page reads one existing action through RouteActionReadbackFlow.recover.
/// Appearance does not write and does not call the reader. This type does not
/// rewrite recover, does not insert a route action, and does not mint originalRequestID.
public struct RouteActionPageRead: Equatable {
    public private(set) var appeared = false
    public private(set) var reads = 0
    public let writes = 0
    private let flow = RouteActionReadbackFlow()

    public init() {}

    /// Visible only. Does not call recover and does not write.
    public mutating func appear() {
        appeared = true
    }

    /// The row is this action only when the session, member, and action id match.
    /// A different id is not returned. An absent id on the row keeps the existing check.
    public mutating func shownRow(
        sessionID: Int64?,
        memberID: Int64?,
        actionID: String?,
        selectAction: ((Int64, Int64, String) -> RouteActionOriginalRow?)?
    ) throws -> RouteActionOriginalRow? {
        reads += 1
        guard let recovered = try flow.recover(
            sessionID: sessionID,
            memberID: memberID,
            actionID: actionID,
            selectAction: selectAction) else { return nil }
        let trimmed = actionID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard recovered.actionID == trimmed else { return nil }
        if let rowSession = recovered.sessionID, rowSession != sessionID { return nil }
        if let rowMember = recovered.memberID, rowMember != memberID { return nil }
        return recovered
    }
}
