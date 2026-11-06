import Foundation
import CoreFoundation
import CryptoKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// SHA-256 of Fastjson2 `JSON.toJSONString(Arrays.asList("SEND", channel, 1, content, null, reply, members, roles, everyone))`.
/// Members and roles are sorted unique positive longs. The current message body is not an input.
public enum NativeChannelOriginalSendDigest {
    public static func requestHash(_ intent: MessageTextIntent) -> String? {
        let reply = intent.channelReference?.replyToID.flatMap { Int64($0.rawValue) } ?? 0
        let members = intent.channelReference?.memberIDs.compactMap { Int64($0.rawValue) } ?? []
        let roles = intent.channelReference?.roleIDs.compactMap { Int64($0.rawValue) } ?? []
        return requestHash(content: intent.content, conversationID: Int64(intent.conversationID), replyToID: reply,
                           memberIDs: members, roleIDs: roles, mentionEveryone: intent.channelReference?.mentionEveryone ?? false)
    }
    /// `<` and `&` can be rewritten by the original HTML cleaner. This client does not
    /// reimplement that cleaner, so those inputs stay unproved instead of hashing raw text.
    public static func requestHash(content: String, conversationID: Int64, replyToID: Int64,
                                   memberIDs: [Int64], roleIDs: [Int64], mentionEveryone: Bool) -> String? {
        guard !content.contains("<"), !content.contains("&") else { return nil }
        let json = "[" + jsonString("SEND") + "," + String(conversationID) + ",1," + jsonString(content)
            + ",null," + String(replyToID) + "," + jsonLongs(uniqueSorted(memberIDs)) + ","
            + jsonLongs(uniqueSorted(roleIDs)) + "," + (mentionEveryone ? "true" : "false") + "]"
        return SHA256.hash(data: Data(json.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private static func uniqueSorted(_ values: [Int64]) -> [Int64] {
        Array(Set(values.filter { $0 > 0 })).sorted()
    }
    private static func jsonLongs(_ values: [Int64]) -> String {
        "[" + values.map(String.init).joined(separator: ",") + "]"
    }
    private static func jsonString(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x22: out += "\\\""
            case 0x5C: out += "\\\\"
            case 0x08: out += "\\b"
            case 0x0C: out += "\\f"
            case 0x0A: out += "\\n"
            case 0x0D: out += "\\r"
            case 0x09: out += "\\t"
            case 0..<0x20: out += String(format: "\\u%04x", scalar.value)
            default: out.unicodeScalars.append(scalar)
            }
        }
        out += "\""
        return out
    }
}

public struct NativeChannelOriginalSendRead: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case notFound
        case unknown
        case legacy
        case applied(messageID: Int)
    }
    public let kind: Kind
    public let displayWithheld: Bool
    public init(kind: Kind, displayWithheld: Bool) {
        self.kind = kind
        self.displayWithheld = displayWithheld
    }
}

/// Server receipt is not a read receipt. The existing MessagingMessage decoder still
/// controls moderation/recall visibility; private wire identity is only a verifier.
public struct NativeChannelTextService {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    private let originalMentionWireEnabled: Bool
    private let originalReplyWireEnabled: Bool
    public init(configuration: APIConfiguration, transport: any HTTPTransport, originalReplyWireEnabled: Bool = false, originalMentionWireEnabled: Bool = false) {
        self.originalMentionWireEnabled = originalMentionWireEnabled
        self.configuration = configuration; self.transport = transport; self.originalReplyWireEnabled = originalReplyWireEnabled
    }
    public func send(_ intent: MessageTextIntent, accountID: Int, token: String) async throws -> MessagingMessage {
        if let reference = intent.channelReference {
            let mentions = !reference.memberIDs.isEmpty || !reference.roleIDs.isEmpty || reference.mentionEveryone
            guard reference.matchesConversation(intent.conversationID),
                  reference.replyToID == nil || originalReplyWireEnabled,
                  !mentions || originalMentionWireEnabled else { throw APIError.notConfigured }
            try reference.validate()
            var fields=["conversation_id":String(intent.conversationID),"client_message_id":intent.clientMessageID,"msg_type":"1","content":intent.content]
            if let reply=reference.replyToID { fields["reply_to_id"]=reply.rawValue }
            if mentions {
                fields["mention_member_ids"]="["+reference.memberIDs.map(\.rawValue).joined(separator:",")+"]"
                fields["mention_role_ids"]="["+reference.roleIDs.map(\.rawValue).joined(separator:",")+"]"
                fields["mention_everyone"]=reference.mentionEveryone ? "1" : "0"
            }
            _ = try await raw(path:"api/im/send",fields:fields,token:token)
            // A successful/current message body is not original reference proof. Read the original request receipt.
            guard let message = try await originalQuotedReceipt(intent, accountID: accountID, token: token) else { throw APIError.malformedResponse }
            return message
        }
        let wire: WireMessage = try await execute(path: "api/im/send", fields: [
            "conversation_id": String(intent.conversationID), "client_message_id": intent.clientMessageID,
            "msg_type": "1", "content": intent.content
        ], token: token)
        return try wire.verified(intent, accountID: accountID)
    }
    public func receipt(_ intent: MessageTextIntent, accountID: Int, token: String) async throws -> MessagingMessage? {
        if intent.channelReference != nil { return try await originalQuotedReceipt(intent, accountID: accountID, token: token) }
        let result: Receipt = try await execute(path: "api/im/send-receipt", fields: [
            "conversation_id": String(intent.conversationID), "client_message_id": intent.clientMessageID
        ], token: token)
        if !result.found {
            guard result.message == nil else { throw APIError.malformedResponse }
            return nil // Unknown, never proof the original request cannot later commit.
        }
        guard let message = result.message else { throw APIError.malformedResponse }
        return try message.verified(intent, accountID: accountID)
    }
    private func originalQuotedReceipt(_ intent: MessageTextIntent, accountID: Int, token: String) async throws -> MessagingMessage? {
        let data = try await raw(path: "api/im/send-receipt", fields: ["conversation_id": String(intent.conversationID),
            "client_message_id": intent.clientMessageID], token: token)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let body = root["data"] as? [String: Any] else { throw APIError.malformedResponse }
        let proof = Self.readOriginalSend(body, intent: intent, accountID: accountID)
        if proof.kind == .notFound { return nil }
        guard case .applied(let id) = proof.kind, !proof.displayWithheld,
              let object = body["message"] as? [String: Any] else { throw APIError.malformedResponse }
        let wire = try JSONDecoder().decode(WireMessage.self, from: JSONSerialization.data(withJSONObject: object))
        let message = try wire.verified(intent, accountID: accountID, referenceProofConfirmed: true)
        guard message.id == id else { throw APIError.malformedResponse }; return message
    }
    /// Proof sits beside message. A missing display message stays a typed result.
    public func confirmOriginal(_ intent: MessageTextIntent, accountID: Int, token: String) async throws -> NativeChannelOriginalSendRead {
        let data = try await raw(path: "api/im/send-receipt", fields: [
            "conversation_id": String(intent.conversationID), "client_message_id": intent.clientMessageID
        ], token: token)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let body = root["data"] as? [String: Any] else { throw APIError.malformedResponse }
        return Self.readOriginalSend(body, intent: intent, accountID: accountID)
    }
    static func readOriginalSend(_ body: [String: Any], intent: MessageTextIntent, accountID: Int) -> NativeChannelOriginalSendRead {
        let state = body["state"] as? String
        if let facade = body["facade_metadata_confirmed"] {
            guard let confirmed = jsonBool(facade) else {
                return NativeChannelOriginalSendRead(kind: .unknown, displayWithheld: false)
            }
            if state == "LEGACY_COMMITTED" || confirmed == false {
                return NativeChannelOriginalSendRead(kind: .legacy, displayWithheld: false)
            }
        } else if state == "LEGACY_COMMITTED" {
            return NativeChannelOriginalSendRead(kind: .legacy, displayWithheld: false)
        }
        let found = jsonBool(body["found"])
        guard found == true, state == "APPLIED" else {
            let messageValue = body["message"]
            let proofValue = body["original_send_proof"]
            let hasMessage = messageValue != nil && !(messageValue is NSNull)
            let hasProof = proofValue != nil && !(proofValue is NSNull)
            if found == false, state == nil || state == "NOT_FOUND", !hasMessage, !hasProof {
                return NativeChannelOriginalSendRead(kind: .notFound, displayWithheld: false)
            }
            return NativeChannelOriginalSendRead(kind: .unknown, displayWithheld: false)
        }
        guard accountID > 0, let proof = body["original_send_proof"] as? [String: Any],
              proof["operation"] as? String == "SEND",
              let request = proof["request_id"] as? String, request.utf8.elementsEqual(intent.clientMessageID.utf8),
              let actor = exactLong(proof["actor_member_id"]), actor == Int64(accountID),
              let channel = exactLong(proof["conversation_id"]), channel == Int64(intent.conversationID),
              let messageID = exactLong(proof["message_id"]), let fit = Int(exactly: messageID),
              let expected = NativeChannelOriginalSendDigest.requestHash(intent),
              let hash = proof["request_hash"] as? String, hash.utf8.elementsEqual(expected.utf8),
              hash.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else {
            return NativeChannelOriginalSendRead(kind: .unknown, displayWithheld: false)
        }
        return NativeChannelOriginalSendRead(kind: .applied(messageID: fit), displayWithheld: displayWithheld(body["message"], proofMessageID: fit, conversationID: intent.conversationID))
    }
    /// The display conversation must be the original intent and proof conversation.
    /// A non-nil id in another channel does not become visible.
    private static func displayWithheld(_ message: Any?, proofMessageID: Int, conversationID: Int) -> Bool {
        guard let message = message as? [String: Any] else { return true }
        if let flag = message["message_unavailable"] {
            guard jsonBool(flag) == false else { return true }
        }
        guard conversationID > 0, let status = exactJSONInteger(message["status"], allowZero: true), status == Int64(0),
              let msgType = exactJSONInteger(message["msgType"], allowZero: false),
              let kind = Int(exactly: msgType), NativeChannelMessageKind(rawValue: kind) != nil,
              exactLong(message["id"]) == Int64(proofMessageID),
              exactLong(message["conversationId"]) == Int64(conversationID) else { return true }
        return false
    }
    private static func jsonBool(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }
    /// JSON status/kind values must be whole numbers, never strings or booleans.
    /// 1.5 does not truncate. 1.0 may map to 1.
    private static func exactJSONInteger(_ value: Any?, allowZero: Bool) -> Int64? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let whole = number.int64Value
        guard number.doubleValue == Double(whole), number.stringValue == String(whole),
              allowZero ? whole >= 0 : whole > 0 else { return nil }
        return whole
    }
    /// Business IDs retain canonical decimal strings and exact positive integers.
    /// Large string IDs never pass through Double.
    private static func exactLong(_ value: Any?) -> Int64? {
        if let text = value as? String {
            guard text.range(of: "^[0-9]{1,19}$", options: .regularExpression) != nil,
                  let number = Int64(text), String(number) == text, number > 0 else { return nil }
            return number
        }
        return exactJSONInteger(value, allowZero: false)
    }
    private struct Receipt: Decodable { let found: Bool; let message: WireMessage? }
    private struct WireMessage: Decodable {
        let senderId: Int
        let conversationId: Int
        let clientMessageId: String
        let msgType: Int
        let message: MessagingMessage
        private enum CodingKeys: String, CodingKey { case senderId, conversationId, clientMessageId, msgType }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            senderId = try c.decode(Int.self, forKey: .senderId)
            conversationId = try c.decode(Int.self, forKey: .conversationId)
            clientMessageId = try c.decode(String.self, forKey: .clientMessageId)
            msgType = try c.decode(Int.self, forKey: .msgType)
            message = try MessagingMessage(from: decoder)
        }
        func verified(_ intent: MessageTextIntent, accountID: Int, referenceProofConfirmed: Bool = false) throws -> MessagingMessage {
            // A matching client key/current text does not prove absent original metadata.
            guard intent.channelReference == nil || referenceProofConfirmed else { throw APIError.notConfigured }
            guard accountID > 0, senderId == accountID, conversationId == intent.conversationID,
                  clientMessageId.utf8.elementsEqual(intent.clientMessageID.utf8), msgType == 1,
                  !message.isPayloadVisible || (message.content.map({ $0.utf8.elementsEqual(intent.content.utf8) }) == true
                      && message.extraJSON == nil) else {
                throw APIError.malformedResponse
            }
            return message
        }
    }
    private func raw(path: String, fields: [String: String], token: String) async throws -> Data {
        guard AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        var request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent(path), fields: fields, token: token)
        request.httpShouldHandleCookies = false
        try Task.checkCancellation()
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation()
        guard data.count <= 2 * 1024 * 1024 else { throw APIError.malformedResponse }
        let header = try? JSONDecoder().decode(Header.self, from: data)
        guard (200..<300).contains(status), header?.code == 200 else {
            throw MessagingReadFailure(httpStatus: (200..<300).contains(status) ? nil : status,
                code: header?.code, errorCode: header?.errorCode, message: nil)
        }
        return data
    }
    private func execute<Value: Decodable>(path: String, fields: [String: String], token: String) async throws -> Value {
        guard AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        var request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent(path), fields: fields, token: token)
        request.httpShouldHandleCookies = false
        try Task.checkCancellation()
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation()
        guard data.count <= 2 * 1024 * 1024 else { throw APIError.malformedResponse }
        let header = try? JSONDecoder().decode(Header.self, from: data)
        guard (200..<300).contains(status), header?.code == 200 else {
            throw MessagingReadFailure(httpStatus: (200..<300).contains(status) ? nil : status,
                code: header?.code, errorCode: header?.errorCode, message: nil)
        }
        do { return try JSONDecoder().decode(Envelope<Value>.self, from: data).data }
        catch { throw APIError.malformedResponse }
    }
    /// The original wire allows an HTTP failure or a bounded, typed Ajax header.
    /// Inspect only an actually returned response, before cancellation hides it.
    /// This does not rewrite status/data or infer rejection from a network error.
    static func receivedUnauthorized(data: Data, status: Int) -> Bool {
        if status == 401 { return true }
        guard data.count <= 2 * 1024 * 1024 else { return false }
        return (try? JSONDecoder().decode(Header.self, from: data))?.code == 401
    }
    private struct Header: Decodable { let code: Int; let errorCode: String? }
    private struct Envelope<Value: Decodable>: Decodable { let data: Value }
}

@MainActor public protocol NativeChannelTextAccess: AnyObject {
    var scope: NativeChannelTextScope { get }
    var identity: MessagingReadIdentity? { get }
    var canReadReceipt: Bool { get }
    var canSend: Bool { get }
    var canSendQuoted: Bool { get }
    var canSendMentions: Bool { get }
    func retireOperations()
    func send(_ intent: MessageTextIntent) async throws -> MessagingMessage
    func receipt(_ intent: MessageTextIntent) async throws -> MessagingMessage?
    func confirmOriginal(_ intent: MessageTextIntent) async throws -> NativeChannelOriginalSendRead
}

public extension NativeChannelTextAccess { var canSendQuoted: Bool { false }; var canSendMentions: Bool { false } }

@MainActor public final class NativeChannelTextClient: NativeChannelTextAccess {
    public let scope: NativeChannelTextScope
    private let context: RuntimeDependencyContext
    private let transport: NativeChannelTextTransport
    private let configuration: APIConfiguration
    private var operationRevision: UInt64 = 0
    private let onUnauthorized: (RuntimeDependencyContext) -> Void
    public var identity: MessagingReadIdentity? {
        transport.isCurrent ? .init(accountID: context.session.accountID, epoch: context.session.epoch) : nil
    }
    public var canReadReceipt: Bool { transport.allows(.receipt, conversationID: scope.conversationID) }
    public var canSend: Bool { transport.allows(.send, conversationID: scope.conversationID) }
    public var canSendQuoted: Bool { transport.allowsOriginalReply(conversationID: scope.conversationID) }
    public var canSendMentions: Bool { transport.allowsOriginalMentions(conversationID: scope.conversationID) }
    public init(context: RuntimeDependencyContext, conversationID: Int, transport: NativeChannelTextTransport,
                onUnauthorized: @escaping (RuntimeDependencyContext) -> Void = { _ in }) throws {
        self.context = context; scope = try .init(context: context, conversationID: conversationID)
        self.transport = transport; self.onUnauthorized = onUnauthorized
        configuration = try .init(baseURL: context.baseURL)
    }
    public func retireOperations() { operationRevision &+= 1 }
    public func send(_ intent: MessageTextIntent) async throws -> MessagingMessage {
        try await checked(intent, operation: .send) { service in
            try await service.send(intent, accountID: scope.accountID, token: context.session.token)
        }
    }
    public func receipt(_ intent: MessageTextIntent) async throws -> MessagingMessage? {
        try await checked(intent, operation: .receipt) { service in
            try await service.receipt(intent, accountID: scope.accountID, token: context.session.token)
        }
    }
    public func confirmOriginal(_ intent: MessageTextIntent) async throws -> NativeChannelOriginalSendRead {
        try await checked(intent, operation: .receipt) { service in
            try await service.confirmOriginal(intent, accountID: scope.accountID, token: context.session.token)
        }
    }
    private func checked<Value>(_ intent: MessageTextIntent, operation: NativeChannelTextOperation,
                                work: (NativeChannelTextService) async throws -> Value) async throws -> Value {
        guard intent.conversationID == scope.conversationID, transport.allows(operation, conversationID: scope.conversationID) else { throw APIError.notConfigured }
        let revision = operationRevision
        // Bind this request to the lifecycle at intent dispatch, not to whichever
        // lifecycle happens to be active when a queued transport resumes.
        let scoped = NativeChannelDispatchTransport { [weak self] request in
            guard let self, self.operationRevision == revision, !Task.isCancelled,
                  self.transport.allows(operation, conversationID: self.scope.conversationID) else { throw CancellationError() }
            do {
                let result = try await self.transport.send(request, onCurrentUnauthorized: { [weak self] in
                    // The transport invokes this synchronously BEFORE retiring the original
                    // approvals, and only while the original context/issuance still matches.
                    guard let self, self.operationRevision == revision, !Task.isCancelled,
                          self.transport.allows(operation, conversationID: self.scope.conversationID) else { return }
                    self.onUnauthorized(self.context)
                })
                guard self.operationRevision == revision, !Task.isCancelled else { throw CancellationError() }
                return result
            } catch {
                guard self.operationRevision == revision, !Task.isCancelled else { throw CancellationError() }
                throw error
            }
        }
        let service = NativeChannelTextService(configuration: configuration, transport: scoped, originalReplyWireEnabled: canSendQuoted, originalMentionWireEnabled: canSendMentions)
        do {
            let result = try await work(service)
            guard operationRevision == revision, !Task.isCancelled,
                  transport.allows(operation, conversationID: scope.conversationID) else { throw CancellationError() }
            return result
        } catch {
            guard operationRevision == revision, !Task.isCancelled,
                  transport.allows(operation, conversationID: scope.conversationID) else { throw CancellationError() }
            if (error as? MessagingReadFailure)?.isUnauthorized == true { onUnauthorized(context) }
            throw error
        }
    }
}
