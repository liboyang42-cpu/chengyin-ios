import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor public protocol TopicSelfPlayServing: AnyObject {
    var session: PublishingSession? { get }
    var configured: Bool { get }
    func document() async throws -> TopicSelfPlayDocument
    func freshTopic(_ topic: SelfPlayTopicID) async throws -> TopicDetail
    func recordConsent(requestID: String, document: TopicSelfPlayDocument) async throws
    func create(_ intent: TopicSelfPlayIntent) async throws -> RegistrationCreateResult
    func paymentParameters(registrationID: Int) async throws -> [String: String]
    func readOrder(registrationID: Int) async throws -> OrderLifecycleDetail
}
/// Each method is an exact single request except consent, which explicitly re-reads proof.
/// No endpoint, credential, document version, SDK, retry, or success value is synthesized.
@MainActor public final class TopicSelfPlayHTTPClient: TopicSelfPlayServing {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    private let credentials: () -> PublishingCredentials?
    private let consent: AccountComplianceService
    private let complianceSession: () -> ComplianceSession?
    private let documentProvider: any TopicSelfPlayDocumentProviding
    private let captured: RuntimeDependencyContext
    private let current: () -> RuntimeDependencyContext?
    public init(configuration: APIConfiguration, transport: any HTTPTransport, consent: AccountComplianceService,
                complianceSession: @escaping () -> ComplianceSession?, documentProvider: any TopicSelfPlayDocumentProviding,
                captured: RuntimeDependencyContext, current: @escaping () -> RuntimeDependencyContext?,
                credentials: @escaping () -> PublishingCredentials?) {
        self.configuration = configuration; self.transport = transport; self.consent = consent
        self.complianceSession = complianceSession; self.documentProvider = documentProvider; self.captured = captured
        self.current = current; self.credentials = credentials
    }
    public var session: PublishingSession? { credentials()?.session }
    public var configured: Bool { current() == captured && captured.market == .china && ["player", "club"].contains(captured.role) }
    private func capture() throws -> PublishingCredentials {
        guard configured, let credential = credentials(), credential.session.accountID == captured.session.accountID,
              credential.session.namespace == captured.session.namespace, credential.token == captured.session.token else { throw TopicSelfPlayFailure.changed }
        try Task.checkCancellation(); return credential
    }
    private func check(_ credential: PublishingCredentials) throws { guard try capture() == credential else { throw TopicSelfPlayFailure.changed } }
    public func document() async throws -> TopicSelfPlayDocument {
        let credential = try capture(); let value = try await documentProvider.currentDocument(context: captured); try check(credential); return value
    }
    public func freshTopic(_ topic: SelfPlayTopicID) async throws -> TopicDetail {
        let credential = try capture()
        let value = try await TopicService(configuration: configuration, transport: transport).detail(id: topic.rawValue, token: credential.token)
        try check(credential); return value
    }
    public func recordConsent(requestID: String, document: TopicSelfPlayDocument) async throws {
        let credential = try capture()
        guard try await self.document() == document, let scope = complianceSession(), scope.accountID == credential.session.accountID,
              scope.namespace == credential.session.namespace else { throw TopicSelfPlayFailure.consent }
        let evidence: ComplianceConsent
        if try consent.unresolved(ComplianceSubject.signup.operation, session: scope) != nil {
            evidence = try await consent.reconcileConsent(.signup, event: .agree, session: scope)
        } else { evidence = try await consent.consent(.signup, event: .agree, requestID: requestID, session: scope) }
        try check(credential)
        guard evidence.matches(.signup, event: .agree), evidence.docVersion == document.version else { throw TopicSelfPlayFailure.consent }
    }
    public func create(_ intent: TopicSelfPlayIntent) async throws -> RegistrationCreateResult {
        let credential = try capture()
        let request = try OperationAdapterHTTP.json(configuration: configuration, path: "api/registration/create", body: JSONEncoder().encode(intent), token: credential.token)
        let (data, status) = try await transport.send(request); try check(credential)
        guard (200..<300).contains(status) else { throw TopicSelfPlayFailure.unknown }
        return try JSONDecoder().decode(RegistrationCreateResponse.self, from: data).data
    }
    public func paymentParameters(registrationID: Int) async throws -> [String: String] {
        let credential = try capture()
        let request = try OrderLifecycleRequestContract.paymentParameters(registrationID: registrationID, baseURL: configuration.baseURL, token: credential.token)
        let (data, status) = try await transport.send(request); try check(credential)
        struct Envelope: Decodable { let code: Int; let data: Payload }
        struct Payload: Decodable { let payParams: [String: String] }
        guard (200..<300).contains(status), let envelope = try? JSONDecoder().decode(Envelope.self, from: data), envelope.code == 200,
              Self.validPaymentParameters(envelope.data.payParams) else { throw TopicSelfPlayFailure.unknown }
        return envelope.data.payParams
    }
    public static func validPaymentParameters(_ value: [String: String]) -> Bool {
        ["appId", "partnerId", "prepayId", "packageValue", "nonceStr", "timeStamp", "sign"].allSatisfy { value[$0]?.isEmpty == false }
            && (Int64(value["timeStamp"] ?? "") ?? 0) > 0
    }
    public func readOrder(registrationID: Int) async throws -> OrderLifecycleDetail {
        let credential = try capture()
        let value = try await OrderLifecycleService(configuration: configuration, transport: transport).detail(id: registrationID, token: credential.token)
        try check(credential); return value
    }
}
