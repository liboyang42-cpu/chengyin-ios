import Foundation

public enum ObjectCardSyntheticFixtures {
    /// Reserved hosts are labels only. Offline fixture loaders never contact these URLs.
    public static let collectionJSON = #"{"list":[{"id":901,"title":"Synthetic notebook","category":"书籍文具","sourceUrl":"https://fixtures.invalid/notebook.png","frames":["https://fixtures.invalid/front.png","https://fixtures.invalid/back.png"],"caption":"Offline example","place":"Synthetic studio","cardStyle":"foil","genStatus":"QUEUED"},{"id":902,"title":"Synthetic cup","category":"日用杂物","sourceUrl":"","cutoutUrl":"","frames":[],"cardStyle":"plain","genStatus":"FAILED"}],"total":52}"#
    public static func collection() throws -> ObjectCardCollection {
        try JSONDecoder().decode(ObjectCardCollection.self, from: Data(collectionJSON.utf8))
    }
}
@MainActor public final class ObjectCardFixtureReader: ObjectCardReading {
    public private(set) var scope = UUID()
    public var isConfigured = true
    public var isAuthenticated = true
    public var failNext = false
    public init() {}
    public func rotateScope() { scope = UUID() }
    public func list(category: ObjectCardCategory) async throws -> ObjectCardCollection {
        if failNext { failNext = false; throw APIError.httpStatus(503) }
        let value = try ObjectCardSyntheticFixtures.collection()
        if category == .all { return value }
        // Decode the same wire shape; do not invent public model constructors for fixture data.
        let cards: [[String: Any]] = category == .books ? [["id":901,"title":"Synthetic notebook","category":"书籍文具","frames":["https://fixtures.invalid/front.png","https://fixtures.invalid/back.png"]]] : []
        return try JSONDecoder().decode(ObjectCardCollection.self, from: JSONSerialization.data(withJSONObject: ["list": cards, "total": cards.count]))
    }
}
