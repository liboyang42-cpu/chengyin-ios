import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Exact final-forward adapter for the existing message actions. It never sends text,
/// creates requests, writes a journal, grants permission, retries, or owns a URLSession.
@MainActor public final class NativeChannelMessageFinalForward: NativeChannelMessageDispatching {
    private let authority: NativeChannelMessageHostAuthority
    private let journal: any NativeChannelMessageMutationRecording
    private let underlying: any HTTPTransport
    private let current: () -> Bool
    private let onUnauthorized: (MessagingReadIdentity) -> Void
    public init(authority: NativeChannelMessageHostAuthority, journal: any NativeChannelMessageMutationRecording,
                underlying: any HTTPTransport, current: @escaping () -> Bool,
                onUnauthorized: @escaping (MessagingReadIdentity) -> Void) throws {
        guard current(), authority.identity != nil, journal.scope.binding.sameTarget(as: authority.binding),
              journal.scope.accountID == String(authority.context.session.accountID),
              journal.scope.namespace.utf8.elementsEqual(authority.context.session.namespace.utf8),
              journal.scope.baseURL.utf8.elementsEqual(authority.context.baseURL.absoluteString.utf8) else { throw APIError.notConfigured }
        self.authority = authority; self.journal = journal; self.underlying = underlying
        self.current = current; self.onUnauthorized = onUnauthorized
    }
    private struct Access {
        let capability: NativeChannelMessageCapability
        var original: NativeChannelMessageCommand? = nil
        var requiresPinReceipt: Bool {
            guard case .mutate(let operation) = capability else { return false }
            return operation == .pin || operation == .unpin || operation == .sort
        }
    }
    public func send(_ request: URLRequest, fence: NativeChannelMessageDispatchFence) async throws -> (Data, Int) {
        try Task.checkCancellation()
        guard current(), fence.isCurrent, let access = try access(request) else { throw APIError.notConfigured }
        let captured = try authority.credentials(for: access.capability, binding: authority.binding)
        guard request.value(forHTTPHeaderField: "Authorization").map({ Data($0.utf8) }) == Data(captured.token.utf8) else { throw APIError.notConfigured }
        // This is independent of write authority. Receipt GET recovery must remain
        // possible without a writer; only a new pin mutation requires both.
        if access.requiresPinReceipt {
            _ = try authority.credentials(for: .receipt, binding: authority.binding)
        }
        let response = try await underlying.send(request)
        if NativeChannelTextService.receivedUnauthorized(data: response.0, status: response.1) {
            // Current normal 401 keeps the existing host callback; cancellation/old
            // identity cannot revoke the replacement. Retire the captured issuance in all cases.
            if current(), fence.isCurrent,
               let live = try? authority.credentials(for: access.capability, binding: authority.binding),
               NativeChannelMessageHostAuthority.same(live, captured) { onUnauthorized(captured.identity) }
            authority.retireReceivedUnauthorized(captured)
            throw APIError.unauthorized
        }
        guard current(), fence.isCurrent,
              let live = try? authority.credentials(for: access.capability, binding: authority.binding),
              NativeChannelMessageHostAuthority.same(live, captured) else { throw CancellationError() }
        if let original = access.original {
            guard let saved = try journal.restore(), NativeChannelMessageMutationJournal.sameBytes(saved, original) else {
                throw NativeChannelMessageJournalError.pending
            }
        }
        return response
    }
    private func access(_ request: URLRequest) throws -> Access? {
        guard let url = request.url, url.fragment == nil, url.user == nil, url.password == nil,
              request.httpBodyStream == nil, !request.httpShouldHandleCookies,
              request.value(forHTTPHeaderField: "Accept") == "application/json",
              Set((request.allHTTPHeaderFields ?? [:]).keys.map { $0.lowercased() }).isSubset(of: ["accept", "authorization", "content-type"]) else { return nil }
        let base = authority.context.baseURL, binding = authority.binding
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard Set(queryItems.map(\.name)).count == queryItems.count,
              queryItems.allSatisfy({ $0.value != nil }) else { return nil }
        let query = Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value!) })
        func exact(_ path: String, _ fields: [String: String] = [:]) -> Bool {
            var c = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)
            if !fields.isEmpty { c?.queryItems = fields.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
            return c?.url?.absoluteString.utf8.elementsEqual(url.absoluteString.utf8) == true
        }
        if request.httpMethod == "POST" {
            guard queryItems.isEmpty, request.value(forHTTPHeaderField: "Content-Type") == "application/json",
                  let bytes = request.httpBody, bytes.count <= 128 * 1024, let original = try journal.restore(),
                  original.binding == binding,
                  try JSONSerialization.data(withJSONObject: original.body, options: [.sortedKeys]) == bytes else { return nil }
            let path: String
            switch original.operation {
            case .edit: path = "api/im/message/edit"
            case .recall: path = "api/im/message/recall"
            case .pin: path = "api/im/pin"
            case .unpin: path = "api/im/unpin"
            case .sort: path = "api/im/pins/sort"
            }
            return exact(path) ? Access(capability: .mutate(original.operation), original: original) : nil
        }
        guard request.httpMethod == "GET", request.httpBody == nil,
              request.value(forHTTPHeaderField: "Content-Type") == nil else { return nil }
        if Set(query.keys) == ["request_id"], let original = try journal.restore(),
           original.binding.sameTarget(as: binding), query["request_id"] == original.requestID,
           exact("api/im/message/request", query) { return Access(capability: .receipt, original: original) }
        if Set(query.keys) == ["conversation_id","message_id","limit"],
           query["conversation_id"] == binding.channelID.rawValue,query["limit"] == "20",
           query["message_id"].flatMap(NativeChannelMessageID.init(rawValue:)) != nil,
           exact("api/im/message/context",query) { return Access(capability:.context) }
        if query == ["conversation_id": binding.channelID.rawValue], exact("api/im/pins", query) {
            return Access(capability: .pins)
        }
        if Set(query.keys) == ["conversation_id", "mutation_cursor", "limit"],
           query["conversation_id"] == binding.channelID.rawValue, query["limit"] == "50",
           query["mutation_cursor"].map(NativeChannelMessageCursor.valid) == true,
           exact("api/im/message/mutations", query) { return Access(capability: .mutations) }
        if Set(query.keys).isSubset(of: ["keyword", "from", "to", "author_id", "conversation_id", "limit", "cursor"]),
           let keyword = query["keyword"], query["conversation_id"] == binding.channelID.rawValue, query["limit"] == "20",
           query["cursor"].map(NativeChannelMessageCursor.valid) ?? true,
           query["author_id"].map({ NativeChannelMessageID(rawValue: $0) != nil }) ?? true,
           exact("api/im/search", query) {
            let value = NativeChannelMessageQuery(keyword: keyword, from: query["from"], to: query["to"],
                authorID: query["author_id"].flatMap(NativeChannelMessageID.init(rawValue:)))
            try value.validate(); return Access(capability: .search)
        }
        if Set(query.keys).isSubset(of: ["limit", "cursor"]), query["limit"] == "20",
           query["cursor"].map({ NativeChannelMessageID(rawValue: $0) != nil }) ?? true {
            let prefix = base.appendingPathComponent("api/im/message").absoluteString + "/"
            let raw = url.absoluteString.components(separatedBy: "?")[0]
            if raw.hasPrefix(prefix), raw.hasSuffix("/revisions") {
                let id = String(raw.dropFirst(prefix.count).dropLast("/revisions".count))
                if NativeChannelMessageID(rawValue: id) != nil, exact("api/im/message/\(id)/revisions", query) {
                    return Access(capability: .revisions)
                }
            }
        }
        return nil
    }
}
