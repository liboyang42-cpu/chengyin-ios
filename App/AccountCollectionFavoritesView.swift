import SwiftUI

/// The host observes session revisions and resets this destination using .id(reader.scope).
/// Favorites route to an existing topic destination through the host's callback.
@MainActor struct AccountCollectionFavoritesView: View {
    let reader: any AccountCollectionReading
    let onOpenTopic: (Int) -> Void
    var pageSize = 10
    @StateObject private var model = AccountCollectionFavoritesScreenModel()
    private var key: AccountCollectionLoadKey { AccountCollectionLoadKey(reader: reader) }
    var body: some View {
        List {
            if reader.isOfflineExample { Text("accountCollection.offlineExample").font(.caption) }
            if !reader.isAuthenticated { AccountCollectionIssueView(issue: .login) }
            else if !reader.isConfigured { AccountCollectionIssueView(issue: .notConfigured) }
            else if model.state.isLoading || model.state.loadedScope != key.scope {
                ProgressView("accountCollection.loading")
            } else if let issue = model.state.issue {
                AccountCollectionIssueView(issue: issue, retry: { Task { await refresh() } })
            } else {
                if model.state.visibleRows(scope: key.scope).isEmpty {
                    ContentUnavailableView("accountCollection.favorites.empty", systemImage: "heart",
                                           description: Text("accountCollection.favorites.emptyHint"))
                        .accessibilityIdentifier("accountCollection.favorites.empty")
                }
                ForEach(model.state.visibleRows(scope: key.scope)) { topic in
                    Button { onOpenTopic(topic.id) } label: { AccountCollectionFavoriteCard(topic: topic) }
                        .buttonStyle(QuestifyCardButtonStyle())
                        .accessibilityIdentifier("accountCollection.favorite.\(topic.id)")
                        .questifyCardListRow()
                }
                if let issue = model.state.moreIssue {
                    AccountCollectionIssueView(issue: issue, retry: { Task { await loadMore() } })
                } else if model.state.isLoadingMore { ProgressView("accountCollection.loading") }
                else if model.state.pagination.hasMore {
                    Button("accountCollection.loadMore") { Task { await loadMore() } }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("accountCollection.favorites.loadMore")
                }
            }
        }
        .listStyle(.insetGrouped)
        .appNavigationTitle("accountCollection.favorites.title")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await refresh() } } label: { Label("accountCollection.refresh", systemImage: "arrow.clockwise") }
                    .disabled(model.state.isLoading || !reader.isAuthenticated || !reader.isConfigured)
                    .accessibilityIdentifier("accountCollection.favorites.refresh")
            }
        }
        .modifier(AccountCollectionReadLifecycle(key: key, refresh: refresh, cancel: model.cancelPending))
    }
    private func refresh() async {
        guard reader.isAuthenticated, reader.isConfigured else { model.invalidate(); return }
        await model.refresh(reader: reader, pageSize: pageSize)
    }
    private func loadMore() async {
        guard reader.isAuthenticated, reader.isConfigured else { model.invalidate(); return }
        await model.loadMore(reader: reader, pageSize: pageSize)
    }
}

/// Shared full-bleed card; artwork and topic routes remain server-backed.
private struct AccountCollectionFavoriteCard: View {
    let topic: TopicSummary
    var body: some View {
        QuestifyImageEntityCard(imageSource: topic.imageURL, title: topic.name,
                               fallbackTitle: "accountCollection.favorites.untitled",
                               fallbackSymbol: "photo", minimumHeight: 250) {
            if let place = topic.addressName, !place.isEmpty {
                QuestifyImageEntityMetadata(label: "accountCollection.favorites.place", value: place, systemImage: "mappin.and.ellipse")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("accountCollection.favorites.openHint"))
    }
}

@MainActor struct AccountCollectionAccountLinks: View {
    let reader: any AccountCollectionReading
    let onOpenTopic: (Int) -> Void
    var body: some View {
        Section {
            NavigationLink {
                AccountCollectionFavoritesView(reader: reader, onOpenTopic: onOpenTopic).id(reader.scope)
            } label: { Label("accountCollection.favorites.title", systemImage: "heart") }
            .accessibilityIdentifier("accountCollection.openFavorites")
            NavigationLink {
                AccountCollectionCouponsView(reader: reader).id(reader.scope)
            } label: { Label("accountCollection.coupons.title", systemImage: "ticket") }
            .accessibilityIdentifier("accountCollection.openCoupons")
        }
    }
}
