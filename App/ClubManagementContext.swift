import Foundation

struct ClubManagementContext {
    let access:any ClubManagementAccess
    let coordinator:ClubManagementCoordinator
    var viewerRevision: UInt64 = 0
    var operations: ClubOperationsContext? = nil
    var governance: ClubGovernanceContext? = nil
}
