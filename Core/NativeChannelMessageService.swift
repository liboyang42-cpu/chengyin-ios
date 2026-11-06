import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor public protocol NativeChannelMessageAccess: AnyObject {
    var identity: MessagingReadIdentity? { get }
    var binding: NativeChannelMessageBinding { get }
    func retireOperations()
    func allows(_ capability: NativeChannelMessageCapability) -> Bool
    func mutate(_ command: NativeChannelMessageCommand) async throws -> NativeChannelMessageResult
    func receipt(_ command: NativeChannelMessageCommand) async throws -> NativeChannelMessageReceipt
    func mutations(after: String) async throws -> NativeChannelMessageMutationPage
    func pins() async throws -> NativeChannelMessagePinPage
    func search(_ query: NativeChannelMessageQuery, cursor: String?) async throws -> NativeChannelMessageSearchPage
    func context(messageID: NativeChannelMessageID) async throws -> NativeChannelMessageContextPage
    func revisions(messageID: NativeChannelMessageID, cursor: Int64?) async throws -> NativeChannelMessageRevisionPage
}

public extension NativeChannelMessageAccess {
    func context(messageID: NativeChannelMessageID) async throws -> NativeChannelMessageContextPage { throw APIError.notConfigured }
}

/// Supplement to the original IM, with an exact route per operation. No send/upload writer.
@MainActor public final class NativeChannelMessageService: NativeChannelMessageAccess {
    public let binding: NativeChannelMessageBinding
    public let scope: NativeChannelMessageScope
    private let expected: MessagingReadIdentity
    private let authority: any NativeChannelMessageAuthorizing
    private let http: any NativeChannelMessageDispatching
    private var generation: UInt64 = 0
    private let onUnauthorized: (MessagingReadIdentity) -> Void
    public var identity: MessagingReadIdentity? { authority.identity == expected ? expected : nil }
    public init(credentials: NativeChannelMessageCredentials, authority: any NativeChannelMessageAuthorizing,
                transport: any NativeChannelMessageDispatching, onUnauthorized: @escaping (MessagingReadIdentity) -> Void) {
        binding = credentials.binding; scope = .init(credentials: credentials); expected = credentials.identity
        self.authority = authority; http = transport; self.onUnauthorized = onUnauthorized
    }
    public func retireOperations() { generation &+= 1 }
    public func allows(_ capability: NativeChannelMessageCapability) -> Bool { (try? checked(capability)) != nil }
    private func checked(_ capability: NativeChannelMessageCapability) throws -> NativeChannelMessageCredentials {
        guard identity == expected else { throw APIError.unauthorized }
        let c = try authority.credentials(for: capability, binding: binding)
        guard c.identity == expected, c.binding == binding, NativeChannelMessageScope(credentials: c) == scope else {
            throw APIError.notConfigured
        }
        return c
    }
    public func mutate(_ command: NativeChannelMessageCommand) async throws -> NativeChannelMessageResult {
        try command.validate()
        guard command.binding == binding else { throw APIError.invalidRequest }
        let path: String
        switch command.operation {
        case .edit: path = "api/im/message/edit"
        case .recall: path = "api/im/message/recall"
        case .pin: path = "api/im/pin"
        case .unpin: path = "api/im/unpin"
        case .sort: path = "api/im/pins/sort"
        }
        let result: NativeChannelMessageResult = try await execute(.mutate(command.operation), path: path, body: command.body)
        try result.verify(command); return result
    }
    public func receipt(_ command: NativeChannelMessageCommand) async throws -> NativeChannelMessageReceipt {
        try command.validate()
        guard command.binding.sameTarget(as: binding) else { throw APIError.invalidRequest }
        let result: NativeChannelMessageReceipt = try await execute(.receipt, path: "api/im/message/request", query: ["request_id": command.requestID])
        _ = try result.verify(command); return result
    }
    public func mutations(after: String) async throws -> NativeChannelMessageMutationPage {
        guard NativeChannelMessageCursor.valid(after) else { throw APIError.invalidRequest }
        let page: NativeChannelMessageMutationPage = try await execute(.mutations, path: "api/im/message/mutations", query: [
            "conversation_id": binding.channelID.rawValue, "mutation_cursor": after, "limit": "50"])
        try page.verify(after: after, binding: binding); return page
    }
    public func pins() async throws -> NativeChannelMessagePinPage {
        let result: NativeChannelMessagePinPage = try await execute(.pins, path: "api/im/pins", query: ["conversation_id": binding.channelID.rawValue])
        try result.verify(binding); return result
    }
    public func search(_ query: NativeChannelMessageQuery, cursor: String?) async throws -> NativeChannelMessageSearchPage {
        try query.validate()
        if let cursor, !NativeChannelMessageCursor.valid(cursor) { throw APIError.invalidRequest }
        var fields = query.fields; fields["conversation_id"] = binding.channelID.rawValue
        fields["limit"] = "20"; fields["cursor"] = cursor
        let page: NativeChannelMessageSearchPage = try await execute(.search, path: "api/im/search", query: fields)
        try page.verify(binding: binding, requested: cursor); return page
    }
    public func context(messageID: NativeChannelMessageID) async throws -> NativeChannelMessageContextPage {
        let page: NativeChannelMessageContextPage = try await execute(.context,path:"api/im/message/context",
            query:["conversation_id":binding.channelID.rawValue,"message_id":messageID.rawValue,"limit":"20"])
        try page.verify(binding:binding,anchor:messageID);return page
    }
    public func revisions(messageID: NativeChannelMessageID, cursor: Int64?) async throws -> NativeChannelMessageRevisionPage {
        if let cursor, cursor <= 0 { throw APIError.invalidRequest }
        var query = ["limit": "20"]; query["cursor"] = cursor.map(String.init)
        let page: NativeChannelMessageRevisionPage = try await execute(.revisions,
            path: "api/im/message/\(messageID.rawValue)/revisions", query: query)
        try page.verify(messageID: messageID, before: cursor); return page
    }
    private func execute<Value: Decodable>(_ capability: NativeChannelMessageCapability, path: String,
            query: [String: String] = [:], body: [String: Any]? = nil) async throws -> Value {
        let credentials = try checked(capability), run = generation
        var components = URLComponents(url: credentials.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        guard let url = components.url else { throw APIError.invalidRequest }
        var request = URLRequest(url: url)
        request.httpMethod = body == nil ? "GET" : "POST"
        request.httpShouldHandleCookies = false; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 25; request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(credentials.token, forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        }
        try Task.checkCancellation()
        // Recheck at final dispatch, including mapping/authority revision and session.
        guard generation == run, try checked(capability) == credentials else { throw CancellationError() }
        let data: Data, status: Int
        do { (data, status) = try await http.send(request, fence: .init { [weak self] in
            guard let self, self.generation == run else { return false }
            return (try? self.checked(capability)) == credentials
        }) }
        catch {
            guard generation == run, !Task.isCancelled, try checked(capability) == credentials else { throw CancellationError() }
            throw error
        }
        try Task.checkCancellation()
        guard generation == run, try checked(capability) == credentials else { throw CancellationError() }
        guard data.count <= 2 * 1024 * 1024 else { throw APIError.malformedResponse }
        let header = try? JSONDecoder().decode(Header.self, from: data)
        if status == 401 || header?.code == 401 { onUnauthorized(expected); throw APIError.unauthorized }
        guard (200..<300).contains(status), header?.code == 200 else {
            throw NativeChannelMessageFailure(httpStatus: status, code: header?.code, errorCode: header?.errorCode,
                                              message: header?.msg, outcomeKnown: header?.outcome_known)
        }
        do { return try JSONDecoder().decode(Envelope<Value>.self, from: data).data }
        catch { throw APIError.malformedResponse }
    }
    private struct Header: Decodable { let code: Int; let errorCode: String?; let msg: String?; let outcome_known: Bool? }
    private struct Envelope<T: Decodable>: Decodable { let data: T }
}

enum NativeChannelMessageCursor {
    static func valid(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { (48...57).contains($0) }
            && Int64(value).map { $0 >= 0 && String($0) == value } == true
    }
}
