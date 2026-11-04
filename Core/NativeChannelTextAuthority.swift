import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum NativeChannelTextOperation: Equatable { case send, receipt }

/// Explicit independent grants. A history lease, login, role or conversation row does
/// not issue either grant. Replace by a new revision; a revoked instance never reopens.
@MainActor @Observable public final class NativeChannelTextApproval {
    public let context: RuntimeDependencyContext
    public let originalMentionWireEnabled: Bool
    public let originalReplyWireEnabled: Bool
    public let operation: NativeChannelTextOperation
    public let conversationIDs: Set<Int>
    public let expiresAt: Date
    public let revision = UUID()
    public private(set) var isRevoked = false
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    public init(context: RuntimeDependencyContext, operation: NativeChannelTextOperation,
                conversationIDs: Set<Int>, expiresAt: Date, originalReplyWireEnabled: Bool = false, originalMentionWireEnabled: Bool = false) throws {
        _ = try APIConfiguration(baseURL: context.baseURL)
        let duration = expiresAt.timeIntervalSinceNow
        guard context.market == .china, context.session.accountID > 0,
              AuthRequestBuilder.isValidToken(context.session.token), !context.session.namespace.isEmpty,
              !conversationIDs.isEmpty, conversationIDs.allSatisfy({ $0 > 0 }),
              duration.isFinite, duration > 0, duration <= 86_400 else { throw APIError.invalidConfiguration }
        self.originalMentionWireEnabled = originalMentionWireEnabled
        self.originalReplyWireEnabled = originalReplyWireEnabled
        self.context = context; self.operation = operation; self.conversationIDs = conversationIDs; self.expiresAt = expiresAt
        expiryTask = Task { @MainActor [weak self] in
            let delay = max(0, min(expiresAt.timeIntervalSinceNow, 86_400))
            do {
                if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
                try Task.checkCancellation()
            } catch { return }
            self?.revoke()
        }
    }
    deinit { expiryTask?.cancel() }
    public func revoke() { isRevoked = true; expiryTask?.cancel(); expiryTask = nil }
    public func matches(_ context: RuntimeDependencyContext, operation: NativeChannelTextOperation,
                        conversationID: Int, now: Date = Date()) -> Bool {
        !isRevoked && now < expiresAt && self.operation == operation && conversationIDs.contains(conversationID)
            && ContentDraftContextFence.matches(self.context, context)
    }
}

/// Exact canonical forms only. No target-member, media, query, cookies, hidden fields,
/// duplicate keys or future routes are admitted by this dedicated capability.
public enum NativeChannelTextRoute: Equatable {
    case send(MessageTextIntent)
    case quotedSend(conversationID: Int, clientMessageID: String, replyToID: String)
    case mentionedSend(conversationID: Int, clientMessageID: String, replyToID: String?, members: [String], roles: [String], everyone: Bool)
    case receipt(conversationID: Int, clientMessageID: String)
    public var operation: NativeChannelTextOperation {
        switch self { case .send, .quotedSend, .mentionedSend: return .send; case .receipt: return .receipt }
    }
    public var conversationID: Int {
        switch self { case .send(let intent): return intent.conversationID; case .quotedSend(let id, _, _), .mentionedSend(let id, _, _, _, _, _), .receipt(let id, _): return id }
    }
    public var isQuotedSend: Bool {
        if case .quotedSend = self { return true }
        if case .mentionedSend(_, _, let reply, _, _, _) = self { return reply != nil }; return false
    }
    public var isMentionedSend: Bool { if case .mentionedSend = self { return true }; return false }
    private static func ids(_ raw: String?) -> [String]? {
        guard let raw, raw.first == "[", raw.last == "]" else { return nil }
        let inner=raw.dropFirst().dropLast()
        let values=inner.isEmpty ? [] : inner.split(separator:",",omittingEmptySubsequences:false).map(String.init)
        guard values.count <= 20, Set(values).count == values.count,
              values.allSatisfy({ NativeChannelMessageID(rawValue:$0) != nil }),
              raw == "["+values.joined(separator:",")+"]" else { return nil }; return values
    }
    public init?(request: URLRequest, baseURL: URL) {
        let prefix = "multipart/form-data; boundary="
        guard let url = request.url, url.query == nil, url.fragment == nil,
              request.httpMethod == "POST", request.httpBodyStream == nil, !request.httpShouldHandleCookies,
              request.value(forHTTPHeaderField: "Cookie") == nil, request.value(forHTTPHeaderField: "Cookie2") == nil,
              request.value(forHTTPHeaderField: "Proxy-Authorization") == nil,
              request.value(forHTTPHeaderField: "Accept") == "application/json",
              let type = request.value(forHTTPHeaderField: "Content-Type"), type.hasPrefix(prefix),
              let body = request.httpBody, body.count <= 20 * 1024,
              let text = String(data: body, encoding: .utf8) else { return nil }
        let boundary = String(type.dropFirst(prefix.count))
        let terminator = "--\(boundary)--\r\n"
        guard text.hasSuffix(terminator) else { return nil }
        let parts = String(text.dropLast(terminator.count)).components(separatedBy: "--\(boundary)\r\n")
        guard parts.first == "" else { return nil }
        var fields: [String: String] = [:]
        let header = "Content-Disposition: form-data; name=\""
        for part in parts.dropFirst() {
            guard part.hasPrefix(header), part.hasSuffix("\r\n"),
                  let separator = part.range(of: "\"\r\n\r\n") else { return nil }
            let nameStart = part.index(part.startIndex, offsetBy: header.count)
            guard separator.lowerBound > nameStart else { return nil }
            let name = String(part[nameStart..<separator.lowerBound])
            guard fields[name] == nil else { return nil }
            // Swift treats CRLF as one Character; remove only the verified delimiter.
            fields[name] = String(part[separator.upperBound...].dropLast("\r\n".count))
        }
        guard let rawID = fields["conversation_id"], let id = Int(rawID), id > 0, String(id) == rawID,
              let key = fields["client_message_id"],
              let parsed = try? MessageTextIntent(conversationID: id, content: fields["content"] ?? "receipt", clientMessageID: key) else { return nil }
        if url.absoluteString.utf8.elementsEqual(baseURL.appendingPathComponent("api/im/send").absoluteString.utf8) {
            let plain: Set<String> = ["conversation_id", "client_message_id", "msg_type", "content"]
            guard fields["msg_type"] == "1", let content = fields["content"],
                  parsed.content.utf8.elementsEqual(content.utf8), content.utf8.count <= 16 * 1024 else { return nil }
            if Set(fields.keys) == plain { self = .send(parsed) }
            else if Set(fields.keys) == plain.union(["reply_to_id"]),
                    let reply = fields["reply_to_id"], NativeChannelMessageID(rawValue: reply) != nil {
                self = .quotedSend(conversationID: id, clientMessageID: key, replyToID: reply)
            } else {
                let mentionKeys: Set<String> = ["mention_member_ids","mention_role_ids","mention_everyone"]
                let keys=Set(fields.keys), reply=fields["reply_to_id"]
                guard keys == plain.union(mentionKeys) || keys == plain.union(mentionKeys).union(["reply_to_id"]),
                      reply == nil || reply.flatMap(NativeChannelMessageID.init(rawValue:)) != nil,
                      let members=Self.ids(fields["mention_member_ids"]),let roles=Self.ids(fields["mention_role_ids"]),
                      let everyone=fields["mention_everyone"],everyone == "0" || everyone == "1",
                      !members.isEmpty || !roles.isEmpty || everyone == "1" else { return nil }
                self = .mentionedSend(conversationID:id,clientMessageID:key,replyToID:reply,members:members,roles:roles,everyone:everyone == "1")
            }
        } else if url.absoluteString.utf8.elementsEqual(baseURL.appendingPathComponent("api/im/send-receipt").absoluteString.utf8) {
            guard Set(fields.keys) == ["conversation_id", "client_message_id"] else { return nil }
            self = .receipt(conversationID: id, clientMessageID: key)
        } else { return nil }
        guard let canonical = try? AuthRequestBuilder.makeFormRequest(url: url, fields: fields,
            token: request.value(forHTTPHeaderField: "Authorization"), boundary: boundary), canonical.httpBody == body else { return nil }
    }
}

/// A final-dispatch and callback fence, including grant revision, context, viewer and
/// lifecycle. Composition must pass its existing underlying transport, not generic IM.
@MainActor public final class NativeChannelTextTransport: HTTPTransport {
    private let context: RuntimeDependencyContext
    private let transport: any HTTPTransport
    private let current: () -> RuntimeDependencyContext?
    private let read: () -> NativeChannelTextApproval?
    private let write: () -> NativeChannelTextApproval?
    private let stillCurrent: () -> Bool
    private let readRevision: UUID?
    private let writeRevision: UUID?
    // Retain the original issuance objects, not the mutable selectors. HTTP 401 must
    // remain retired across normal factory remount without touching replacement grants.
    private let capturedRead: NativeChannelTextApproval?
    private let capturedWrite: NativeChannelTextApproval?
    public init(context: RuntimeDependencyContext, transport: any HTTPTransport,
                current: @escaping () -> RuntimeDependencyContext?,
                read: @escaping () -> NativeChannelTextApproval? = { nil },
                write: @escaping () -> NativeChannelTextApproval? = { nil },
                stillCurrent: @escaping () -> Bool = { false }) {
        self.context = context; self.transport = transport; self.current = current
        self.read = read; self.write = write; self.stillCurrent = stillCurrent
        let originalRead = read(), originalWrite = write()
        capturedRead = originalRead; capturedWrite = originalWrite
        readRevision = originalRead?.revision; writeRevision = originalWrite?.revision
    }
    public var isCurrent: Bool { stillCurrent() && ContentDraftContextFence.matches(current(), context) }
    public func allows(_ operation: NativeChannelTextOperation, conversationID: Int) -> Bool {
        guard isCurrent else { return false }
        let grant = operation == .receipt ? read() : write()
        let revision = operation == .receipt ? readRevision : writeRevision
        return revision != nil && grant?.revision == revision
            && grant?.matches(context, operation: operation, conversationID: conversationID) == true
    }
    public func allowsOriginalMentions(conversationID: Int) -> Bool {
        allows(.send,conversationID:conversationID) && capturedWrite?.originalMentionWireEnabled == true
    }
    public func allowsOriginalReply(conversationID: Int) -> Bool {
        allows(.send, conversationID: conversationID) && capturedWrite?.originalReplyWireEnabled == true
    }
    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        try await send(request, onCurrentUnauthorized: {})
    }
    /// Preserve the original client's current-identity unauthorized callback. It runs
    /// before retirement, never for cancellation, a stale lifecycle or another issuance.
    public func send(_ request: URLRequest, onCurrentUnauthorized: () -> Void) async throws -> (Data, Int) {
        try Task.checkCancellation()
        guard let route = NativeChannelTextRoute(request: request, baseURL: context.baseURL),
              request.value(forHTTPHeaderField: "Authorization").map({ Data($0.utf8) }) == Data(context.session.token.utf8),
              allows(route.operation, conversationID: route.conversationID),
              !route.isQuotedSend || allowsOriginalReply(conversationID: route.conversationID),
              !route.isMentionedSend || allowsOriginalMentions(conversationID: route.conversationID) else { throw APIError.notConfigured }
        let result = try await transport.send(request)
        if NativeChannelTextService.receivedUnauthorized(data: result.0, status: result.1) {
            if !Task.isCancelled, allows(route.operation, conversationID: route.conversationID) {
                onCurrentUnauthorized()
            }
            // Only an actual HTTP/header 401 retires these captured issuances.
            // Do this before cancellation/context checks: a late response still proves
            // the old credentials were rejected, not that a newer session is invalid.
            if let grant = capturedRead, ContentDraftContextFence.matches(grant.context, context) { grant.revoke() }
            if let grant = capturedWrite, ContentDraftContextFence.matches(grant.context, context) { grant.revoke() }
            throw APIError.unauthorized
        }
        try Task.checkCancellation()
        guard allows(route.operation, conversationID: route.conversationID),
              !route.isQuotedSend || allowsOriginalReply(conversationID: route.conversationID),
              !route.isMentionedSend || allowsOriginalMentions(conversationID: route.conversationID) else { throw CancellationError() }
        return result
    }
}
