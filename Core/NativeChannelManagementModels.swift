import Foundation

/// im_channel identity from ChannelPlatformService/ChannelDirectoryService only.
/// A legacy MessagingConversation, biz_key or client-generated id never constructs a channel.
public struct NativeChannelManagementID: Codable, Hashable, Identifiable, CustomStringConvertible {
    public let rawValue: String
    public var id: String { rawValue }
    public var description: String { rawValue }
    public init(_ rawValue: String) throws {
        guard let value = Int64(rawValue), value > 0, String(value) == rawValue else {
            throw NativeChannelManagementError.invalidSource
        }
        self.rawValue = rawValue
    }
    public init(from decoder: Decoder) throws { try self.init(decoder.singleValueContainer().decode(String.self)) }
    public func encode(to encoder: Encoder) throws { var box = encoder.singleValueContainer(); try box.encode(rawValue) }
}

/// Channel metadata version and permission epoch are different server fields.
/// Current metadata uses decimal strings; permission readers also return JSON integers.
public struct NativeChannelManagementVersion: Codable, Hashable {
    public let value: Int64
    public init(_ value: Int64) throws {
        guard value >= 0 else { throw NativeChannelManagementError.invalidSource }; self.value = value
    }
    public init(from decoder: Decoder) throws {
        let box = try decoder.singleValueContainer()
        if let raw = try? box.decode(String.self), let number = Int64(raw), String(number) == raw {
            try self.init(number)
        } else { try self.init(box.decode(Int64.self)) }
    }
    public func encode(to encoder: Encoder) throws { var box = encoder.singleValueContainer(); try box.encode(String(value)) }
}

public struct NativeChannelManagementScope: Codable, Hashable {
    public let guildKind: Int
    public let guildID: NativeChannelManagementID
    public init(guildKind: Int, guildID: NativeChannelManagementID) throws {
        guard (1...3).contains(guildKind) else { throw NativeChannelManagementError.invalidSource }
        self.guildKind = guildKind; self.guildID = guildID
    }
}

/// Actual ChannelCapability registry at 2946/251834; design 24's older bitmap is not used.
public enum NativeChannelManagementCapability: String, CaseIterable, Codable, Identifiable {
    case view = "VIEW_CHANNEL", send = "SEND_MESSAGE", attach = "ATTACH_FILE", embed = "EMBED_LINK"
    case react = "ADD_REACTION", history = "READ_HISTORY", mention = "MENTION_EVERYONE", poll = "CREATE_POLL"
    case pin = "PIN_MESSAGE", moderateMessage = "MANAGE_MESSAGE", manageChannel = "MANAGE_CHANNEL"
    case manageRole = "MANAGE_ROLE", kick = "KICK_MEMBER", ban = "BAN_MEMBER", timeout = "TIMEOUT_MEMBER"
    case bot = "MANAGE_BOT", rule = "MANAGE_RULE", audit = "VIEW_AUDIT", administrator = "ADMINISTRATOR"
    case voiceConnect = "VOICE_CONNECT", voiceSpeak = "VOICE_SPEAK", voiceModerate = "VOICE_MODERATE"
    case stageRequest = "STAGE_REQUEST", bypassSlowmode = "BYPASS_SLOWMODE", sendAsBot = "SEND_AS_BOT"
    case webhook = "MANAGE_WEBHOOKS"
    case progress = "MANAGE_PROGRESS" // Root-reserved 27; 26 belongs to MANAGE_BOUNTY.
    public var id: String { rawValue }
    public var bit: UInt64 {
        // Explicit mapping; never infer backend bits from Swift enum order.
        switch self {
        case .view: return 1 << 0; case .send: return 1 << 1; case .attach: return 1 << 2
        case .embed: return 1 << 3; case .react: return 1 << 4; case .history: return 1 << 5
        case .mention: return 1 << 6; case .poll: return 1 << 7; case .pin: return 1 << 8
        case .moderateMessage: return 1 << 9; case .manageChannel: return 1 << 10
        case .manageRole: return 1 << 11; case .kick: return 1 << 12; case .ban: return 1 << 13
        case .timeout: return 1 << 14; case .bot: return 1 << 15; case .rule: return 1 << 16
        case .audit: return 1 << 17; case .administrator: return 1 << 18; case .voiceConnect: return 1 << 19
        case .voiceSpeak: return 1 << 20; case .voiceModerate: return 1 << 21; case .stageRequest: return 1 << 22
        case .bypassSlowmode: return 1 << 23; case .sendAsBot: return 1 << 24; case .webhook: return 1 << 25
        case .progress: return 1 << 27
        }
    }
    public var guildScoped: Bool {
        [.manageChannel, .manageRole, .kick, .ban, .bot, .audit, .administrator, .webhook, .progress].contains(self)
    }
    public var available: Bool { ![.voiceConnect, .voiceSpeak, .voiceModerate, .stageRequest, .sendAsBot].contains(self) }
}

public struct NativeChannelManagementChannel: Decodable, Equatable, Identifiable {
    public let id: NativeChannelManagementID
    public let scope: NativeChannelManagementScope
    public let parentID: String
    public let kind: Int
    public let name: String
    public let topic: String?
    public let position: Int
    public let isDefault: Bool
    public let status: Int
    public let version: NativeChannelManagementVersion
    public let permissionVersion: NativeChannelManagementVersion?
    public let visibility: Int
    public let slowmodeSeconds: Int
    public let archiveReason: String?
    public let purgeAt: String?
    public let recoverable: Bool
    public let permissionNames: Set<String>
    public let memberCount: Int?
    public let memberCountCapped: Bool
    public var canManage: Bool { permissionNames.contains(NativeChannelManagementCapability.manageChannel.rawValue) }
    public var canManagePermissions: Bool { permissionNames.contains(NativeChannelManagementCapability.manageRole.rawValue) }
    public var canDelete: Bool { canManage && !isDefault && kind != 2 && (0...1).contains(status) }
    private enum CodingKeys: String, CodingKey {
        case id, kind, name, topic, position, status, version, visibility, recoverable
        case guildKind = "guild_kind", guildID = "guild_id", parentID = "parent_id", isDefault = "is_default"
        case permissionVersion = "perm_version", slowmode = "slowmode_sec", archiveReason = "archive_reason"
        case purgeAt = "purge_at", names = "my_permissions_list", count = "member_count", capped = "member_count_capped"
    }
    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = try box.decode(NativeChannelManagementID.self, forKey: .id)
        scope = try .init(guildKind: box.decode(Int.self, forKey: .guildKind), guildID: box.decode(NativeChannelManagementID.self, forKey: .guildID))
        parentID = try box.decode(String.self, forKey: .parentID)
        guard parentID == "0" || (try? NativeChannelManagementID(parentID)) != nil else { throw NativeChannelManagementError.invalidSource }
        kind = try box.decode(Int.self, forKey: .kind); name = try box.decode(String.self, forKey: .name)
        topic = try box.decodeIfPresent(String.self, forKey: .topic); position = try box.decode(Int.self, forKey: .position)
        let defaultBit = try box.decode(Int.self, forKey: .isDefault)
        status = try box.decode(Int.self, forKey: .status); version = try box.decode(NativeChannelManagementVersion.self, forKey: .version)
        permissionVersion = try box.decodeIfPresent(NativeChannelManagementVersion.self, forKey: .permissionVersion)
        // Management inventory has metadata result fields but intentionally omits topic/visibility/permissions.
        visibility = try box.decodeIfPresent(Int.self, forKey: .visibility) ?? 0
        slowmodeSeconds = try box.decodeIfPresent(Int.self, forKey: .slowmode) ?? -1
        archiveReason = try box.decodeIfPresent(String.self, forKey: .archiveReason)
        purgeAt = try box.decodeIfPresent(String.self, forKey: .purgeAt)
        recoverable = try box.decodeIfPresent(Bool.self, forKey: .recoverable) ?? false
        let names = try box.decodeIfPresent([String].self, forKey: .names) ?? []
        permissionNames = Set(names)
        memberCount = try box.decodeIfPresent(Int.self, forKey: .count)
        let capped = try box.decodeIfPresent(Int.self, forKey: .capped) ?? 0
        guard (0...8).contains(kind), (0...4).contains(status), [0,1].contains(defaultBit),
              (0...2).contains(visibility), (-1...21600).contains(slowmodeSeconds),
              !name.isEmpty, name.unicodeScalars.count <= 64, names.count == permissionNames.count,
              names.count <= 64, names.allSatisfy({ $0.range(of: "^[A-Z][A-Z0-9_]{0,63}$", options: .regularExpression) != nil }),
              memberCount.map({ (0...50).contains($0) }) ?? true, [0,1].contains(capped) else {
            throw NativeChannelManagementError.invalidSource
        }
        isDefault = defaultBit == 1; memberCountCapped = capped == 1
    }
    public func requireDirectoryRow(in scope: NativeChannelManagementScope) throws {
        guard self.scope == scope, permissionNames.contains("VIEW_CHANNEL"), (1...2).contains(visibility),
              slowmodeSeconds >= 0, status < 2 else { throw NativeChannelManagementError.invalidSource }
    }
    public func requireDetail(in scope: NativeChannelManagementScope) throws {
        try requireDirectoryRow(in: scope)
        guard permissionVersion != nil else { throw NativeChannelManagementError.invalidSource }
    }
}

public struct NativeChannelManagementDirectory: Decodable, Equatable {
    public struct Category: Decodable, Equatable, Identifiable {
        public let id: NativeChannelManagementID
        public let name: String
        public let kind: Int
    }
    public struct Group: Decodable, Equatable, Identifiable {
        public let category: Category
        public let channels: [NativeChannelManagementChannel]
        public var id: NativeChannelManagementID { category.id }
    }
    public let scope: NativeChannelManagementScope
    public let groups: [Group]
    public let ungrouped: [NativeChannelManagementChannel]
    public var channels: [NativeChannelManagementChannel] { groups.flatMap(\.channels) + ungrouped }
    private enum CodingKeys: String, CodingKey { case groups, ungrouped, kind = "guild_kind", guild = "guild_id" }
    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        scope = try .init(guildKind: box.decode(Int.self, forKey: .kind), guildID: box.decode(NativeChannelManagementID.self, forKey: .guild))
        groups = try box.decode([Group].self, forKey: .groups); ungrouped = try box.decode([NativeChannelManagementChannel].self, forKey: .ungrouped)
        let rows = groups.flatMap(\.channels) + ungrouped
        guard rows.count <= 2000, groups.count <= 500, Set(rows.map(\.id)).count == rows.count,
              Set(groups.map(\.id)).count == groups.count, rows.allSatisfy({ $0.scope == scope && $0.kind != 0 }),
              groups.allSatisfy({ $0.category.kind == 0 && !$0.category.name.isEmpty }) else { throw NativeChannelManagementError.invalidSource }
    }
}

public struct NativeChannelManagementOverwrite: Codable, Equatable, Identifiable {
    public let targetType: Int
    public let targetID: String
    public let allowBits: String
    public let denyBits: String
    public let note: String?
    public var id: String { "\(targetType):\(targetID)" }
    enum CodingKeys: String, CodingKey { case targetType = "target_type", targetID = "target_id", allowBits = "allow_bits", denyBits = "deny_bits", note }
    public init(targetType: Int, targetID: String, allowBits: String, denyBits: String, note: String?) throws {
        guard (targetType == 1 && targetID == "0") || (targetType == 2 && (try? NativeChannelManagementID(targetID)) != nil),
              (note?.utf16.count ?? 0) <= 120 else { throw NativeChannelManagementError.invalidDraft }
        self.targetType = targetType; self.targetID = targetID; self.allowBits = allowBits; self.denyBits = denyBits; self.note = note
        _ = try masks()
    }
    public func masks() throws -> (allow: UInt64, deny: UInt64) {
        func parse(_ text: String) throws -> UInt64 {
            guard text.hasPrefix("0x"), let value = UInt64(text.dropFirst(2), radix: 16), value <= 0x3ffffff else {
                throw NativeChannelManagementError.invalidDraft
            }; return value
        }
        let allow = try parse(allowBits), deny = try parse(denyBits)
        let guild = NativeChannelManagementCapability.allCases.filter(\.guildScoped).reduce(UInt64(0)) { $0 | $1.bit }
        guard allow & deny == 0, allow & guild == 0 else { throw NativeChannelManagementError.invalidDraft }
        return (allow, deny)
    }
}

public struct NativeChannelManagementPermissions: Decodable, Equatable {
    public let channelID: NativeChannelManagementID
    public let version: NativeChannelManagementVersion
    public let permissionVersion: NativeChannelManagementVersion
    public let overrides: [NativeChannelManagementOverwrite]
    enum CodingKeys: String, CodingKey { case channelID = "channel_id", version, permissionVersion = "perm_version", overrides }
}

public struct NativeChannelManagementRole: Decodable, Equatable, Identifiable {
    public let id: NativeChannelManagementID
    public let guildKind: Int
    public let guildID: NativeChannelManagementID
    public let name: String
    public let status: Int
    enum CodingKeys: String, CodingKey { case id, name, status, guildKind = "guild_kind", guildID = "guild_id" }
}

public struct NativeChannelManagementEffectivePermissions: Decodable, Equatable {
    public let channelID: NativeChannelManagementID
    public let memberID: NativeChannelManagementID
    public let permissions: String
    public let names: [String]
    public let version: NativeChannelManagementVersion
    enum CodingKeys: String, CodingKey { case channelID = "channel_id", memberID = "member_id", permissions, names = "permissions_list", version }
}

public enum NativeChannelManagementError: Error, Equatable {
    case unavailable, changedIdentity, invalidSource, invalidDraft, versionConflict, forbidden
    case pendingOriginal, storageUnavailable, outcomeUnknown, rejected(String), permissionCASUnavailable
}
