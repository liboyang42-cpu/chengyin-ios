import Foundation

/// Shared nullable Long contract for the public template shelf and detail.
/// Absence is unknown. Malformed values fail closed; public preview rows are never a fallback.
enum PublicTemplateRouteCount {
    static func decode<Key: CodingKey>(from container: KeyedDecodingContainer<Key>, forKey key: Key) throws -> Int? {
        let count = try container.decodeIfPresent(Int.self, forKey: key)
        guard count.map({ $0 >= 0 }) ?? true else { throw APIError.malformedResponse }
        return count
    }
}
