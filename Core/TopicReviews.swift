import Foundation

/// The display-only review preview in an allowed topic detail response.
/// No author identifiers or review-writing capability are inferred from these rows.
public struct TopicReview: Decodable, Equatable {
    public let authorName: String?
    public let createTime: String?
    public let rating: Int?
    public let contents: String?
    private enum Keys: String, CodingKey { case memberNickname, createTime, rating, contents }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: Keys.self)
        authorName = Self.nonempty(try values.decodeIfPresent(String.self, forKey: .memberNickname))
        createTime = Self.nonempty(try values.decodeIfPresent(String.self, forKey: .createTime))
        contents = Self.nonempty(try values.decodeIfPresent(String.self, forKey: .contents))
        let score = try? values.decode(Int.self, forKey: .rating)
        rating = score.flatMap { (1...5).contains($0) ? $0 : nil }
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }
}

public struct TopicReviews: Decodable, Equatable {
    public let averageRating: Double?
    /// The server total is separate from the bounded preview and can be unavailable.
    public let commentCount: Int?
    public let preview: [TopicReview]
    public var hasConfirmedNoReviews: Bool { commentCount == 0 && preview.isEmpty }
    private enum Keys: String, CodingKey { case averageRating, commentCount, commentList }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: Keys.self)
        let average = try? values.decode(Double.self, forKey: .averageRating)
        averageRating = average.flatMap { $0.isFinite && (0...5).contains($0) ? $0 : nil }
        let count = try? values.decode(Int.self, forKey: .commentCount)
        commentCount = count.flatMap { $0 >= 0 ? $0 : nil }
        preview = try values.decodeIfPresent([TopicReview].self, forKey: .commentList) ?? []
        // The existing detail service returns at most five visible, nondeleted review rows.
        // Malformed list shapes and oversized previews must not become empty success.
        guard preview.count <= 5 else { throw APIError.malformedResponse }
    }
}
