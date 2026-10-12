import Foundation

/// A local export of two already-public fields. It is not a profile URL or an invite.
/// Keep server IDs, media URLs, contacts, credentials and statistics out of the payload.
public struct ProfileIdentityShareCard: Equatable {
    public let nickname: String
    public let introduction: String?

    public init?(profile: SocialPublicProfile, owner: SocialAccountIdentity) {
        guard let accountID = owner.accountID, accountID > 0, profile.id == accountID,
              let nickname = profile.nickname, !nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              nickname.utf8.count <= 1_024, (profile.introduction?.utf8.count ?? 0) <= 16_384 else { return nil }
        self.nickname = nickname
        introduction = profile.introduction
    }

    /// The preview and system handoff use the same retained value, not two renderings.
    public func text(title: String) -> String {
        var lines = [title, nickname]
        if let introduction, !introduction.isEmpty { lines.append(introduction) }
        return lines.joined(separator: "\n\n")
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.nickname.utf8.elementsEqual(rhs.nickname.utf8) && same(lhs.introduction, rhs.introduction)
    }
    private static func same(_ lhs: String?, _ rhs: String?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case (.some(let l), .some(let r)): return l.utf8.elementsEqual(r.utf8)
        default: return false
        }
    }
}

/// The view identity deliberately contains exact bytes. Canonically equivalent edits
/// must still invalidate a preview of the previous public-profile response.
public struct ProfileIdentityShareSource: Hashable {
    public let memberID: Int
    private let nickname: [UInt8]?
    private let introduction: [UInt8]?
    public init(profile: SocialPublicProfile) {
        memberID = profile.id
        nickname = profile.nickname.map { Array($0.utf8) }
        introduction = profile.introduction.map { Array($0.utf8) }
    }
}
