import Foundation

/// Host closures stay live: never capture a login token/account as a static snapshot.
/// The host observes AppSession and keys the subtree by its session identity.
@MainActor final class SquareGovernanceSessionAccess: SquareGovernanceAccess {
    private let identityProvider: () -> SquareGovernanceIdentity?
    private let tokenProvider: () -> String?
    private let commentRefresh: () async throws -> [SquareGovernanceComment]
    var identity: SquareGovernanceIdentity? { identityProvider() }
    var token: String? { tokenProvider() }
    init(identity: @escaping () -> SquareGovernanceIdentity?, token: @escaping () -> String?, freshComments: @escaping () async throws -> [SquareGovernanceComment] = { [] }) {
        identityProvider = identity; tokenProvider = token; commentRefresh = freshComments
    }
    func freshComments() async throws -> [SquareGovernanceComment] { try await commentRefresh() }
}
