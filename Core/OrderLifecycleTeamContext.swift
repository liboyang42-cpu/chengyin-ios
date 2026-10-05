import Foundation

/// Carries the owned registration identity alongside the activity context. Re-read this
/// exact registration before creation; an arbitrary activity ID is not eligibility proof.
public struct OrderLifecycleTeamSource: Equatable {
    public let registrationID: Int
    public let context: TeamCreationContext
}
public extension OrderLifecycleDetail {
    var teamCreationSource: OrderLifecycleTeamSource? {
        guard ownerType == 2, let ownerID, ownerID > 0, registrationStatus == 2,
              teamMode == 2, let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return OrderLifecycleTeamSource(registrationID: id, context: TeamCreationContext(ownerID: ownerID, title: title,
            registrationStatus: 2, teamMode: 2, maxMembers: teamMaxMembers))
    }
}
