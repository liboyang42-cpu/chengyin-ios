#if DEBUG
import Foundation

/// Opt-in offline UI data. Root launch/test wiring decides whether to inject this reader.
/// URLs and credentials are absent so snapshots cannot accidentally fetch remote resources.
@MainActor
final class DiscoveryFixtureReader: DiscoveryReading {
    enum Scenario { case content, empty, failure, unauthorized, unconfigured, unavailable }
    let scenario: Scenario
    var isConfigured: Bool { scenario != .unconfigured }
    init(scenario: Scenario = .content) { self.scenario = scenario }

    private func check() throws {
        switch scenario {
        case .unconfigured: throw APIError.notConfigured
        case .failure: throw APIError.httpStatus(503)
        case .unauthorized: throw APIError.unauthorized
        default: break
        }
    }
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try check()
        return try JSONDecoder().decode(type, from: Data(json.utf8))
    }
    func discoveryBanners() async throws -> [DiscoveryBanner] {
        try decode([DiscoveryBanner].self, scenario == .empty ? "[]" : #"[{"id":901,"linkType":0}]"#)
    }
    func discoveryCategories(type: Int?) async throws -> [DiscoveryCategory] {
        try decode([DiscoveryCategory].self, scenario == .empty ? "[]" : #"[{"id":11,"categoryName":"City walks","type":4}]"#)
    }
    func discoveryTemplateHome() async throws -> DiscoveryTemplateHome {
        try decode(DiscoveryTemplateHome.self, scenario == .empty ? "{}" : #"{"total":2,"categoryList":[{"id":11,"categoryName":"City walks","type":4}],"bannerList":[{"id":701,"title":"Notice the city","players":"2–6","duration":45}],"latestList":[{"id":702,"title":"A story around the corner","packType":1}],"recommendList":[{"id":701,"title":"Notice the city"}],"mustPlayList":[{"id":702,"title":"A story around the corner","packType":1}],"hotList":[{"id":701,"title":"Notice the city"}]}"#)
    }
    func discoveryPlayTemplates(keyword: String, packType: DiscoveryPackType?) async throws -> [DiscoveryPlayTemplate] {
        let rows = try decode([DiscoveryPlayTemplate].self, scenario == .empty ? "[]" : #"[{"id":701,"title":"Notice the city","players":"2–6","duration":45,"packType":0},{"id":702,"title":"A story around the corner","packType":1}]"#)
        return rows.filter { (packType == nil || $0.pack == packType) && (keyword.isEmpty || $0.title.localizedCaseInsensitiveContains(keyword)) }
    }
    func discoveryTopicTemplates() async throws -> [DiscoveryTopicTemplate] {
        try decode([DiscoveryTopicTemplate].self, scenario == .empty ? "[]" : #"[{"id":801,"name":"A neighborhood in three chapters","subtitle":"A sample route for offline UI checks","chapterCount":3,"locationCount":6,"totalTime":5400,"categoryIds":"11","templateStatus":"VERIFIED"},{"id":802,"name":"A route in progress","previewOnly":true,"categoryIds":"12"}]"#)
    }
    func discoveryTopicTemplateDetail(id: Int) async throws -> PublicTopicTemplateDetail {
        try check()
        if scenario == .unavailable { throw DiscoveryTemplateUnavailable.offline }
        let json = scenario == .empty ? "{\"id\":\(id)}" : PublicTopicTemplateFixtures.content(id: id)
        return try decode(PublicTopicTemplateDetail.self, json)
    }
    func discoveryPlayTemplate(id: Int) async throws -> DiscoveryPlayTemplate {
        try check()
        if scenario == .unavailable { throw DiscoveryTemplateUnavailable.offline }
        guard id > 0 else { throw APIError.invalidRequest }
        return try decode(DiscoveryPlayTemplate.self, """
        {"id":\(id),"title":"Notice the city","description":"Look for the small details on a neighborhood walk.","players":"2–6","duration":45,"difficulty":"Easy","ruleInstructions":"Choose a detail and share what you noticed.","requiredMaterials":"Paper and a pencil","usageLocation":"A public walking route","validationMethod":2,"storyText":"An offline fixture with the source-backed public fields."}
        """)
    }
}
#endif
