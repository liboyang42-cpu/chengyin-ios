import Foundation

/// Mirrors the two source response shapes; role remains server data, not registration intent.
public struct Account: Decodable, Equatable {
    public let id: Int
    public let nickname: String
    public let avatar: String
    public let role: String
    public let userType: Int?
    public let xp: Int
    public let level: Int
    enum CodingKeys: String, CodingKey { case id, userId, nickname, nickName, avatar, role, userType, point, xp, levelId, level }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int.self, forKey: .id) ?? c.decodeIfPresent(Int.self, forKey: .userId) ?? 0
        nickname = try c.decodeIfPresent(String.self, forKey: .nickname) ?? c.decodeIfPresent(String.self, forKey: .nickName) ?? ""
        avatar = try c.decodeIfPresent(String.self, forKey: .avatar) ?? ""
        role = try c.decodeIfPresent(String.self, forKey: .role) ?? ""
        if let numeric = try? c.decode(Int.self, forKey: .userType) { userType = numeric }
        else if let text = try? c.decode(String.self, forKey: .userType) { userType = Int(text) }
        else { userType = nil }
        xp = try c.decodeIfPresent(Int.self, forKey: .point) ?? c.decodeIfPresent(Int.self, forKey: .xp) ?? 0
        level = try c.decodeIfPresent(Int.self, forKey: .levelId) ?? c.decodeIfPresent(Int.self, forKey: .level) ?? 1
    }
    /// Presentation only. API endpoints must still enforce server authorization.
    public var effectiveRole: String { !role.isEmpty ? role : (userType == 2 ? "merchant" : "player") }
}

public struct LoginResult {
    public let token: String
    public let account: Account
}
