import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Refund authorization is independent of gameplay, read-only governance and QR issuance.
/// No shipped composition installs this grant. A reviewed deployment/account must opt in.
public struct ClubOwnerRefundApproval {
    public let market: RegionalMarket
    public let endpoints: OperationEndpointApproval
    public init(market: RegionalMarket, endpoints: OperationEndpointApproval) { self.market = market; self.endpoints = endpoints }
    public func matches(_ context: RuntimeDependencyContext) -> Bool {
        let required: Set<String> = ["api/registration/cancel-by-owner", "api/club/access/me", "api/club/crm/checkin/detail"]
        return market == .china && context.market == market && endpoints.baseURL == context.baseURL &&
            endpoints.namespace == context.session.namespace && endpoints.accountID == context.session.accountID && required.isSubset(of: endpoints.paths)
    }
}

/// Dynamic session access keeps the coordinator and its durable unknown-outcome locks
/// retained across navigation. Exact context guards cover role, epoch, token and deployment.
@MainActor public final class ClubOwnerRefundConfiguredAccess: ClubOwnerRefundAccess {
    private let fallback: any ClubOwnerRefundAccess
    private let configuration: APIConfiguration?
    private let approval: ClubOwnerRefundApproval?
    private let transport: any HTTPTransport
    private let current: () -> RuntimeDependencyContext?
    private let onUnauthorized: (RuntimeDependencyContext) -> Void
    private var observedContext: RuntimeDependencyContext?
    private var generation = UUID()
    public var authorizationGeneration: UUID? {
        let context = current()
        if context != observedContext { observedContext = context; generation = UUID() }
        return generation
    }
    public init(fallback: any ClubOwnerRefundAccess, configuration: APIConfiguration?, approval: ClubOwnerRefundApproval? = nil,
                transport: any HTTPTransport, current: @escaping () -> RuntimeDependencyContext?,
                onUnauthorized: @escaping (RuntimeDependencyContext) -> Void = { _ in }) {
        self.fallback = fallback; self.configuration = configuration; self.approval = approval; self.transport = transport; self.current = current; self.onUnauthorized = onUnauthorized
    }
    public var identity: ClubReadIdentity? { fallback.identity }
    public var namespace: String { fallback.namespace }
    public let canDispatchOffline = false
    public var canDispatch: Bool {
        guard let configuration, let approval, let context = current(), configuration.baseURL == context.baseURL,
              identity?.accountID == context.session.accountID, identity?.epoch == context.session.epoch,
              namespace == context.session.namespace else { return false }
        return approval.matches(context)
    }
    private func capturedContext() throws -> RuntimeDependencyContext {
        guard canDispatch, let captured = current() else { throw ClubOwnerRefundFailure.disabled }; return captured
    }
    private func check(_ captured: RuntimeDependencyContext) throws {
        guard !Task.isCancelled, current() == captured, canDispatch else { throw ClubOwnerRefundFailure.stale }
    }
    private func scopedTransport(_ captured: RuntimeDependencyContext) throws -> RuntimeDependencyTransport {
        guard let approval else { throw ClubOwnerRefundFailure.disabled }
        return RuntimeDependencyTransport(configuration: .init(market: approval.market, endpoints: approval.endpoints),
            captured: captured, transport: transport, current: current)
    }
    public func evidence(_ target: ClubOwnerRefundTarget) async throws -> ClubOwnerRefundEvidence {
        guard canDispatch else { return try await fallback.evidence(target) }
        let captured = try capturedContext()
        guard let configuration else { throw ClubOwnerRefundFailure.disabled }
        let session = try ClubGovernanceSession(accountID: captured.session.accountID, epoch: captured.session.epoch,
            token: captured.session.token, storageNamespace: captured.session.namespace)
        let service = ClubGovernanceService(configuration: configuration, transport: try scopedTransport(captured))
        do {
            let snapshot = try await service.read(.checkin, scope: target.scope, session: session) { try self.check(captured) }
            try check(captured)
            return try ClubOwnerRefundEvidence(snapshot: snapshot, target: target)
        } catch {
            if error as? APIError == .unauthorized || error as? ClubGovernanceFailure == .signedOut {
                if current() == captured { onUnauthorized(captured) }
            }
            throw error
        }
    }
    public func send(_ review: ClubOwnerRefundReview) async throws -> ClubOwnerRefundReceipt {
        let captured = try capturedContext()
        guard review.identity == identity, review.namespace == namespace, let configuration else { throw ClubOwnerRefundFailure.stale }
        // Request builder is shared with the inert/offline client; exact form contains only id.
        let request = try ClubOwnerRefundService(configuration: configuration).request(
            registrationID: review.evidence.target.registrationID, token: captured.session.token)
        let scoped = try scopedTransport(captured)
        try check(captured)
        let result: (Data, Int)
        do { result = try await scoped.send(request); try check(captured) }
        catch { throw ClubOwnerRefundFailure.unknown }
        let envelope = try? JSONDecoder().decode(ClubGovernanceValue.self, from: result.0)
        let message = envelope?["msg"].string.map { String($0.prefix(500)) }
        if result.1 == 401 || envelope?["code"].int == 401 {
            if current() == captured { onUnauthorized(captured) }
            throw ClubOwnerRefundFailure.unconfirmed(message: message)
        }
        guard (200..<300).contains(result.1), envelope?["code"].int == 200, let envelope else {
            throw ClubOwnerRefundFailure.unconfirmed(message: message)
        }
        do { return try ClubOwnerRefundReceipt(value: envelope["data"], message: message, registrationID: review.evidence.target.registrationID) }
        catch { throw ClubOwnerRefundFailure.unconfirmed(message: message) }
    }
}
