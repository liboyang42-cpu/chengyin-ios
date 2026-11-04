import Foundation
import CryptoKit

@MainActor public protocol NativeFriendPickerSource: AnyObject {
    var items: [NativeFriendPickerItem] { get }; var selected: [NativeFriendPickerItem] { get }
    var section: NativeFriendDirectorySection { get }; var busy: Bool { get }; var isCurrent: Bool { get }
    var canWrite: Bool { get }; var hasPickerReview: Bool { get }; var alreadyMemberLabel: String { get }
    func chooseSection(_ section: NativeFriendDirectorySection) async
    func toggle(_ item: NativeFriendPickerItem); func prepareCreate()
}
public enum NativeFriendTeamInviteMode: Equatable {
    case team(Int64), offer(String), mine
    public var valid: Bool { switch self { case .team(let id): return id > 0; case .offer(let id): return UUID(uuidString: id)?.uuidString.lowercased() == id; case .mine: return true } }
}
public struct NativeFriendTeamInviteCommand: Codable, Equatable {
    public struct Body: Codable, Equatable {
        public let teamId: Int64
        public var peers: [NativeFriendChannelInvitePeer]? = nil
        public var offerId: String? = nil
        public var joinMode: Int? = nil
    }
    private struct Envelope: Codable { let requestId, action: String; let expectedTeamId: Int64; let body: Body }
    public let requestID, action: String
    public let teamID: Int64
    public let body: Body
    public let raw: Data
    public var fingerprint: String { SHA256.hash(data: raw).map { String(format: "%02x", $0) }.joined() }
    public init(action: String, body: Body) throws {
        requestID = UUID().uuidString.lowercased(); self.action = action; teamID = body.teamId; self.body = body
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        raw = try encoder.encode(Envelope(requestId: requestID, action: action, expectedTeamId: teamID, body: body)); try validate()
    }
    public func validate() throws {
        guard teamID > 0, body.teamId == teamID, UUID(uuidString: requestID)?.uuidString.lowercased() == requestID, raw.count <= 4096 else { throw NativeFriendFailure.invalid }
        let decoded = try JSONDecoder().decode(Envelope.self, from: raw)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard decoded.requestId == requestID, decoded.action == action, decoded.expectedTeamId == teamID, decoded.body == body,
              try encoder.encode(decoded) == raw else { throw NativeFriendFailure.invalid }
        if action == "FRIEND_OFFER" {
            guard let peers = body.peers, (1...10).contains(peers.count), Set(peers.map(\.id)).count == peers.count,
                  peers.allSatisfy({ $0.id > 0 && $0.version > 0 }), body.offerId == nil, body.joinMode == nil else { throw NativeFriendFailure.invalid }
        } else {
            guard ["FRIEND_CONFIRM", "FRIEND_DECLINE", "FRIEND_REVOKE"].contains(action), body.peers == nil,
                  let id = body.offerId, UUID(uuidString: id)?.uuidString.lowercased() == id,
                  action == "FRIEND_CONFIRM" ? [1, 2].contains(body.joinMode ?? 0) : body.joinMode == nil else { throw NativeFriendFailure.invalid }
        }
    }
    public static func fromRaw(_ raw: Data) throws -> Self {
        let d = try JSONDecoder().decode(Envelope.self, from: raw)
        let value = Self(requestID: d.requestId, action: d.action, teamID: d.expectedTeamId, body: d.body, raw: raw)
        try value.validate(); return value
    }
    private init(requestID: String, action: String, teamID: Int64, body: Body, raw: Data) {
        self.requestID = requestID; self.action = action; self.teamID = teamID; self.body = body; self.raw = raw
    }
}
/// In-memory confirmation only. Names are frozen with the exact command, never a new authority or journal format.
public struct NativeFriendTeamInviteReviewContext: Equatable {
    public let command: NativeFriendTeamInviteCommand
    public let teamName: String
    public let peers: [NativeFriendPickerItem]
}
public struct NativeFriendTeamInvitePicker: Decodable {
    public let directory: NativeFriendDirectoryPage
    public let items: [NativeFriendPickerItem]
    public let teamID, name: String
    enum CodingKeys: String, CodingKey { case items, teamID = "team_id", name }
    public init(from decoder: Decoder) throws {
        directory = try NativeFriendDirectoryPage(from: decoder); let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decode([NativeFriendPickerItem].self, forKey: .items); teamID = try c.decode(String.self, forKey: .teamID); name = try c.decode(String.self, forKey: .name)
    }
}
public struct NativeFriendTeamOffer: Decodable, Equatable, Identifiable {
    public let viewerID: Int64
    public let offerID, teamID, name, state: String
    public let inviter: NativeFriendItem?
    public let recipient, canAct: Bool
    public let joinMode: Int
    public var id: String { offerID }
    enum CodingKeys: String, CodingKey { case viewerID = "viewer_id", offerID = "offer_id", teamID = "team_id", name, state, recipient, inviter, canAct = "can_act", joinMode = "join_mode" }
    public var stateLabel: String {
        switch state { case "WAITING_CONFIRM": return "等待本人确认（尚未入队）"; case "PENDING_REVIEW": return "本人已确认，等待队长审核"; case "JOINED": return "原成员记录已加入"; case "DECLINED": return "本人已拒绝邀请"; case "REJECTED": return "原入队审核未通过"; case "WITHDRAWN": return "本人已撤回申请"; case "REVOKED": return "队长已撤销未确认邀请"; case "EXPIRED": return "邀请或原待审记录已失效"; case "ACCESS_ENDED": return "原成员资格已结束"; default: return "当前原状态不可确认" }
    }
}
public struct NativeFriendTeamInviteMine: Decodable {
    public let viewerID: Int64; public let items: [NativeFriendTeamOffer]; public let nextBefore: String
    enum CodingKeys: String, CodingKey { case viewerID = "viewer_id", items, nextBefore = "next_before" }
}
public struct NativeFriendTeamInviteReceipt: Decodable {
    /// Output from the original writer, not a membership grant or a current landing projection.
    public struct IssuedOffer: Decodable, Equatable, Identifiable {
        public let offerID, peerID: String
        public var id: String { offerID }
        enum CodingKeys: String, CodingKey { case offerID = "offer_id", peerID = "peer_id" }
    }
    public struct FriendOffer: Decodable {
        public let offers: [IssuedOffer]?
        public let offerID: String?
        enum CodingKeys: String, CodingKey { case offers, offerID = "offer_id" }
    }
    public let contract, outcome, requestId: String
    public let action, targetKey, requestFingerprint: String?
    public let teamId: Int64?
    public let errorCode: String?
    // Optional so an exact legacy terminal receipt still closes its existing v1 journal.
    public let friendOffer: FriendOffer?
}
/// Historical original direct-message card, never a membership grant or an invitation code.
public struct NativeFriendTeamInviteNotice: Equatable {
    public let offerID: String; public let recipientID: Int
    public static func parse(message: MessagingMessage, conversation: MessagingConversation?, identity: MessagingReadIdentity?) -> Self? {
        guard let identity, identity.accountID > 0, conversation?.id == message.conversationID, conversation?.kind == .direct,
              message.id > 0, let senderID = message.senderID, senderID > 0, senderID != identity.accountID, message.type == 3, message.isPayloadVisible,
              let data = message.extraJSON?.data(using: .utf8), data.count <= 4096,
              let c = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(c.keys) == ["cardType", "contract", "offerId", "recipientMemberId", "title"],
              c["cardType"] as? String == "friend_team_offer", c["contract"] as? String == "original_friend_team_offer_v1",
              c["title"] as? String == "队长邀请你加入队伍", c["recipientMemberId"] as? String == String(identity.accountID),
              let id = c["offerId"] as? String, UUID(uuidString: id)?.uuidString.lowercased() == id else { return nil }
        return .init(offerID: id, recipientID: identity.accountID)
    }
}
