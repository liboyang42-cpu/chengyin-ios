#if DEBUG
import Foundation

/// Opt-in offline UI data. Root launch/test wiring decides whether to inject this reader.
/// URLs and credentials are absent so snapshots cannot accidentally fetch remote resources.
@MainActor
final class DiscoveryFixtureReader: DiscoveryReading {
    enum Scenario { case content, empty, failure, unauthorized, unconfigured, unavailable }
    let scenario: Scenario
    enum MetadataScenario: String { case dictionary, categories, lifecycle }
    let metadataScenario: MetadataScenario?
    private(set) var metadataReadInvocations: [String] = []
    private(set) var metadataReadCompletions: [String] = []
    private var heldMetadataRead: CheckedContinuation<[TemplateMetadataOption], Error>?
    var metadataPendingReadCount: Int { heldMetadataRead == nil ? 0 : 1 }
    var isConfigured: Bool { scenario != .unconfigured }
    init(scenario: Scenario = .content, metadataScenario: MetadataScenario? = nil) {
        self.scenario = scenario; self.metadataScenario = metadataScenario
    }

    // These exact wire-shaped rows are only used by the opted-in DEBUG authoring host.
    // Labels intentionally differ from values. Unsupported durations stay visible.
    static let metadataPlayersJSON = #"[{"dictValue":"  team:2-6  ","dictLabel":"A friendly group"},{"dictValue":"solo:exact","dictLabel":"One explorer"}]"#
    static let metadataDurationJSON = #"[{"dictValue":"45","dictLabel":"Three quarters of an hour"},{"dictValue":"045","dictLabel":"Padded unsupported"},{"dictValue":"+45","dictLabel":"Signed unsupported"},{"dictValue":"45.0","dictLabel":"Decimal unsupported"},{"dictValue":"2147483648","dictLabel":"Overflow unsupported"}]"#
    static let metadataCategoriesJSON = #"[{"id":11,"categoryName":"City walks","type":4},{"id":12,"categoryName":"Stories","type":4},{"id":101,"categoryName":"Category 101","type":4},{"id":102,"categoryName":"Category 102","type":4},{"id":103,"categoryName":"Category 103","type":4},{"id":104,"categoryName":"Category 104","type":4},{"id":105,"categoryName":"Category 105","type":4},{"id":106,"categoryName":"Category 106","type":4},{"id":107,"categoryName":"Category 107","type":4},{"id":108,"categoryName":"Category 108","type":4},{"id":109,"categoryName":"Category 109","type":4},{"id":110,"categoryName":"Category 110","type":4},{"id":111,"categoryName":"Category 111","type":4},{"id":112,"categoryName":"Category 112","type":4},{"id":113,"categoryName":"Category 113","type":4}]"#

    func templateMetadataDictionaryRequest(kind: TemplateMetadataKind) -> DiscoveryReadRequest<[TemplateMetadataOption]> {
        DiscoveryReadRequest(read: { [weak self] in
            guard let self else { throw CancellationError() }
            return try await self.templateMetadataDictionary(kind: kind)
        }, onUnauthorized: {})
    }
    func templateMetadataCategoriesRequest() -> DiscoveryReadRequest<[DiscoveryCategory]> {
        DiscoveryReadRequest(read: { [weak self] in
            guard let self else { throw CancellationError() }
            guard self.metadataScenario != nil else { return try await self.discoveryCategories(type: 4) }
            self.metadataReadInvocations.append("categories:4")
            defer { self.metadataReadCompletions.append("categories:4") }
            return try self.decode([DiscoveryCategory].self, Self.metadataCategoriesJSON)
        }, onUnauthorized: {})
    }
    func releaseHeldMetadataRead() {
        // The fixture's account switch calls this only AFTER synchronizing the owner.
        // Deliberately finish a canceled read; the production editor must reject it.
        let continuation = heldMetadataRead; heldMetadataRead = nil
        continuation?.resume(returning: [.init(value: "late-old-owner", label: "Late old owner")])
    }

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
    func templateMetadataDictionary(kind: TemplateMetadataKind) async throws -> [TemplateMetadataOption] {
        if metadataScenario != nil {
            metadataReadInvocations.append(kind.rawValue)
            defer { metadataReadCompletions.append(kind.rawValue) }
            if metadataScenario == .lifecycle, kind == .players {
                let attempt = metadataReadInvocations.filter { $0 == kind.rawValue }.count
                switch attempt {
                case 1: throw APIError.notConfigured
                case 2: throw APIError.httpStatus(503)
                case 3: return []
                case 4:
                    return try await withCheckedThrowingContinuation { continuation in
                        heldMetadataRead = continuation
                    }
                default: break
                }
            }
            return try decode([TemplateMetadataOption].self,
                              kind == .players ? Self.metadataPlayersJSON : Self.metadataDurationJSON)
        }
        try check()
        guard scenario != .empty else { return [] }
        switch kind {
        case .players: return [.init(value: "synthetic-group", label: "Synthetic group")]
        case .duration: return [.init(value: "45", label: "Synthetic 45 minutes"), .init(value: "half-day", label: "Synthetic unsupported duration")]
        }
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
