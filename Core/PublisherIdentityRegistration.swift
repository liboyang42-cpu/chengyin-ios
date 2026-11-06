import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Registration never borrows activity creation or content editing approval.
public struct PublisherIdentityRegistrationGrants: Equatable {
    public let revision: UUID?
    public let read: OperationEndpointApproval?
    public let register: OperationEndpointApproval?
    public init(read: OperationEndpointApproval? = nil, register: OperationEndpointApproval? = nil) {
        revision = read == nil && register == nil ? nil : UUID()
        self.read = read; self.register = register
    }
}
@MainActor public protocol PublisherIdentityRegistrationHTTPTransport {
    func sendPublisherIdentityRegistration(_ request: URLRequest, session: PublishingSession,
        grants: PublisherIdentityRegistrationGrants) async throws -> (Data, Int)
}
public enum PublisherIdentityRegistrationWire {
    public static let statusPath = "api/publisher/identity/status"
    public static let registerPath = "api/publisher/identity"
    public static func path(_ request: URLRequest, configuration: APIConfiguration) -> String? {
        guard request.httpMethod == "POST", request.url?.query == nil, request.url?.fragment == nil,
              request.value(forHTTPHeaderField: "Content-Type") == "application/json",
              let bytes = request.httpBody,
              let fields = try? JSONDecoder().decode([String: ProjectEditJSON].self, from: bytes) else { return nil }
        if request.url == configuration.baseURL.appendingPathComponent(statusPath), fields.isEmpty { return statusPath }
        if request.url == configuration.baseURL.appendingPathComponent(registerPath),
           Set(fields.keys) == Set(["realName", "idCard", "consent", "source"]),
           fields["realName"]?.text != nil, fields["idCard"]?.text != nil,
           fields["consent"] == .bool(true), fields["source"] == .string("topic_publish"),
           let descriptor = try? PublishingIdentity.registration(name: fields["realName"]?.text ?? "",
               idCard: fields["idCard"]?.text ?? "", consent: true, source: "topic_publish", region: .china, registered: false,
               currentYear: Calendar(identifier: .gregorian).component(.year, from: Date())), descriptor.fields == fields { return registerPath }
        return nil
    }
}

/// Reuses the existing identity validation, explicit review and uncertainty journal.
/// The journal stores only an opaque owner/target/operation marker. Input is never persisted.
@MainActor public final class PublisherIdentityRegistrationService {
    private let gate: PublisherIdentityRegistrationGate
    private let auxiliary: PublishingAuxiliaryService
    private let journal: any OperationPendingJournal
    public let session: PublishingSession
    public init(configuration: APIConfiguration, transport: any HTTPTransport,
                grants: PublisherIdentityRegistrationGrants = .init(), journal: any OperationPendingJournal,
                session: PublishingSession, credentials: @escaping () -> PublishingCredentials?) {
        self.session = session; self.journal = journal
        let gate = PublisherIdentityRegistrationGate(configuration: configuration, transport: transport,
            grants: grants, session: session, credentials: credentials)
        self.gate = gate
        auxiliary = PublishingAuxiliaryService(configuration: configuration, transport: gate,
            approval: grants.register, journal: journal, credentials: { [weak gate] in gate?.currentCredentials })
    }
    public var currentSession: PublishingSession? { gate.currentCredentials?.session }
    public var configured: Bool { gate.configured }
    public func activate() { gate.activate() }
    public func retire() { gate.retire(); auxiliary.invalidate() }
    public func pending() throws -> OperationPendingRecord? {
        guard currentSession == session else { throw PublishModesError.changedSession }
        return try journal.pending(ownerKey: session.storageKey, targetKey: "publishingAuxiliary:api/publisher/identity")
    }
    public func status() async throws -> Bool { try await gate.status() }
    public func prepare(name: String, idCard: String, consent: Bool, currentYear: Int) throws -> PublishingAuxiliaryReview {
        guard configured, try pending() == nil else { throw PublishModesError.unavailable }
        return try auxiliary.prepareIdentity(name: name, idCard: idCard, consent: consent,
            source: "topic_publish", registered: false, currentYear: currentYear, session: session)
    }
    public func cancel(_ review: PublishingAuxiliaryReview) { auxiliary.cancel(review) }
    public func submit(_ review: PublishingAuxiliaryReview) async -> PublishingAuxiliaryOutcome {
        await auxiliary.confirm(review)
    }
}

@MainActor private final class PublisherIdentityRegistrationGate: HTTPTransport {
    let configuration: APIConfiguration
    let transport: any HTTPTransport
    let grants: PublisherIdentityRegistrationGrants
    let session: PublishingSession
    let credentials: () -> PublishingCredentials?
    private var visible = false
    private var visit = UUID()
    init(configuration: APIConfiguration, transport: any HTTPTransport, grants: PublisherIdentityRegistrationGrants,
         session: PublishingSession, credentials: @escaping () -> PublishingCredentials?) {
        self.configuration = configuration; self.transport = transport; self.grants = grants
        self.session = session; self.credentials = credentials
    }
    var currentCredentials: PublishingCredentials? {
        guard visible, session.region == .china, session.role == "club", let value = credentials(), value.session == session else { return nil }
        return value
    }
    func activate() { guard !visible else { return }; visit = UUID(); visible = true }
    func retire() { visible = false; visit = UUID() }
    private func permitted(_ path: String) -> Bool {
        let approval = path == PublisherIdentityRegistrationWire.statusPath ? grants.read : grants.register
        return approval?.allows(configuration: configuration, namespace: session.namespace, accountID: session.accountID, path: path) == true
    }
    var configured: Bool { currentCredentials != nil && permitted(PublisherIdentityRegistrationWire.statusPath) && permitted(PublisherIdentityRegistrationWire.registerPath) }
    func status() async throws -> Bool {
        guard let captured = currentCredentials else { throw PublishModesError.changedSession }
        let request = try OperationAdapterHTTP.json(configuration: configuration,
            path: PublisherIdentityRegistrationWire.statusPath, body: Data("{}".utf8), token: captured.token)
        let (data, status) = try await send(request)
        let body = try OperationAdapterHTTP.envelope(data)
        guard (200..<300).contains(status), body["code"]?.integer == 200,
              case .bool(let value)? = body["data"]?.object?["registered"] else { throw PublishModesError.invalidContract }
        return value
    }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        try Task.checkCancellation()
        guard let captured = currentCredentials,
              request.value(forHTTPHeaderField: "Authorization").map({ Data($0.utf8) }) == Data(captured.token.utf8),
              let path = PublisherIdentityRegistrationWire.path(request, configuration: configuration), permitted(path) else { throw PublishModesError.unavailable }
        let stamp = visit
        let response: (Data, Int)
        if let typed = transport as? any PublisherIdentityRegistrationHTTPTransport {
            response = try await typed.sendPublisherIdentityRegistration(request, session: session, grants: grants)
        } else { response = try await transport.send(request) }
        try Task.checkCancellation()
        guard stamp == visit, currentCredentials == captured else { throw PublishModesError.changedSession }
        // A malformed apparent success stays uncertain; auxiliary must not clear its marker.
        if path == PublisherIdentityRegistrationWire.registerPath, (200..<300).contains(response.1),
           let body = try? OperationAdapterHTTP.envelope(response.0), body["code"]?.integer == 200 {
            guard body["data"]?.object?["registered"] == .bool(true) else { throw PublishModesError.invalidContract }
        }
        return response
    }
}
