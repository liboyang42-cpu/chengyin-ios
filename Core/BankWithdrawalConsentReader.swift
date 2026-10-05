import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Independently verified current document metadata. Latest consent is not proof of
/// which document version is currently in force. No legal copy or version is invented.
public struct BankWithdrawalCurrentDocument: Equatable {
    public let version: String
    public let officialURL: URL
    public init(version: String, officialURL: URL) throws {
        guard !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let parts = URLComponents(url: officialURL, resolvingAgainstBaseURL: false), parts.scheme == "https",
              parts.host?.isEmpty == false, parts.user == nil, parts.password == nil else { throw BankWithdrawalFailure.consentRequired }
        self.version = version; self.officialURL = officialURL
    }
}
@MainActor public protocol BankWithdrawalCurrentDocumentProviding {
    /// Must resolve the current bank_account_collection document for withdrawal in
    /// this exact deployment. The source agreement/get API does not expose it.
    func currentDocument(context: RuntimeDependencyContext) async throws -> BankWithdrawalCurrentDocument
}
@MainActor @Observable public final class BankWithdrawalConsentReader {
    public private(set) var document: BankWithdrawalCurrentDocument?
    public private(set) var evidence: BankWithdrawalConsentEvidence?
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    private let provider: any BankWithdrawalCurrentDocumentProviding
    private let captured: RuntimeDependencyContext
    private let scope: WalletCommerceScope
    private let current: () -> RuntimeDependencyContext?
    public init(configuration: APIConfiguration, transport: any HTTPTransport,
                provider: any BankWithdrawalCurrentDocumentProviding, captured: RuntimeDependencyContext,
                scope: WalletCommerceScope, current: @escaping () -> RuntimeDependencyContext?) {
        self.configuration = configuration; self.transport = transport; self.provider = provider
        self.captured = captured; self.scope = scope; self.current = current
    }
    public func refresh() async throws {
        document = nil; evidence = nil
        guard current() == captured, scope.accountID == captured.session.accountID, scope.namespace == captured.session.namespace else { throw BankWithdrawalFailure.staleSession }
        let currentDocument = try await provider.currentDocument(context: captured)
        guard current() == captured, !Task.isCancelled else { throw BankWithdrawalFailure.staleSession }
        let request = try OperationAdapterHTTP.json(configuration: configuration, path: "api/compliance/consents/latest",
            body: Data(#"{"docType":"bank_account_collection","scene":"withdrawal"}"#.utf8), token: captured.session.token)
        let (data, status) = try await transport.send(request)
        guard current() == captured, !Task.isCancelled else { throw BankWithdrawalFailure.staleSession }
        struct Envelope: Decodable { let code: Int; let data: ComplianceConsent? }
        guard (200..<300).contains(status), let envelope = try? JSONDecoder().decode(Envelope.self, from: data), envelope.code == 200,
              let consent = envelope.data else { throw BankWithdrawalFailure.consentRequired }
        let result = BankWithdrawalConsentEvidence(scope: scope, currentDocumentVersion: currentDocument.version, consent: consent)
        document = currentDocument
        guard result.valid else { throw BankWithdrawalFailure.consentRequired }
        evidence = result
    }
}

/// Dynamic confirm/reject paths are admitted only after the adapter validates an
/// actual preflight response. A deployment selects each action independently.
@MainActor public final class BankWithdrawalRuntimeRoutes {
    private let factory: BusinessRuntimeFactory
    private var challengeID: Int?
    public init(factory: BusinessRuntimeFactory) { self.factory = factory }
    public func validatedChallenge(_ id: Int?) { challengeID = id.flatMap { $0 > 0 ? $0 : nil } }
    public var dynamicRoutes: Set<BusinessRuntimeRoute> {
        guard let challengeID else { return [] }
        return Set(factory.configuration.bankChallengeActions.compactMap { action in
            try? BusinessRuntimeRoute.post("api/fund/preflight/\(challengeID)/" + (action == .confirm ? "confirm" : "reject"))
        })
    }
    public func approval(path: String) -> OperationEndpointApproval? {
        let routes = factory.routes([.bankPrepare, .bankCreate]).union(dynamicRoutes)
        guard routes.contains(where: { $0.method == "POST" && $0.path == path }) else { return nil }
        return try? OperationEndpointApproval(baseURL: factory.captured.baseURL, namespace: factory.captured.session.namespace,
            accountID: factory.captured.session.accountID, paths: [path])
    }
}
