import SwiftUI

/// Embed in the root's NavigationStack or present through DiscoveryHomeView.
@MainActor
struct DiscoveryTemplateBrowserView: View {
    let reader: any DiscoveryReading
    let authoringFactory: ((DiscoveryPlayTemplate) -> TemplateAuthoringCoordinator)?
    let authoringRevision: UInt64
    @State private var tab = Shelf.topics
    @State private var categoryID: Int?
    @State private var pack: DiscoveryPackType?
    @State private var keyword = ""
    @State private var appliedKeyword = ""
    @StateObject private var topics = DiscoveryLoader<[DiscoveryTopicTemplate]>()
    @StateObject private var games = DiscoveryLoader<[DiscoveryPlayTemplate]>()
    @StateObject private var home = DiscoveryLoader<DiscoveryTemplateHome>()

    private enum Shelf: String, CaseIterable { case topics, games }
    private struct Query: Equatable {
        let tab: Shelf
        let pack: DiscoveryPackType?
        let keyword: String
    }
    private var query: Query { Query(tab: tab, pack: pack, keyword: appliedKeyword) }
    private var hasGameFilter: Bool { pack != nil || !appliedKeyword.isEmpty }

    init(reader: any DiscoveryReading, authoringFactory: ((DiscoveryPlayTemplate) -> TemplateAuthoringCoordinator)? = nil, authoringRevision: UInt64 = 0) {
        self.reader = reader; self.authoringFactory = authoringFactory; self.authoringRevision = authoringRevision
    }

    var body: some View {
        Group {
            if !reader.isConfigured {
                ContentUnavailableView("discovery.unavailable", systemImage: "network.slash", description: Text("auth.notConfigured"))
            } else {
                List {
                    Section {
                        Picker("discovery.shelf", selection: $tab) {
                            Text("discovery.topics").tag(Shelf.topics)
                            Text("discovery.games").tag(Shelf.games)
                        }.pickerStyle(.segmented).accessibilityIdentifier("discovery.shelf")
                    }
                    if tab == .topics { topicShelf }
                    else { gameShelf }
                }.refreshable { await reloadCurrent() }
            }
        }
        .appNavigationTitle("discovery.browseTemplates")
        .task {
            guard reader.isConfigured, home.value == nil else { return }
            await loadHome()
        }
        .task(id: query) {
            guard reader.isConfigured else { return }
            if tab == .topics {
                if topics.value == nil { await loadTopics() }
            } else if hasGameFilter {
                await loadGames()
            }
        }
    }

    @ViewBuilder private var topicShelf: some View {
        if let categories = home.value?.categories, !categories.isEmpty {
            Section {
                Picker("discovery.category", selection: $categoryID) {
                    Text("discovery.recommended").tag(Optional<Int>.none)
                    ForEach(categories) { category in
                        Text(category.name).tag(Optional(category.id))
                    }
                }.accessibilityIdentifier("discovery.topicCategory")
            }
        }
        if let error = topics.error {
            DiscoveryErrorView(error: error) { Task { await loadTopics() } }
        }
        if topics.isLoading { ProgressView("discovery.loading") }
        if let rows = topics.value {
            if rows.isEmpty {
                ContentUnavailableView("discovery.emptyTopics", systemImage: "map", description: Text("discovery.emptyTopicsHint"))
            } else {
                let matching = rows.filter { $0.matchesCategory(categoryID) }
                let other = rows.filter { !$0.matchesCategory(categoryID) }
                topicSection(categoryID == nil ? "discovery.recommended" : "discovery.categoryMatches", rows: matching)
                topicSection("discovery.otherTemplates", rows: other)
            }
        }
        // Optional category loading must never replace a successful topic shelf with an error screen.
        if home.error != nil {
            Section {
                Text("discovery.categoriesUnavailable").font(.caption).foregroundStyle(.secondary)
                Button("action.retry") { Task { await loadHome() } }
            }
        }
    }

    @ViewBuilder private var gameShelf: some View {
        Section {
            Picker("discovery.pack", selection: $pack) {
                Text("discovery.allPacks").tag(Optional<DiscoveryPackType>.none)
                ForEach(DiscoveryPackType.allCases, id: \.rawValue) { item in
                    Text(item.label).tag(Optional(item))
                }
            }.accessibilityIdentifier("discovery.packFilter")
            HStack {
                TextField("discovery.search", text: $keyword)
                    .submitLabel(.search)
                    .onSubmit { applySearch() }
                    .accessibilityIdentifier("discovery.search")
                Button("discovery.searchAction") { applySearch() }
            }
            if hasGameFilter {
                Button("discovery.clearFilters") {
                    keyword = ""; appliedKeyword = ""; pack = nil
                }
            }
        }
        if hasGameFilter {
            if games.isLoading { ProgressView("discovery.loading") }
            if let error = games.error {
                DiscoveryErrorView(error: error) { Task { await loadGames() } }
            }
            if let rows = games.value {
                if rows.isEmpty { ContentUnavailableView("discovery.noResults", systemImage: "magnifyingglass") }
                else { gameSection("discovery.searchResults", rows: rows) }
            }
        } else {
            if home.isLoading { ProgressView("discovery.loading") }
            if let error = home.error {
                DiscoveryErrorView(error: error) { Task { await loadHome() } }
            }
            if let value = home.value {
                if value.isEmpty { ContentUnavailableView("discovery.emptyGames", systemImage: "sparkles.rectangle.stack") }
                gameSection("discovery.featured", rows: value.banner)
                gameSection("discovery.latest", rows: value.latest)
                gameSection("discovery.recommended", rows: value.recommended)
                gameSection("discovery.mustPlay", rows: value.mustPlay)
                gameSection("discovery.hot", rows: value.hot)
            }
        }
    }
    @ViewBuilder private func topicSection(_ title: LocalizedStringKey, rows: [DiscoveryTopicTemplate]) -> some View {
        if !rows.isEmpty {
            Section(title) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, item in
                    NavigationLink {
                        DiscoveryTopicTemplatePreview(item: item)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            DiscoveryTitle(text: item.name, fallback: "discovery.untitledTopic").font(.headline)
                            if !item.subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(item.subtitle).font(.subheadline)
                            }
                            DiscoveryTopicMetadata(item: item)
                        }.padding(.vertical, 6)
                    }.accessibilityIdentifier("discovery.topic.\(item.id)")
                }
            }
        }
    }
    @ViewBuilder private func gameSection(_ title: LocalizedStringKey, rows: [DiscoveryPlayTemplate]) -> some View {
        if !rows.isEmpty {
            Section(title) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, item in
                    NavigationLink {
                        DiscoveryTemplateDetailView(id: item.id, reader: reader, authoringFactory: authoringFactory, authoringRevision: authoringRevision)
                    } label: { DiscoveryPlayRow(item: item) }
                    .accessibilityIdentifier("discovery.play.\(item.id)")
                }
            }
        }
    }
    private func applySearch() {
        appliedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private func loadHome() async { await home.load { try await reader.discoveryTemplateHome() } }
    private func loadTopics() async { await topics.load { try await reader.discoveryTopicTemplates() } }
    private func loadGames() async {
        let requestedKeyword = appliedKeyword
        let requestedPack = pack
        await games.load { try await reader.discoveryPlayTemplates(keyword: requestedKeyword, packType: requestedPack) }
    }
    private func reloadCurrent() async {
        if tab == .topics {
            async let a: Void = loadTopics()
            async let b: Void = loadHome()
            _ = await (a, b)
        } else if hasGameFilter { await loadGames() }
        else { await loadHome() }
    }
}
