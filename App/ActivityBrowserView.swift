import SwiftUI

/// The existing activity route owns its destination independently of refreshed list rows.
/// This identity does not select a gameplay mode.
private struct ActivityListDestination: Hashable { let id: Int }

@MainActor struct ActivityBrowserView: View {
    let reader: any ActivityReading
    var playReaderForActivity: ((Int)->PlaySessionReader)? = nil
    var peopleProfile: ActivityPeopleProfileContext? = nil
    var registrationEnabled=false
    @StateObject private var model = ActivityListModel()
    @State private var query = ""
    @State private var path: [ActivityListDestination] = []
    @State private var readerChange: UInt64 = 0
    @State private var loads = SignedInContentDetailLoadOwner()
    private var identity: ActivityListReadIdentity { _ = readerChange; return ActivityListReadIdentity(reader) }
    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                if !reader.activityListIsConfigured {
                    ContentUnavailableView("activity.unavailable",systemImage:"network.slash",
                        description:Text(LocalizedStringKey(reader.activityListUnavailableMessageKey ?? "auth.notConfigured")))
                } else if model.identity != identity || (model.isLoading && model.items.isEmpty) {
                    ProgressView("activity.loading")
                } else if model.failed && model.items.isEmpty {
                    ContentUnavailableView {
                        Label { Text("activity.loadFailed").accessibilityIdentifier("activity.list.error") } icon: { Image(systemName:"wifi.exclamationmark") }
                    } actions: {
                        Button("action.retry") { loads.start { await model.load(reader: reader, reset: true, keyword: query) } }
                            .accessibilityIdentifier("activity.list.retry")
                    }
                } else if model.items.isEmpty {
                    ContentUnavailableView {
                        Label { Text("activity.empty").accessibilityIdentifier("activity.list.empty") } icon: { Image(systemName:"map") }
                    } description: { Text("activity.emptyHint") }
                } else {
                    List {
                        ForEach(model.items) { item in
                            NavigationLink(value: ActivityListDestination(id: item.id)) { ActivityListCard(item:item) }
                                .buttonStyle(QuestifyCardButtonStyle())
                                .questifyCardListRow()
                                .accessibilityIdentifier("activity.row.\(item.id)")
                        }
                        if model.hasMore || model.failed {
                            Button(model.failed ? LocalizedStringKey("action.retry") : LocalizedStringKey("activity.loadMore")) {
                                loads.start { await model.load(reader: reader, reset: false, keyword: query) }
                            }.frame(minHeight:44).disabled(model.isLoading).accessibilityIdentifier("activity.list.loadMore")
                        }
                        if model.isLoading { ProgressView() }
                    }
                    .listStyle(.insetGrouped)
                    .listSectionSpacing(20)
                    .refreshable { await loads.run { await model.load(reader: reader, reset: true, keyword: query) } }
                    .accessibilityIdentifier("activity.list.content")
                }
            }
            .appNavigationTitle("activity.browse")
            .searchable(text:$query,placement:.navigationBarDrawer(displayMode:.always),prompt:"activity.search")
            .onSubmit(of:.search) { loads.start { await model.load(reader: reader, reset: true, keyword: query) } }
            .onChange(of: query) { _, text in
                if text.isEmpty, model.canClearSearch(reader: reader) {
                    loads.start { await model.clearSearchIfNeeded(reader: reader) }
                }
            }
            .task(id: identity) {
                if model.identity != identity { query = "" }
                await loads.run { await model.resume(reader: reader, keyword: query) }
            }
            .onDisappear { loads.cancel(); model.cancelPending() }
            // Kept outside replaceable List content, preserving a pushed Activity→topic route.
            .navigationDestination(for: ActivityListDestination.self) { destination in
                ActivityDetailView(id:destination.id,reader:reader,playReaderForActivity:playReaderForActivity,
                    registrationEnabled:registrationEnabled,peopleProfile:peopleProfile)
            }
        }
        .onReceive(reader.activityPresentationChanges) { readerChange &+= 1 }
        .onChange(of: ObjectIdentifier(reader)) { _, _ in path = [] }
    }
}

@MainActor final class ActivityListModel: ObservableObject {
    @Published private(set) var items: [ActivitySummary] = []
    @Published private(set) var identity: ActivityListReadIdentity?
    @Published private(set) var page = 0
    @Published private(set) var hasMore = false
    @Published private(set) var isLoading = false
    @Published private(set) var failed = false
    private var generation: UInt64 = 0
    private var appliedQuery = ""
    func cancelPending() { generation &+= 1; isLoading = false }
    /// Navigation return is not a new search. Preserve accepted pages and any
    /// later-page retry; only an initial unfinished read or changed reader needs loading.
    func resume(reader: any ActivityReading, keyword: String) async {
        guard !Task.isCancelled else { return }
        let sameReader = identity == ActivityListReadIdentity(reader)
        if sameReader, page > 0 { return }
        await load(reader: reader, reset: true, keyword: sameReader ? appliedQuery : keyword)
    }
    /// Clearing the search field explicitly returns to the unfiltered first page.
    func canClearSearch(reader: any ActivityReading) -> Bool {
        identity == ActivityListReadIdentity(reader) && !appliedQuery.isEmpty
    }
    func clearSearchIfNeeded(reader: any ActivityReading) async {
        guard !Task.isCancelled, canClearSearch(reader: reader) else { return }
        await load(reader: reader, reset: true, keyword: "")
    }
    func load(reader: any ActivityReading, reset: Bool, keyword: String) async {
        let captured = ActivityListReadIdentity(reader)
        let replaced = identity != captured
        guard reset || replaced || !isLoading else { return }
        if replaced || reset {
            generation &+= 1; items = []; page = 0; hasMore = false; failed = false
            identity = captured; appliedQuery = keyword
        }
        guard reader.activityListIsConfigured else { isLoading = false; return }
        let operation = generation, next = page + 1
        isLoading = true; failed = false
        func current() -> Bool {
            !Task.isCancelled && generation == operation && identity == captured && ActivityListReadIdentity(reader) == captured
        }
        defer { if generation == operation && identity == captured { isLoading = false } }
        do {
            let result = try await reader.activities(page: next, keyword: appliedQuery)
            guard current() else { return }
            var existing = Set(items.map(\.id))
            items.append(contentsOf: result.filter { existing.insert($0.id).inserted })
            page = next; hasMore = result.count >= 10
        } catch is CancellationError { }
        catch { if current() { failed = true } }
    }
}

struct AmountLabel: View {
    let amount: Decimal?
    @Environment(\.locale) private var locale
    private var formatted: String? {
        guard let amount else { return nil }
        let formatter=NumberFormatter();formatter.locale=locale;formatter.numberStyle = .decimal
        formatter.minimumFractionDigits=2;formatter.maximumFractionDigits=2
        return formatter.string(from:NSDecimalNumber(decimal:amount))
    }
    var captionKey: String? = nil
    var body: some View {
        if let formatted {
            RevolutAmountView(figure: formatted, label: quietLabel(includeCurrency: true))
        } else if let captionKey {
            RevolutAmountView(figure: appLocalized("activity.priceUnknown", locale: locale), label: localized(captionKey))
        } else { Text("activity.priceUnknown").foregroundStyle(.secondary) }
    }
    private func quietLabel(includeCurrency: Bool) -> String {
        var parts: [String] = []
        if let captionKey { parts.append(localized(captionKey)) }
        if includeCurrency { parts.append(appLocalized("activity.currencyUnconfirmed", locale: locale)) }
        return parts.joined(separator: "\n")
    }
    private func localized(_ key: String) -> String {
        appLocalized(String.LocalizationValue(stringLiteral: key), locale: locale)
    }
}
