import Foundation
import CoreFoundation

public enum NativeChannelNotificationError: Error, Equatable {
    case invalidInput, malformedResponse, accessClosed, persistenceFailed, pendingCommand
    case server(httpStatus: Int, code: Int?, errorCode: String?)
    case serverResponse(NativeChannelNotificationServerFailure)

    public var serverDetails: NativeChannelNotificationServerFailure? {
        switch self {
        case .server(let status, let code, let errorCode):
            return .init(httpStatus: status, code: code, errorCode: errorCode)
        case .serverResponse(let failure): return failure
        default: return nil
        }
    }
}

/// Recovery metadata is not authorization, a redirect, or evidence of success.
/// Only the exact original notification receipt path can be used for a read.
public struct NativeChannelNotificationRecovery: Codable, Equatable {
    public let conversationID: String?
    public let requestID: String?
    public let lookupPath: String?
    public let returnPath: String?
    public let useOriginalRequest: Bool?
    public let queryBeforeRetry: Bool?
    enum CodingKeys: String, CodingKey {
        case conversationID = "conversation_id", requestID = "request_id", lookupPath = "lookup_path"
        case returnPath, useOriginalRequest = "use_original_request", queryBeforeRetry = "query_before_retry"
    }
    public func validate(for command: NativeChannelNotificationCommand) throws {
        guard requestID.map({ $0 == command.requestID }) ?? true,
              conversationID.map({ command.scope.type == 1 && $0 == command.scope.value }) ?? true,
              lookupPath.map({ $0 == "/api/im/notification-requests/" + command.requestID }) ?? true,
              returnPath.map(Self.validReturnPath) ?? true,
              useOriginalRequest != false, queryBeforeRetry != false else {
            throw NativeChannelNotificationError.malformedResponse
        }
    }
    static func validReturnPath(_ text: String) -> Bool {
        text.hasPrefix("/") && !text.hasPrefix("//") && text.utf8.count <= 512
            && !text.contains("\\") && !text.contains("..")
            && !text.contains("?") && !text.contains("#") && !text.contains("%")
            && text.utf8.allSatisfy { $0 >= 0x21 && $0 < 0x7f }
    }
}

public struct NativeChannelNotificationServerFailure: Codable, Equatable {
    public let httpStatus: Int
    public let code: Int?
    public let errorCode: String?
    public let outcomeKnown: Bool?
    public let requestID: String?
    public let returnPath: String?
    public let recovery: NativeChannelNotificationRecovery?
    public init(httpStatus: Int, code: Int?, errorCode: String?, outcomeKnown: Bool? = nil,
                requestID: String? = nil, returnPath: String? = nil, recovery: NativeChannelNotificationRecovery? = nil) {
        self.httpStatus = httpStatus; self.code = code; self.errorCode = errorCode
        self.outcomeKnown = outcomeKnown; self.requestID = requestID; self.returnPath = returnPath; self.recovery = recovery
    }
    public func validate(for command: NativeChannelNotificationCommand) throws {
        guard requestID.map({ $0 == command.requestID }) ?? true,
              returnPath.map(NativeChannelNotificationRecovery.validReturnPath) ?? true else {
            throw NativeChannelNotificationError.malformedResponse
        }
        try recovery?.validate(for: command)
    }
}

/// IDs remain exact decimal strings; JSON floating point never participates.
public struct NativeChannelNotificationScope: Codable, Hashable, Identifiable {
    public let type: Int
    public let value: String
    public var id: String { "\(type):\(value)" }
    public init(type: Int, value: String) throws {
        guard [1, 2, 4].contains(type), Self.validID(value) else { throw NativeChannelNotificationError.invalidInput }
        self.type = type; self.value = value
    }
    /// Scope 4 is the original backend account-default row, not scope 0 or a channel.
    public var isAccountDefault: Bool { type == 4 }
    public func belongsToAccount(_ accountID: String) -> Bool {
        !isAccountDefault || value == accountID
    }
    public static func validID(_ value: String) -> Bool {
        value.first != "0" && !value.isEmpty && value.utf8.allSatisfy { (48...57).contains($0) }
            && Int64(value).map { $0 > 0 } == true
    }
    enum CodingKeys: String, CodingKey { case type = "scope_type", value = "scope_id" }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(type: c.decode(Int.self, forKey: .type), value: c.decode(String.self, forKey: .value))
    }
}

public enum NativeChannelNotificationLevel: Int, Codable, CaseIterable, Identifiable {
    case all = 0, mentions = 1, nothing = 2, inherit = 3
    public var id: Int { rawValue }
    public var label: String {
        switch self { case .all: return "所有消息"; case .mentions: return "仅提及我"
        case .nothing: return "关闭普通通知"; case .inherit: return "继承上级设置" }
    }
}

public struct NativeChannelNotificationQuietHours: Codable, Equatable {
    public let start: String
    public let end: String
    public let timeZone: String
    public init(start: String, end: String, timeZone: String) throws {
        func valid(_ value: String) -> Bool {
            let bytes = Array(value.utf8)
            guard bytes.count == 5, bytes[2] == 58,
                  [bytes[0], bytes[1], bytes[3], bytes[4]].allSatisfy({ (48...57).contains($0) }),
                  let h = Int(value.prefix(2)), let m = Int(value.suffix(2)) else { return false }
            return h < 24 && m < 60
        }
        guard valid(start), valid(end), start != end, TimeZone(identifier: timeZone) != nil else {
            throw NativeChannelNotificationError.invalidInput
        }
        self.start = start; self.end = end; self.timeZone = timeZone
    }
}

public struct NativeChannelNotificationEffective: Codable, Equatable {
    public let level: NativeChannelNotificationLevel
    public let muted: Bool
    public let permanentMuted: Bool?
    public let quiet: Bool
    public let suppressBroadcast: Bool
    public let suppressTeamStatus: Bool
    public let showPreview: Bool
    enum CodingKeys: String, CodingKey {
        case level, muted, quiet
        case permanentMuted = "permanent_muted", suppressBroadcast = "suppress_broadcast"
        case suppressTeamStatus = "suppress_team_status", showPreview = "show_preview"
    }
}

public struct NativeChannelNotificationPreference: Decodable, Equatable, Identifiable {
    public let scope: NativeChannelNotificationScope
    public var id: String { scope.id }
    public let level: NativeChannelNotificationLevel
    public let effective: NativeChannelNotificationEffective
    public let permanentMuted: Bool
    public let mutedUntil: String?
    public let quietHours: NativeChannelNotificationQuietHours?
    public let suppressBroadcast: Bool
    public let suppressTeamStatus: Bool
    /// Nil is inherited preview, not false.
    public let showPreview: Bool?
    public let version: Int64
    enum CodingKeys: String, CodingKey {
        case level, effective, version
        case permanentMuted = "permanent_muted", mutedUntil = "muted_until"
        case quietStart = "quiet_start", quietEnd = "quiet_end", quietTZ = "quiet_tz"
        case suppressBroadcast = "suppress_broadcast", suppressTeamStatus = "suppress_team_status"
        case showPreview = "show_preview", effectiveLevel = "effective_level"
    }
    public init(from decoder: Decoder) throws {
        scope = try .init(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        level = try c.decode(NativeChannelNotificationLevel.self, forKey: .level)
        effective = try c.decode(NativeChannelNotificationEffective.self, forKey: .effective)
        let effectiveLevel = try c.decode(NativeChannelNotificationLevel.self, forKey: .effectiveLevel)
        permanentMuted = try c.decode(Bool.self, forKey: .permanentMuted)
        mutedUntil = try c.decodeIfPresent(String.self, forKey: .mutedUntil)
        suppressBroadcast = try c.decode(Bool.self, forKey: .suppressBroadcast)
        suppressTeamStatus = try c.decode(Bool.self, forKey: .suppressTeamStatus)
        showPreview = try c.decodeIfPresent(Bool.self, forKey: .showPreview)
        version = try c.decode(Int64.self, forKey: .version)
        let from = try c.decodeIfPresent(String.self, forKey: .quietStart)
        let to = try c.decodeIfPresent(String.self, forKey: .quietEnd)
        let zone = try c.decodeIfPresent(String.self, forKey: .quietTZ)
        if let from, let to, let zone { quietHours = try .init(start: from, end: to, timeZone: zone) }
        else {
            guard from == nil, to == nil, zone == nil else { throw NativeChannelNotificationError.malformedResponse }
            quietHours = nil
        }
        guard !scope.isAccountDefault || (!permanentMuted && mutedUntil == nil
                && !suppressBroadcast && !suppressTeamStatus),
              version >= 0, effective.level != .inherit, effectiveLevel == effective.level,
              !(permanentMuted && mutedUntil != nil),
              mutedUntil.map({ NativeChannelNotificationCommand.instant($0) != nil }) ?? true else {
            throw NativeChannelNotificationError.malformedResponse
        }
    }
}

public struct NativeChannelNotificationDirectory: Decodable, Equatable {
    public struct Defaults: Decodable, Equatable {
        public let level: NativeChannelNotificationLevel
        public let effectiveLevel: NativeChannelNotificationLevel
        /// Old deployments expose only the two fallback levels. Preserve read compatibility,
        /// but never fabricate an account scope/version that would enable saving.
        public let preference: NativeChannelNotificationPreference?
        enum CodingKeys: String, CodingKey {
            case level, effectiveLevel = "effective_level", scopeType = "scope_type", scopeID = "scope_id"
            case version, effective
        }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            level = try c.decode(NativeChannelNotificationLevel.self, forKey: .level)
            effectiveLevel = try c.decode(NativeChannelNotificationLevel.self, forKey: .effectiveLevel)
            if c.contains(.scopeType) || c.contains(.scopeID) || c.contains(.version) || c.contains(.effective) {
                let row = try NativeChannelNotificationPreference(from: decoder)
                guard row.scope.isAccountDefault else { throw NativeChannelNotificationError.malformedResponse }
                preference = row
            } else { preference = nil }
        }
    }
    public let list: [NativeChannelNotificationPreference]
    public let defaults: Defaults
    public let serverTime: String
    enum CodingKeys: String, CodingKey { case list, defaults, serverTime = "server_time" }
    public func validate(accountID: String? = nil) throws {
        let accountRows = list.filter { $0.scope.isAccountDefault }
        if defaults.preference != nil || !accountRows.isEmpty {
            guard let accountID, NativeChannelNotificationScope.validID(accountID),
                  let originalDefault = defaults.preference,
                  originalDefault.scope.value == accountID,
                  accountRows.allSatisfy({ $0.scope.value == accountID }) else {
                throw NativeChannelNotificationError.malformedResponse
            }
        }
        guard Set(list.map(\.scope)).count == list.count, defaults.effectiveLevel != .inherit,
              NativeChannelNotificationCommand.instant(serverTime) != nil else {
            throw NativeChannelNotificationError.malformedResponse
        }
    }
}

/// Shared CLUB default is NOT this viewer's scope2 preference. Missing rows use the formal MENTIONS default/version0.
public struct NativeClubNotificationDefault: Decodable, Equatable {
    public let clubID: String
    public let level: NativeChannelNotificationLevel
    public let version: Int64
    public let configured: Bool
    public let updatedAt: String?
    enum CodingKeys: String, CodingKey { case clubID = "club_id", level, version, configured, updatedAt = "updated_at" }
    public func validate(club: String) throws {
        guard clubID == club, NativeChannelNotificationScope.validID(clubID), [.all, .mentions].contains(level),
              (configured ? (version > 0 && updatedAt.flatMap(NativeChannelNotificationCommand.instant) != nil)
                : (version == 0 && level == .mentions && updatedAt == nil)) else { throw NativeChannelNotificationError.malformedResponse }
    }
}

public struct NativeChannelNotificationDraft: Equatable {
    public var level: NativeChannelNotificationLevel
    public var mutedUntil: String?
    public var quietHours: NativeChannelNotificationQuietHours?
    public var suppressBroadcast: Bool
    public var suppressTeamStatus: Bool
    public var showPreview: Bool?
    public init(_ preference: NativeChannelNotificationPreference) {
        level = preference.level; mutedUntil = preference.mutedUntil; quietHours = preference.quietHours
        suppressBroadcast = preference.suppressBroadcast; suppressTeamStatus = preference.suppressTeamStatus
        showPreview = preference.showPreview
    }
}

/// This exact immutable body is persisted before dispatch. It is never reconstructed
/// from current controls or a new relative mute deadline after an unknown result.
public struct NativeChannelNotificationCommand: Codable, Equatable {
    public enum Operation: String, Codable { case preference = "PREFERENCE", mute = "MUTE", ack = "ACK", clubDefault = "CLUB_DEFAULT" }
    public let requestID: String
    public let scope: NativeChannelNotificationScope
    public let operation: Operation
    public let body: Data
    public static func validKey(_ key: String) -> Bool {
        (16...96).contains(key.utf8.count) && key.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95
        }
    }
    public static func instant(_ text: String) -> Date? {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
    public init(preference: NativeChannelNotificationPreference, draft: NativeChannelNotificationDraft,
                requestID: String = UUID().uuidString, now: Date = Date()) throws {
        guard Self.validKey(requestID), !(preference.permanentMuted && draft.mutedUntil != nil),
              draft.mutedUntil.map({ Self.instant($0).map { $0 <= now.addingTimeInterval(30 * 86400) } == true }) ?? true else {
            throw NativeChannelNotificationError.invalidInput
        }
        guard !preference.scope.isAccountDefault || (draft.mutedUntil == nil
                && !draft.suppressBroadcast && !draft.suppressTeamStatus) else {
            throw NativeChannelNotificationError.invalidInput
        }
        if let quiet = draft.quietHours { _ = try NativeChannelNotificationQuietHours(start: quiet.start, end: quiet.end, timeZone: quiet.timeZone) }
        self.requestID = requestID; scope = preference.scope; operation = .preference
        let fields: [String: Any] = [
            "request_id": requestID, "scope_type": scope.type, "scope_id": scope.value,
            "level": draft.level.rawValue, "version": preference.version,
            "muted_until": draft.mutedUntil as Any? ?? NSNull(), "quiet_start": draft.quietHours?.start as Any? ?? NSNull(),
            "quiet_end": draft.quietHours?.end as Any? ?? NSNull(), "quiet_tz": draft.quietHours?.timeZone as Any? ?? NSNull(),
            "suppress_broadcast": draft.suppressBroadcast, "suppress_team_status": draft.suppressTeamStatus,
            "show_preview": draft.showPreview as Any? ?? NSNull()
        ]
        body = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
    }
    public init(clubDefault: NativeClubNotificationDefault, level: NativeChannelNotificationLevel,
                requestID: String = UUID().uuidString) throws {
        try clubDefault.validate(club: clubDefault.clubID)
        guard Self.validKey(requestID), [.all, .mentions].contains(level) else { throw NativeChannelNotificationError.invalidInput }
        self.requestID = requestID; scope = try .init(type: 2, value: clubDefault.clubID); operation = .clubDefault
        body = try JSONSerialization.data(withJSONObject: ["request_id": requestID, "clubId": clubDefault.clubID,
            "level": level.rawValue, "version": clubDefault.version], options: [.sortedKeys])
    }
    public init(scope: NativeChannelNotificationScope, minutes: Int, requestID: String = UUID().uuidString) throws {
        guard scope.type == 1, (-1...43200).contains(minutes), Self.validKey(requestID) else {
            throw NativeChannelNotificationError.invalidInput
        }
        self.requestID = requestID; self.scope = scope; operation = .mute
        body = try JSONSerialization.data(withJSONObject: ["conversation_id": scope.value, "request_id": requestID, "minutes": minutes], options: [.sortedKeys])
    }
    /// Original POST api/im/read. conversation_id is the channel. Scope is not an HTTP field.
    public init(ackChannelID: Int64, lastMessageID: Int64, requestID: String = UUID().uuidString) throws {
        guard ackChannelID > 0, lastMessageID >= 0, Self.validKey(requestID) else {
            throw NativeChannelNotificationError.invalidInput
        }
        self.requestID = requestID
        scope = try NativeChannelNotificationScope(type: 1, value: String(ackChannelID))
        operation = .ack
        body = try JSONSerialization.data(withJSONObject: ["conversation_id": String(ackChannelID), "last_message_id": String(lastMessageID), "request_id": requestID], options: [.sortedKeys])
    }
    public func validate() throws {
        guard Self.validKey(requestID), body.count <= 8192,
              let fields = try JSONSerialization.jsonObject(with: body) as? [String: Any],
              fields["request_id"] as? String == requestID else { throw NativeChannelNotificationError.invalidInput }
        _ = try NativeChannelNotificationScope(type: scope.type, value: scope.value)
        if operation == .clubDefault {
            guard scope.type == 2, fields["clubId"] as? String == scope.value,
                  Set(fields.keys) == ["request_id", "clubId", "level", "version"],
                  let level = fields["level"] as? NSNumber, CFGetTypeID(level) != CFBooleanGetTypeID(),
                  level.doubleValue == Double(level.intValue), (0...1).contains(level.intValue),
                  let version = fields["version"] as? NSNumber, CFGetTypeID(version) != CFBooleanGetTypeID(),
                  version.int64Value >= 0, version.stringValue == String(version.int64Value) else { throw NativeChannelNotificationError.invalidInput }
        } else if operation == .mute {
            guard scope.type == 1, fields["conversation_id"] as? String == scope.value,
                  Set(fields.keys) == ["conversation_id", "request_id", "minutes"],
                  let n = fields["minutes"] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
                  n.doubleValue == Double(n.intValue), (-1...43200).contains(n.intValue) else { throw NativeChannelNotificationError.invalidInput }
        } else if operation == .ack {
            guard scope.type == 1, fields["conversation_id"] as? String == scope.value,
                  Set(fields.keys) == ["conversation_id", "last_message_id", "request_id"],
                  let last = fields["last_message_id"] as? String, let value = Int64(last), value >= 0, String(value) == last else {
                throw NativeChannelNotificationError.invalidInput
            }
        } else {
            // Decode the complete persisted shape, including nulls; unknown fields
            // and attempts to write the read-only permanent flag are rejected.
            guard Set(fields.keys) == ["request_id", "scope_type", "scope_id", "level", "version", "muted_until", "quiet_start", "quiet_end", "quiet_tz", "suppress_broadcast", "suppress_team_status", "show_preview"],
                  fields["scope_id"] as? String == scope.value,
                  let type = fields["scope_type"] as? NSNumber, CFGetTypeID(type) != CFBooleanGetTypeID(), type.doubleValue == Double(type.intValue), type.intValue == scope.type,
                  let level = fields["level"] as? NSNumber, CFGetTypeID(level) != CFBooleanGetTypeID(), level.doubleValue == Double(level.intValue), (0...3).contains(level.intValue),
                  let version = fields["version"] as? NSNumber, CFGetTypeID(version) != CFBooleanGetTypeID(), version.int64Value >= 0,
                  version.stringValue == String(version.int64Value),
                  ["suppress_broadcast", "suppress_team_status"].allSatisfy({ (fields[$0] as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() } == true }),
                  fields["show_preview"] is NSNull || (fields["show_preview"] as? NSNumber).map({ CFGetTypeID($0) == CFBooleanGetTypeID() }) == true else {
                throw NativeChannelNotificationError.invalidInput
            }
            if scope.isAccountDefault {
                guard fields["muted_until"] is NSNull,
                      (fields["suppress_broadcast"] as? NSNumber)?.boolValue == false,
                      (fields["suppress_team_status"] as? NSNumber)?.boolValue == false else {
                    throw NativeChannelNotificationError.invalidInput
                }
            }
            if !(fields["muted_until"] is NSNull) { guard let text = fields["muted_until"] as? String, Self.instant(text) != nil else { throw NativeChannelNotificationError.invalidInput } }
            if !(fields["quiet_start"] is NSNull && fields["quiet_end"] is NSNull && fields["quiet_tz"] is NSNull) {
                guard let start = fields["quiet_start"] as? String, let end = fields["quiet_end"] as? String, let zone = fields["quiet_tz"] as? String else { throw NativeChannelNotificationError.invalidInput }
                _ = try NativeChannelNotificationQuietHours(start: start, end: end, timeZone: zone)
            }
        }
    }
}

public struct NativeChannelNotificationReceipt: Decodable, Equatable {
    public let requestID: String
    public let status: String
    public let operation: NativeChannelNotificationCommand.Operation?
    public let scopeType: Int?
    public let scopeID: String?
    public let resultRedacted: Bool?
    public let mustRefreshState: Bool?
    public let resumeWithSameRequest: Bool?
    public let outcome: String?
    public let result: HistoricalResult?
    /// Missing fields in an old immutable result remain unknown.
    public struct HistoricalResult: Decodable, Equatable {
        public let version: Int64?
        public let rejectionCode: String?
        public let permanentMuted: Bool?
        public let mutedUntil: String?
        enum CodingKeys: String, CodingKey { case version, rejectionCode = "rejection_code", permanentMuted = "permanent_muted", mutedUntil = "muted_until" }
    }
    enum CodingKeys: String, CodingKey {
        case status, operation, outcome, result
        case requestID = "request_id", scopeType = "scope_type", scopeID = "scope_id"
        case resultRedacted = "result_redacted", mustRefreshState = "must_refresh_state"
        case resumeWithSameRequest = "resume_with_same_request"
    }
    public func validate(for command: NativeChannelNotificationCommand) throws {
        guard requestID == command.requestID, (["APPLIED", "PENDING", "NOT_FOUND"].contains(status) || (command.operation == .clubDefault && status == "REJECTED")) else { throw NativeChannelNotificationError.malformedResponse }
        if status == "NOT_FOUND" {
            guard outcome == "UNKNOWN", result == nil, operation == nil, scopeID == nil, scopeType == nil else { throw NativeChannelNotificationError.malformedResponse }
        } else {
            guard operation == command.operation, scopeType == command.scope.type, scopeID == command.scope.value,
                  resultRedacted != nil, mustRefreshState != nil else { throw NativeChannelNotificationError.malformedResponse }
            if status == "REJECTED" {
                guard command.operation == .clubDefault, outcome == "REJECTED",
                      (resultRedacted == true ? result == nil : (result.map { ["CLUB_DEFAULT_VERSION_CONFLICT", "CLUB_DEFAULT_VERSION_EXHAUSTED"].contains($0.rejectionCode ?? "") } == true)) else {
                    throw NativeChannelNotificationError.malformedResponse
                }
            } else {
                guard status == "APPLIED" ? (resultRedacted == true ? result == nil : result != nil) : (outcome == "UNKNOWN" && result == nil) else { throw NativeChannelNotificationError.malformedResponse }
            }
            // APPLIED is the original success contract. resume_with_same_request is not on
            // the real applied wire and does not authorize success. Retry reads that flag
            // only when the receipt is still unknown.
        }
    }
}
