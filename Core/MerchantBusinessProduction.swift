import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Separate opinion decisions and team/CRM actions; no refund-execution action exists.
public enum MerchantBusinessAction: String, Hashable {
    case addNote, hideNote, assignTag, removeTag, batchTag, aftercareAgree, aftercareReject, aftercareEvidence
    case reviewReply, reviewUpdate, reviewDelete, reviewReport, inviteOperator, operatorRole, removeOperator, revokeInvite
}
public extension MerchantBusinessMutation {
    var action: MerchantBusinessAction {
        switch self {
        case .addNote: return .addNote; case .hideNote: return .hideNote; case .assignTag: return .assignTag
        case .removeTag: return .removeTag; case .batchTag: return .batchTag
        case .aftercare(_, let decision, _, _):
            switch decision { case .agree: return .aftercareAgree; case .reject: return .aftercareReject; case .evidence: return .aftercareEvidence }
        case .review(_, _, let action, _):
            switch action { case .reply: return .reviewReply; case .update: return .reviewUpdate; case .delete: return .reviewDelete; case .report: return .reviewReport }
        case .inviteOperator: return .inviteOperator; case .operatorRole: return .operatorRole
        case .removeOperator: return .removeOperator; case .revokeInvite: return .revokeInvite
        }
    }
    /// Batch grants preserve the exact customer set instead of the broad UI lock category.
    var productionTarget: String {
        switch self {
        case .batchTag(let ids, _, _): return "customers:" + ids.map(\.rawValue).sorted().map(String.init).joined(separator: ",")
        case .hideNote(let id, let note, _): return "customer:\(id.rawValue)|note:\(note)"
        case .removeTag(let id, let tag): return "customer:\(id.rawValue)|tag:\(tag)"
        case .addNote(let id, _, let correction): return "customer:\(id.rawValue)|corrects:\(correction.map(String.init) ?? "")"
        case .inviteOperator(let role): return "operator-invite|role:\(role)"
        case .operatorRole(let id, _, let role): return "operator:\(id.rawValue)|role:\(role)"
        default: return targetKey
        }
    }
}
public struct MerchantBusinessActionGrant: Hashable {
    public let merchantID: Int
    public let action: MerchantBusinessAction
    public let target: String
    public init(merchantID: Int, mutation: MerchantBusinessMutation) throws {
        guard merchantID > 0 else { throw APIError.invalidConfiguration }
        _ = try mutation.request(requestID: "grant-validation")
        self.merchantID = merchantID; action = mutation.action; target = mutation.productionTarget
    }
}
public struct MerchantBusinessProductionApproval {
    public let market: RegionalMarket
    public let endpoints: OperationEndpointApproval
    public let grants: Set<MerchantBusinessActionGrant>
    public let reviewedPolicyVersion: String
    public init(market: RegionalMarket, endpoints: OperationEndpointApproval, grants: Set<MerchantBusinessActionGrant>, reviewedPolicyVersion: String) throws {
        guard !reviewedPolicyVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw APIError.invalidConfiguration }
        self.market = market; self.endpoints = endpoints; self.grants = grants; self.reviewedPolicyVersion = reviewedPolicyVersion
    }
    public func permits(_ mutation: MerchantBusinessMutation, merchantID: Int, context: RuntimeDependencyContext) -> Bool {
        guard market == .china, context.market == market, endpoints.baseURL == context.baseURL,
              endpoints.accountID == context.session.accountID, endpoints.namespace == context.session.namespace,
              let descriptor = try? mutation.request(requestID: "grant-validation"), endpoints.paths.contains(descriptor.path) else { return false }
        return grants.contains { $0.merchantID == merchantID && $0.action == mutation.action && $0.target == mutation.productionTarget }
    }
}

@MainActor public final class MerchantBusinessProductionTransport: HTTPTransport {
    private let configuration: APIConfiguration
    private let approval: MerchantBusinessProductionApproval
    private let captured: RuntimeDependencyContext
    private let mutation: MerchantBusinessMutation
    private let merchantID: Int
    private let transport: any HTTPTransport
    private let current: () -> RuntimeDependencyContext?
    private var authorization: MerchantBusinessDispatchAuthorization?
    private let beforeForward: (@MainActor () async -> Void)?
    fileprivate init(configuration: APIConfiguration, approval: MerchantBusinessProductionApproval, captured: RuntimeDependencyContext,
                     mutation: MerchantBusinessMutation, merchantID: Int, transport: any HTTPTransport, current: @escaping () -> RuntimeDependencyContext?, beforeForward: (@MainActor () async -> Void)?) {
        self.configuration = configuration; self.approval = approval; self.captured = captured; self.mutation = mutation
        self.merchantID = merchantID; self.transport = transport; self.current = current; self.beforeForward = beforeForward
    }
    public func permits(_ mutation: MerchantBusinessMutation) -> Bool {
        self.mutation == mutation && current() == captured && approval.permits(mutation, merchantID: merchantID, context: captured)
    }
    func permits(_ mutation: MerchantBusinessMutation, merchantID: Int) -> Bool { self.merchantID == merchantID && permits(mutation) }
    func authorize(_ authorization: MerchantBusinessDispatchAuthorization) throws {
        try authorization.validate(mutation, merchantID: merchantID); self.authorization = authorization
    }
    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        try Task.checkCancellation()
        guard permits(mutation), let data = request.httpBody,
              let fields = try? JSONDecoder().decode(MerchantBusinessValue.self, from: data).object,
              let requestID = fields["requestId"]?.string else { throw MerchantBusinessFailure.disabled }
        let expected = try MerchantBusinessService(configuration: configuration, readTransport: transport).makeRequest(
            mutation.request(requestID: requestID), token: captured.session.token)
        guard request.httpMethod == expected.httpMethod, request.url == expected.url,
              request.httpBody == expected.httpBody, request.allHTTPHeaderFields == expected.allHTTPHeaderFields else { throw MerchantBusinessFailure.disabled }
        if let beforeForward { await beforeForward() }
        guard permits(mutation), let authorization else { throw MerchantBusinessFailure.disabled }
        // envelope() may hop executors. Recheck the exact review at the final gate.
        try authorization.validate(mutation, merchantID: merchantID)
        let result = try await transport.send(request)
        guard !Task.isCancelled, current() == captured else { throw MerchantBusinessFailure.unknown }
        try authorization.validate(mutation, merchantID: merchantID)
        return result
    }
}
@MainActor public struct MerchantBusinessProductionFactory {
    private let api: APIConfiguration
    private let approval: MerchantBusinessProductionApproval?
    private let transport: any HTTPTransport
    private let current: () -> RuntimeDependencyContext?
    private var beforeForward: (@MainActor () async -> Void)?
    public init(api: APIConfiguration, approval: MerchantBusinessProductionApproval? = nil, transport: any HTTPTransport, current: @escaping () -> RuntimeDependencyContext?) {
        self.api = api; self.approval = approval; self.transport = transport; self.current = current
    }
    /// Internal deterministic scheduling seam for ordinary HTTP transport tests.
    /// It grants no capability, and the final ticket fence always runs after it.
    func withDispatchBarrier(_ barrier: @escaping @MainActor () async -> Void) -> Self {
        var copy = self; copy.beforeForward = barrier; return copy
    }
    public func service(for mutation: MerchantBusinessMutation, merchantID: Int) -> MerchantBusinessService? {
        guard let approval, let captured = current(), api.baseURL == captured.baseURL, approval.permits(mutation, merchantID: merchantID, context: captured) else { return nil }
        let scoped = MerchantBusinessProductionTransport(configuration: api, approval: approval, captured: captured, mutation: mutation, merchantID: merchantID, transport: transport, current: current, beforeForward: beforeForward)
        return MerchantBusinessService(productionConfiguration: api, productionTransport: scoped)
    }
}
