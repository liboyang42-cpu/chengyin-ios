import SwiftUI

@MainActor struct GlobalSearchView<Destination: View>: View {
    let reader: any SearchMapReading
    var historyNamespace: String? = nil
    var onSignIn: (() -> Void)? = nil
    let destination: (SearchMapDestination) -> Destination
    @State private var filter = GlobalSearchQuery()
    @State private var categories: [DiscoveryCategory] = []
    @State private var categoryFailed = false
    @State private var result: GlobalSearchResults?
    @State private var issue: String?
    @State private var loading = false
    @State private var activeQuery: GlobalSearchQuery?
    @State private var selectedKind: GlobalSearchKind?
    @State private var showsFilters = false
    @State private var history: [String] = []
    @State private var historyFailure = false
    @State private var gate = SearchMapQueryGate()
    @State private var categoryGate = SearchMapQueryGate()
    @State private var preparedScope: UUID?
    private let historyStore = SearchMapLocalHistory()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if historyFailure { Text("searchMap.historyUnavailable").font(.caption).foregroundStyle(.secondary) }
                if reader.isOfflineExample { Text("searchMap.offline").font(.caption).foregroundStyle(.secondary) }
                HStack {
                    TextField("searchMap.placeholder", text: $filter.keyword).textInputAutocapitalization(.never)
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
                if !reader.isConfigured { SearchMapIssue(key: "searchMap.notConfigured") }
                else if loading { ProgressView("searchMap.loading").frame(maxWidth: .infinity) }
                else if let issue { SearchMapIssue(key: issue) { Task { await search() } } }
                else if let result { results(result) }
                else { suggestions }
            }.padding()
        }
        .appNavigationTitle("searchMap.title")
        .sheet(isPresented: $showsFilters) {
            SearchMapFilterSheet(filter: filter, categories: categories, categoryFailed: categoryFailed) { next in
                filter = next; invalidate(); Task { await search() }
            }
        }
        .task(id: reader.scope) { await prepare() }
        .onChange(of: filter.keyword) { _, keyword in if activeQuery?.keyword != keyword { invalidate() } }
        .onDisappear { gate.invalidate(); categoryGate.invalidate(); loading = false }
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
                Button { filter.keyword = keyword; Task { await search() } } label: { Label(keyword, systemImage: "clock") }
                    .frame(minHeight: 44)
            }
        }
        Text("searchMap.categories").font(.headline)
        if categoryFailed { SearchMapIssue(key: "searchMap.categoryFailed") { Task { await prepare(force: true) } } }
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 125))], spacing: 12) {
            ForEach(categories) { category in
                Button { filter.categoryID = category.id; Task { await search() } } label: {
                    Text(verbatim: category.name).frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.bordered).accessibilityIdentifier("searchMap.category.\(category.id)")
            }
        }
    }
    @ViewBuilder private func results(_ value: GlobalSearchResults) -> some View {
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
        if visible.isEmpty && !value.allFailed { ContentUnavailableView("searchMap.empty", systemImage: "magnifyingglass", description: Text("searchMap.emptyHint")) }
        ForEach(visible) { row in
            NavigationLink { destination(row.destination) } label: { SearchMapCard(row: row, offline: reader.isOfflineExample) }
                .buttonStyle(QuestifyCardButtonStyle()).accessibilityIdentifier("searchMap.result.\(row.id)")
        }
        Text("searchMap.pageLimit").font(.caption).foregroundStyle(.secondary)
    }
    private func invalidate() { gate.invalidate(); activeQuery = nil; result = nil; issue = nil; loading = false }
    private func prepare(force: Bool = false) async {
        if preparedScope != reader.scope {
            preparedScope = reader.scope; invalidate(); categories = []; categoryFailed = false
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
        guard reader.isConfigured, query.canSearch else { return }
        let ticket = gate.begin(scope: reader.scope)
        activeQuery = query
        loading = true; result = nil; issue = nil
        defer { if gate.accepts(ticket, scope: reader.scope) { loading = false } }
        do {
            let value = try await reader.search(query)
            guard gate.accepts(ticket, scope: reader.scope), filter == query else { return }
            result = value
            history = historyStore.add(query.keyword, namespace: historyNamespace, current: history); historyFailure = historyStore.failed
        } catch {
            guard gate.accepts(ticket, scope: reader.scope), filter == query else { return }
            issue = SearchMapIssue.key(error)
        }
    }
}
