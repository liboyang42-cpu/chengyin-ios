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

    public struct SentMessage: Equatable, Sendable {
        public var clientMessageId: String?
        public var requestHash: String?
        public var content: String?
        public init(clientMessageId: String?, requestHash: String?, content: String?) {
            self.clientMessageId = ImmutableReceiptProducer.parse(clientMessageId)
            self.requestHash = ImmutableReceiptProducer.parse(requestHash, limit: 128)
            self.content = ImmutableReceiptProducer.parse(content, limit: 4096)
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

    /// Delegate to the existing send. Routing fields come from the caller.
    /// A missing field returns nil and does not send. Does not occupy the in-memory store.
    public func sendOriginal(
        _ request: OriginalRequest,
        memberID: Int64?,
        conversationID: Int64?,
        targetMemberID: Int64?,
        msgType: Int?,
        send: ((Int64, Int64, Int64, Int, String, String) -> SentMessage?)?
    ) throws -> OriginalReceipt? {
        _ = try Self.requireRequestID(request.requestId)
        guard let memberID, memberID > 0, let conversationID, conversationID > 0,
              let targetMemberID, targetMemberID > 0, let msgType else { return nil }
        guard let send else {
            throw NotifyFailure.waitingSource(capability: Self.imSend)
        }
        guard let sent = send(memberID, conversationID, targetMemberID, msgType, request.body ?? "", request.requestId) else {
            return Self.unknownReceipt(requestId: request.requestId, projection: nil)
        }
        return OriginalReceipt(
            requestId: Self.parse(sent.clientMessageId) ?? request.requestId,
            kind: nil,
            payloadHash: sent.requestHash,
            outcome: Self.outcomeUnknown,
            originalBody: sent.content,
            currentProjectionClaimsApplied: false,
            recoveryNote: nil,
            mintedNewRequest: false)
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
        guard let original = journal(memberId ?? 0, conversationId ?? 0, id) else {
            return Self.unknownReceipt(requestId: id, projection: nil)
        }
        return OriginalReceipt(
            requestId: Self.parse(original.clientMessageId) ?? id,
            kind: nil,
            payloadHash: original.requestHash,
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
