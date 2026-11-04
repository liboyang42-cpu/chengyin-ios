import Foundation

public enum NativeFriendDirectorySection: String, Codable, CaseIterable, Sendable { case together, recent, all }
public struct NativeFriendDirectoryFilter: Equatable, Sendable {
    public var section: NativeFriendDirectorySection
    /// nil = all groups; zero = the existing virtual default group; positive = an owner-owned group.
    public var groupID: Int64?
    public var starredOnly: Bool
    public init(section: NativeFriendDirectorySection = .all, groupID: Int64? = nil, starredOnly: Bool = false) {
        self.section = section; self.groupID = groupID; self.starredOnly = starredOnly
    }
}
public struct NativeFriendDirectoryPage: Codable, Equatable, Sendable {
    public let viewerID: Int64
    public let section: NativeFriendDirectorySection
    public let groupID: Int64?
    public let starredOnly: Bool
    public let revision: String
    public let groups: NativeFriendMetadataGroups
    public let counts: [String: Int]
    public let total: Int
    public let items: [NativeFriendItem]
    public let hasMore: Bool
    public let nextCursor: String?
    enum CodingKeys: String, CodingKey {
        case viewerID = "viewer_id", section, groupID = "group_id", starredOnly = "starred_only", revision, groups, counts, total, items
        case hasMore = "has_more", nextCursor = "next_cursor"
    }
}
public struct NativeFriendDirectoryDetail: Codable, Equatable, Sendable {
    public let viewerID: Int64
    public let item: NativeFriendItem
    public let conversationID: Int?
    enum CodingKeys: String, CodingKey { case viewerID = "viewer_id", item, conversationID = "conversation_id" }
}
public enum NativeFriendDirectoryFailure: Error, Equatable { case changed, missingGroup, unavailablePeer, readUnavailable }
@MainActor public protocol NativeFriendDirectoryServing: AnyObject {
    var viewerID: Int64 { get }
    var isCurrent: Bool { get }
    func page(filter: NativeFriendDirectoryFilter, cursor: String?) async throws -> NativeFriendDirectoryPage
    func detail(peerID: Int64) async throws -> NativeFriendDirectoryDetail
}
