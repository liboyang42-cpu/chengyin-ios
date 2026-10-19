import SwiftUI

/// Embed in the root's NavigationStack or present through DiscoveryHomeView.
@MainActor
struct DiscoveryTemplateBrowserView: View {
    let reader: any DiscoveryReading
    let authoringFactory: ((DiscoveryPlayTemplate) -> TemplateAuthoringCoordinator)?
    let authoringRevision: UInt64
    let authoringCompletion: TemplateAuthoringCompletionContext?
    let imageReader: (any RetainedPublicImageReading)?
    /// Mini-program merchant scope; staff without project management only browse.
    let templateTabScope: TemplateTabScope
    @State private var tab = Shelf.topics
    @State private var categoryID: Int?
    @State private var pack: DiscoveryPackType?
    @State private var keyword = ""
    @State private var appliedKeyword = ""
    @State private var topicKeyword = ""
    @FocusState private var topicSearchFocused: Bool
    @State private var appliedTopicSearch = DiscoveryTopicTemplateNameSearch("")
    @StateObject private var topics = PublicTemplateCatalogVisitOwner()
    @State private var topicSelection: PublicTemplateCatalogSelection?
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

    init(reader: any DiscoveryReading, authoringFactory: ((DiscoveryPlayTemplate) -> TemplateAuthoringCoordinator)? = nil, authoringRevision: UInt64 = 0, imageReader: (any RetainedPublicImageReading)? = nil, authoringCompletion: TemplateAuthoringCompletionContext? = nil, templateTabScope: TemplateTabScope = .consumer) {
        self.reader = reader; self.authoringFactory = authoringFactory; self.authoringRevision = authoringRevision
        self.imageReader = imageReader; self.authoringCompletion = authoringCompletion; self.templateTabScope = templateTabScope
    }

    var body: some View {
        Group {
            if !reader.isConfigured {
                ContentUnavailableView("discovery.unavailable", systemImage: "network.slash", description: Text("auth.notConfigured"))
            } else {
                List {
                    if templateTabScope == .merchant(canManageProjects: false) {
                        Section {
                            Text("discovery.templateTab.staffReadOnly").font(.footnote)
                                .accessibilityIdentifier("discovery.templateTab.staffReadOnly")
                        }
                    }
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
            if tab == .games && hasGameFilter { await loadGames() }
        }
        .onAppear {
            if let visit = topics.appear(reader: reader), tab == .topics, topicSelection == nil {
                Task { await topics.load(reader: reader, visit: visit) }
            }
        }
        .onDisappear { topics.disappear() }
        .onChange(of: tab) { _, next in
            if next == .topics { scheduleTopicReload() }
            else { topics.cancelPending() }
        }
        .onReceive(reader.discoveryPresentationChanges) { _ in
            // AppSession publishes before mutating its identity.
            Task { @MainActor in
                await Task.yield()
                if topics.synchronize(reader: reader) {
                    topicSelection = nil
                    if tab == .topics { scheduleTopicReload() }
                }
            }
        }
        .navigationDestination(isPresented: topicDetailBinding) {
            if let selected = topicSelection,
               selected.identity == reader.discoveryPresentationIdentity {
                DiscoveryTopicTemplatePreview(coordinator: selected.coordinator).id(selected.id)
            } else { Text("social.changed") }
        }
    }

    private var topicDetailBinding: Binding<Bool> {
        let selectedID = topicSelection?.id
        return Binding(get: { topicSelection != nil }, set: { presented in
            guard !presented, let selectedID, topicSelection?.id == selectedID else { return }
            topicSelection = nil
            topics.uncover()
            // A retained parent may not receive another onAppear.
            if tab == .topics { scheduleTopicReload() }
        })
    }
    private func scheduleTopicReload() {
        let visit = topics.visit
        Task { await topics.load(reader: reader, visit: visit) }
    }

    @ViewBuilder private var topicShelf: some View {
        Section {
            HStack {
                TextField("discovery.topicNameSearch", text: $topicKeyword)
                    .focused($topicSearchFocused)
                    .submitLabel(.search)
                    .onSubmit { applyTopicSearch() }
                    .accessibilityIdentifier("discovery.topicNameSearch")
                Button("discovery.searchAction") { applyTopicSearch() }
                    .accessibilityIdentifier("discovery.topicNameSearch.submit")
            }
            Text("discovery.topicNameSearchScope").font(.caption).foregroundStyle(.secondary)
            if appliedTopicSearch.isActive {
                Text(verbatim: appliedTopicSearch.keyword)
                    .accessibilityIdentifier("discovery.topicNameSearch.applied")
                Button("discovery.clearTopicNameSearch") {
                    topicKeyword = ""; appliedTopicSearch = DiscoveryTopicTemplateNameSearch("")
                    topicSearchFocused = false
                }.accessibilityIdentifier("discovery.topicNameSearch.clear")
            }
        }
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
                let filtered = appliedTopicSearch.filter(rows)
                if filtered.isEmpty {
                    ContentUnavailableView("discovery.noResults", systemImage: "magnifyingglass",
                                           description: Text("discovery.topicNameSearchScope"))
                        .accessibilityIdentifier("discovery.topicNameSearch.noResults")
                } else {
                    let matching = filtered.filter { $0.matchesCategory(categoryID) }
                    let other = filtered.filter { !$0.matchesCategory(categoryID) }
                    topicSection(categoryID == nil ? "discovery.recommended" : "discovery.categoryMatches", rows: matching)
                    topicSection("discovery.otherTemplates", rows: other)
                }
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
                    Button {
                        guard topicSelection == nil, topics.canOpen(reader: reader),
                              topics.value?.contains(where: { $0.id == item.id }) == true else { return }
                        topicSelection = .init(identity: reader.discoveryPresentationIdentity,
                            coordinator: reader.publicTopicTemplateCoordinator(id: item.id))
                        topics.cover()
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            DiscoveryTitle(text: item.name, fallback: "discovery.untitledTopic").font(.headline)
                            if !item.subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(item.subtitle).font(.subheadline)
                            }
                            DiscoveryTopicMetadata(item: item)
                        }.padding(.vertical, 6)
                    }.disabled(!topics.canOpen(reader: reader))
                        .accessibilityIdentifier("discovery.topic.\(item.id)")
                }
            }
        }
    }
    @ViewBuilder private func gameSection(_ title: LocalizedStringKey, rows: [DiscoveryPlayTemplate]) -> some View {
        if !rows.isEmpty {
            Section(title) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, item in
                    NavigationLink {
                        DiscoveryTemplateDetailView(id: item.id, reader: reader, authoringFactory: TemplateTabPolicy.refusal(for: .configure, previewOnly: false, scope: templateTabScope) == nil ? authoringFactory : nil, authoringRevision: authoringRevision, imageReader: imageReader, authoringCompletion: authoringCompletion)
                    } label: { DiscoveryPlayRow(item: item) }
                    .accessibilityIdentifier("discovery.play.\(item.id)")
                }
            }
        }
    }
    private func applyTopicSearch() {
        appliedTopicSearch = DiscoveryTopicTemplateNameSearch(topicKeyword)
        topicSearchFocused = false
    }
    private func applySearch() {
        appliedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private func loadHome() async { await home.load { try await reader.discoveryTemplateHome() } }
    private func loadTopics() async {
        await topics.load(reader: reader, visit: topics.visit)
    }
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


@MainActor private struct PublicTemplateCatalogSelection {
    let id = UUID()
    let identity: String
    let coordinator: PublicTopicTemplateCoordinator
}

/// One visible catalog visit owns accepted rows and any deferred unauthorized effect.
/// Hiding cancels acceptance, not the rows that still anchor a navigation transition.
@MainActor final class PublicTemplateCatalogVisitOwner: ObservableObject {
    @Published private(set) var value: [DiscoveryTopicTemplate]?
    @Published private(set) var error: Error?
    @Published private(set) var isLoading = false
    private(set) var visit = UUID()
    private(set) var visible = false
    private var covered = false
    private var readerID: ObjectIdentifier?
    private var identity: String?
    private var operation: UUID?

    @discardableResult func synchronize(reader: any DiscoveryReading) -> Bool {
        let next = reader.discoveryPresentationIdentity
        guard readerID != ObjectIdentifier(reader) || identity != next else { return false }
        cancelPending(); visit = UUID(); value = nil; error = nil; covered = false
        readerID = ObjectIdentifier(reader); identity = next
        return true
    }
    func appear(reader: any DiscoveryReading) -> UUID? {
        let changed = synchronize(reader: reader)
        guard !visible || changed else { return nil }
        visible = true; visit = UUID(); return visit
    }
    func disappear() { visible = false; visit = UUID(); cancelPending() }
    func cover() { covered = true; visit = UUID(); cancelPending() }
    func uncover() { covered = false; visit = UUID(); cancelPending() }
    func cancelPending() { visit = UUID(); operation = nil; isLoading = false }
    func canOpen(reader: any DiscoveryReading) -> Bool {
        visible && !covered && !isLoading && error == nil && value != nil && matches(reader)
    }
    private func matches(_ reader: any DiscoveryReading) -> Bool {
        readerID == ObjectIdentifier(reader) && identity == reader.discoveryPresentationIdentity && reader.isConfigured
    }
    func load(reader: any DiscoveryReading, visit expectedVisit: UUID) async {
        guard visible, !covered, visit == expectedVisit, matches(reader), operation == nil else { return }
        let request = reader.publicTopicTemplateCatalogRequest(), run = UUID()
        operation = run; isLoading = true; error = nil
        func current() -> Bool {
            !Task.isCancelled && visible && !covered && visit == expectedVisit && operation == run && matches(reader)
        }
        defer { if operation == run { operation = nil; isLoading = false } }
        do {
            let rows = try await request.read()
            guard current() else { return }
            value = rows
        } catch is CancellationError { }
        catch {
            guard current() else { return }
            self.error = error
            if error as? APIError == .unauthorized { request.onUnauthorized() }
        }
    }
}
