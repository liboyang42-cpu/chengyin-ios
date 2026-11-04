import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Only the original ordinary text/image request. This is not a delivery/read receipt,
/// a history lease, a channel proof, or permission to resend an UNKNOWN request.
public enum OrdinaryIMSendReceiptResult: Equatable {
    case found(MessagingMessage)
    case notFound
}
public enum OrdinaryIMReceiptReadState: Equatable {
    case idle, reading, notFound, unknown
}

/// Independently issued POST /api/im/send-receipt. No send/upload/start fallback.
/// The server locks current read membership, then selects conversation + authenticated
/// owner + client ID. Errors, malformed envelopes and timeouts are never NOT_FOUND.
public struct OrdinaryIMSendReceipt {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    public init(configuration: APIConfiguration, transport: any HTTPTransport) {
        self.configuration = configuration; self.transport = transport
    }
    public func read(_ intent: MessageTextIntent, accountID: Int, token: String) async throws -> OrdinaryIMSendReceiptResult {
        guard intent.channelReference == nil else { throw APIError.notConfigured }
        return try await read(conversationID: intent.conversationID, accountID: accountID,
            clientID: intent.clientMessageID, type: 1, content: intent.content, token: token)
    }
    public func readImage(_ intent: IMOutgoingIntent, token: String) async throws -> OrdinaryIMSendReceiptResult {
        guard case .image(let url) = intent.payload else { throw APIError.notConfigured }
        // Recover the original bytes even if the upload origin is no longer writable.
        // This request never dereferences the image URL and does not grant preview access.
        return try await read(conversationID: intent.scope.conversationID, accountID: intent.scope.identity.accountID,
            clientID: intent.clientMessageID, type: 2, content: url.absoluteString, token: token)
    }
    /// Exact read endpoint rejection: do not keep probing a revoked/closed owner.
    static func revokesRead(_ failure: MessagingReadFailure) -> Bool {
        [401, 403, 404, 409].contains(failure.httpStatus ?? 0)
            || [401, 403, 404, 409].contains(failure.code ?? 0)
            || failure.isClosed || failure.errorCode == "IM_CONVERSATION_CLOSED"
    }
    static func visibleOrder(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let bytes = Array(raw.utf8)
        guard bytes.count == 26 else { return nil }
        let separators: [Int: UInt8] = [4: 45, 7: 45, 10: 32, 13: 58, 16: 58, 19: 46]
        guard bytes.enumerated().allSatisfy({ index, byte in
            if let separator = separators[index] { return byte == separator }
            return (48...57).contains(byte)
        }) else { return nil }
        return raw
    }
    private func read(conversationID: Int, accountID: Int, clientID: String,
                      type: Int, content: String, token: String) async throws -> OrdinaryIMSendReceiptResult {
        guard accountID > 0, conversationID > 0, AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        _ = try MessageTextIntent(conversationID: conversationID, content: "identity", clientMessageID: clientID)
        try Task.checkCancellation()
        var request = try AuthRequestBuilder.makeFormRequest(
            url: configuration.baseURL.appendingPathComponent("api/im/send-receipt"),
            fields: ["conversation_id": String(conversationID), "client_message_id": clientID], token: token)
        request.httpShouldHandleCookies = false
        request.timeoutInterval = 20
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation()
        guard data.count <= 2 * 1024 * 1024 else { throw APIError.malformedResponse }
        struct Header: Decodable { let code: Int; let errorCode: String?; let msg: String? }
        let header = try? JSONDecoder().decode(Header.self, from: data)
        guard (200..<300).contains(status) else {
            throw MessagingReadFailure(httpStatus: status, code: header?.code, errorCode: header?.errorCode, message: header?.msg)
        }
        guard let header else { throw APIError.malformedResponse }
        guard header.code == 200 else { throw MessagingReadFailure(code: header.code, errorCode: header.errorCode, message: header.msg) }
        struct Message: Decodable { let clientMessageId: String }
        struct Envelope: Decodable {
            struct Body: Decodable {
                let found: Bool
                let message: MessagingMessage?
                let identity: Message?
                enum CodingKeys: String, CodingKey { case found, message }
                init(from decoder: Decoder) throws {
                    let c = try decoder.container(keyedBy: CodingKeys.self)
                    found = try c.decode(Bool.self, forKey: .found)
                    // The original controller always includes message (explicit null on miss).
                    guard c.contains(.message) else { throw APIError.malformedResponse }
                    message = try c.decodeIfPresent(MessagingMessage.self, forKey: .message)
                    identity = try c.decodeIfPresent(Message.self, forKey: .message)
                }
            }
            let data: Body
        }
        guard let body = try? JSONDecoder().decode(Envelope.self, from: data).data else { throw APIError.malformedResponse }
        if !body.found {
            guard body.message == nil, body.identity == nil else { throw APIError.malformedResponse }
            return .notFound
        }
        guard let message = body.message, let key = body.identity?.clientMessageId,
              key.utf8.elementsEqual(clientID.utf8), message.id > 0,
              message.conversationID == conversationID, message.senderID == accountID,
              message.isPayloadVisible, message.type == type,
              let returned = message.content, returned.utf8.elementsEqual(content.utf8),
              message.extraJSON == nil else { throw APIError.malformedResponse }
        return .found(message)
    }
}
