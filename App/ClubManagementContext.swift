import Foundation

struct ClubManagementContext {
    let access:any ClubManagementAccess
    let coordinator:ClubManagementCoordinator
    var operations: ClubOperationsContext? = nil
    var governance: ClubGovernanceContext? = nil
}
