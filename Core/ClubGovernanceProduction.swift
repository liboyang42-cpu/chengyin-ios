import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Reviewed deployment input, never a server role assertion or a remotely enabled flag.
/// Each grant covers one operation and one exact target, including its activity scope.
public struct ClubGovernanceActionGrant: Hashable {
    public let operation: ClubGovernanceMutation
    public let scope: ClubGovernanceScope
    public let risk: ClubGovernanceRisk
    public let targetBinding: String
    public init(command: ClubGovernanceCommand, risk: ClubGovernanceRisk) throws {
        guard risk == command.operation.risk else { throw APIError.invalidConfiguration }
        operation = command.operation; scope = command.scope; self.risk = risk; targetBinding = command.productionTargetBinding
    }
}
extension ClubGovernanceCommand {
    /// Scope is not enough: these source IDs and role choices are carried in fields.
    /// Non-target text, personal data and request IDs are deliberately not retained.
    var productionTargetBinding: String {
        let keys = ["targetMemberId", "banId", "assignmentId", "targetType", "targetId", "defaultLeadMemberId", "roleCode", "hourKind", "dimension", "enabled", "audienceType"]
        return keys.sorted().map { "\($0)=\(fields[$0]?.text ?? "")" }.joined(separator: "&")
    }
}
public struct ClubGovernanceProductionApproval {
    public let market: RegionalMarket
    public let endpoints: OperationEndpointApproval
    public let grants: Set<ClubGovernanceActionGrant>
    public let reviewedPolicyVersion: String
    public init(market: RegionalMarket, endpoints: OperationEndpointApproval,
                grants: Set<ClubGovernanceActionGrant>, reviewedPolicyVersion: String) throws {
        guard !reviewedPolicyVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              grants.allSatisfy({ endpoints.paths.contains($0.operation.path) }) else { throw APIError.invalidConfiguration }
        self.market = market; self.endpoints = endpoints; self.grants = grants; self.reviewedPolicyVersion = reviewedPolicyVersion
    }
    public func permits(_ command: ClubGovernanceCommand, context: RuntimeDependencyContext) -> Bool {
        var required: Set<String> = [command.operation.path, command.operation.reviewRead.path]
        if command.scope.clubID != nil { required.insert(ClubGovernanceRead.access.path) }
        if command.operation == .hostApply { required.insert("api/userInfo") }
        if [.createSeries, .updateSeries, .assignRole].contains(command.operation) { required.insert(ClubGovernanceRead.members.path) }
        return market == .china && context.market == market && endpoints.baseURL == context.baseURL &&
        endpoints.accountID == context.session.accountID && endpoints.namespace == context.session.namespace && required.isSubset(of: endpoints.paths) &&
        grants.contains { $0.operation == command.operation && $0.scope == command.scope && $0.risk == command.operation.risk && $0.targetBinding == command.productionTargetBinding }
    }
}

/// Only the typed factory can construct this transport. A write must equal the reviewed
/// method, URL, body and credential. Read paths remain the closed review/access catalog.
@MainActor public final class ClubGovernanceProductionTransport: HTTPTransport {
    private let approval: ClubGovernanceProductionApproval
    private let captured: RuntimeDependencyContext
    private let command: ClubGovernanceCommand
    private let expected: URLRequest
    private let transport: any HTTPTransport
    private let current: () -> RuntimeDependencyContext?
    private var authorization: ClubGovernanceDispatchAuthorization?
    fileprivate init(approval: ClubGovernanceProductionApproval, captured: RuntimeDependencyContext,
                     command: ClubGovernanceCommand, expected: URLRequest, transport: any HTTPTransport,
                     current: @escaping () -> RuntimeDependencyContext?) {
        self.approval = approval; self.captured = captured; self.command = command; self.expected = expected
        self.transport = transport; self.current = current
    }
    public func permits(_ command: ClubGovernanceCommand) -> Bool {
        self.command == command && current() == captured && approval.permits(command, context: captured)
    }
    func request(for command: ClubGovernanceCommand, token: String, authorization: ClubGovernanceDispatchAuthorization) throws -> URLRequest {
        guard permits(command), expected.value(forHTTPHeaderField: "Authorization") == token else { throw ClubGovernanceFailure.notConfigured }
        try authorization.validate(command); self.authorization = authorization
        // Reuse the same validated multipart boundary and bytes, not a rebuilt form.
        return expected
    }
    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        try Task.checkCancellation()
        guard permits(command), request.httpMethod == "POST", request.value(forHTTPHeaderField: "Authorization") == captured.session.token,
              let url = request.url, approval.endpoints.paths.contains(where: { captured.baseURL.appendingPathComponent($0) == url }) else { throw ClubGovernanceFailure.notConfigured }
        if url == expected.url { guard request.httpBody == expected.httpBody && request.allHTTPHeaderFields == expected.allHTTPHeaderFields else { throw ClubGovernanceFailure.invalidRequest } }
        else {
            let reads = Set(ClubGovernanceRead.allCases.map(\.path)).union(["api/userInfo"])
            guard reads.contains(where: { captured.baseURL.appendingPathComponent($0) == url }) else { throw ClubGovernanceFailure.notConfigured }
        }
        if url == expected.url {
            guard let authorization else { throw ClubGovernanceFailure.notConfigured }
            try authorization.validate(command)
        }
        let result = try await transport.send(request)
        guard !Task.isCancelled, current() == captured else { throw CancellationError() }
        if url == expected.url { try authorization?.validate(command) }
        return result
    }
}
@MainActor public struct ClubGovernanceProductionFactory {
    private let api: APIConfiguration
    private let approval: ClubGovernanceProductionApproval?
    private let transport: any HTTPTransport
    private let current: () -> RuntimeDependencyContext?
    public init(api: APIConfiguration, approval: ClubGovernanceProductionApproval? = nil,
                transport: any HTTPTransport, current: @escaping () -> RuntimeDependencyContext?) {
        self.api = api; self.approval = approval; self.transport = transport; self.current = current
    }
    public func service(for command: ClubGovernanceCommand) -> ClubGovernanceService? {
        guard let approval, let captured = current(), api.baseURL == captured.baseURL, approval.permits(command, context: captured),
              let request = try? ClubGovernanceService(configuration: api, transport: transport).request(path: command.operation.path,
                fields: command.fields, form: [.chapterRecruit, .chapterFinish].contains(command.operation), token: captured.session.token) else { return nil }
        let scoped = ClubGovernanceProductionTransport(approval: approval, captured: captured, command: command, expected: request, transport: transport, current: current)
        return ClubGovernanceService(productionConfiguration: api, productionTransport: scoped)
    }
}
