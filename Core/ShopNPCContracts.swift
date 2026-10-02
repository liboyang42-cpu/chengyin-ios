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
        case .server: return "shopNPC.server"
        }
    }
}
public struct ShopNPCReply: Equatable {
    public let text: String
    public let asr: String?
    /// Source response has no audio URL or bytes. Do not synthesize a media contract.
    public let audio: ShopNPCAudioSource = .unavailableInSource
    public static func decode(_ bytes: Data, voice: Bool) throws -> Self {
        struct Envelope: Decodable {
            var code: Int?; var msg: String?; var asr: String?; var data: Payload?
            struct Payload: Decodable { var safeText: String?; var text: String? }
        }
        let body: Envelope
        do { body = try JSONDecoder().decode(Envelope.self, from: bytes) }
        catch { throw ShopNPCFailure.malformed }
        guard let code = body.code else { throw ShopNPCFailure.malformed }
        guard code == 200 else { throw ShopNPCFailure.server(code: code, message: body.msg) }
        let safe = body.data?.safeText ?? ""
        return Self(text: safe.isEmpty ? body.data?.text ?? "" : safe, asr: voice ? body.asr : nil)
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
    public let id: UUID
    public let mine: Bool
    public var text: String
    public init(id: UUID = UUID(), mine: Bool, text: String) { self.id = id; self.mine = mine; self.text = text }
}
