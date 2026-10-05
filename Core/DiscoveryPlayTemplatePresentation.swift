import Foundation

/// Read-only display values from the current public-library DTO. This is not an
/// album, author identity, ownership grant, or an owner-template projection.
public struct DiscoveryPlayTemplatePresentation: Equatable {
    public let publisher: String?
    public let storyText: String?
    public let storyImage: String?
    public let gallerySources: [String]
    public let useCount: Int?
    public var hasStory: Bool { storyText != nil || storyImage != nil }

    public init(_ item: DiscoveryPlayTemplate) {
        publisher = Self.nonempty(item.publisher)
        storyText = Self.nonempty(item.storyText)
        storyImage = Self.safeImage(item.storyImg)
        var sources: [String] = []
        // The public DTO has exactly these two image fields. Never infer imgUrls.
        for raw in [item.imgUrl, item.storyImg] {
            if let source = Self.safeImage(raw), !sources.contains(source) { sources.append(source) }
        }
        gallerySources = sources
        useCount = item.useNum
    }

    private static func nonempty(_ raw: String?) -> String? {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
    /// Screening is not origin approval. The existing retained-image reader still
    /// owns permission, bounded download, redirect rejection, and image sanitation.
    private static func safeImage(_ raw: String?) -> String? {
        guard let value = nonempty(raw), value.utf8.count <= 8192,
              !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              value.removingPercentEncoding != nil,
              let parts = URLComponents(string: value), parts.scheme == "https",
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              parts.url != nil else { return nil }
        return value
    }
}
