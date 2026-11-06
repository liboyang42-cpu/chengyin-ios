import Foundation

/// A dedicated normal-growth adapter over the composition's original private client.
/// It never falls through to generic send, never rewrites requests and never issues authority.
@MainActor final class GrowthNormalReadTransport: HTTPTransport {
    private let deployment: ReviewedAppDeployment?
    private let underlying: any HTTPTransport
    private let current: @MainActor () -> CompositionHTTPTransport.SessionIdentity?
    private let selectApproval: @MainActor (RuntimeDependencyContext) -> GrowthNormalReadApproval?

    init(deployment: ReviewedAppDeployment?, underlying: any HTTPTransport,
         current: @escaping @MainActor () -> CompositionHTTPTransport.SessionIdentity?,
         approval: @escaping @MainActor (RuntimeDependencyContext) -> GrowthNormalReadApproval?) {
        self.deployment = deployment; self.underlying = underlying; self.current = current; selectApproval = approval
    }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        guard let deployment, let api = deployment.regional.apiConfiguration,
              let captured = current(), let account = captured.accountID, account > 0,
              let role = captured.role, ["player", "club", "merchant"].contains(role), let token = captured.token,
              let session = try? PlayExperienceSession(accountID: account, epoch: captured.epoch,
                  namespace: deployment.storageScope.service, token: token) else { throw APIError.notConfigured }
        let context = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL, role: role, session: session)
        guard let approval = selectApproval(context),
              GrowthNormalReadRoute.accepts(request, context: context, approval: approval) else { throw APIError.notConfigured }
        let live: () -> Bool = {
            self.current() == captured && self.selectApproval(context) === approval && approval.matches(context)
        }
        try Task.checkCancellation()
        guard live() else { throw CancellationError() }
        do {
            let result = try await underlying.send(request)
            // A late success, transport error, or 401 from a retired viewer/lease cannot
            // reach the reader and expire a newer login. Current 401 handling stays original.
            guard !Task.isCancelled, live() else { throw CancellationError() }
            return result
        } catch {
            guard !Task.isCancelled, live() else { throw CancellationError() }
            throw error
        }
    }
}

/// A concrete normal-growth child always consumes the strict anonymous contract.
/// The explicit existential cast selects the Core initializer, avoiding recursion.
/// This selects decoding only: the child still refuses unapproved leaderboard wire.
extension GrowthCenterService {
    init(configuration: APIConfiguration, transport: GrowthNormalReadTransport) {
        self.init(configuration: configuration, transport: transport as any HTTPTransport,
                  leaderboardContract: .anonymous)
    }
}
