#if DEBUG
import Combine
import SwiftUI

/// Synthetic `api/template/info` rows with the mini-program detail fields
/// (`--template-parity-scenario public|official|choice|text|topic`). Offline only.
@MainActor final class TemplateDetailParityFixtureReader: ObservableObject, DiscoveryReading {
    let scenario: String
    private let shelf = DiscoveryFixtureReader()
    var isConfigured: Bool { true }
    var discoveryPresentationIdentity: String { "template-parity-fixture" }
    var discoveryPresentationChanges: AnyPublisher<Void, Never> { objectWillChange.eraseToAnyPublisher() }
    init(scenario: String) { self.scenario = scenario }
    func discoveryBanners() async throws -> [DiscoveryBanner] { try await shelf.discoveryBanners() }
    func discoveryCategories(type: Int?) async throws -> [DiscoveryCategory] { try await shelf.discoveryCategories(type: type) }
    func discoveryTemplateHome() async throws -> DiscoveryTemplateHome { try await shelf.discoveryTemplateHome() }
    func discoveryPlayTemplates(keyword: String, packType: DiscoveryPackType?) async throws -> [DiscoveryPlayTemplate] { try await shelf.discoveryPlayTemplates(keyword: keyword, packType: packType) }
    func discoveryTopicTemplates() async throws -> [DiscoveryTopicTemplate] { try await shelf.discoveryTopicTemplates() }
    func discoveryTopicTemplateDetail(id: Int) async throws -> PublicTopicTemplateDetail { try await shelf.discoveryTopicTemplateDetail(id: id) }
    func discoveryPlayTemplate(id: Int) async throws -> DiscoveryPlayTemplate { try await discoveryPlayTemplateRead(id: id).template }

    static func row(id: Int, scenario: String) -> String {
        let shared = #""title":"Notice the city","description":"Look for small details on a walk.","duration":45,"useNum":12,"ruleInstructions":"Pick a detail\nShare what you noticed","requiredMaterials":"Paper、Pencil","usageLocation":"Public walking route","sysCategoryList":[{"categoryName":"City walks"}]"#
        switch scenario {
        case "official":
            return #"{"id":\#(id),\#(shared),"validationMethod":2,"validationMethodStr":"Photo"}"#
        case "choice":
            return #"{"id":\#(id),\#(shared),"memberId":9,"rating":"4.8","commentCount":3,"validationMethod":3,"validationMethodStr":"Choice","questionName":"Which colour is the door?","questionA":"Red","questionB":"Blue","questionAnswer":"A"}"#
        case "text":
            return #"{"id":\#(id),\#(shared),"memberId":9,"rating":"4.5","validationMethod":1,"validationMethodStr":"Text answer","questionName":"Name the street &lt;fixture&gt;"}"#
        case "topic":
            return #"{"id":\#(id),"title":"Three chapters","productType":2,"chapterCount":3,"locationCount":6,"totalTime":90,"imgUrls":"https://template-parity.invalid/a.jpg;https://template-parity.invalid/b.jpg"}"#
        default:
            return #"{"id":\#(id),\#(shared),"publisher":"Fixture creator","memberId":9,"rating":"4.8","validationMethod":2,"validationMethodStr":"Photo","questionName":"Photograph the gate"}"#
        }
    }
    func discoveryPlayTemplateRead(id: Int) async throws -> DiscoveryPlayTemplateRead {
        let data = Data(Self.row(id: id, scenario: scenario).utf8)
        return DiscoveryPlayTemplateRead(template: try JSONDecoder().decode(DiscoveryPlayTemplate.self, from: data),
                                         extras: try JSONDecoder().decode(DiscoveryPlayTemplateExtras.self, from: data))
    }
}

@MainActor struct TemplateDetailParityFixtureHost: View {
    @StateObject private var reader: TemplateDetailParityFixtureReader
    init() {
        let args = ProcessInfo.processInfo.arguments
        let index = args.firstIndex(of: "--template-parity-scenario")
        let scenario = index.flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } ?? "public"
        _reader = StateObject(wrappedValue: TemplateDetailParityFixtureReader(scenario: scenario))
    }
    var body: some View {
        NavigationStack {
            DiscoveryTemplateDetailView(id: 701, reader: reader, imageReader: RetainedPublicImageReader())
        }
    }
}
#endif
