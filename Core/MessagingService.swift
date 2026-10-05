import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct MessagingReadFailure: Error, Equatable {
    public let httpStatus: Int?
    public let code: Int?
    public let errorCode: String?
    public let message: String?
    public var isUnauthorized: Bool { httpStatus == 401 || code == 401 }
    public var isForbidden: Bool { httpStatus == 403 || code == 403 }
    public var isClosed: Bool { errorCode == "HANGOUT_CLOSED" }
    public init(httpStatus: Int? = nil, code: Int? = nil, errorCode: String? = nil, message: String? = nil) {
        self.httpStatus = httpStatus; self.code = code
        self.errorCode = errorCode?.trimmingCharacters(in: .whitespacesAndNewlines); self.message = message
    }
}

/// Exactly two source-backed reads. No read receipts, sockets, timers, mutation endpoints,
/// media requests or default host. Inject the existing ephemeral no-redirect transport.
public struct MessagingService {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    public init(configuration: APIConfiguration, transport: any HTTPTransport) {
        self.configuration = configuration; self.transport = transport
    }
    /// Source returns a bare data array and accepts no paging/search/account arguments.
    public func conversations(token: String) async throws -> [MessagingConversation] {
        let rows: [MessagingConversation] = try await execute(path: "api/im/conversations", fields: [:], token: token)
        guard Set(rows.map(\.id)).count == rows.count else { throw APIError.malformedResponse }
        return rows
    }
    /// cursor 0 = latest; the normal source page size is 30. The verified server bounds each page to 50.
    public func messages(conversationID: Int, cursor: Int = 0, size: Int = 30, token: String) async throws -> MessagingPage {
        guard conversationID > 0, cursor >= 0, (1...50).contains(size) else { throw APIError.invalidRequest }
        let page: MessagingPage = try await execute(path: "api/im/messages", fields: [
            "conversation_id": String(conversationID), "cursor_id": String(cursor), "size": String(size)
        ], token: token)
        guard page.messages.allSatisfy({ $0.conversationID == conversationID }) else { throw APIError.malformedResponse }
        return page
    }
    private func execute<Value: Decodable>(path: String, fields: [String: String], token: String) async throws -> Value {
        guard AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        try Task.checkCancellation()
        let request = try AuthRequestBuilder.makeFormRequest(
            url: configuration.baseURL.appendingPathComponent(path), fields: fields, token: token)
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation()
        if !(200..<300).contains(status) {
            let failure = try? JSONDecoder().decode(FailureEnvelope.self, from: data)
            throw MessagingReadFailure(httpStatus: status, code: failure?.code,
                errorCode: failure?.errorCode, message: failure?.msg)
        }
        do { return try JSONDecoder().decode(Envelope<Value>.self, from: data).data }
        catch let error as MessagingReadFailure { throw error }
        catch { throw APIError.malformedResponse }
    }
    private struct FailureEnvelope: Decodable {
        let code: Int?
        let errorCode: String?
        let msg: String?
    }
    private struct Envelope<Value: Decodable>: Decodable {
        let data: Value
        private enum CodingKeys: String, CodingKey { case code, errorCode, msg, data }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let code = try c.decode(Int.self, forKey: .code)
            guard code == 200 else {
                throw MessagingReadFailure(code: code,
                    errorCode: (try? c.decode(String.self, forKey: .errorCode))?.trimmingCharacters(in: .whitespacesAndNewlines),
                    message: try? c.decode(String.self, forKey: .msg))
            }
            data = try c.decode(Value.self, forKey: .data)
        }
    }
}
