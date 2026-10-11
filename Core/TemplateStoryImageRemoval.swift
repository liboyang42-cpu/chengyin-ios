import Foundation

/// A local, occurrence-specific edit. References are opaque strings, never fetched or deleted.
public struct TemplateStoryImageRemoval: Equatable {
    public let index: Int
    private let snapshot: [String]

    public init(index: Int, images: [String]) {
        self.index = index
        self.snapshot = images
    }

    /// Reject an obsolete UI action rather than remove the next image after a previous tap.
    /// Byte comparison also preserves canonically equivalent but differently encoded references.
    public func applying(to images: [String]) -> [String]? {
        guard images.indices.contains(index), images.count == snapshot.count,
              zip(images, snapshot).allSatisfy({ pair in pair.0.utf8.elementsEqual(pair.1.utf8) }) else { return nil }
        var result = images
        result.remove(at: index)
        return result
    }
}
