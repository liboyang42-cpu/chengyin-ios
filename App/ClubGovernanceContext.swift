import SwiftUI

@MainActor struct ClubGovernanceContext {
    // Composition revision fences role-only refreshes and same-account ABA changes.
    var viewerRevision: UInt64 = 0
    let access: any ClubGovernanceAccess
    let coordinator: ClubGovernanceCoordinator
    var enrollmentProfile: ClubEnrollmentProfileContext? = nil
    var ownerRefund: ClubOwnerRefundCoordinator? = nil
    var opsTimeFactory: ((Int) -> ClubOpsTimeCoordinator?)? = nil
    var topicDestination: ((Int) -> AnyView)? = nil
    var storyTemplates = ClubStoryTemplateContext()
    var customerTopics: ClubCustomerTopicContext { .init(viewerRevision: viewerRevision, destination: topicDestination) }
}

struct ClubCustomerTopicContext {
    var viewerRevision: UInt64 = 0
    var destination: ((Int) -> AnyView)? = nil
}
private struct ClubCustomerTopicKey: EnvironmentKey {
    static let defaultValue = ClubCustomerTopicContext()
}
extension EnvironmentValues {
    var clubCustomerTopics: ClubCustomerTopicContext {
        get { self[ClubCustomerTopicKey.self] }
        set { self[ClubCustomerTopicKey.self] = newValue }
    }
}
