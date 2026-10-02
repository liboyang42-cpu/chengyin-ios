import Foundation

/// Receives a path from the host's already-approved URL router. This parser neither trusts hosts
/// nor opens URLs; the platform layer must apply its own scheme/host policy first.
public struct MerchantOperatorInviteRoute: Equatable {
    public let invitation: MerchantOperatorAcceptance
    public init(path: String, queryItems: [URLQueryItem]) throws {
        guard path == "/merchant/team" else { throw MerchantBusinessFailure.invalid }
        let tokens = queryItems.filter { $0.name == "invite" }
        guard tokens.count == 1, let token = tokens.first?.value else { throw MerchantBusinessFailure.invalid }
        invitation = try .init(token: token)
    }
}
/// Login-return state is ephemeral and does not authorize acceptance by itself.
@MainActor public final class MerchantOperatorInviteContinuation {
    public private(set) var invitation: MerchantOperatorAcceptance?
    public init(route: MerchantOperatorInviteRoute) { invitation = route.invitation }
    public func commandForExplicitReview() throws -> MerchantEngagementCommand {
        guard let invitation else { throw MerchantBusinessFailure.stale }; return .acceptInvitation(invitation)
    }
    public func cancelOrConsume() { invitation = nil }
}
