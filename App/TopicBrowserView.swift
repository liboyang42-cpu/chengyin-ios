import SwiftUI

/// Host must observe its session and refresh this subtree when account/epoch/token changes.
/// `scope` prevents old personalized content from rendering during the replacement task.
@MainActor
struct TopicBrowserView: View {
    let reader: any TopicReading
    var onClose:(()->Void)? = nil
    var categoryID: String? = nil
    var pageSize: Int = 10
    var publicMerchant: PublicMerchantHomeContext? = nil
    var makeAudio: (@MainActor () -> PlatformAudioPlayback)? = nil
    var makeExternalMaps: (@MainActor () -> PlatformExternalMaps)? = nil
    var selfPlayDestination: ((TopicDetail) -> AnyView)? = nil
    @State private var keyword = ""
    @State private var recommend = false
    @State private var pagination = TopicPagination()
    @State private var loadedKey: Key?
    @State private var loading = false
    @State private var issue: TopicScreenIssue?
    @State private var generation = 0
    @State private var artworkRevision = UUID()
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
                            TopicDetailView(id: item.id, reader: reader, publicMerchant: publicMerchant, makeAudio: makeAudio, makeExternalMaps: makeExternalMaps, selfPlayDestination: selfPlayDestination)
                        } label: {
                            QuestifyImageEntityCard(imageSource:item.imageURL,title:item.name,
                                                    subtitle:item.introduction,fallbackSymbol:"map",progressiveBlur:.cover,
                                                    artworkIdentity:.init(owner:reader.scope.uuidString,content:"topic:\(item.id)",version:artworkRevision.uuidString)) {
                                TopicTotalStops(count: item.locationCount, identifier: "topic.totalStops.\(item.id)")
                                if item.betaFlag == 1 { Text("topic.beta").font(.caption.weight(.semibold)) }
                                if let address=item.addressName,!address.isEmpty {
                                    QuestifyImageEntityMetadata(label:"homeFeed.place",value:address,systemImage:"mappin")
                                }
                                if let date=item.startDate,!date.isEmpty {
                                    QuestifyImageEntityMetadata(label:"homeFeed.date",value:date,systemImage:"calendar")
                                }
                                VStack(alignment:.leading,spacing:3) {
                                    Text("topic.startingPrice").font(.caption)
                                    if let amount=item.minimumAmount,amount>=0 { Text(amount,format:.number.precision(.fractionLength(2))).font(.headline) }
                                    else { Text("topic.priceUnknown") }
                                    Text("homeFeed.currencyUnknown").font(.caption)
                                }
                            }
                        }.buttonStyle(QuestifyCardButtonStyle()).questifyCardListRow()
                        .accessibilityIdentifier("topic.row.\(item.id)")
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
        if reset { artworkRevision = UUID(); pagination.reset(); loadedKey = nil }
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
