import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Only the missing source-backed operations. Existing list/older reads remain
/// MessagingReading, and the server's existing IM engine remains authoritative.
public struct NativeChannelService {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    public let allowsNewer: Bool
    public let allowsReadReceipt: Bool
    public init(configuration: APIConfiguration, transport: any HTTPTransport,
                allowsNewer: Bool = false, allowsReadReceipt: Bool = false) {
        self.configuration = configuration; self.transport = transport
        self.allowsNewer = allowsNewer; self.allowsReadReceipt = allowsReadReceipt
    }
    public struct IncrementalPage: Decodable {
        public let page: MessagingPage
        public let nextAfter: Int
        private enum CodingKeys: String, CodingKey { case nextAfter }
        public init(from decoder: Decoder) throws {
            page = try MessagingPage(from: decoder)
            nextAfter = try decoder.container(keyedBy: CodingKeys.self).decode(Int.self, forKey: .nextAfter)
            guard nextAfter >= 0 else { throw APIError.malformedResponse }
        }
    }
    public func newer(conversationID: Int, after: Int, token: String) async throws -> IncrementalPage {
        guard allowsNewer else { throw APIError.notConfigured }
        guard conversationID > 0, after >= 0 else { throw APIError.invalidRequest }
        let result: IncrementalPage = try await execute(path: "api/im/messages", fields: [
            "conversation_id": String(conversationID), "after_id": String(after), "size": "30"
        ], token: token)
        guard result.page.messages.count <= 30,
              result.page.messages.allSatisfy({ $0.conversationID == conversationID }) else { throw APIError.malformedResponse }
        return result
    }
    public func readThrough(conversationID: Int, readTo: Int, token: String) async throws -> NativeChannelReadReceipt {
        guard allowsReadReceipt else { throw APIError.notConfigured }
        guard conversationID > 0, readTo > 0 else { throw APIError.invalidRequest }
        let receipt: NativeChannelReadReceipt = try await execute(path: "api/native/channels/read-through", fields: [
            "conversation_id": String(conversationID), "read_to": String(readTo)
        ], token: token)
        guard receipt.conversationId == conversationID, receipt.readTo == readTo,
              receipt.lastReadMessageId > 0, receipt.unread >= 0 else { throw APIError.malformedResponse }
        return receipt
    }
    private func execute<Value: Decodable>(path: String, fields: [String: String], token: String) async throws -> Value {
        guard AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        try Task.checkCancellation()
        var request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent(path), fields: fields, token: token)
        request.httpShouldHandleCookies = false
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation()
        guard data.count <= 2 * 1024 * 1024 else { throw APIError.malformedResponse }
        do {
            let header = try? JSONDecoder().decode(Header.self, from: data)
            guard (200..<300).contains(status) else { throw MessagingReadFailure(httpStatus: status, code: header?.code, errorCode: header?.errorCode, message: header?.msg) }
            guard let header else { throw APIError.malformedResponse }
            guard header.code == 200 else { throw MessagingReadFailure(code: header.code, errorCode: header.errorCode, message: header.msg) }
        }
        do { return try JSONDecoder().decode(Envelope<Value>.self, from: data).data }
        catch { throw APIError.malformedResponse }
    }
    private struct Header: Decodable { let code: Int; let errorCode: String?; let msg: String? }
    private struct Envelope<Value: Decodable>: Decodable { let data: Value }
}

public struct NativeChannelSession: Equatable {
    public let identity: MessagingReadIdentity
    fileprivate let token: String
    public init(accountID: Int, epoch: UInt64, token: String) throws {
        guard accountID > 0, AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        self.identity = .init(accountID: accountID, epoch: epoch); self.token = token
    }
}

@MainActor public final class NativeChannelSessionClient {
    public let history: any MessagingReading
    private let service: NativeChannelService?
    private let currentSession: () -> NativeChannelSession?
    private let isAvailable: () -> Bool
    private let onUnauthorized: (NativeChannelSession) -> Void
    public var identity: MessagingReadIdentity? { isAvailable() ? currentSession()?.identity : nil }
    public var isConfigured: Bool { isAvailable() && history.isConfigured && identity != nil && history.identity == identity }
    public var canLoadNewer: Bool { isConfigured && service?.allowsNewer == true }
    public var canReadThrough: Bool { isConfigured && service?.allowsReadReceipt == true }
    public init(history: any MessagingReading, service: NativeChannelService? = nil,
                currentSession: @escaping () -> NativeChannelSession?, isAvailable: @escaping () -> Bool = { false },
                onUnauthorized: @escaping (NativeChannelSession) -> Void = { _ in }) {
        self.history = history; self.service = service; self.currentSession = currentSession
        self.isAvailable = isAvailable; self.onUnauthorized = onUnauthorized
    }
    public func directory() async throws -> [NativeChannelSpace] {
        try await checked { _ in NativeChannelSpace.project(try await history.messagingConversations()) }
    }
    public func page(conversationID: Int, cursor: Int) async throws -> MessagingPage {
        try await checked { _ in try await history.messagingMessages(conversationID: conversationID, cursor: cursor) }
    }
    public func newer(conversationID: Int, after: Int) async throws -> NativeChannelService.IncrementalPage {
        try await checked { session in
            guard let service else { throw APIError.notConfigured }
            return try await service.newer(conversationID: conversationID, after: after, token: session.token)
        }
    }
    public func readThrough(conversationID: Int, readTo: Int) async throws -> NativeChannelReadReceipt {
        try await checked { session in
            guard let service else { throw APIError.notConfigured }
            return try await service.readThrough(conversationID: conversationID, readTo: readTo, token: session.token)
        }
    }
    private func checked<T>(_ operation: (NativeChannelSession) async throws -> T) async throws -> T {
        guard isConfigured, let captured = currentSession() else { throw APIError.notConfigured }
        try Task.checkCancellation()
        do {
            let result = try await operation(captured)
            guard isConfigured, currentSession() == captured else { throw CancellationError() }
            try Task.checkCancellation()
            return result
        } catch {
            guard isConfigured, currentSession() == captured, !Task.isCancelled else { throw CancellationError() }
            if (error as? MessagingReadFailure)?.isUnauthorized == true { onUnauthorized(captured) }
            throw error
        }
    }
}

/// Exact composition dispatch is injected, never a new or general-purpose session.
public struct NativeChannelDispatchTransport: HTTPTransport {
    private let operation: @MainActor (URLRequest) async throws -> (Data, Int)
    public init(_ operation: @escaping @MainActor (URLRequest) async throws -> (Data, Int)) { self.operation = operation }
    public func send(_ request: URLRequest) async throws -> (Data, Int) { try await operation(request) }
}
