import Foundation
import CryptoKit

/// C09 exclusive original-request receipts. Reply / mention / edit / withdraw / pin / search
/// bind once. APPLIED+CURRENT / VISIBLE current projection is never original proof.
/// Missing unsigned originals stay WAITING_SOURCE (v12 DOCX, 232 pack, unpushed e2d86c4).
/// Untrusted wire values stay JSON null / Optional.none. Never coerce to "" or [].
public enum NotifyFailure: Error, Equatable {
    case waitingSource(capability: String)
    case missingOriginalRequestID
    case fingerprintConflict(requestId: String)
    case originalMissing(String)
    case invalidEnvironment
    case invalidFixtureToken
    case revokedDeviceCannotReregister
    case attachmentConflict(requestId: String)
    case invalidReviewDecision
    case incompleteWebhookConfig
    case invalidFixtureSigningKey
    case ssrfRejected(String)
    case unsignedSourceRewrite
    case invalidRequestID
    public var isWaitingSource: Bool {
        if case .waitingSource = self { return true }
        return false
    }
}

public enum NotifySourceInventory {
    public static let v12Docx = "v12.docx"
    public static let pack232 = "232.pack"
    public static let unpushedIosSHA = "e2d86c4"
    public static var v12DocxPresent: Bool { false }
    public static var pack232Present: Bool { false }
    public static var unpushedIosSHAPresent: Bool { false }
}

public enum NotifyKind: String, Equatable, Sendable {
    case reply = "REPLY"
    case mention = "MENTION"
    case edit = "EDIT"
    case withdraw = "WITHDRAW"
    case pin = "PIN"
    case search = "SEARCH"
}

public struct ImmutableReceiptProducer: Equatable {
    public static let projectionApplied = "APPLIED+CURRENT"
    public static let outcomeAccepted = "ACCEPTED"
    public static let outcomeUnknown = "UNKNOWN"
    public static let unknownNotRecovered = "UNKNOWN_NOT_RECOVERED"

    public struct OriginalRequest: Equatable, Sendable {
        public var requestId: String?
        public var kind: NotifyKind?
        public var body: String?
        public var outcome: String?
        public init(requestId: String?, kind: NotifyKind?, body: String?, outcome: String?) {
            self.requestId = ImmutableReceiptProducer.parse(requestId)
            self.kind = kind
            self.body = ImmutableReceiptProducer.parse(body, limit: 4096)
            self.outcome = ImmutableReceiptProducer.parse(outcome)
        }
    }

    public struct AppliedProjection: Equatable, Sendable {
        public var requestId: String?
        public var appliedState: String?
        public init(requestId: String?, appliedState: String?) {
            self.requestId = ImmutableReceiptProducer.parse(requestId)
            self.appliedState = ImmutableReceiptProducer.parse(appliedState)
        }
    }

    public struct OriginalReceipt: Equatable, Sendable {
        public var requestId: String?
        public var kind: NotifyKind?
        public var payloadHash: String?
        public var outcome: String?
        public var originalBody: String?
        public var currentProjectionClaimsApplied: Bool
        public var recoveryNote: String?
        public var mintedNewRequest: Bool
        public func originalIsNotProjectionSuccess() -> Bool {
            outcome != ImmutableReceiptProducer.projectionApplied
        }
        public func jsonObject() -> [String: Any] {
            [
                "requestId": requestId.map { $0 as Any } ?? NSNull(),
                "kind": kind.map { $0.rawValue as Any } ?? NSNull(),
                "payloadHash": payloadHash.map { $0 as Any } ?? NSNull(),
                "outcome": outcome.map { $0 as Any } ?? NSNull(),
                "usedCurrentProjectionAsSuccess": false,
                "recoveryNote": recoveryNote.map { $0 as Any } ?? NSNull(),
                "mintedNewRequest": mintedNewRequest
            ]
        }
        public func withProjectionClaim(_ claimed: Bool) -> OriginalReceipt {
            var next = self
            next.currentProjectionClaimsApplied = claimed
            return next
        }
        public func withNoted(_ note: String?) -> OriginalReceipt {
            var next = self
            next.recoveryNote = ImmutableReceiptProducer.parse(note)
            return next
        }
    }

    public static let imReadSent = "im.readSentMessage"
    public static let imSend = "im.send"
    public static let imSendCommand = "im.send.originalCommand"
    public static let imSendWire = "im.send.originalWire"
    public static let channelMessageSend = "channelMessage.send"
    public static let channelMessageEdit = "channelMessage.edit"
    public static let channelMessageRecall = "channelMessage.recall"
    public static let channelMessagePin = "channelMessage.pin"
    public static let channelMessageSearch = "channelMessage.search"
    public static let notASend = "IM_OPERATION_NOT_SEND"

    public struct SentMessage: Equatable, Sendable {
        public var clientMessageId: String?
        public var requestHash: String?
        public var content: String?
        public var conversationId: Int64?
        public var senderId: Int64?
        public init(clientMessageId: String?, requestHash: String?, content: String?,
                    conversationId: Int64? = nil, senderId: Int64? = nil) {
            self.clientMessageId = ImmutableReceiptProducer.parse(clientMessageId)
            self.requestHash = ImmutableReceiptProducer.parse(requestHash, limit: 128)
            self.content = ImmutableReceiptProducer.parse(content, limit: 4096)
            self.conversationId = conversationId
            self.senderId = senderId
        }
    }

    public private(set) var originalByRequestID: [String: OriginalReceipt] = [:]
    public init() {}

    public static func parse(_ raw: String?, limit: Int = 64) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= limit else { return nil }
        return trimmed
    }

    public static func requireRequestID(_ raw: String?) throws -> String {
        guard let id = parse(raw) else { throw NotifyFailure.missingOriginalRequestID }
        return id
    }

    public static func jsonValue(_ raw: String?) -> Any {
        raw.map { $0 as Any } ?? NSNull()
    }

    public static func sha256Hex(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public mutating func accept(_ request: OriginalRequest) throws -> OriginalReceipt {
        let id = try Self.requireRequestID(request.requestId)
        guard let kind = request.kind else { throw NotifyFailure.missingOriginalRequestID }
        let outcome = request.outcome ?? Self.outcomeUnknown
        let fingerprint = Self.fingerprint(requestId: id, kind: kind, body: request.body, outcome: outcome)
        if let existing = originalByRequestID[id] {
            if existing.payloadHash != fingerprint {
                throw NotifyFailure.fingerprintConflict(requestId: id)
            }
            return existing
        }
        let receipt = OriginalReceipt(
            requestId: id, kind: kind, payloadHash: fingerprint, outcome: outcome,
            originalBody: request.body, currentProjectionClaimsApplied: false,
            recoveryNote: nil, mintedNewRequest: false)
        originalByRequestID[id] = receipt
        return receipt
    }

    public mutating func offlineReopen(originalRequestID: String, projection: AppliedProjection?) throws -> OriginalReceipt {
        try recover(originalRequestID: originalRequestID, projection: projection)
    }

    public mutating func recoverOriginal(originalRequestID: String, projection: AppliedProjection?) -> OriginalReceipt {
        recoverUnknown(originalRequestID: originalRequestID, projection: projection)
    }

    public mutating func recoverUnknown(originalRequestID: String, projection: AppliedProjection?) -> OriginalReceipt {
        guard let id = Self.parse(originalRequestID) else {
            return Self.unknownReceipt(requestId: nil, projection: projection)
        }
        if let original = originalByRequestID[id] {
            let claimed = projection?.requestId == id
                && projection?.appliedState == Self.projectionApplied
            var recovered = original.withProjectionClaim(claimed)
            if recovered.outcome == Self.outcomeUnknown || recovered.outcome == nil {
                recovered = recovered.withNoted(Self.unknownNotRecovered)
            }
            recovered.mintedNewRequest = false
            return recovered
        }
        return Self.unknownReceipt(requestId: id, projection: projection)
    }

    public mutating func recover(originalRequestID: String, projection: AppliedProjection?) throws -> OriginalReceipt {
        let id = try Self.requireRequestID(originalRequestID)
        guard let original = originalByRequestID[id] else {
            throw NotifyFailure.originalMissing(id)
        }
        let claimed = projection?.requestId == id
            && projection?.appliedState == Self.projectionApplied
        return original.withProjectionClaim(claimed)
    }

    public func treatsAppliedProjectionAsOriginalProof(_ projection: AppliedProjection?) -> Bool {
        false
    }

    public func persistOriginal(_ request: OriginalRequest) throws -> OriginalReceipt {
        _ = try Self.requireRequestID(request.requestId)
        throw NotifyFailure.waitingSource(capability: Self.imSend)
    }

    public enum NotASend: Error, Equatable {
        case missingKind
        case kind(NotifyKind)
    }

    static func originalWire(_ kind: NotifyKind, _ extraJSON: String) -> Bool {
        guard let data = extraJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        switch kind {
        case .reply:
            return object["reply_to_id"] is NSNumber
        case .mention:
            if object["mention_member_ids"] is [Any] || object["mention_role_ids"] is [Any] { return true }
            return object["mention_everyone"] is NSNumber
        default:
            return false
        }
    }

    /// The installed channel writer. Nil keeps the send closed. One call, no second receipt store.
    public typealias ChannelOriginalSend = (
        _ actorID: Int64, _ conversationID: Int64, _ requestID: String, _ msgType: Int,
        _ content: String, _ extraJSON: String?, _ replyToID: Int64?,
        _ mentionMemberIDs: [Int64], _ mentionRoleIDs: [Int64], _ mentionEveryone: Bool
    ) throws -> [String: Any]

    /// Channel REPLY/MENTION uses ChannelMessageService.send fields, not the legacy direct send.
    /// SEARCH/EDIT/WITHDRAW/PIN do not send. OriginalRequest.body is fingerprint material, not content.
    public func sendOriginal(
        _ request: OriginalRequest,
        actorID: Int64?,
        conversationID: Int64?,
        msgType: Int?,
        content: String?,
        extraJSON: String?,
        replyToID: Int64?,
        mentionMemberIDs: [Int64],
        mentionRoleIDs: [Int64],
        mentionEveryone: Bool,
        channel: ChannelOriginalSend? = nil
    ) throws -> OriginalReceipt? {
        let id = try Self.requireRequestID(request.requestId)
        guard let kind = request.kind else { throw NotASend.missingKind }
        guard kind == .reply || kind == .mention else { throw NotASend.kind(kind) }
        let trimmedContent = content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let actorID, actorID > 0, let conversationID, conversationID > 0, let msgType,
              !trimmedContent.isEmpty, trimmedContent != request.body else {
            throw NotifyFailure.waitingSource(capability: Self.imSendCommand)
        }
        if kind == .reply {
            guard let replyToID, replyToID > 0 else {
                throw NotifyFailure.waitingSource(capability: Self.imSendWire)
            }
        } else if mentionMemberIDs.isEmpty && mentionRoleIDs.isEmpty && !mentionEveryone {
            throw NotifyFailure.waitingSource(capability: Self.imSendWire)
        }
        guard let channel else {
            throw NotifyFailure.waitingSource(capability: Self.channelMessageSend)
        }
        let sent = try channel(actorID, conversationID, id, msgType, trimmedContent, extraJSON,
                               replyToID, mentionMemberIDs, mentionRoleIDs, mentionEveryone)
        guard Self.sameChannelReceipt(sent, requestID: id) else {
            throw NotifyFailure.fingerprintConflict(requestId: id)
        }
        return OriginalReceipt(requestId: id, kind: kind, payloadHash: nil, outcome: Self.outcomeUnknown,
                               originalBody: nil, currentProjectionClaimsApplied: false, recoveryNote: nil,
                               mintedNewRequest: false)
    }

    /// Same request id, and either one agreed message id or message_unavailable. Does not invent an id.
    private static func sameChannelReceipt(_ sent: [String: Any], requestID: String) -> Bool {
        let client = sent["client_message_id"] as? String
        let request = sent["request_id"] as? String
        if let client, let request, client != request { return false }
        guard (client ?? request) == requestID else { return false }
        let message = channelID(sent, "message_id")
        let top = channelID(sent, "id")
        let nested = nestedMessageID(sent)
        if message.invalid || top.invalid || nested.invalid { return false }
        if !agree(message, top) || !agree(message, nested) || !agree(top, nested) { return false }
        if message.present || top.present || nested.present { return true }
        return (sent["message_unavailable"] as? Bool) == true
    }

    private struct ParsedID {
        var invalid = false
        var present = false
        var value: Int64?
    }

    private static func agree(_ left: ParsedID, _ right: ParsedID) -> Bool {
        guard let left = left.value, let right = right.value else { return true }
        return left == right
    }

    private static func channelID(_ source: [String: Any], _ key: String) -> ParsedID {
        guard let value = source[key] else { return ParsedID() }
        if value is NSNull { return ParsedID(invalid: true) }
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            let int = number.int64Value
            if int > 0, number.doubleValue == Double(int), number.stringValue == String(int) {
                return ParsedID(present: true, value: int)
            }
        }
        if let text = value as? String, let int = Int64(text), int > 0, String(int) == text {
            return ParsedID(present: true, value: int)
        }
        return ParsedID(invalid: true)
    }

    private static func nestedMessageID(_ sent: [String: Any]) -> ParsedID {
        guard let value = sent["message"] else { return ParsedID() }
        if value is NSNull { return ParsedID(invalid: true) }
        guard let map = value as? [String: Any] else { return ParsedID(invalid: true) }
        return channelID(map, "id")
    }

    /// Original `ChannelMessageService.edit`. SEARCH/WITHDRAW/PIN/SEND do not edit.
    /// Nil keeps the edit closed. One call, no local receipt store.
    public typealias ChannelOriginalEdit = (
        _ actorID: Int64, _ conversationID: Int64, _ messageID: Int64, _ requestID: String,
        _ content: String, _ expectedVersion: Int64?,
        _ mentionMemberIDs: [Int64], _ mentionRoleIDs: [Int64], _ mentionEveryone: Bool
    ) throws -> [String: Any]

    public func editOriginal(
        _ request: OriginalRequest,
        actorID: Int64?,
        conversationID: Int64?,
        messageID: Int64?,
        content: String?,
        expectedVersion: Int64?,
        mentionMemberIDs: [Int64] = [],
        mentionRoleIDs: [Int64] = [],
        mentionEveryone: Bool = false,
        channel: ChannelOriginalEdit? = nil
    ) throws -> OriginalReceipt {
        guard let kind = request.kind else { throw NotASend.missingKind }
        guard kind == .edit else { throw NotASend.kind(kind) }
        guard let raw = request.requestId, Self.validSendKey(raw), raw == request.requestId else {
            throw NotifyFailure.invalidRequestID
        }
        let trimmed = content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let actorID, actorID > 0, let conversationID, conversationID > 0,
              let messageID, messageID > 0, !trimmed.isEmpty, trimmed != request.body else {
            throw NotifyFailure.waitingSource(capability: Self.imSendCommand)
        }
        if let expectedVersion, expectedVersion <= 0 {
            throw NotifyFailure.waitingSource(capability: Self.imSendWire)
        }
        guard let channel else {
            throw NotifyFailure.waitingSource(capability: Self.channelMessageEdit)
        }
        let sent = try channel(actorID, conversationID, messageID, raw, trimmed, expectedVersion,
                               mentionMemberIDs, mentionRoleIDs, mentionEveryone)
        let echoed = channelID(sent, "message_id")
        guard echoed.present, echoed.value == messageID else {
            throw NotifyFailure.fingerprintConflict(requestId: raw)
        }
        if let echoedRequest = sent["request_id"] as? String, echoedRequest != raw {
            throw NotifyFailure.fingerprintConflict(requestId: raw)
        }
        return OriginalReceipt(requestId: raw, kind: .edit, payloadHash: nil, outcome: Self.outcomeUnknown,
                               originalBody: nil, currentProjectionClaimsApplied: false, recoveryNote: nil,
                               mintedNewRequest: false)
    }

    /// Original `ChannelMessageService.recall`. The exclusive kind is withdraw. One call, no local store.
    public typealias ChannelOriginalRecall = (
        _ actorID: Int64, _ conversationID: Int64, _ messageID: Int64, _ requestID: String,
        _ reason: String, _ expectedVersion: Int64?
    ) throws -> [String: Any]

    public func recallOriginal(
        _ request: OriginalRequest,
        actorID: Int64?,
        conversationID: Int64?,
        messageID: Int64?,
        reason: String?,
        expectedVersion: Int64?,
        channel: ChannelOriginalRecall? = nil
    ) throws -> OriginalReceipt {
        guard let kind = request.kind else { throw NotASend.missingKind }
        guard kind == .withdraw else { throw NotASend.kind(kind) }
        guard let raw = request.requestId, Self.validSendKey(raw) else { throw NotifyFailure.invalidRequestID }
        guard let actorID, actorID > 0, let conversationID, conversationID > 0, let messageID, messageID > 0 else {
            throw NotifyFailure.waitingSource(capability: Self.imSendCommand)
        }
        let trimmedReason = reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedReason.count > 200 || (expectedVersion != nil && expectedVersion! <= 0) {
            throw NotifyFailure.waitingSource(capability: Self.imSendWire)
        }
        guard let channel else { throw NotifyFailure.waitingSource(capability: Self.channelMessageRecall) }
        let sent = try channel(actorID, conversationID, messageID, raw, trimmedReason, expectedVersion)
        let echoed = channelID(sent, "message_id")
        guard echoed.present, echoed.value == messageID else {
            throw NotifyFailure.fingerprintConflict(requestId: raw)
        }
        if let echoedRequest = sent["request_id"] as? String, echoedRequest != raw {
            throw NotifyFailure.fingerprintConflict(requestId: raw)
        }
        return OriginalReceipt(requestId: raw, kind: .withdraw, payloadHash: nil, outcome: Self.outcomeUnknown,
                               originalBody: nil, currentProjectionClaimsApplied: false, recoveryNote: nil,
                               mintedNewRequest: false)
    }

    /// Original `ChannelMessageService.pin`. `pinned` false is unpin. One call, no local store.
    public typealias ChannelOriginalPin = (
        _ actorID: Int64, _ conversationID: Int64, _ messageID: Int64, _ requestID: String, _ pinned: Bool
    ) throws -> [String: Any]

    public func pinOriginal(
        _ request: OriginalRequest,
        actorID: Int64?,
        conversationID: Int64?,
        messageID: Int64?,
        pinned: Bool,
        channel: ChannelOriginalPin? = nil
    ) throws -> OriginalReceipt {
        guard let kind = request.kind else { throw NotASend.missingKind }
        guard kind == .pin else { throw NotASend.kind(kind) }
        guard let raw = request.requestId, Self.validSendKey(raw) else { throw NotifyFailure.invalidRequestID }
        guard let actorID, actorID > 0, let conversationID, conversationID > 0, let messageID, messageID > 0 else {
            throw NotifyFailure.waitingSource(capability: Self.imSendCommand)
        }
        guard let channel else { throw NotifyFailure.waitingSource(capability: Self.channelMessagePin) }
        let sent = try channel(actorID, conversationID, messageID, raw, pinned)
        let echoed = channelID(sent, "message_id")
        guard echoed.present, echoed.value == messageID, (sent["pinned"] as? Bool) == pinned else {
            throw NotifyFailure.fingerprintConflict(requestId: raw)
        }
        if let echoedRequest = sent["request_id"] as? String, echoedRequest != raw {
            throw NotifyFailure.fingerprintConflict(requestId: raw)
        }
        return OriginalReceipt(requestId: raw, kind: .pin, payloadHash: nil, outcome: Self.outcomeUnknown,
                               originalBody: nil, currentProjectionClaimsApplied: false, recoveryNote: nil,
                               mintedNewRequest: false)
    }

    /// Original `GET /api/im/search`. It does not take a request id and does not write a receipt.
    public typealias ChannelOriginalSearch = (
        _ actorID: Int64, _ conversationID: Int64?, _ keyword: String,
        _ from: String?, _ to: String?, _ authorID: Int64?, _ cursor: Int64?, _ limit: Int
    ) throws -> [String: Any]

    public func searchOriginal(
        _ request: OriginalRequest,
        actorID: Int64?,
        conversationID: Int64?,
        keyword: String?,
        from: String? = nil,
        to: String? = nil,
        authorID: Int64? = nil,
        cursor: Int64? = nil,
        limit: Int = 20,
        channel: ChannelOriginalSearch? = nil
    ) throws -> [String: Any] {
        guard let kind = request.kind else { throw NotASend.missingKind }
        guard kind == .search else { throw NotASend.kind(kind) }
        let term = keyword?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let actorID, actorID > 0, !term.isEmpty, term.count <= 100,
              conversationID == nil || conversationID! > 0,
              authorID == nil || authorID! > 0,
              cursor == nil || cursor! >= 0 else {
            throw NotifyFailure.waitingSource(capability: Self.imSendWire)
        }
        guard let channel else { throw NotifyFailure.waitingSource(capability: Self.channelMessageSearch) }
        let page = try channel(actorID, conversationID, term, from, to, authorID, cursor, limit)
        guard page["list"] is [Any], page["operation"] as? String != "ACK" else {
            throw NotifyFailure.fingerprintConflict(requestId: request.requestId ?? "")
        }
        return page
    }

    /// Read-only original SEND proof. Digest, actor, channel, request, operation, and the
    /// stored message identity come from the request row. Current body and mentions are ignored.
    public struct OriginalSendRow: Equatable, Sendable {
        public var actorMemberID: Int64?
        public var channelID: Int64?
        public var operation: String?
        public var digest: String?
        public var state: String?
        public var resultMessageID: Int64?
        public var resultClientMessageID: String?
        public init(actorMemberID: Int64? = nil, channelID: Int64? = nil, operation: String? = nil,
                    digest: String? = nil, state: String? = nil, resultMessageID: Int64? = nil,
                    resultClientMessageID: String? = nil) {
            self.actorMemberID = actorMemberID
            self.channelID = channelID
            self.operation = operation
            self.digest = digest
            self.state = state
            self.resultMessageID = resultMessageID
            self.resultClientMessageID = resultClientMessageID
        }
    }

    public struct OriginalSendProof: Equatable, Sendable {
        public let actor: Int64?
        public let channel: Int64?
        public let requestId: String?
        public let operation: String?
        public let digest: String?
        public let messageId: Int64?
        public let state: String
        public let outcomeConfirmed: Bool
    }

    public static func projectOriginalSend(actor: Int64?, channel: Int64?, requestId: String?,
                                           row: OriginalSendRow?, legacyCommitted: Bool) -> OriginalSendProof {
        guard let actor, actor > 0, let channel, channel > 0, validSendKey(requestId) else {
            return OriginalSendProof(actor: actor, channel: channel, requestId: requestId, operation: nil,
                                     digest: nil, messageId: nil, state: "NOT_FOUND", outcomeConfirmed: false)
        }
        guard let row else {
            return OriginalSendProof(actor: actor, channel: channel, requestId: requestId, operation: nil,
                                     digest: nil, messageId: nil, state: legacyCommitted ? "LEGACY" : "NOT_FOUND",
                                     outcomeConfirmed: false)
        }
        if let rowActor = row.actorMemberID, rowActor != actor {
            return OriginalSendProof(actor: actor, channel: channel, requestId: requestId, operation: nil,
                                     digest: nil, messageId: nil, state: "ACTOR_MISMATCH", outcomeConfirmed: false)
        }
        guard row.channelID == channel else {
            return OriginalSendProof(actor: actor, channel: channel, requestId: requestId, operation: nil,
                                     digest: nil, messageId: nil, state: "CHANNEL_MISMATCH", outcomeConfirmed: false)
        }
        guard row.operation == "SEND" else {
            return OriginalSendProof(actor: actor, channel: channel, requestId: requestId, operation: row.operation,
                                     digest: nil, messageId: nil, state: "WRONG_OPERATION", outcomeConfirmed: false)
        }
        guard row.state == "APPLIED" else {
            return OriginalSendProof(actor: actor, channel: channel, requestId: requestId, operation: "SEND",
                                     digest: nil, messageId: nil,
                                     state: row.state == "PENDING" ? "PENDING" : "NOT_FOUND", outcomeConfirmed: false)
        }
        guard let digest = exactDigest(row.digest), let messageId = row.resultMessageID, messageId > 0,
              row.resultClientMessageID == requestId else {
            return OriginalSendProof(actor: actor, channel: channel, requestId: requestId, operation: "SEND",
                                     digest: nil, messageId: nil, state: "NOT_FOUND", outcomeConfirmed: false)
        }
        return OriginalSendProof(actor: actor, channel: channel, requestId: requestId, operation: "SEND",
                                 digest: digest, messageId: messageId, state: "APPLIED", outcomeConfirmed: true)
    }

    private static func validSendKey(_ requestId: String?) -> Bool {
        guard let requestId else { return false }
        return requestId.range(of: "^[A-Za-z0-9_-]{16,64}$", options: .regularExpression) != nil
    }

    private static func exactDigest(_ value: String?) -> String? {
        guard let value, value.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else { return nil }
        return value
    }

    public func recoverFromJournal(memberId: Int64?, conversationId: Int64?,
                                   clientMessageId: String?,
                                   journal: ((Int64, Int64, String) -> SentMessage?)?) throws -> OriginalReceipt {
        guard let id = Self.parse(clientMessageId) else {
            return Self.unknownReceipt(requestId: nil, projection: nil)
        }
        guard let journal else {
            throw NotifyFailure.waitingSource(capability: Self.imReadSent)
        }
        guard let memberId, memberId > 0, let conversationId, conversationId > 0 else {
            return Self.unknownReceipt(requestId: id, projection: nil)
        }
        guard let original = journal(memberId, conversationId, id),
              let hash = original.requestHash, !hash.isEmpty,
              Self.parse(original.clientMessageId) == id,
              original.conversationId == conversationId,
              original.senderId == memberId else {
            return Self.unknownReceipt(requestId: id, projection: nil)
        }
        return OriginalReceipt(
            requestId: id,
            kind: nil,
            payloadHash: hash,
            outcome: Self.outcomeUnknown,
            originalBody: original.content,
            currentProjectionClaimsApplied: false,
            recoveryNote: nil,
            mintedNewRequest: false)
    }

    public mutating func commitUnsignedOriginal(capability: String) throws -> Never {
        throw NotifyFailure.waitingSource(capability: capability)
    }

    public mutating func rewriteUnsignedSource() throws -> Never {
        throw NotifyFailure.unsignedSourceRewrite
    }

    static func fingerprint(requestId: String, kind: NotifyKind, body: String?, outcome: String) -> String {
        sha256Hex(requestId + "\n" + kind.rawValue + "\n" + (body ?? "") + "\n" + outcome)
    }

    private static func unknownReceipt(requestId: String?, projection: AppliedProjection?) -> OriginalReceipt {
        OriginalReceipt(
            requestId: requestId, kind: nil, payloadHash: nil, outcome: outcomeUnknown,
            originalBody: nil,
            currentProjectionClaimsApplied: projection?.appliedState == projectionApplied,
            recoveryNote: unknownNotRecovered, mintedNewRequest: false)
    }
}
