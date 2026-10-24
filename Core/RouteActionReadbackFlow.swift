import Foundation

/// Read back one existing route action and recover that same originalRequestID.
/// The reader is topicRouteSessionMapper.selectActionByAction. This flow does not
/// insert a route action and does not invent a writer.
public struct RouteActionReadbackFlow: Equatable {
    public init() {}

    /// Request → read. A different session, member, or action id is not this action.
    /// An absent id on the returned row keeps the existing selectAction check.
    /// A missing row or an unusable request id returns nil. A missing reader is WAITING_SOURCE.
    public func recover(
        sessionID: Int64?,
        memberID: Int64?,
        actionID: String?,
        selectAction: ((Int64, Int64, String) -> RouteActionOriginalRow?)?
    ) throws -> RouteActionOriginalRow? {
        let trimmed = actionID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let sessionID, sessionID > 0, let memberID, memberID > 0, !trimmed.isEmpty else { return nil }
        guard let selectAction else {
            throw MechanismFailure.waitingSource(capability: MechanismRequestIdProjection.selectActionByAction)
        }
        guard let row = selectAction(sessionID, memberID, trimmed) else { return nil }
        if row.actionID != trimmed { return nil }
        if let rowSession = row.sessionID, rowSession != sessionID { return nil }
        if let rowMember = row.memberID, rowMember != memberID { return nil }
        return row
    }
}
