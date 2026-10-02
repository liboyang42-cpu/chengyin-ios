import Foundation

@MainActor final class SquareReportSessionAccess: SquareReportAccess {
    private let identityProvider: () -> SquareGovernanceIdentity?
    private let tokenProvider: () -> String?
    private let subjectProvider: (SocialActionTarget) async throws -> SocialActionSnapshot
    var identity: SquareGovernanceIdentity? { identityProvider() }
    var token: String? { tokenProvider() }
    init(identity: @escaping () -> SquareGovernanceIdentity?, token: @escaping () -> String?,
         subject: @escaping (SocialActionTarget) async throws -> SocialActionSnapshot) {
        identityProvider = identity; tokenProvider = token; subjectProvider = subject
    }
    func freshSubject(_ target: SocialActionTarget) async throws -> SocialActionSnapshot { try await subjectProvider(target) }
}
