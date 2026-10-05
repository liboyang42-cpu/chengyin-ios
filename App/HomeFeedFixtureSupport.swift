#if DEBUG
import SwiftUI

@MainActor final class HomeFeedFixtureReader: HomeFeedReading {
    let isConfigured = true
    let isOfflineExample = true
    let scope = UUID()
    let scenario: String
    private var failedOnce = false
    init(scenario: String = "content") { self.scenario = scenario }
    func banners() async throws -> [DiscoveryBanner] { [] }
    func categories() async throws -> [DiscoveryCategory] {
        try JSONDecoder().decode([DiscoveryCategory].self, from: Data(#"[{"id":2,"categoryName":"Sample category"}]"#.utf8))
    }
    func section(_ section: HomeFeedSection) async throws -> [HomeFeedItem] {
        if scenario == "empty" { return [] }
        return try section == .recommended ? [HomeFeedSyntheticFixtures.topic()] : [HomeFeedSyntheticFixtures.activity()]
    }
    func page(query: HomeFeedQuery, number: Int) async throws -> HomeFeedPage {
        if scenario == "retry", !failedOnce { failedOnce = true; throw APIError.httpStatus(503) }
        if scenario == "empty" || number > 1 || (!query.keyword.isEmpty && !"sample".contains(query.keyword.lowercased())) {
            return HomeFeedPage(items: [], number: number, size: query.pageSize)
        }
        let item = try query.kind == .topics ? HomeFeedSyntheticFixtures.topic() : HomeFeedSyntheticFixtures.activity()
        // Full raw page of duplicate IDs verifies dedup does not disable next-page probing.
        return HomeFeedPage(items: Array(repeating: item, count: query.pageSize), number: number, size: query.pageSize)
    }
}

/// Integrator routes module fixture `home-feed` here. Real detail views belong to app composition.
@MainActor struct HomeFeedFixtureHostView: View {
    @State private var reader: HomeFeedFixtureReader
    @State private var path: [HomeFeedDestination] = []
    init() {
        let args = ProcessInfo.processInfo.arguments
        let index = args.firstIndex(of: "--uitesting-home-feed-scenario")
        _reader = State(initialValue: HomeFeedFixtureReader(scenario: index.flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } ?? "content"))
    }
    var body: some View {
        NavigationStack(path: $path) {
            HomeFeedView(reader: reader) { path.append($0) }
                .navigationDestination(for: HomeFeedDestination.self) { destination in
                    switch destination {
                    case .activity(let id): Text(verbatim: "Synthetic activity destination \(id)").accessibilityIdentifier("homeFeed.destination.activity")
                    case .topic(let id): Text(verbatim: "Synthetic topic destination \(id)").accessibilityIdentifier("homeFeed.destination.topic")
                    }
                }
        }
    }
}

#endif
