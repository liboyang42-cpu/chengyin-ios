import SwiftUI

@MainActor struct ClubGovernanceContext {
    let access: any ClubGovernanceAccess
    let coordinator: ClubGovernanceCoordinator
    var enrollmentProfile: ClubEnrollmentProfileContext? = nil
    var ownerRefund: ClubOwnerRefundCoordinator? = nil
    var opsTimeFactory: ((Int) -> ClubOpsTimeCoordinator?)? = nil
}
