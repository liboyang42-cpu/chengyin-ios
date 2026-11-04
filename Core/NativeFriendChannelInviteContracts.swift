import Foundation
import CryptoKit

public enum NativeFriendChannelInviteMode: Equatable, Sendable {
    case mine, channel(Int64), invite(Int64, joinedNotice: Bool)
    public var valid: Bool { switch self { case .mine: return true; case .channel(let id), .invite(let id, _): return id > 0 } }
}
public struct NativeFriendChannelInvitePeer: Codable, Equatable, Sendable { public let id: Int64; public let version: Int64 }
public struct NativeFriendChannelInviteAcceptance: Codable, Equatable, Sendable {
    public let key, hash: String
    enum CodingKeys: String, CodingKey { case key = "rule_key", hash = "rule_hash" }
}
public struct NativeFriendChannelInviteCommand: Codable, Equatable, Sendable {
    public let action: String
    public let objectID: Int64
    public let requestID: String
    public let peers: [NativeFriendChannelInvitePeer]
    public let message: String
    public let accepted: [NativeFriendChannelInviteAcceptance]
    enum CodingKeys: String, CodingKey { case action, objectID = "object_id", requestID = "request_id", peers, message, accepted }
    public init(action: String, objectID: Int64, peers: [NativeFriendChannelInvitePeer] = [], message: String = "", accepted: [NativeFriendChannelInviteAcceptance] = [], requestID: String = UUID().uuidString) throws {
        self.action = action; self.objectID = objectID; self.requestID = requestID; self.message = message
        self.peers = peers.sorted { $0.id < $1.id }; self.accepted = accepted.sorted { $0.key < $1.key }; try validate()
    }
    public func validate() throws {
        guard ["CREATE", "SUBMIT", "PARENT_SUBMIT", "ACCEPT_CHANNEL", "ACCEPT_RULES", "REVOKE"].contains(action), objectID > 0, UUID(uuidString: requestID) != nil,
              peers.count <= 10, peers == peers.sorted(by: { $0.id < $1.id }), Set(peers.map(\.id)).count == peers.count,
              peers.allSatisfy({ $0.id > 0 && $0.version > 0 }), message.unicodeScalars.count <= 60,
              accepted.count <= 50, accepted == accepted.sorted(by: { $0.key < $1.key }), Set(accepted.map(\.key)).count == accepted.count,
              accepted.allSatisfy({ $0.key.range(of: "^[a-zA-Z0-9_-]{1,48}$", options: .regularExpression) != nil && $0.hash.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil }),
              action == "CREATE" ? (!peers.isEmpty && message.isEmpty && accepted.isEmpty) : peers.isEmpty,
              ["SUBMIT", "PARENT_SUBMIT"].contains(action) || message.isEmpty, action == "ACCEPT_RULES" || accepted.isEmpty else { throw NativeFriendFailure.invalid }
    }
    public var proof: String {
        var fields = ["original-friend-channel-invite-v1", action, String(objectID), message, String(peers.count)]
        for peer in peers { fields += [String(peer.id), String(peer.version)] }
        fields.append(String(accepted.count)); for item in accepted { fields += [item.key, item.hash] }
        return SHA256.hash(data: Data(fields.map { "\($0.utf8.count):\($0)" }.joined().utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
public struct NativeFriendPickerItem: Decodable, Equatable, Identifiable {
    public let friend: NativeFriendItem
    public let alreadyMember: Bool
    public var id: Int64 { friend.peerID }
    enum CodingKeys: String, CodingKey { case alreadyMember = "already_member" }
    public init(from decoder: Decoder) throws { friend = try NativeFriendItem(from: decoder); alreadyMember = try decoder.container(keyedBy: CodingKeys.self).decode(Bool.self, forKey: .alreadyMember) }
}
public struct NativeFriendChannelInvitePicker: Decodable {
    public let directory: NativeFriendDirectoryPage
    public let items: [NativeFriendPickerItem]
    public let channelID, guildID, name: String
    public let guildKind: Int
    public let targetChannel: Bool?
    enum CodingKeys: String, CodingKey { case items, channelID = "channel_id", guildID = "guild_id", guildKind = "guild_kind", name, targetChannel = "target_channel" }
    public init(from decoder: Decoder) throws {
        directory = try NativeFriendDirectoryPage(from: decoder); let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decode([NativeFriendPickerItem].self, forKey: .items); channelID = try c.decode(String.self, forKey: .channelID)
        guildKind = try c.decode(Int.self, forKey: .guildKind)
        guildID = try c.decode(String.self, forKey: .guildID); name = try c.decode(String.self, forKey: .name); targetChannel = try c.decodeIfPresent(Bool.self, forKey: .targetChannel)
    }
}
public struct NativeFriendChannelInviteReceipt: Decodable {
    public let viewerID: Int64
    public let requestID, outcome: String
    public let action, objectID, payloadHash, errorCode: String?
    enum CodingKeys: String, CodingKey { case viewerID = "viewer_id", requestID = "request_id", outcome, action, objectID = "object_id", payloadHash = "payload_hash", errorCode = "error_code" }
}
public struct NativeFriendChannelInviteBatch: Decodable, Equatable {
    public struct Item: Decodable, Equatable, Identifiable {
        public let inviteID, peerID, state: String
        public let friend: NativeFriendItem
        public let parentMember, channelAccess, channelAccepted: Bool?
        public var id: String { inviteID }
        enum CodingKeys: String, CodingKey { case inviteID = "invite_id", peerID = "peer_id", state, friend, parentMember = "parent_member", channelAccess = "channel_access", channelAccepted = "channel_accepted" }
    }
    public let viewerID: Int64
    public let channelID, requestID, name: String
    public let guildKind: Int
    public let targetChannel: Bool?
    public let invited, joined, pending, closed: Int
    public let items: [Item]
    enum CodingKeys: String, CodingKey { case viewerID = "viewer_id", channelID = "channel_id", requestID = "request_id", name, guildKind = "guild_kind", targetChannel = "target_channel", invited, joined, pending, closed, items }
}
public struct NativeFriendChannelInviteLanding: Decodable, Equatable {
    public struct Space: Decodable, Equatable { public let name: String }
    public struct Rule: Decodable, Equatable, Identifiable {
        public let key, hash, title, body: String
        public let required, accepted: Bool
        public var id: String { key }
        enum CodingKeys: String, CodingKey { case key = "rule_key", hash = "rule_hash", title, body, required, accepted }
    }
    public let viewerID: Int64
    public let inviteID, guildID, joinState: String
    public let guildKind: Int
    public let space: Space?
    public let rules: [Rule]
    public struct Application: Decodable, Equatable { public let id: String; public let status: Int; public let expired: Bool }
    public let admissionScope, channelID, channelName: String?
    public let parentApplication: Application?
    public let parentMember, channelAccess, channelAccepted, inviteAvailable, parentInviteAvailable, channelReady, joiningPaused: Bool?
    public var isTargetChannel: Bool { admissionScope == "CHANNEL" }
    public var canEnterOriginalChannel: Bool { isTargetChannel && parentMember == true && channelAccess == true && channelAccepted == true }
    enum CodingKeys: String, CodingKey {
        case viewerID = "viewer_id", inviteID = "invite_id", guildID = "guild_id", guildKind = "guild_kind", joinState = "join_state", space, rules
        case admissionScope = "admission_scope", channelID = "channel_id", channelName = "channel_name", parentApplication = "parent_application"
        case parentMember = "parent_member", channelAccess = "channel_access", channelAccepted = "channel_accepted", inviteAvailable = "invite_available", parentInviteAvailable = "parent_invite_available", channelReady = "channel_ready", joiningPaused = "joining_paused"
    }
}
public struct NativeFriendChannelInviteMine: Decodable {
    public struct Item: Decodable, Equatable, Identifiable {
        public let inviteID, channelID, requestID: String
        public var id: String { inviteID }
        enum CodingKeys: String, CodingKey { case inviteID = "invite_id", channelID = "channel_id", requestID = "request_id" }
    }
    public let viewerID: Int64
    public let items: [Item]
    public let nextBefore: String
    enum CodingKeys: String, CodingKey { case viewerID = "viewer_id", items, nextBefore = "next_before" }
}
