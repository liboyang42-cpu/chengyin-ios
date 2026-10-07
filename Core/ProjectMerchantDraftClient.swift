import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct ProjectMerchantDraftCredentials: Equatable {
    public let session: ProjectEditSession
    fileprivate let token: String
    public init(session: ProjectEditSession, token: String) throws {
        guard AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        self.session = session; self.token = token
    }
}
@MainActor public protocol ProjectMerchantDraftReading: AnyObject {
    var identity: UUID { get }
    func isCurrent(session: ProjectEditSession) -> Bool
    func list(beforeSourceID: Int?, session: ProjectEditSession) async throws -> ProjectMerchantDraftPage
    func resolve(_ choice: ProjectMerchantDraftChoice, merchantRowID: Int, session: ProjectEditSession) async throws -> ProjectMerchantDraftResolution
}

/// Separate exact owner-read grants. Default construction dispatches nothing; neither
/// publishingRead.templates nor a project write grant can activate these routes.
@MainActor public final class ProjectMerchantDraftClient: ProjectMerchantDraftReading {
    public let identity = UUID()
    private let configuration: APIConfiguration
    private let approval: OperationEndpointApproval?
    private let transport: any HTTPTransport
    private let currentCredentials: () -> ProjectMerchantDraftCredentials?
    private let currentCapability: (String) -> Bool
    public init(configuration: APIConfiguration, approval: OperationEndpointApproval? = nil, transport: any HTTPTransport,
                currentCredentials: @escaping () -> ProjectMerchantDraftCredentials?, currentCapability: @escaping (String) -> Bool = { _ in false }) {
        self.configuration = configuration; self.approval = approval; self.transport = transport
        self.currentCredentials = currentCredentials; self.currentCapability = currentCapability
    }
    private func permits(_ path: String, session: ProjectEditSession) -> Bool {
        guard currentCapability(path), currentCredentials()?.session == session, let approval else { return false }
        return approval.allows(configuration: configuration, namespace: session.storageNamespace, accountID: session.accountID, path: path)
    }
    public func isCurrent(session: ProjectEditSession) -> Bool {
        permits(ProjectMerchantDraftPath.list, session: session) && permits(ProjectMerchantDraftPath.resolve, session: session)
    }
    public func list(beforeSourceID: Int?, session: ProjectEditSession) async throws -> ProjectMerchantDraftPage {
        let body = try ProjectMerchantDraftWire.listFields(beforeSourceID: beforeSourceID)
        let value = try await send(body, session: session, path: ProjectMerchantDraftPath.list)
        return try .decode(value, accountID: session.accountID, beforeSourceID: beforeSourceID)
    }
    public func resolve(_ choice: ProjectMerchantDraftChoice, merchantRowID: Int, session: ProjectEditSession) async throws -> ProjectMerchantDraftResolution {
        guard merchantRowID > 0 else { throw ProjectMerchantDraftError.invalidResponse }
        let value = try await send(choice.resolveFields, session: session, path: ProjectMerchantDraftPath.resolve)
        return try .decode(value, accountID: session.accountID, merchantRowID: merchantRowID, expected: choice)
    }
    private func send(_ body: [String: ProjectEditJSON], session: ProjectEditSession, path: String) async throws -> ProjectEditJSON {
        try Task.checkCancellation()
        guard isCurrent(session: session), let credentials = currentCredentials(), credentials.session == session else { throw ProjectMerchantDraftError.notConfigured }
        guard ProjectMerchantDraftWire.permitsRequest(body, path: path) else { throw ProjectMerchantDraftError.invalidResponse }
        let encoded = try JSONEncoder().encode(body)
        let request = try OperationAdapterHTTP.json(configuration: configuration, path: path, body: encoded, token: credentials.token)
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation()
        guard currentCredentials() == credentials, isCurrent(session: session) else { throw ProjectMerchantDraftError.changedContext }
        if status == 401 { throw APIError.unauthorized }
        if status == 403 { throw ProjectMerchantDraftError.forbidden }
        if status == 409 { throw ProjectMerchantDraftError.sourceChanged }
        guard data.count <= 64 * 1024 else { throw ProjectMerchantDraftError.invalidResponse }
        let envelope: [String: ProjectEditJSON]
        do { envelope = try ApprovedTopicReleaseWire.envelope(data) }
        catch { throw ProjectMerchantDraftError.invalidResponse }
        switch envelope["code"]?.integer {
        case 401: throw APIError.unauthorized
        case 403: throw ProjectMerchantDraftError.forbidden
        case 409: throw ProjectMerchantDraftError.sourceChanged
        default: break
        }
        guard (200..<300).contains(status), envelope["code"] == .number(200), let value = envelope["data"] else { throw ProjectMerchantDraftError.unavailable }
        return value
    }
}
