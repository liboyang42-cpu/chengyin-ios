import Foundation

struct ClubManagementContext {
    let access:ClubManagementSessionAccess
    let coordinator:ClubManagementCoordinator
    var operations: ClubOperationsContext? = nil
    var governance: ClubGovernanceContext? = nil
}
