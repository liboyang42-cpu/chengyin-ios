import SwiftUI

@MainActor struct ClubGovernanceContext {
    let access: any ClubGovernanceAccess
    let coordinator: ClubGovernanceCoordinator
    var enrollmentProfile: ClubEnrollmentProfileContext? = nil
}
