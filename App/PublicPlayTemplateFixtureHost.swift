#if DEBUG
import Combine
import SwiftUI

/// Synthetic public-library responses only. HTTPS .invalid identifiers are consumed
/// exclusively by an offline image fixture or an empty-origin rejecting reader.
@MainActor final class PublicPlayTemplateFixtureReader: ObservableObject, DiscoveryReading {
    let scenario: String
    private let shelf = DiscoveryFixtureReader()
    @Published var revision = 0
    @Published var detailReads = 0
    var failNextDetail: Bool
    var isConfigured: Bool { true }
    var discoveryPresentationIdentity: String { "fixture-\(revision)" }
    var discoveryPresentationChanges: AnyPublisher<Void, Never> { objectWillChange.eraseToAnyPublisher() }
    init(scenario: String) { self.scenario = scenario; failNextDetail = scenario == "failure" }
    func discoveryBanners() async throws -> [DiscoveryBanner] { try await shelf.discoveryBanners() }
    func discoveryCategories(type: Int?) async throws -> [DiscoveryCategory] { try await shelf.discoveryCategories(type: type) }
    func discoveryTemplateHome() async throws -> DiscoveryTemplateHome { try await shelf.discoveryTemplateHome() }
    func discoveryPlayTemplates(keyword: String, packType: DiscoveryPackType?) async throws -> [DiscoveryPlayTemplate] { try await shelf.discoveryPlayTemplates(keyword: keyword, packType: packType) }
    func discoveryTopicTemplates() async throws -> [DiscoveryTopicTemplate] { try await shelf.discoveryTopicTemplates() }
    func discoveryTopicTemplateDetail(id: Int) async throws -> PublicTopicTemplateDetail { try await shelf.discoveryTopicTemplateDetail(id: id) }
    func discoveryPlayTemplate(id: Int) async throws -> DiscoveryPlayTemplate {
        detailReads += 1
        if failNextDetail { failNextDetail = false; throw APIError.httpStatus(503) }
        var row: [String: Any] = ["id": id, "title": revision == 0 ? "Public fixture template" : "Updated public template"]
        if scenario != "missing" {
            let story = "https://public-template-fixture.invalid/story.jpg"
            row["storyImg"] = story
            if scenario != "imageOnly" {
                row["imgUrl"] = scenario == "duplicate" ? story : "https://public-template-fixture.invalid/cover.jpg"
                row["publisher"] = "Fixture publisher"
                row["storyText"] = "Independent fixture narrative"
                row["useNum"] = 0
            }
        }
        if revision > 0 { row["imgUrl"] = nil; row["storyImg"] = "https://public-template-fixture.invalid/replacement.jpg" }
        return try JSONDecoder().decode(DiscoveryPlayTemplate.self, from: JSONSerialization.data(withJSONObject: row))
    }
}

@MainActor struct PublicPlayTemplateFixtureHost: View {
    @StateObject private var reader: PublicPlayTemplateFixtureReader
    @State private var images = NativePresentationImageReader()
    private let scenario: String
    init() {
        let args = ProcessInfo.processInfo.arguments
        let index = args.firstIndex(of: "--public-play-scenario")
        let scenario = index.flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } ?? "content"
        self.scenario = scenario
        _reader = StateObject(wrappedValue: PublicPlayTemplateFixtureReader(scenario: scenario))
    }
    private var imageReader: any RetainedPublicImageReading {
        if scenario == "disabled" { return RetainedPublicImageReader() }
        if scenario == "denied" { return RetainedPublicImageReader(enabled: true, origins: []) }
        return images
    }
    var body: some View {
        VStack(spacing: 4) {
            Group {
                Text(verbatim: String(images.readCount)).accessibilityIdentifier("publicPlay.fixture.imageReads")
                Text(verbatim: String(reader.detailReads)).accessibilityIdentifier("publicPlay.fixture.detailReads")
                Button("Replace public fixture context") { images.onRead = { reader.revision += 1 } }
                    .accessibilityIdentifier("publicPlay.fixture.replaceOnImage")
            }
            // Keep synthetic probes compact. The real browser/detail/gallery
            // below still receives the requested accessibility text size.
            .font(.caption).dynamicTypeSize(.large)
            NavigationStack {
                DiscoveryTemplateBrowserView(reader: reader, imageReader: imageReader)
            }
        }
    }
}
#endif
