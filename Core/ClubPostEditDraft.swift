import Foundation

/// An exact local draft, not a normalized wire body or permission to publish.
public struct ClubPostEditDraft: Equatable {
    public let content: String
    public let images: [String]

    public init(content: String, images: [String]) {
        self.content = content
        self.images = images
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.content.utf8.elementsEqual(rhs.content.utf8) &&
        lhs.images.count == rhs.images.count &&
        zip(lhs.images, rhs.images).allSatisfy { pair in pair.0.utf8.elementsEqual(pair.1.utf8) }
    }
}
