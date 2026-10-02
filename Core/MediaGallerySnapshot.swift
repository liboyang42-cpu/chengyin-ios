import Foundation

/// Preserve source order and duplicate positions: selected index belongs to this immutable list.
/// URLs are not promoted into network authority; the reader separately approves each origin.
public struct MediaGallerySnapshot: Equatable {
    public let sources: [String]
    public let initialIndex: Int
    public init(sources: [String], selectedIndex: Int = 0) {
        self.sources = Array(sources.prefix(100))
        self.initialIndex = self.sources.isEmpty ? 0 : min(max(0, selectedIndex), self.sources.count - 1)
    }
}
