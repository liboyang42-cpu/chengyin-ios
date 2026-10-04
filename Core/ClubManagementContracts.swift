import Foundation

public struct ClubManagementRequest: Decodable, Equatable, Identifiable {
    public var id: Int { memberId }
    public let memberId: Int
    public let nickname: String?
    public let avatar: String?
    public let joinTime: String?
    public let joinMessage: String?
    enum CodingKeys: String, CodingKey { case memberId, nickname, avatar, joinTime, joinMessage }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        memberId = try c.decode(Int.self, forKey: .memberId)
        guard memberId > 0 else { throw APIError.malformedResponse }
        nickname = try c.decodeIfPresent(String.self, forKey: .nickname)
        avatar = try c.decodeIfPresent(String.self, forKey: .avatar)
        joinTime = try c.decodeIfPresent(String.self, forKey: .joinTime)
        joinMessage = try c.decodeIfPresent(String.self, forKey: .joinMessage)
    }
}

public enum ClubManagementAction: String, CaseIterable, Equatable {
    case approve, reject, remove
    var path: String {
        switch self {
        case .approve: return "api/club/join-request/approve"
        case .reject: return "api/club/join-request/reject"
        case .remove: return "api/club/remove-member"
        }
    }
}

public struct ClubManagementSnapshot: Equatable {
    public let club: ClubRecord
    public let requests: [ClubManagementRequest]
    public let members: [ClubMember]
    public init(club: ClubRecord, requests: [ClubManagementRequest], members: [ClubMember]) {
        self.club = club; self.requests = requests; self.members = members
    }
    public func allows(_ action: ClubManagementAction, memberID: Int) -> Bool {
        guard memberID > 0 else { return false }
        switch action {
        case .approve, .reject:
            return club.canGovern && requests.filter { $0.memberId == memberID }.count == 1
        case .remove:
            return club.isOwner && members.filter { $0.memberId == memberID }.count == 1
                && members.first { $0.memberId == memberID }?.isOwner == false
        }
    }
}

public struct ClubManagementSession: Equatable {
    public let identity: ClubReadIdentity
    let token: String
    public init(accountID: Int, epoch: UInt64, token: String) throws {
        guard accountID > 0, AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        identity = ClubReadIdentity(accountID: accountID, epoch: epoch); self.token = token
    }
}

@MainActor
public protocol ClubManagementAccess: AnyObject {
    var identity: ClubReadIdentity? { get }
    var isConfigured: Bool { get }
    func snapshot(clubID: Int) async throws -> ClubManagementSnapshot
    func perform(_ action: ClubManagementAction, clubID: Int, memberID: Int,
                 expectedIdentity: ClubReadIdentity) async throws -> ClubActionReceipt
}
