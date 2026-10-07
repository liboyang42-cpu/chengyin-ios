import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct ProjectStoryTemplateCredentials: Equatable {
    public let session: ProjectEditSession
    fileprivate let token: String
    public init(session: ProjectEditSession, token: String) throws {
        guard AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        self.session = session; self.token = token
    }
}

public enum ProjectStoryTemplatePath {
    public static let list = "api/template/my-list"
    public static let detail = "api/template/myinfo"
}

@MainActor public protocol ProjectStoryTemplateReading: AnyObject {
    var identity: UUID { get }
    func isCurrent(session: ProjectEditSession) -> Bool
    func list(page: Int, session: ProjectEditSession) async throws -> ProjectStoryTemplatePage
    func detail(id: MemberPlayTemplateID, session: ProjectEditSession) async throws -> ProjectStoryTemplateDraft
}

/// Personal saved-draft reads only. Both exact endpoint approval and live capability
/// are required; construction is off by default. Reading never grants local adoption,
/// mutation, public-library fallback, merchant scope, or publication authority.
@MainActor public final class ProjectStoryTemplateClient: ProjectStoryTemplateReading {
    public let identity = UUID()
    private let configuration: APIConfiguration
    private let approval: OperationEndpointApproval?
    private let transport: any HTTPTransport
    private let currentCredentials: () -> ProjectStoryTemplateCredentials?
    private let currentCapability: (String) -> Bool

    public init(configuration: APIConfiguration, approval: OperationEndpointApproval? = nil,
                transport: any HTTPTransport, currentCredentials: @escaping () -> ProjectStoryTemplateCredentials?,
                currentCapability: @escaping (String) -> Bool = { _ in false }) {
        self.configuration = configuration; self.approval = approval; self.transport = transport
        self.currentCredentials = currentCredentials; self.currentCapability = currentCapability
    }

    private func permits(_ path: String, session: ProjectEditSession) -> Bool {
        guard currentCapability(path), currentCredentials()?.session == session, let approval else { return false }
        return approval.allows(configuration: configuration, namespace: session.storageNamespace,
                               accountID: session.accountID, path: path)
    }

    public func isCurrent(session: ProjectEditSession) -> Bool {
        permits(ProjectStoryTemplatePath.list, session: session) && permits(ProjectStoryTemplatePath.detail, session: session)
    }

    public func list(page: Int, session: ProjectEditSession) async throws -> ProjectStoryTemplatePage {
        guard (1...ProjectStoryTemplatePage.maximumPages).contains(page) else { throw ProjectStoryTemplateError.invalidResponse }
        return try await read(.list(page), session: session) {
            try ProjectStoryTemplatePage.decode($0, accountID: session.accountID, page: page)
        }
    }

    public func detail(id: MemberPlayTemplateID, session: ProjectEditSession) async throws -> ProjectStoryTemplateDraft {
        try await read(.detail(id), session: session) {
            try ProjectStoryTemplateDraft.decode($0, accountID: session.accountID, requestedID: id)
        }
    }

    /// No caller-supplied request descriptor, arbitrary path, or extra form fields.
    private enum Route {
        case list(Int), detail(MemberPlayTemplateID)
        var path: String {
            switch self {
            case .list: return ProjectStoryTemplatePath.list
            case .detail: return ProjectStoryTemplatePath.detail
            }
        }
        var fields: [String: String] {
            switch self {
            case .list(let page):
                return ["draft_status": "0", "scope": "", "pageNum": String(page),
                        "pageSize": String(ProjectStoryTemplatePage.pageSize)]
            case .detail(let id): return ["id": String(id.rawValue)]
            }
        }
    }

    private func requireCurrent(_ credentials: ProjectStoryTemplateCredentials) throws {
        try Task.checkCancellation()
        guard currentCredentials() == credentials, isCurrent(session: credentials.session) else {
            throw ProjectStoryTemplateError.changedContext
        }
    }

    private func read<Value>(_ route: Route, session: ProjectEditSession,
                             decode: (ProjectEditJSON) throws -> Value) async throws -> Value {
        try Task.checkCancellation()
        guard isCurrent(session: session), let credentials = currentCredentials(), credentials.session == session else {
            throw ProjectStoryTemplateError.notConfigured
        }
        let request = try AuthRequestBuilder.makeFormRequest(
            url: configuration.baseURL.appendingPathComponent(route.path), fields: route.fields, token: credentials.token)
        do {
            let (data, status) = try await transport.send(request)
            try requireCurrent(credentials)
            if status == 401 { throw APIError.unauthorized }
            if status == 409 { throw ProjectStoryTemplateError.sourceChanged }
            guard (200..<300).contains(status) else { throw APIError.httpStatus(status) }
            guard data.count <= 1024 * 1024 else { throw ProjectStoryTemplateError.invalidResponse }
            let envelope: [String: ProjectEditJSON]
            do { envelope = try ApprovedTopicReleaseWire.envelope(data) }
            catch { throw ProjectStoryTemplateError.invalidResponse }
            guard let code = envelope["code"]?.integer else { throw ProjectStoryTemplateError.invalidResponse }
            if code == 401 { throw APIError.unauthorized }
            if code == 409 { throw ProjectStoryTemplateError.sourceChanged }
            guard code == 200 else { throw APIError.businessCode(code) }
            guard let raw = envelope["data"] else { throw ProjectStoryTemplateError.invalidResponse }
            let value = try decode(raw)
            try requireCurrent(credentials)
            return value
        } catch {
            // A late failure belongs to the captured account just as a late success
            // does. It must not escape into the replacement account/session.
            try requireCurrent(credentials)
            throw error
        }
    }
}
