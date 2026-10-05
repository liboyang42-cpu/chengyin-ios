#if DEBUG
import Foundation
public enum CreatorContentSyntheticFixtures {
    public static let projectsJSON = #"{"code":200,"data":{"rows":[{"id":301,"bizType":"topic","title":"Synthetic published topic","state":"running","stateText":"Synthetic running","ownerType":"member","signupCount":2,"viewCount":12},{"id":301,"bizType":"activity","title":"Synthetic owned activity","state":"draft","ownerType":"club"},{"id":302,"bizType":"template","title":"Synthetic template","state":"offline"}],"total":"208"}}"#
    public static let centerJSON = #"{"code":200,"data":{"applyStatus":"approved","profile":{"creatorName":"Synthetic creator","bio":"Offline example"},"metric":{"contentCount":3,"viewCount":12},"recentIncome":[{"date":"2026-01-01","amount":"001.2300","source":"Synthetic source"}]}}"#
}
@MainActor public final class CreatorContentFixtureReader: CreatorContentReading {
    public private(set) var scope = UUID()
    public var isConfigured = true
    public var isAuthenticated = true
    public var isOfflineExample: Bool { true }
    public var failure: APIError?
    public var projectsJSON = CreatorContentSyntheticFixtures.projectsJSON
    public var centerJSON = CreatorContentSyntheticFixtures.centerJSON
    public func signOut() { isAuthenticated = false; scope = UUID() }
    public private(set) var readCount = 0
    public init() {}
    public func projects(query: CreatorContentQuery) async throws -> CreatorContentProjectPage {
        try check()
        struct Envelope: Decodable { let data: CreatorContentProjectPage }
        let page = try JSONDecoder().decode(Envelope.self, from: Data(projectsJSON.utf8)).data
        let rows = page.rows.filter { (query.type == "all" || $0.bizType == query.type) && (query.state == "all" || $0.state == query.state) && (query.ownerType == "all" || $0.ownerType == query.ownerType) }
        return CreatorContentProjectPage(rows: rows, total: query == CreatorContentQuery() ? page.total : rows.count)
    }
    public func center() async throws -> CreatorContentCenter {
        try check()
        struct Envelope: Decodable { let data: CreatorContentCenter }
        return try JSONDecoder().decode(Envelope.self, from: Data(centerJSON.utf8)).data
    }
    private func check() throws { readCount += 1; if let failure { throw failure } }
}

#endif
