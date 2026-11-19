import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// F11 independent endpoint grants. Reads list reference amounts; settle (payer) and dispute
/// (merchant) are production writes and stay off unless independently approved.
public struct FeReferenceSettlementGrants {
    public let reads: OperationEndpointApproval?
    public let settle: OperationEndpointApproval?
    public let dispute: OperationEndpointApproval?
    public init(reads: OperationEndpointApproval? = nil, settle: OperationEndpointApproval? = nil, dispute: OperationEndpointApproval? = nil) {
        self.reads = reads; self.settle = settle; self.dispute = dispute
    }
    public static var dormant: Self { .init() }
}

public enum FeReferenceSettlementOutcome: Equatable { case acknowledged, rejected(String), notSent, unknown }

@MainActor public final class FeReferenceSettlementHTTP {
    let configuration: APIConfiguration
    let transport: any HTTPTransport
    let credentials: () -> PublishingCredentials?
    let grants: FeReferenceSettlementGrants
    public init(configuration: APIConfiguration, transport: any HTTPTransport, grants: FeReferenceSettlementGrants = .dormant,
                credentials: @escaping () -> PublishingCredentials?) {
        self.configuration = configuration; self.transport = transport; self.grants = grants; self.credentials = credentials
    }
    /// Shares the publisher client's deployment, transport and live credentials; grants stay separate.
    public convenience init(sharing client: PublisherLifecycleHTTP, grants: FeReferenceSettlementGrants = .dormant) {
        self.init(configuration: client.configuration, transport: client.transport, grants: grants, credentials: client.credentials)
    }
    private func permits(_ path: String, _ grant: OperationEndpointApproval?) -> PublishingCredentials? {
        guard let credential = credentials(),
              grant?.allows(configuration: configuration, namespace: credential.session.namespace,
                            accountID: credential.session.accountID, path: path) == true else { return nil }
        return credential
    }
    public var canRead: Bool { permits(FeReferenceSettlementRoute.merchantPath, grants.reads) != nil || permits(FeReferenceSettlementRoute.payerPath, grants.reads) != nil }
    public var canSettle: Bool { permits(FeReferenceSettlementRoute.settlePath, grants.settle) != nil }
    public var canDispute: Bool { permits(FeReferenceSettlementRoute.disputePath, grants.dispute) != nil }

    public func merchantList(_ query: FeReferenceMerchantQuery = .init()) async throws -> FeReferenceSettlementList {
        try await read(FeReferenceSettlementRoute.merchantPath, query: query.queryItems)
    }
    public func payerList(_ query: FeReferencePayerQuery) async throws -> FeReferenceSettlementList {
        try await read(FeReferenceSettlementRoute.payerPath, query: query.queryItems)
    }
    public func settle(_ request: FeReferenceSettleRequest) async -> FeReferenceSettlementOutcome {
        await write(FeReferenceSettlementRoute.settlePath, grant: grants.settle, body: request.body)
    }
    public func dispute(_ request: FeReferenceDisputeRequest) async -> FeReferenceSettlementOutcome {
        await write(FeReferenceSettlementRoute.disputePath, grant: grants.dispute, body: request.body)
    }

    private func read(_ path: String, query: [URLQueryItem]) async throws -> FeReferenceSettlementList {
        guard FeReferenceSettlementRoute.readPaths.contains(path), let credential = permits(path, grants.reads) else { throw CoopFlowFailure.disabled }
        guard var components = URLComponents(url: configuration.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else { throw APIError.invalidRequest }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw APIError.invalidRequest }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"; request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(credential.token, forHTTPHeaderField: "Authorization")
        let envelope = try await send(request, credential: credential)
        return try FeReferenceSettlementList(envelope["data"])
    }
    private func write(_ path: String, grant: OperationEndpointApproval?, body: CoopFlowJSON) async -> FeReferenceSettlementOutcome {
        guard let credential = permits(path, grant),
              let data = try? body.canonical(),
              let request = try? OperationAdapterHTTP.json(configuration: configuration, path: path, body: data, token: credential.token) else { return .notSent }
        do { _ = try await send(request, credential: credential); return .acknowledged }
        catch CoopFlowFailure.server(_, let message) { return .rejected(message ?? "") }
        catch CoopFlowFailure.stale { return .notSent }
        catch { return .unknown }
    }
    private func send(_ request: URLRequest, credential: PublishingCredentials) async throws -> CoopFlowJSON {
        try Task.checkCancellation()
        guard credentials() == credential else { throw CoopFlowFailure.stale }
        let (data, status) = try await transport.send(request)
        guard credentials() == credential else { throw CoopFlowFailure.stale }
        if status == 401 { throw APIError.unauthorized }
        let envelope = try JSONDecoder().decode(CoopFlowJSON.self, from: data)
        if envelope["code"].integer == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(status) else { throw APIError.httpStatus(status) }
        guard let code = envelope["code"].integer else { throw APIError.malformedResponse }
        guard code == 200 else { throw CoopFlowFailure.server(code, envelope["msg"].text) }
        return envelope
    }
}
