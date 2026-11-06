import Foundation

public struct ClubCalendarSessionsReadKey: Hashable {
    public let context: ClubGovernanceReadContext
    public let month: ClubEventMonth
    public init(context: ClubGovernanceReadContext, month: ClubEventMonth) { self.context = context; self.month = month }
}

@MainActor public enum ClubCalendarSessionsReader {
    public static func live(_ key: ClubCalendarSessionsReadKey, access: any ClubGovernanceAccess) -> Bool {
        key.context.operation == .topics && (key.context.scope.clubID ?? 0) > 0 &&
        (key.context.identity?.accountID ?? 0) > 0 && access.isConfigured &&
        key.context.identity == access.identity && key.context.authorizationGeneration == access.authorizationGeneration &&
        key.context.accessIdentity == ObjectIdentifier(access)
    }
    public static func read(_ key: ClubCalendarSessionsReadKey, access: any ClubGovernanceAccess,
                            check validity: () throws -> Void) async throws -> ClubCalendarSessionsSnapshot {
        func check() throws {
            try validity()
            guard live(key, access: access), !Task.isCancelled else { throw ClubGovernanceFailure.staleReview }
        }
        try check()
        guard let clubID = key.context.scope.clubID else { throw ClubGovernanceFailure.invalidRequest }
        let snapshot = try await access.readCalendarSessions(clubID: clubID, month: key.month, check: check)
        try check()
        guard snapshot.clubID == clubID, snapshot.month == key.month else { throw ClubGovernanceFailure.targetChanged }
        return snapshot
    }
}
