import SwiftUI

@MainActor struct GlobalSearchView<Destination: View>: View {
    @Environment(\.scenePhase) private var scenePhase
    let reader: any SearchMapReading
    var historyNamespace: String? = nil
    var publicMerchant = PublicMerchantHomeContext()
    var onSignIn: (() -> Void)? = nil
    var recommendedKeywords: [String] = []
    let destination: (SearchMapDestination) -> Destination
    @State private var filter = GlobalSearchQuery()
    @State private var categoryRecovery = SearchMapCategoryRecovery()
    @State private var categoryPresentationID = UUID()
    @State private var filterPresentationID = UUID()
    @State private var filterSheetVisible = false
    @State private var retainedResults = GlobalSearchRetainedResults()
    @State private var isVisible = false
    @State private var issue: String?
    @State private var loading = false
    @State private var selectedKind: GlobalSearchKind?
    @State private var showsFilters = false
    @State private var history: [String] = []
    @State private var historyFailure = false
    @State private var preparedOwner: ReadOwner?
    private let historyStore = SearchMapLocalHistory()

    private struct ReadOwner: Equatable {
        let readerID: ObjectIdentifier
        let scope: UUID
        let authenticated: Bool
        let configured: Bool
    }
    private var readOwner: ReadOwner {
        .init(readerID: ObjectIdentifier(reader), scope: reader.scope,
              authenticated: reader.isAuthenticated, configured: reader.isConfigured)
    }
    private var resultContext: GlobalSearchResultContext {
        .init(readerID: ObjectIdentifier(reader), scope: reader.scope, isAuthenticated: reader.isAuthenticated,
              isConfigured: reader.isConfigured, query: filter)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if historyFailure { Text("searchMap.historyUnavailable").font(.caption).foregroundStyle(.secondary) }
                if reader.isOfflineExample { Text("searchMap.offline").font(.caption).foregroundStyle(.secondary) }
                HStack {
                    TextField("searchMap.placeholder", text: Binding(get: { filter.keyword }, set: setKeyword)).textInputAutocapitalization(.never)
                        .submitLabel(.search).onSubmit { Task { await search() } }
                        .accessibilityIdentifier("searchMap.keyword")
                    Button { openFilters() } label: { Label("searchMap.filters", systemImage: "line.3.horizontal.decrease") }
                        .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("searchMap.filters")
                }.padding(12).background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                Button("searchMap.search") { Task { await search() } }
                    .buttonStyle(.borderedProminent).frame(minHeight: 44).disabled(!reader.isConfigured || !filter.canSearch)
                    .accessibilityIdentifier("searchMap.submit")
                HStack {
                    NavigationLink { SearchMapExplorerView(reader: reader, mode: .city, initialFilter: filter, onSignIn: onSignIn, destination: destination) } label: { Label("searchMap.citySearch", systemImage: "mappin.and.ellipse") }
                    NavigationLink { SearchMapExplorerView(reader: reader, mode: .nearby, onSignIn: onSignIn, destination: destination) } label: { Label("searchMap.nearby", systemImage: "map") }
                }.buttonStyle(.bordered).frame(minHeight: 44)
                NavigationLink {
                    MerchantDiscoverView(reader: reader, publicMerchant: publicMerchant)
                } label: { Label("merchant.discover.title", systemImage: "storefront") }
                    .frame(minHeight: 44).accessibilityIdentifier("merchant.discover.entry")
                if !reader.isConfigured { SearchMapIssue(key: "searchMap.notConfigured") }
                else {
                    if loading { ProgressView("searchMap.loading").frame(maxWidth: .infinity).accessibilityIdentifier("searchMap.loading") }
                    if let issue { SearchMapIssue(key: issue) { Task { await search() } } }
                    if let snapshot = retainedResults.snapshot(in: resultContext) {
                        results(snapshot.results, retainedKinds: snapshot.retainedKinds)
                    } else if !loading && issue == nil { suggestions }
                }
            }.padding()
        }
        .appNavigationTitle("searchMap.title")
        .sheet(isPresented: $showsFilters) {
            let presentationID = filterPresentationID
            let context = categoryRecovery.context(for: categoryOwner)
            let applyContext = categoryRecovery.presentationContext(for: categoryOwner)
            SearchMapFilterSheet(filter: filter, categories: categories, categoryFailed: categoryFailed,
                                 categoryLoading: categoryLoading, categoryLoaded: categoryLoaded,
                                 retryCategories: context.map { captured in {
                                     guard showsFilters, filterSheetVisible, presentationID == filterPresentationID else { return }
                                     _ = categoryRecovery.retry(in: captured)
                                 } }) { next in
                guard showsFilters, filterSheetVisible, presentationID == filterPresentationID,
                      let applyContext, categoryRecovery.acceptsPresentation(applyContext) else { return }
                applyFilter(next)
            }
            .onAppear {
                guard showsFilters, presentationID == filterPresentationID, categoryRecovery.owns(categoryOwner) else { return }
                filterSheetVisible = true; updateCategoryPresentation()
            }
            .onDisappear {
                guard presentationID == filterPresentationID, categoryRecovery.owns(categoryOwner) else { return }
                filterSheetVisible = false; updateCategoryPresentation()
            }
        }
        .task(id: readOwner) { await prepare() }
        .onChange(of: categoryOwner) { _, _ in updateCategoryPresentation() }
        .onChange(of: scenePhase) { _, _ in updateCategoryPresentation() }
        .onChange(of: showsFilters) { _, visible in
            if !visible { filterSheetVisible = false }
            updateCategoryPresentation()
        }
        .onAppear { isVisible = true; categoryPresentationID = UUID(); updateCategoryPresentation() }
        .onDisappear {
            isVisible = false; retainedResults.cancelPending(); loading = false
            categoryRecovery.update(reader: reader, presentationID: nil, active: false)
        }
    }
    private var categoryOwner: SearchMapCategoryRecovery.Owner { .init(reader: reader) }
    private var categories: [DiscoveryCategory] { categoryRecovery.owns(categoryOwner) ? categoryRecovery.categories : [] }
    private var categoryFailed: Bool { categoryRecovery.owns(categoryOwner) && categoryRecovery.phase == .failed }
    private var categoryLoading: Bool { categoryRecovery.owns(categoryOwner) && categoryRecovery.phase == .loading }
    private var categoryLoaded: Bool { categoryRecovery.owns(categoryOwner) && categoryRecovery.phase == .loaded }
    private func openFilters() {
        filterPresentationID = UUID(); filterSheetVisible = false; showsFilters = true
        updateCategoryPresentation()
    }
    private func updateCategoryPresentation() {
        // The page and sheet share the directory, never a draft or search request.
        // Switching surfaces retires callbacks; a settled directory survives reopening.
        let presentationID = showsFilters ? (filterSheetVisible ? filterPresentationID : nil) : categoryPresentationID
        categoryRecovery.update(reader: reader, presentationID: presentationID,
                                active: isVisible && scenePhase == .active)
        if let context = categoryRecovery.context(for: categoryOwner) {
            categoryRecovery.loadIfNeeded(in: context)
        }
    }
    @ViewBuilder private var suggestions: some View {
        let context = categoryRecovery.context(for: categoryOwner)
        if !history.isEmpty {
            HStack {
                Text("searchMap.history").font(.headline)
                Spacer()
                Button("searchMap.clearHistory") { if historyStore.clear(namespace: historyNamespace) { history = [] }; historyFailure = historyStore.failed }
                    .frame(minHeight: 44).accessibilityIdentifier("searchMap.clearHistory")
            }
            ForEach(history, id: \.self) { keyword in
                Button { setKeyword(keyword); Task { await search() } } label: { Label(keyword, systemImage: "clock") }
                    .frame(minHeight: 44)
            }
        }
        if !recommendedKeywords.isEmpty {
            Text("searchMap.recommended").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88))], spacing: 8) {
                ForEach(Array(recommendedKeywords.enumerated()), id: \.offset) { index, keyword in
                    Button { setKeyword(keyword); Task { await search() } } label: {
                        Text(verbatim: keyword).frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.bordered).disabled(!reader.isConfigured)
                        .accessibilityIdentifier("searchMap.recommended.\(index)")
                }
            }
        }
        Text("searchMap.categories").font(.headline)
        if categoryLoading {
            ProgressView("searchMap.loading").accessibilityIdentifier("globalSearch.category.loading")
        } else if categoryFailed {
            SearchMapIssue(key: "searchMap.categoryFailed") {
                guard !showsFilters, let context else { return }
                _ = categoryRecovery.retry(in: context)
            }
        }
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 125))], spacing: 12) {
            ForEach(categories) { category in
                Button {
                    guard !showsFilters, let context, categoryRecovery.accepts(context) else { return }
                    var next = filter; next.categoryID = category.id; applyFilter(next)
                } label: {
                    Text(verbatim: category.name).frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.bordered).accessibilityIdentifier("searchMap.category.\(category.id)")
            }
        }
    }
    @ViewBuilder private func results(_ value: GlobalSearchResults, retainedKinds: [GlobalSearchKind]) -> some View {
        if loading && !value.rows.isEmpty {
            Text("globalSearchRetention.refreshing").font(.footnote).foregroundStyle(.secondary)
                .accessibilityIdentifier("globalSearchRetention.refreshing")
        }
        if !retainedKinds.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("globalSearchRetention.stale")
                ForEach(retainedKinds, id: \.self) { kind in Label(kind.titleKey, systemImage: "clock.arrow.circlepath") }
            }.font(.footnote).accessibilityIdentifier("globalSearchRetention.stale")
        }
        if !value.gatedKinds.isEmpty {
            Label("searchMap.partialSignIn", systemImage: "lock").font(.footnote)
                .accessibilityIdentifier("searchMap.guestGate")
            if let onSignIn { Button("searchMap.signIn", action: onSignIn).frame(minHeight: 44) }
        }
        if !value.failedKinds.isEmpty {
            VStack(alignment: .leading) {
                Text(LocalizedStringKey(value.allFailed ? "searchMap.allFailed" : "searchMap.partialFailure"))
                ForEach(value.failedKinds, id: \.self) { kind in Label(kind.titleKey, systemImage: "exclamationmark.circle") }
                Button("searchMap.retry") { Task { await search() } }.frame(minHeight: 44)
            }.font(.footnote).accessibilityIdentifier("searchMap.partialFailure")
        }
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                Button("searchMap.all") { selectedKind = nil }.buttonStyle(.bordered)
                ForEach(GlobalSearchKind.allCases, id: \.self) { kind in
                    Button { selectedKind = kind } label: { Text(kind.titleKey) + Text(verbatim: " \(value.count(kind))") }
                        .buttonStyle(.bordered).accessibilityAddTraits(selectedKind == kind ? [.isSelected] : [])
                        .accessibilityIdentifier("searchMap.kind.\(kind.rawValue)")
                }
            }.frame(minHeight: 44)
        }
        let visible = value.rows.filter { selectedKind == nil || $0.kind == selectedKind }
        if visible.isEmpty && !loading && !value.allFailed && value.failedKinds.isEmpty && value.gatedKinds.isEmpty { ContentUnavailableView("searchMap.empty", systemImage: "magnifyingglass", description: Text("searchMap.emptyHint")) }
        ForEach(visible) { row in
            NavigationLink { destination(row.destination) } label: { SearchMapCard(row: row, offline: reader.isOfflineExample) }
                .buttonStyle(QuestifyCardButtonStyle()).accessibilityIdentifier("searchMap.result.\(row.id)")
        }
        Text("searchMap.pageLimit").font(.caption).foregroundStyle(.secondary)
    }
    private func applyFilter(_ next: GlobalSearchQuery) {
        // Invalidate synchronously, including category-only searches cleared to an empty query.
        filter = next; invalidate(); Task { await search() }
    }
    private func setKeyword(_ value: String) {
        guard !filter.keyword.utf8.elementsEqual(value.utf8) else { return }
        invalidate(); filter.keyword = value
    }
    private func invalidate() { retainedResults.invalidate(); issue = nil; loading = false; selectedKind = nil }
    private func prepare() async {
        guard !Task.isCancelled else { return }
        if preparedOwner != readOwner {
            preparedOwner = readOwner; invalidate()
            history = historyStore.read(namespace: historyNamespace); historyFailure = historyStore.failed
        }
        updateCategoryPresentation()
    }
    private func search() async {
        let query = filter
        guard isVisible else { return }
        guard reader.isConfigured, query.canSearch else { return }
        let captured = resultContext
        let ticket = retainedResults.begin(in: captured)
        loading = true; issue = nil
        do {
            let value = try await reader.search(query)
            guard !Task.isCancelled, isVisible, filter == query, retainedResults.accepts(ticket, in: resultContext) else { return }
            loading = false
            retainedResults.finish(value, ticket: ticket, in: resultContext)
            history = historyStore.add(query.keyword, namespace: historyNamespace, current: history); historyFailure = historyStore.failed
        } catch {
            guard isVisible, retainedResults.accepts(ticket, in: resultContext) else { return }
            loading = false
            retainedResults.fail(ticket, in: resultContext)
            if !(error is CancellationError) { issue = SearchMapIssue.key(error) }
        }
    }
}
