import Foundation

/// A navigation source snapshot, never channel permission or an endpoint approval.
/// The channel service still reads the real TEAM directory and enforces its own lease/RBAC.
@MainActor public struct NativeTeamChannelManagementSource {
    public let detail: TeamDetail
    public let scope: NativeChannelManagementScope
    private weak var coordinator: TeamCoordinator?
    private let sourceScope: UUID

    public init?(coordinator: TeamCoordinator, lookup: TeamLookup, readOnly: Bool) {
        guard !readOnly, case .id(let teamID) = lookup,
              let detail = coordinator.detail, detail.team.id == teamID,
              Self.available(coordinator),
              let id = try? NativeChannelManagementID(String(teamID)),
              let scope = try? NativeChannelManagementScope(guildKind: 3, guildID: id) else { return nil }
        self.coordinator = coordinator; self.detail = detail; self.scope = scope
        sourceScope = coordinator.scope
    }

    /// Rechecked at the actual navigation/factory boundary, not only while rendering a row.
    /// A session/approval replacement synchronizes the original coordinator before any new flow.
    public func isCurrent(for selected: NativeChannelManagementScope) -> Bool {
        guard let coordinator else { return false }
        coordinator.synchronizeSession()
        return selected == scope && coordinator.scope == sourceScope
            && coordinator.detail == detail && Self.available(coordinator)
    }

    private static func available(_ coordinator: TeamCoordinator) -> Bool {
        coordinator.authenticated && coordinator.configured && !coordinator.busy
            && coordinator.detail?.joined == true && coordinator.retiredMembershipTeamID == nil
            && coordinator.messageKey == nil && coordinator.readFailure == nil
            && coordinator.pending == nil && coordinator.review == nil && coordinator.writeState != .blocked
    }
}
