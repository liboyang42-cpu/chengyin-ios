import Foundation

/// P045 onPreviewImage opens the tapped image in that exact post's image list.
/// This value is ephemeral UI context, never a URL grant or persistent media record.
public struct ClubPostImageSelection: Identifiable, Equatable {
    public let id = UUID()
    public let postID: Int
    public let postVersion: Int
    public let clubID: Int?
    public let identity: ClubReadIdentity
    public let readScope: UUID
    public let sources: [String]
    public let initialIndex: Int
    public init?(post: ClubCommunityPost, clubID: Int?, identity: ClubReadIdentity, readScope: UUID, index: Int) {
        guard clubID == nil || (clubID ?? 0) > 0,
              post.images.indices.contains(index), !post.images[index].isEmpty,
              post.clubID == nil || post.clubID == clubID else { return nil }
        postID = post.id; postVersion = post.version; self.clubID = clubID
        self.identity = identity; self.readScope = readScope; sources = post.images; initialIndex = index
    }
    public func isCurrent(post: ClubCommunityPost, clubID: Int?, identity: ClubReadIdentity, readScope: UUID) -> Bool {
        self.postID == post.id && postVersion == post.version && self.clubID == clubID &&
        self.identity == identity && self.readScope == readScope && sources == post.images &&
        (post.clubID == nil || post.clubID == clubID)
    }
    public func previous(_ index: Int) -> Int { max(0, min(sources.count - 1, index - (index > 0 ? 1 : 0))) }
    public func next(_ index: Int) -> Int { min(sources.count - 1, max(0, index + (index < sources.count - 1 ? 1 : 0))) }
}

/// Small, deterministic zoom state shared by the preview and its focused tests.
public struct ClubPostImageZoom: Equatable {
    public private(set) var scale: Double = 1
    public private(set) var x: Double = 0
    public private(set) var y: Double = 0
    public init() {}
    public mutating func reset() { scale = 1; x = 0; y = 0 }
    public mutating func setScale(_ value: Double, width: Double, height: Double) {
        guard value.isFinite else { return }
        scale = min(5, max(1, value)); pan(x: x, y: y, width: width, height: height)
    }
    public mutating func pan(x: Double, y: Double, width: Double, height: Double) {
        guard x.isFinite, y.isFinite, width.isFinite, height.isFinite else { return }
        let limitX = max(0, width) * (scale - 1) / 2
        let limitY = max(0, height) * (scale - 1) / 2
        self.x = min(limitX, max(-limitX, x)); self.y = min(limitY, max(-limitY, y))
    }
}
