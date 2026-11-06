import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Explicit first-party endpoint approval, not a server role, membership or appeal decision.
/// The reviewed deployment must select this policy. Authentication and notices never create it.
public struct NativeChannelAppealEndpointPolicy: Equatable {
    public enum Right: String, Hashable {
        case moderationRead, appealRead, submit, evidence, withdraw, originalReceipt
    }
    public let baseURL: URL
    public let namespace: String
    public let revision: UUID
    public let rights: Set<Right>
    public init(baseURL: URL, namespace: String, rights: Set<Right>, revision: UUID = UUID()) throws {
        _ = try APIConfiguration(baseURL: baseURL)
        guard !namespace.isEmpty, !rights.isEmpty else { throw APIError.invalidConfiguration }
        self.baseURL = baseURL; self.namespace = namespace; self.rights = rights; self.revision = revision
    }
    func matches(_ context: RuntimeDependencyContext) -> Bool {
        context.market == .china && context.baseURL == baseURL && context.session.namespace == namespace && context.session.accountID > 0
    }
}

/// Owned by reviewed composition. A replacement (including same-right replacement) invalidates
/// all previously issued objects. Receipt-only policies can restore without restoring a writer.
@MainActor @Observable public final class NativeChannelAppealPolicyStore {
    public private(set) var selected: NativeChannelAppealEndpointPolicy?
    private(set) var generation = UUID()
    public init(_ selected: NativeChannelAppealEndpointPolicy? = nil) { self.selected = selected }
    public func replace(with policy: NativeChannelAppealEndpointPolicy?) { generation = UUID(); selected = policy }
}

/// A body-bound original command. This is not an authorization and is never derived from a
/// receipt's historical can_add_evidence/status. Only the Flow's validated journal creates recovery input.
struct NativeChannelAppealOriginalCommand: Equatable {
    let operation: NativeChannelAppealFlow.Operation
    let requestID: String
    let path: String
    let body: Data
}

@MainActor public final class NativeChannelAppealRuntimeAuthorization {
    private struct IssuedCommand {
        let original: NativeChannelAppealOriginalCommand
        let pendingMatches: () -> Bool
    }
    let context: RuntimeDependencyContext
    private let notice: NativeChannelGovernanceNotice
    private let store: NativeChannelAppealPolicyStore
    private let policy: NativeChannelAppealEndpointPolicy
    private let generation: UUID
    private let current: () -> Bool
    private var readIDs: Set<String> = []
    private var verifiedAppealIDs: Set<String> = []
    private var recoveryPaths: Set<String> = []
    private var commands: [String: IssuedCommand] = [:]

    fileprivate init?(notice: NativeChannelGovernanceNotice, context: RuntimeDependencyContext,
                      store: NativeChannelAppealPolicyStore, current: @escaping () -> Bool) {
        guard let policy = store.selected, policy.matches(context), current(), notice.recipientID == context.session.accountID,
              [1, 2, 3].contains(notice.guildKind), NativeChannelGovernanceNotice.positive(notice.guildID) != nil,
              NativeChannelGovernanceNotice.positive(notice.actionID) != nil else { return nil }
        self.notice = notice; self.context = context; self.store = store
        self.policy = policy; self.generation = store.generation; self.current = current
    }
    var isCurrent: Bool { current() && store.generation == generation && store.selected == policy && policy.matches(context) }
    private func allows(_ right: NativeChannelAppealEndpointPolicy.Right) -> Bool { isCurrent && policy.rights.contains(right) }
    private func receiptPath(_ id: String) -> String { "api/channel-platform/governance/moderation/requests/" + id }
    private func canonicalUUID(_ id: String) -> Bool { UUID(uuidString: id)?.uuidString.lowercased() == id }
    private func appealPathID(_ path: String, suffix: String? = nil) -> String? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == (suffix == nil ? 4 : 5), Array(parts.prefix(3)) == ["api", "im", "appeals"],
              let id = NativeChannelGovernanceNotice.positive(parts[3]), suffix == nil || parts[4] == suffix else { return nil }
        return id
    }
    /// A locator chooses an exact own-appeal read under an independent reviewed read policy.
    /// It grants no writer and the Flow must still validate the returned actor/action/appeal.
    func locateCurrentAppeal(_ path: String) {
        guard allows(.appealRead), let id = appealPathID(path) else { return }
        readIDs.insert(id)
    }
    func acceptCurrentAppeal(_ id: String) {
        guard isCurrent, NativeChannelGovernanceNotice.positive(id) != nil else { return }
        verifiedAppealIDs.insert(id)
    }
    func permits(_ method: String, _ path: String) -> Bool {
        guard isCurrent else { return false }
        if method == "GET" {
            if path == "api/im/moderation/me" { return allows(.moderationRead) }
            if let id = appealPathID(path) { return allows(.appealRead) && readIDs.contains(id) }
            return allows(.originalReceipt) && commands.values.contains { receiptPath($0.original.requestID) == path }
        }
        guard method == "POST" else { return false }
        if path == "api/im/appeals" { return allows(.submit) }
        if let id = appealPathID(path, suffix: "evidence") { return allows(.evidence) && (verifiedAppealIDs.contains(id) || recoveryPaths.contains(path)) }
        if let id = appealPathID(path, suffix: "withdraw") { return allows(.withdraw) && (verifiedAppealIDs.contains(id) || recoveryPaths.contains(path)) }
        return false
    }
    /// Narrow an independently approved receipt right to this original UUID and exact bytes.
    /// A writer is required for fresh issuance, but deliberately not for recovery issuance.
    func issue(_ original: NativeChannelAppealOriginalCommand, recovering: Bool, pendingMatches: @escaping () -> Bool) -> Bool {
        guard allows(.originalReceipt), valid(original), recovering || permits("POST", original.path) else { return false }
        if let existing = commands[original.requestID], existing.original != original { return false }
        if recovering, !pendingMatches() { return false }
        // Restoring a validated original may select its existing write path only. The
        // independent writer policy is still checked on every retry and dispatch.
        if recovering { recoveryPaths.insert(original.path) }
        commands[original.requestID] = IssuedCommand(original: original, pendingMatches: pendingMatches)
        return true
    }
    func finish(_ requestID: String) {
        guard let removed = commands.removeValue(forKey: requestID) else { return }
        if !commands.values.contains(where: { $0.original.path == removed.original.path }) { recoveryPaths.remove(removed.original.path) }
    }
    private func valid(_ original: NativeChannelAppealOriginalCommand) -> Bool {
        guard canonicalUUID(original.requestID), original.body.count <= 8192,
              let body = try? JSONSerialization.jsonObject(with: original.body) as? [String: Any],
              let canonical = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys, .withoutEscapingSlashes]), canonical == original.body else { return false }
        func text(_ key: String) -> String? {
            guard let text = body[key] as? String, !text.isEmpty,
                  text == text.trimmingCharacters(in: .whitespacesAndNewlines), text.utf16.count <= 500 else { return nil }
            return text
        }
        switch original.operation {
        case .submit:
            return original.path == "api/im/appeals" && Set(body.keys) == ["guild_kind", "guild_id", "action_id", "reason_code", "reason_text", "submit_request_id"] &&
                NativeChannelGovernanceNotice.positive(body["guild_kind"]) == String(notice.guildKind) &&
                body["guild_id"] as? String == notice.guildID && body["action_id"] as? String == notice.actionID &&
                body["reason_code"] as? String == "MISJUDGE" && text("reason_text") != nil && body["submit_request_id"] as? String == original.requestID
        case .evidence:
            guard appealPathID(original.path, suffix: "evidence") != nil, Set(body.keys) == ["request_id", "evidence_json"],
                  body["request_id"] as? String == original.requestID, let evidence = body["evidence_json"] as? [String: Any],
                  Set(evidence.keys) == ["text"], let text = evidence["text"] as? String else { return false }
            return !text.isEmpty && text == text.trimmingCharacters(in: .whitespacesAndNewlines) && text.utf16.count <= 500
        case .withdraw:
            return appealPathID(original.path, suffix: "withdraw") != nil && Set(body.keys) == ["request_id", "reason"] &&
                body["request_id"] as? String == original.requestID && text("reason") != nil
        }
    }
    /// This final gate checks the real URL, credentials, query, body and durable original.
    /// Catalog shape or a matching prefix is never a dispatch grant.
    func accepts(_ request: URLRequest) -> Bool {
        guard isCurrent, request.httpBodyStream == nil, request.httpShouldHandleCookies == false,
              request.value(forHTTPHeaderField: "Authorization").map({ Data($0.utf8) }) == Data(context.session.token.utf8),
              request.value(forHTTPHeaderField: "Cookie") == nil, request.value(forHTTPHeaderField: "Proxy-Authorization") == nil,
              request.value(forHTTPHeaderField: "Accept") == "application/json", let url = request.url,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false), parts.user == nil, parts.password == nil, parts.fragment == nil,
              let method = request.httpMethod else { return false }
        if method == "GET", request.httpBody == nil {
            if allows(.moderationRead) {
                var expected = URLComponents(url: context.baseURL.appendingPathComponent("api/im/moderation/me"), resolvingAgainstBaseURL: false)
                expected?.queryItems = [URLQueryItem(name: "guild_kind", value: String(notice.guildKind)), URLQueryItem(name: "guild_id", value: notice.guildID)]
                if url.absoluteString == expected?.url?.absoluteString { return true }
            }
            guard parts.query == nil else { return false }
            if allows(.appealRead), readIDs.contains(where: { context.baseURL.appendingPathComponent("api/im/appeals/" + $0).absoluteString == url.absoluteString }) { return true }
            return allows(.originalReceipt) && commands.values.contains {
                context.baseURL.appendingPathComponent(receiptPath($0.original.requestID)).absoluteString == url.absoluteString && $0.pendingMatches()
            }
        }
        guard method == "POST", parts.query == nil, request.value(forHTTPHeaderField: "Content-Type") == "application/json", let body = request.httpBody else { return false }
        return commands.values.contains { issued in
            let original = issued.original
            return permits("POST", original.path) && allows(.originalReceipt) && body == original.body &&
                url.absoluteString == context.baseURL.appendingPathComponent(original.path).absoluteString && issued.pendingMatches()
        }
    }
}

@MainActor private final class NativeChannelAppealDispatchTransport: HTTPTransport {
    let authorization: NativeChannelAppealRuntimeAuthorization
    let underlying: any HTTPTransport
    init(authorization: NativeChannelAppealRuntimeAuthorization, underlying: any HTTPTransport) { self.authorization = authorization; self.underlying = underlying }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        try Task.checkCancellation()
        guard authorization.accepts(request) else { throw APIError.notConfigured }
        do {
            let response = try await underlying.send(request)
            try Task.checkCancellation()
            guard authorization.accepts(request) else { throw CancellationError() }
            return response
        } catch {
            guard authorization.isCurrent, !Task.isCancelled else { throw CancellationError() }
            throw error
        }
    }
}

/// The normal App factory calls this concrete assembly. It creates the issuer and its final
/// transport together; a permits-always-true fixture is neither necessary nor sufficient.
@MainActor public enum NativeChannelAppealRuntime {
    static func binding(notice: NativeChannelGovernanceNotice, context: RuntimeDependencyContext,
                        policyStore: NativeChannelAppealPolicyStore, underlying: any HTTPTransport,
                        current: @escaping () -> Bool) -> (authorization: NativeChannelAppealRuntimeAuthorization, transport: any HTTPTransport)? {
        guard let authority = NativeChannelAppealRuntimeAuthorization(notice: notice, context: context, store: policyStore, current: current) else { return nil }
        return (authority, NativeChannelAppealDispatchTransport(authorization: authority, underlying: underlying))
    }
    public static func makeFlow(notice: NativeChannelGovernanceNotice, context: RuntimeDependencyContext,
                                policyStore: NativeChannelAppealPolicyStore, underlying: any HTTPTransport,
                                storage: any ProjectEditDataStorage, locatorStorage: any ProjectEditDataStorage,
                                current: @escaping () -> Bool, unauthorized: @escaping () -> Void) -> NativeChannelAppealFlow? {
        guard let binding = binding(notice: notice, context: context, policyStore: policyStore, underlying: underlying, current: current) else { return nil }
        let authority = binding.authorization, transport = binding.transport
        return try? NativeChannelAppealFlow(notice: notice, context: context, transport: transport, storage: storage,
            current: { current() && authority.isCurrent }, permits: { authority.permits($0, $1) }, unauthorized: unauthorized,
            locatorStorage: locatorStorage, runtimeAuthorization: authority)
    }
}
