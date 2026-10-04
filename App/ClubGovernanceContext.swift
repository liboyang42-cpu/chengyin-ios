import SwiftUI

@MainActor struct ClubGovernanceContext {
    // Composition revision fences role-only refreshes and same-account ABA changes.
    var viewerRevision: UInt64 = 0
    let access: any ClubGovernanceAccess
    let coordinator: ClubGovernanceCoordinator
    var enrollmentProfile: ClubEnrollmentProfileContext? = nil
    var ownerRefund: ClubOwnerRefundCoordinator? = nil
    var opsTimeFactory: ((Int) -> ClubOpsTimeCoordinator?)? = nil
}
