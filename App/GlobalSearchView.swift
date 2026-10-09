import SwiftUI

@MainActor struct GlobalSearchView<Destination: View>: View {
    let reader: any SearchMapReading
    var historyNamespace: String? = nil
    var publicMerchant = PublicMerchantHomeContext()
    var onSignIn: (() -> Void)? = nil
    let destination: (SearchMapDestination) -> Destination
    @State private var filter = GlobalSearchQuery()
    @State private var categories: [DiscoveryCategory] = []
    @State private var categoryFailed = false
    @State private var retainedResults = GlobalSearchRetainedResults()
    @State private var isVisible = false
    @State private var issue: String?
    @State private var loading = false
    @State private var selectedKind: GlobalSearchKind?
    @State private var showsFilters = false
    @State private var history: [String] = []
    @State private var historyFailure = false
    @State private var categoryGate = SearchMapQueryGate()
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
                    Button { showsFilters = true } label: { Label("searchMap.filters", systemImage: "line.3.horizontal.decrease") }
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
            SearchMapFilterSheet(filter: filter, categories: categories, categoryFailed: categoryFailed) { next in
                applyFilter(next)
            }
        }
        .task(id: readOwner) { await prepare() }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false; retainedResults.cancelPending(); categoryGate.invalidate(); loading = false }
    }
    @ViewBuilder private var suggestions: some View {
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
        Text("searchMap.categories").font(.headline)
        if categoryFailed { SearchMapIssue(key: "searchMap.categoryFailed") { Task { await prepare(force: true) } } }
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 125))], spacing: 12) {
            ForEach(categories) { category in
                Button {
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
    private func prepare(force: Bool = false) async {
        if preparedOwner != readOwner {
            preparedOwner = readOwner; invalidate(); categories = []; categoryFailed = false
            history = historyStore.read(namespace: historyNamespace); historyFailure = historyStore.failed
        }
        guard reader.isConfigured, force || categories.isEmpty else { return }
        let ticket = categoryGate.begin(scope: reader.scope)
        do {
            let value = try await reader.categories()
            guard categoryGate.accepts(ticket, scope: reader.scope) else { return }; categories = value; categoryFailed = false
        } catch {
            guard categoryGate.accepts(ticket, scope: reader.scope) else { return }; categoryFailed = true
        }
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
