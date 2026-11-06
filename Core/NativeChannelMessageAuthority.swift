import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The source-owned adapter must check this at the real final forward, with no retry,
/// redirect, cookie or generic-session fallback. A preflight check alone is insufficient.
@MainActor public struct NativeChannelMessageDispatchFence {
    private let check: () -> Bool
    public init(check: @escaping () -> Bool) { self.check = check }
    public var isCurrent: Bool { !Task.isCancelled && check() }
}
@MainActor public protocol NativeChannelMessageDispatching {
    func send(_ request: URLRequest, fence: NativeChannelMessageDispatchFence) async throws -> (Data, Int)
}

public enum NativeChannelMessageCapability: Hashable {
    case receipt, mutations, revisions, pins, search, context
    case mutate(NativeChannelMessageOperation)
}

/// Supplied by the source-owned live authority adapter. No local role/default grants.
/// `receipt` is independent so an original APPLIED receipt can be redacted after revocation.
@MainActor public protocol NativeChannelMessageAuthorizing: AnyObject {
    var identity: MessagingReadIdentity? { get }
    func credentials(for capability: NativeChannelMessageCapability,
                     binding: NativeChannelMessageBinding) throws -> NativeChannelMessageCredentials
}

public struct NativeChannelMessageCredentials: Equatable {
    public let identity: MessagingReadIdentity
    public let namespace: String
    public let baseURL: URL
    public let binding: NativeChannelMessageBinding
    public let authorityRevision: String
    public let token: String
    public init(identity: MessagingReadIdentity, namespace: String, baseURL: URL,
                binding: NativeChannelMessageBinding, authorityRevision: String, token: String) throws {
        _ = try APIConfiguration(baseURL: baseURL)
        guard identity.accountID > 0, !namespace.isEmpty, !authorityRevision.isEmpty,
              AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidConfiguration }
        self.identity = identity; self.namespace = namespace; self.baseURL = baseURL
        self.binding = binding; self.authorityRevision = authorityRevision; self.token = token
    }
}

/// Persisted identity deliberately excludes the transient epoch and credentials.
public struct NativeChannelMessageScope: Codable, Equatable {
    public let accountID: String
    public let namespace: String
    public let baseURL: String
    public let binding: NativeChannelMessageBinding
    public init(credentials: NativeChannelMessageCredentials) {
        accountID = String(credentials.identity.accountID); namespace = credentials.namespace
        baseURL = credentials.baseURL.absoluteString; binding = credentials.binding
    }
    public static func == (a: Self, b: Self) -> Bool {
        a.accountID == b.accountID && a.namespace.utf8.elementsEqual(b.namespace.utf8)
            && a.baseURL.utf8.elementsEqual(b.baseURL.utf8) && a.binding.sameTarget(as: b.binding)
    }
    var storageKey: String {
        let values = [accountID, namespace, baseURL, binding.channelID.rawValue, binding.conversationID.rawValue]
        return "native-channel-message.v1." + Data(values.map { "\($0.utf8.count):\($0)" }.joined().utf8).base64EncodedString()
    }
}
