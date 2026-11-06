import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct NativeWebhookScope: Codable, Hashable, Sendable {
    public let ownerID: NativeWebhookID
    public let channelID: NativeWebhookID
    public var ownerType: String { "CLUB" }
    public init(ownerID: NativeWebhookID, channelID: NativeWebhookID) { self.ownerID = ownerID; self.channelID = channelID }
}

/// Binding supplied by the existing session/channel authority. Its fields are isolation keys, never grants.
public struct NativeWebhookBinding: Codable, Hashable, Sendable {
    public let accountID: String
    public let market: String
    public let namespace: String
    public let origin: URL
    public let scope: NativeWebhookScope
    public let authorizationVersion: String
    public init(accountID: String, market: String, namespace: String, origin: URL,
                scope: NativeWebhookScope, authorizationVersion: String) throws {
        guard NativeWebhookID(rawValue: accountID) != nil, !market.isEmpty, !namespace.isEmpty, !authorizationVersion.isEmpty,
              origin.scheme == "https", origin.host != nil, origin.user == nil, origin.password == nil,
              origin.query == nil, origin.fragment == nil,
              !origin.path.split(separator: "/").contains("..") else {
            throw NativeWebhookClientError.sourceUnavailable("WEBHOOK_CONTEXT_UNAVAILABLE")
        }
        self.accountID = accountID; self.market = market; self.namespace = namespace
        self.origin = origin; self.scope = scope; self.authorizationVersion = authorizationVersion
    }
    private var identityBytes: [Data] { [accountID, market, namespace, origin.absoluteString, authorizationVersion].map { Data($0.utf8) } }
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.scope == rhs.scope && lhs.identityBytes == rhs.identityBytes }
    public func hash(into hasher: inout Hasher) { hasher.combine(scope); hasher.combine(identityBytes) }
    private enum CodingKeys: String, CodingKey { case accountID, market, namespace, origin, scope, authorizationVersion }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(accountID: values.decode(String.self, forKey: .accountID), market: values.decode(String.self, forKey: .market),
                      namespace: values.decode(String.self, forKey: .namespace), origin: values.decode(URL.self, forKey: .origin),
                      scope: values.decode(NativeWebhookScope.self, forKey: .scope), authorizationVersion: values.decode(String.self, forKey: .authorizationVersion))
    }
}

public struct NativeWebhookEventOption: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public init(id: String, title: String) { self.id = id; self.title = title }
}

public enum NativeWebhookEventCatalogue: Equatable, Sendable {
    case available(revision: String, options: [NativeWebhookEventOption])
    case unavailable(code: String)
    public var options: [NativeWebhookEventOption]? {
        if case .available(_, let options) = self { return options }; return nil
    }
}

public struct NativeWebhookContext: Equatable, Sendable {
    public let binding: NativeWebhookBinding
    public let eventCatalogue: NativeWebhookEventCatalogue
    public init(binding: NativeWebhookBinding, eventCatalogue: NativeWebhookEventCatalogue) {
        self.binding = binding; self.eventCatalogue = eventCatalogue
    }
}

/// Implemented by root using the real new-channel resolver and existing native/RBAC source.
/// No default provider, conversation-to-channel cast, header proof or allow-all implementation is supplied.
@MainActor public protocol NativeWebhookScopeProvider: AnyObject {
    func currentContext() async throws -> NativeWebhookContext
    func revalidate(_ binding: NativeWebhookBinding) async throws -> NativeWebhookContext
}

/// Root uses the current original session credential at request time. Never persist it in a factory or journal.
@MainActor public protocol NativeWebhookRequestAuthorizer: AnyObject {
    func authorize(_ request: URLRequest, binding: NativeWebhookBinding) async throws -> URLRequest
    func unauthorized(_ binding: NativeWebhookBinding)
}

/// Minimal consumer of the original runtime context, raw-token request convention and
/// exact OperationEndpointApproval. The lookup must come from 7/27's reviewed source;
/// this adapter validates isolation, and does not issue native identity or RBAC grants.
@MainActor public final class NativeWebhookRuntimeScopeProvider: NativeWebhookScopeProvider, NativeWebhookRequestAuthorizer {
    private let captured: RuntimeDependencyContext
    private let expectedScope: NativeWebhookScope
    private let current: () -> RuntimeDependencyContext?
    private let lookup: () async throws -> NativeWebhookContext
    private let endpointApproval: () -> OperationEndpointApproval?
    private let onUnauthorized: (RuntimeDependencyContext) -> Void
    public init(captured: RuntimeDependencyContext, scope: NativeWebhookScope, current: @escaping () -> RuntimeDependencyContext?,
                lookup: @escaping () async throws -> NativeWebhookContext,
                endpointApproval: @escaping () -> OperationEndpointApproval?, onUnauthorized: @escaping (RuntimeDependencyContext) -> Void) {
        self.captured = captured; self.expectedScope = scope; self.current = current; self.lookup = lookup; self.endpointApproval = endpointApproval
        self.onUnauthorized = onUnauthorized
    }
    public func currentContext() async throws -> NativeWebhookContext {
        guard current() == captured else { throw NativeWebhookClientError.scopeChanged }
        let value = try await lookup()
        guard current() == captured, value.binding.scope == expectedScope, value.binding.accountID == String(captured.session.accountID),
              value.binding.namespace.utf8.elementsEqual(captured.session.namespace.utf8),
              value.binding.origin.absoluteString.utf8.elementsEqual(captured.baseURL.absoluteString.utf8),
              value.binding.market == captured.market.rawValue else { throw NativeWebhookClientError.scopeChanged }
        return value
    }
    public func revalidate(_ binding: NativeWebhookBinding) async throws -> NativeWebhookContext {
        let value = try await currentContext()
        guard value.binding == binding else { throw NativeWebhookClientError.scopeChanged }; return value
    }
    public func authorize(_ request: URLRequest, binding: NativeWebhookBinding) async throws -> URLRequest {
        _ = try await revalidate(binding)
        let configuration = try APIConfiguration(baseURL: captured.baseURL)
        guard let url = request.url, url.scheme == binding.origin.scheme, url.host == binding.origin.host,
              url.port == binding.origin.port, url.user == nil, url.password == nil, url.fragment == nil,
              var target = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let approval = endpointApproval(), AuthRequestBuilder.isValidToken(captured.session.token),
              approval.baseURL.absoluteString.utf8.elementsEqual(configuration.baseURL.absoluteString.utf8),
              approval.namespace.utf8.elementsEqual(captured.session.namespace.utf8) else {
            throw NativeWebhookClientError.sourceUnavailable("WEBHOOK_REVIEWED_ENDPOINT_APPROVAL_UNAVAILABLE")
        }
        target.query = nil
        guard let targetURL = target.url,
              approval.paths.contains(where: { path in
                  guard let canonical = try? NativeWebhookRuntimeRoute.url(binding: binding, path: "/" + path) else { return false }
                  return approval.allows(configuration: configuration, namespace: captured.session.namespace,
                          accountID: captured.session.accountID, path: path)
                      && canonical.absoluteString.utf8.elementsEqual(targetURL.absoluteString.utf8)
              }), current() == captured else {
            throw NativeWebhookClientError.sourceUnavailable("WEBHOOK_REVIEWED_ENDPOINT_APPROVAL_UNAVAILABLE")
        }
        var authorized = request
        authorized.setValue(captured.session.token, forHTTPHeaderField: "Authorization")
        return authorized
    }
    public func unauthorized(_ binding: NativeWebhookBinding) {
        guard current() == captured, binding.accountID == String(captured.session.accountID),
              binding.namespace == captured.session.namespace, binding.origin == captured.baseURL else { return }
        onUnauthorized(captured)
    }
}

/// Supplied at the original AppCompositionRoot only after real resolver/native/RBAC and
/// event catalogue sources are wired. A nil factory keeps ordinary composition closed.
@MainActor public protocol NativeWebhookRuntimeFactory {
    func make(captured: RuntimeDependencyContext, scope: NativeWebhookScope,
              current: @escaping () -> RuntimeDependencyContext?, journal: any OperationPendingJournal,
              onUnauthorized: @escaping (RuntimeDependencyContext) -> Void) throws -> NativeWebhookCoordinator
}

/// Concrete composition of the existing service/provider/journal. The original owner
/// supplies its real resolver and operation approval; this factory issues neither.
/// Construction does not resolve, send, generate credentials or replay pending work.
@MainActor public final class NativeWebhookConfiguredRuntimeFactory: NativeWebhookRuntimeFactory {
    public typealias Lookup = (RuntimeDependencyContext, NativeWebhookScope) async throws -> NativeWebhookContext
    public typealias Approval = (RuntimeDependencyContext, NativeWebhookScope) -> OperationEndpointApproval?
    private let transport: any HTTPTransport
    private let lookup: Lookup
    private let approval: Approval
    public init(transport: any HTTPTransport, lookup: @escaping Lookup, approval: @escaping Approval) {
        self.transport = transport; self.lookup = lookup; self.approval = approval
    }
    public func make(captured: RuntimeDependencyContext, scope: NativeWebhookScope,
                     current: @escaping () -> RuntimeDependencyContext?, journal: any OperationPendingJournal,
                     onUnauthorized: @escaping (RuntimeDependencyContext) -> Void) throws -> NativeWebhookCoordinator {
        guard current() == captured else { throw NativeWebhookClientError.scopeChanged }
        let provider = NativeWebhookRuntimeScopeProvider(captured: captured, scope: scope, current: current,
            lookup: { [lookup] in
                guard current() == captured else { throw NativeWebhookClientError.scopeChanged }
                return try await lookup(captured, scope)
            }, endpointApproval: { [approval] in
                guard current() == captured else { return nil }
                return approval(captured, scope)
            }, onUnauthorized: onUnauthorized)
        let service = NativeWebhookHTTPService(provider: provider, authorizer: provider, transport: transport)
        return NativeWebhookCoordinator(service: service, provider: provider,
            journal: NativeWebhookPendingJournal(journal: journal))
    }
}

/// Paired with the first-party ChannelWebhookManagementContextService candidate.
/// Uses the caller's original transport and exact reviewed context route. It does not
/// enable that route or manufacture a native/channel permission from stored metadata.
@MainActor public final class NativeWebhookManagementContextSource {
    private let transport: any HTTPTransport
    private let current: () -> RuntimeDependencyContext?
    private let approval: NativeWebhookConfiguredRuntimeFactory.Approval
    private let onUnauthorized: (RuntimeDependencyContext) -> Void
    public init(transport: any HTTPTransport, current: @escaping () -> RuntimeDependencyContext?,
                approval: @escaping NativeWebhookConfiguredRuntimeFactory.Approval,
                onUnauthorized: @escaping (RuntimeDependencyContext) -> Void) {
        self.transport = transport; self.current = current; self.approval = approval; self.onUnauthorized = onUnauthorized
    }
    public func context(_ captured: RuntimeDependencyContext, scope: NativeWebhookScope) async throws -> NativeWebhookContext {
        let path = "api/im/webhook/context"
        guard current() == captured, let grant = approval(captured, scope),
              grant.allows(configuration: try APIConfiguration(baseURL: captured.baseURL),
                namespace: captured.session.namespace, accountID: captured.session.accountID, path: path),
              AuthRequestBuilder.isValidToken(captured.session.token) else {
            throw NativeWebhookClientError.sourceUnavailable("WEBHOOK_CONTEXT_ENDPOINT_APPROVAL_UNAVAILABLE")
        }
        var parts = URLComponents(url: captured.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        parts.queryItems = [URLQueryItem(name: "owner_id", value: scope.ownerID.rawValue),
                            URLQueryItem(name: "channel_id", value: scope.channelID.rawValue)]
        guard let url = parts.url else { throw NativeWebhookClientError.invalidWire }
        var request = URLRequest(url: url); request.httpMethod = "GET"; request.httpShouldHandleCookies = false
        request.setValue(captured.session.token, forHTTPHeaderField: "Authorization")
        try Task.checkCancellation()
        let (data, status) = try await transport.send(request)
        guard current() == captured, let live = approval(captured, scope), live == grant,
              live.allows(configuration: try APIConfiguration(baseURL: captured.baseURL),
                namespace: captured.session.namespace, accountID: captured.session.accountID, path: path) else {
            throw NativeWebhookClientError.scopeChanged
        }
        try Task.checkCancellation()
        guard data.count <= 64 * 1024 else { throw NativeWebhookClientError.invalidWire }
        struct Envelope: Decodable { let code: Int; let data: Body? }
        struct Body: Decodable {
            let actor_id: String; let owner_type: String; let owner_id: String; let channel_id: String
            let authorization_version: String; let management_permission: String
            let event_revision: String; let events: [NativeWebhookEventOption]
        }
        let envelope = try? JSONDecoder().decode(Envelope.self, from: data)
        if status == 401 || envelope?.code == 401 { onUnauthorized(captured); throw APIError.unauthorized }
        guard (200..<300).contains(status), let envelope, envelope.code == 200, let body = envelope.data else {
            throw NativeWebhookClientError.sourceUnavailable("WEBHOOK_CURRENT_MANAGEMENT_CONTEXT_UNAVAILABLE")
        }
        guard body.actor_id == String(captured.session.accountID), body.owner_type == "CLUB",
              body.owner_id == scope.ownerID.rawValue, body.channel_id == scope.channelID.rawValue,
              body.management_permission == "im:webhook:manage", !body.authorization_version.isEmpty,
              !body.event_revision.isEmpty, body.events.count <= 32,
              Set(body.events.map(\.id)).count == body.events.count,
              body.events.allSatisfy({ !$0.id.isEmpty && !$0.title.isEmpty }) else { throw NativeWebhookClientError.invalidWire }
        let binding = try NativeWebhookBinding(accountID: body.actor_id, market: captured.market.rawValue,
            namespace: captured.session.namespace, origin: captured.baseURL, scope: scope,
            authorizationVersion: body.authorization_version)
        return NativeWebhookContext(binding: binding, eventCatalogue: .available(revision: body.event_revision, options: body.events))
    }
}
