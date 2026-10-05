import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Explicit obligations are deployment-reviewed metadata, never consent fabricated by the client.
/// Marketing eligibility and withdrawals remain the server's per-recipient decision.
public enum MerchantEngagementObligation: Hashable {
    case marketingConsent, customerContactPrivacy, customerExportPrivacy, aftercareEvidencePrivacy
}
public struct MerchantEngagementActionGrant: Equatable {
    public let merchantID: Int
    public let command: MerchantEngagementCommand
    public init(merchantID: Int, command: MerchantEngagementCommand) throws {
        guard merchantID > 0 else { throw APIError.invalidConfiguration }
        _ = try command.request(requestID: "grant-validation")
        // The source has no invitation destination/role preview. A token is not identity proof.
        if case .acceptInvitation = command { throw MerchantBusinessFailure.disabled }
        self.merchantID = merchantID; self.command = command
    }
}
public struct MerchantEngagementDeviceGrant: Equatable {
    public enum Action: Equatable { case contact(MerchantCustomerID, MerchantContactPurpose), saveExport(Int), selectEvidence(MerchantRefundID) }
    public let merchantID: Int
    public let action: Action
    public init(merchantID: Int, action: Action) throws {
        guard merchantID > 0 else { throw APIError.invalidConfiguration }
        if case .saveExport(let id) = action, id <= 0 { throw APIError.invalidConfiguration }
        self.merchantID = merchantID; self.action = action
    }
}
/// Memory-only exact commands include audience, content and one-time credentials.
/// Nothing here is persisted, encoded, printed, or accepted from an Info.plist switch.
public struct MerchantEngagementProductionApproval {
    public let market: RegionalMarket
    public let endpoints: OperationEndpointApproval
    public let grants: [MerchantEngagementActionGrant]
    public let deviceGrants: [MerchantEngagementDeviceGrant]
    public let reviewedObligations: Set<MerchantEngagementObligation>
    public let reviewedPolicyVersion: String
    public init(market: RegionalMarket, endpoints: OperationEndpointApproval, grants: [MerchantEngagementActionGrant],
                deviceGrants: [MerchantEngagementDeviceGrant] = [], reviewedObligations: Set<MerchantEngagementObligation> = [], reviewedPolicyVersion: String) throws {
        guard !reviewedPolicyVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw APIError.invalidConfiguration }
        self.market = market; self.endpoints = endpoints; self.grants = grants; self.deviceGrants = deviceGrants
        self.reviewedObligations = reviewedObligations; self.reviewedPolicyVersion = reviewedPolicyVersion
    }
    public func matches(_ context: RuntimeDependencyContext) -> Bool {
        market == .china && context.market == market && endpoints.baseURL == context.baseURL &&
        endpoints.accountID == context.session.accountID && endpoints.namespace == context.session.namespace
    }
    public func permits(_ command: MerchantEngagementCommand, merchantID: Int, context: RuntimeDependencyContext) -> Bool {
        guard matches(context), let request = try? command.request(requestID: "grant-validation"), endpoints.paths.contains(request.path),
              grants.contains(where: { $0.merchantID == merchantID && $0.command == command }) else { return false }
        if case .acceptInvitation = command { return false }
        return command.productionObligation.map { reviewedObligations.contains($0) } ?? true
    }
    public func permitsDevice(_ action: MerchantEngagementDeviceGrant.Action, merchantID: Int, context: RuntimeDependencyContext) -> Bool {
        guard matches(context), deviceGrants.contains(where: { $0.merchantID == merchantID && $0.action == action }) else { return false }
        switch action {
        case .contact: return reviewedObligations.contains(.customerContactPrivacy)
        case .saveExport: return reviewedObligations.contains(.customerExportPrivacy)
        case .selectEvidence: return reviewedObligations.contains(.aftercareEvidencePrivacy)
        }
    }
}
public extension MerchantEngagementCommand {
    var productionObligation: MerchantEngagementObligation? {
        switch self {
        case .createCampaign, .dispatchCampaign, .retryCampaign, .broadcast: return .marketingConsent
        case .contact: return .customerContactPrivacy
        case .createExport, .downloadExport: return .customerExportPrivacy
        case .uploadEvidence: return .aftercareEvidencePrivacy
        case .saveSegment, .acceptInvitation: return nil
        }
    }
    /// Existing campaign source omits content. Never turn a title-only view into send approval.
    func validateProductionProof(_ proof: MerchantEngagementProof) throws {
        try proof.access.require(permissions)
        switch self {
        case .dispatchCampaign, .retryCampaign:
            guard let task = proof.campaign, task.hasReviewableMessage else { throw MerchantBusinessFailure.disabled }
        case .acceptInvitation: throw MerchantBusinessFailure.disabled
        case .uploadEvidence:
            guard let fields = proof.refund?.rows.first(where: { $0.kind == .refund })?.fields,
                  fields["canRespond"]?.bool == true,
                  fields["allowedDecisions"]?.array?.contains(.string("EVIDENCE")) == true else { throw MerchantBusinessFailure.denied }
        default: break
        }
    }
}

/// Ordinary HTTP transport with exact request reconstruction and one-shot coordinator authority.
@MainActor public final class MerchantEngagementProductionTransport: HTTPTransport {
    private let api: APIConfiguration
    private let approval: MerchantEngagementProductionApproval
    private let captured: RuntimeDependencyContext
    private let command: MerchantEngagementCommand
    private let merchantID: Int
    private let transport: any HTTPTransport
    private let current: () -> RuntimeDependencyContext?
    private let beforeForward: (@MainActor () async -> Void)?
    private var authorization: MerchantEngagementDispatchAuthorization?
    private var review: MerchantEngagementReview?
    private var forwarded = false
    fileprivate init(api: APIConfiguration, approval: MerchantEngagementProductionApproval, captured: RuntimeDependencyContext,
                     command: MerchantEngagementCommand, merchantID: Int, transport: any HTTPTransport,
                     current: @escaping () -> RuntimeDependencyContext?, beforeForward: (@MainActor () async -> Void)?) {
        self.api = api; self.approval = approval; self.captured = captured; self.command = command; self.merchantID = merchantID
        self.transport = transport; self.current = current; self.beforeForward = beforeForward
    }
    public func permits(_ command: MerchantEngagementCommand, merchantID: Int) -> Bool {
        !forwarded && self.command == command && self.merchantID == merchantID && current() == captured &&
        approval.permits(command, merchantID: merchantID, context: captured)
    }
    func authorize(_ review: MerchantEngagementReview, authorization: MerchantEngagementDispatchAuthorization) throws {
        guard permits(review.command, merchantID: review.proof.access.merchantID ?? 0) else { throw MerchantBusinessFailure.disabled }
        try command.validateProductionProof(review.proof); try authorization.validate(review)
        self.review = review; self.authorization = authorization
    }
    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        try Task.checkCancellation()
        guard let review, let authorization, permits(command, merchantID: merchantID) else { throw MerchantBusinessFailure.disabled }
        let expected = try MerchantEngagementService(configuration: api, readTransport: transport)
            .actionRequest(command, requestID: review.requestID, token: captured.session.token)
        guard request.url == expected.url, request.httpMethod == expected.httpMethod, request.httpBody == expected.httpBody,
              request.httpBodyStream == nil, request.allHTTPHeaderFields == expected.allHTTPHeaderFields else { throw MerchantBusinessFailure.disabled }
        if let beforeForward { await beforeForward() }
        guard permits(command, merchantID: merchantID) else { throw MerchantBusinessFailure.disabled }
        try authorization.validate(review)
        forwarded = true
        let response: (Data, Int)
        do { response = try await transport.send(request) }
        catch { if error as? MerchantBusinessFailure == .disabled { throw MerchantBusinessFailure.unknown }; throw error }
        guard !Task.isCancelled, current() == captured else { throw MerchantBusinessFailure.unknown }
        try authorization.validate(review)
        return response
    }
}
@MainActor public struct MerchantEngagementProductionFactory {
    public static let maximumDownloadBytes = 32 * 1024 * 1024 // Native memory budget, not a server guarantee.
    private let api: APIConfiguration
    private let approval: MerchantEngagementProductionApproval?
    private let transport: any HTTPTransport
    private let current: () -> RuntimeDependencyContext?
    private var beforeForward: (@MainActor () async -> Void)?
    private var downloadTestingTransport: (any HTTPTransport)?
    public init(api: APIConfiguration, approval: MerchantEngagementProductionApproval? = nil, transport: any HTTPTransport, current: @escaping () -> RuntimeDependencyContext?) {
        self.api = api; self.approval = approval; self.transport = transport; self.current = current
    }
    func withDispatchBarrier(_ barrier: @escaping @MainActor () async -> Void) -> Self { var copy = self; copy.beforeForward = barrier; return copy }
    func withDownloadTestingTransport(_ transport: any HTTPTransport) -> Self { var copy = self; copy.downloadTestingTransport = transport; return copy }
    public func service(for command: MerchantEngagementCommand, merchantID: Int) -> MerchantEngagementService? {
        guard let approval, let captured = current(), api.baseURL == captured.baseURL,
              approval.permits(command, merchantID: merchantID, context: captured) else { return nil }
        let wire: any HTTPTransport
        if case .downloadExport = command {
            wire = downloadTestingTransport ?? ResponseLimitedHTTPTransport(enabled: true, maximumResponseBytes: Self.maximumDownloadBytes)
        } else { wire = transport }
        let scoped = MerchantEngagementProductionTransport(api: api, approval: approval, captured: captured, command: command,
            merchantID: merchantID, transport: wire, current: current, beforeForward: beforeForward)
        return .init(productionConfiguration: api, productionTransport: scoped)
    }
    public func permitsDevice(_ action: MerchantEngagementDeviceGrant.Action, merchantID: Int) -> Bool {
        guard let approval, let context = current(), api.baseURL == context.baseURL else { return false }
        return approval.permitsDevice(action, merchantID: merchantID, context: context)
    }
}
