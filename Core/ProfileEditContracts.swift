import Foundation

/// Only the two text fields are editable. The remaining replacement fields retain their
/// wire values, including whitespace and delimiter order; do not round-trip image URLs.
public struct ProfileEditSnapshot: Decodable, Equatable {
    public let id: Int
    public let nickname: String
    public let introduction: String
    public let avatar: String
    public let wechat: String
    public let casePics: String
    public let tagIds: String
    enum CodingKeys: String, CodingKey { case id, nickname, introduction, avatar, wechat, casePics, tagIds, sysCategoryList }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        guard id > 0 else { throw APIError.malformedResponse }
        nickname = try c.decode(String.self, forKey: .nickname)
        // Explicit null is the source contract's empty value. Missing replacement fields
        // cannot safely be inferred as empty when this read is used for a destructive update.
        func preserved(_ key: CodingKeys) throws -> String {
            guard c.contains(key) else { throw APIError.malformedResponse }
            return try c.decodeIfPresent(String.self, forKey: key) ?? ""
        }
        introduction = try preserved(.introduction)
        avatar = try preserved(.avatar); wechat = try preserved(.wechat); casePics = try preserved(.casePics)
        if c.contains(.tagIds) { tagIds = try preserved(.tagIds) }
        else {
            struct Category: Decodable { let id: Int }
            let categories = try c.decode([Category].self, forKey: .sysCategoryList)
            guard categories.allSatisfy({ $0.id > 0 }) else { throw APIError.malformedResponse }
            tagIds = categories.map { String($0.id) }.joined(separator: ",")
        }
    }
    public var draft: ProfileEditDraft { .init(name: nickname, introduction: introduction) }
}
public struct ProfileEditDraft: Equatable {
    public var name: String
    public var introduction: String
    /// Nil preserves the complete wire string. An explicit empty selection clears preferences.
    public var routePreferenceIDs: [Int]?
    public init(name: String = "", introduction: String = "", routePreferenceIDs: [Int]? = nil) {
        self.name = name; self.introduction = introduction; self.routePreferenceIDs = routePreferenceIDs
    }
    public var normalized: Self { .init(name: name.trimmingCharacters(in: .whitespacesAndNewlines), introduction: introduction.trimmingCharacters(in: .whitespacesAndNewlines), routePreferenceIDs: routePreferenceIDs) }
    public var isValid: Bool {
        let ids = routePreferenceIDs ?? []
        return !normalized.name.isEmpty && ids.allSatisfy { $0 > 0 } && Set(ids).count == ids.count
    }
}
public struct ProfileEditPayload: Encodable, Equatable {
    public let name: String
    public let introduction: String
    public let avatar: String
    public let wechat: String
    public let casePics: String
    public let tagIds: String
    public init(draft: ProfileEditDraft, preserving snapshot: ProfileEditSnapshot) throws {
        guard draft.isValid else { throw APIError.invalidRequest }
        name = draft.normalized.name; introduction = draft.normalized.introduction
        avatar = snapshot.avatar; wechat = snapshot.wechat; casePics = snapshot.casePics
        tagIds = draft.routePreferenceIDs.map { $0.map(String.init).joined(separator: ",") } ?? snapshot.tagIds
    }
    public func matches(_ snapshot: ProfileEditSnapshot) -> Bool {
        name == snapshot.nickname && introduction == snapshot.introduction && avatar == snapshot.avatar
        && wechat == snapshot.wechat && casePics == snapshot.casePics && tagIds == snapshot.tagIds
    }
}
public struct ProfileEditSession: Equatable {
    public let identity: ProfileReadIdentity
    let token: String
    public init(accountID: Int, epoch: UInt64, token: String) throws {
        guard accountID > 0, AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        identity = .init(accountID: accountID, epoch: epoch); self.token = token
    }
}
public enum ProfileEditWriteError: Error { case notSent, rejected(ProfileReadFailure), outcomeUnknown }
public protocol ProfileEditServing {
    func read(token: String) async throws -> ProfileEditSnapshot
    func save(_ payload: ProfileEditPayload, token: String) async throws
}
