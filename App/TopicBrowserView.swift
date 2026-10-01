import SwiftUI

/// Host must observe its session and refresh this subtree when account/epoch/token changes.
/// `scope` prevents old personalized content from rendering during the replacement task.
@MainActor
struct TopicBrowserView: View {
    let reader: any TopicReading
    var onClose:(()->Void)? = nil
    var categoryID: String? = nil
    var pageSize: Int = 10
    @State private var keyword = ""
    @State private var recommend = false
    @State private var pagination = TopicPagination()
    @State private var loadedKey: Key?
    @State private var loading = false
    @State private var issue: TopicScreenIssue?
    @State private var generation = 0
    private struct Key: Hashable { let scope: UUID; let query: TopicQuery; let configured: Bool }
    private var key: Key {
        Key(scope: reader.scope, query: TopicQuery(keyword: keyword.isEmpty ? nil : keyword, categoryID: categoryID, recommend: recommend, pageSize: pageSize), configured: reader.isConfigured)
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    if reader.isOfflineExample { Text("topic.offlineExample").font(.caption) }
                    Toggle("topic.recommended", isOn: $recommend)
                }
                if !reader.isConfigured { TopicIssueView(issue: .notConfigured) }
                else if loadedKey != key { ProgressView("topic.loading") }
                else {
                    if let issue { TopicIssueView(issue: issue) { Task { await load(reset: pagination.rows.isEmpty) } } }
                    if pagination.rows.isEmpty && !loading && issue == nil { Text("topic.empty") }
                    ForEach(pagination.rows) { item in
                        NavigationLink {
                            TopicDetailView(id: item.id, reader: reader)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(verbatim: item.name).font(.headline)
                                if item.betaFlag == 1 { Text("topic.beta").font(.caption) }
                                if let intro = item.introduction { Text(verbatim: intro).lineLimit(3).foregroundStyle(.secondary) }
                                if let address = item.addressName { Label { Text(verbatim: address) } icon: { Image(systemName: "mappin") } }
                                if let date = item.startDate { Text(verbatim: date).font(.caption) }
                                TopicPrice(value: item.minimumAmount, label: "topic.startingPrice")
                            }
                        }.accessibilityIdentifier("topic.row.\(item.id)")
                    }
                    if loading { ProgressView("topic.loading") }
                    else if pagination.hasMore && issue == nil {
                        Button("topic.loadMore") { Task { await load(reset: false) } }
                            .accessibilityIdentifier("topic.loadMore")
                    }
                }
                Section { Text("topic.readOnly").font(.footnote).foregroundStyle(.secondary) }
            }
            .appNavigationTitle("topic.title")
            .toolbar { if let onClose { ToolbarItem(placement:.cancellationAction) { Button("action.close",action:onClose) } } }
            .searchable(text: $keyword, prompt: "topic.search")
            .task(id: key) { await load(reset: true) }
            .refreshable { await load(reset: true) }
            .onDisappear { generation += 1; loading = false }
            .accessibilityIdentifier("topic.browser")
        }
    }
    private func load(reset: Bool) async {
        if !reset && loading { return }
        generation += 1
        let operation = generation, captured = key
        if reset { pagination.reset(); loadedKey = nil }
        issue = nil
        guard reader.isConfigured else { loading = false; return }
        loading = true
        defer { if operation == generation { loading = false } }
        let page = reset ? 1 : pagination.nextPage
        do {
            let result = try await reader.topicList(query: captured.query, pageNumber: page)
            try Task.checkCancellation()
            guard operation == generation, captured == key else { return }
            try pagination.accept(result); loadedKey = captured
        } catch is CancellationError { }
        catch {
            guard operation == generation, captured == key else { return }
            issue = TopicScreenIssue(error); loadedKey = captured
        }
    }
}
