import Foundation

/// Node IDs belong to play nodes. Merchant-row IDs are deliberately a different type.
public struct ShopNPCNodeID: Equatable, Hashable {
    public let rawValue: Int
    public init?(_ value: Int) { guard value > 0 else { return nil }; rawValue = value }
}
public struct ShopNPCScope: Equatable {
    public let sessionID: String
    public let accountID: String
    public let roleID: String
    public let accessRevision: UInt64
    public let nodeID: ShopNPCNodeID
    public init(sessionID: String, accountID: String, roleID: String, accessRevision: UInt64, nodeID: ShopNPCNodeID) {
        self.sessionID = sessionID; self.accountID = accountID; self.roleID = roleID
        self.accessRevision = accessRevision; self.nodeID = nodeID
    }
    public var valid: Bool { !sessionID.isEmpty && !accountID.isEmpty && !roleID.isEmpty }
}
public struct ShopNPCGrants: Equatable {
    public var server = false
    public var provider = false
    public var legal = false
    public var access = false
    public var voiceTransmission = false
    public var voiceFormatVerified = false
    public var microphone = false
    public var playback = false
    public init() {}
    public var textAllowed: Bool { server && provider && legal && access }
    public var voiceAllowed: Bool { textAllowed && voiceTransmission && voiceFormatVerified }
}
public enum ShopNPCFailure: Error, Equatable {
    case disabled, stale, busy, invalid, rateLimited, unknownOutcome, malformed
    case replyProcessing, replyRetryable, replyRejected, replyFailed
    case server(code: Int, message: String?)
    public var key: String {
        switch self {
        case .disabled: return "shopNPC.disabled"
        case .stale: return "shopNPC.stale"
        case .busy: return "shopNPC.busy"
        case .invalid: return "shopNPC.invalid"
        case .rateLimited: return "shopNPC.rateLimited"
        case .unknownOutcome: return "shopNPC.unknownOutcome"
        case .malformed: return "shopNPC.malformed"
        case .replyProcessing: return "shopNPCOutcome.processing"
        case .replyRetryable: return "shopNPCOutcome.retryable"
        case .replyRejected: return "shopNPCOutcome.rejected"
        case .replyFailed: return "shopNPCOutcome.failed"
        case .server: return "shopNPC.server"
        }
    }
}
public struct ShopNPCReply: Equatable {
    public enum Outcome: String, Equatable { case succeeded = "SUCCEEDED", rejected = "REJECTED", failed = "FAILED", processing = "PROCESSING" }
    public let requestID: UUID
    public let outcome: Outcome
    public let retryable: Bool
    public let retryAfterSeconds: Int?
    public let text: String
    public let asr: String?
    public var needsRetry: Bool { outcome == .processing || retryable }
    /// This path does not consume audio. An optional server audioUrl does not
    /// establish an approved native playback capability; the legacy case name is retained.
    public let audio: ShopNPCAudioSource = .unavailableInSource
    public static func decode(_ bytes: Data, voice: Bool) throws -> Self {
        struct Envelope: Decodable {
            var code: Int?; var msg: String?; var asr: String?; var data: Payload?
            struct Payload: Decodable {
                var requestId: String?; var outcomeStatus: String?; var safetyDecision: String?
                var retryable: Bool?; var retryAfterSeconds: Int?; var safeText: String?
            }
        }
        let body: Envelope
        do { body = try JSONDecoder().decode(Envelope.self, from: bytes) }
        catch { throw ShopNPCFailure.malformed }
        guard let code = body.code else { throw ShopNPCFailure.malformed }
        guard code == 200 else { throw ShopNPCFailure.server(code: code, message: body.msg) }
        guard let data = body.data, let request = data.requestId, let id = UUID(uuidString: request),
              let status = data.outcomeStatus, let outcome = Outcome(rawValue: status),
              let retryable = data.retryable, let safety = data.safetyDecision,
              ["PASS", "BLOCKED", "NOT_RUN"].contains(safety) else { throw ShopNPCFailure.malformed }
        // 9b emits either the one-second in-progress delay or secondsUntilTomorrow,
        // which is bounded to one day. This is not an inferred reset timestamp.
        if let seconds = data.retryAfterSeconds, !(0...86_400).contains(seconds) { throw ShopNPCFailure.malformed }
        let safe = data.safeText ?? ""
        guard safe.utf8.count <= 32_768, (body.asr?.utf8.count ?? 0) <= 32_768 else { throw ShopNPCFailure.malformed }
        if outcome == .succeeded, !retryable {
            guard safety == "PASS", !safe.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ShopNPCFailure.malformed }
        }
        // No legacy data.text fallback: missing terminal evidence is not success.
        return Self(requestID: id, outcome: outcome, retryable: retryable, retryAfterSeconds: data.retryAfterSeconds,
                    text: safe, asr: voice ? body.asr : nil)
    }
}
public enum ShopNPCAudioSource: Equatable { case unavailableInSource }
public struct ShopNPCVoiceClip: Equatable {
    public let bytes: Data
    public let duration: TimeInterval
    public init(bytes: Data, duration: TimeInterval) throws {
        guard !bytes.isEmpty, bytes.count <= 2 * 1024 * 1024, duration >= 0.5, duration <= 60 else { throw ShopNPCFailure.invalid }
        self.bytes = bytes; self.duration = duration
    }
}
public struct ShopNPCMessage: Identifiable, Equatable {
    public enum Source: Equatable { case text, voice }
    public let id: UUID
    public let mine: Bool
    public var text: String
    public let source: Source
    public var hasReusableQuestion: Bool { mine && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    public var voiceTranscriptMissing: Bool { mine && source == .voice && !hasReusableQuestion }
    public init(id: UUID = UUID(), mine: Bool, text: String, source: Source = .text) {
        self.id = id; self.mine = mine; self.text = text; self.source = mine ? source : .text
    }
}
