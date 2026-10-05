import SwiftUI

@MainActor struct AccountCollectionFavoritesView: View {
    let reader: any AccountCollectionReading
    let onOpenTopic: (Int) -> Void
    var pageSize = 10
    var onOpenPost: ((SquareContentRoute) -> Void)? = nil
    @State private var selectedTab: Tab = .posts
    private enum Tab: Hashable { case posts, topics }
    var body: some View {
        VStack(spacing: 0) {
            Picker("accountCollection.favorites.title", selection: $selectedTab) {
                Text("social.posts").tag(Tab.posts)
                Text("searchMap.kind.topic").tag(Tab.topics)
            }
            .pickerStyle(.segmented).padding()
            .accessibilityIdentifier("accountCollection.favorites.tabs")
            if selectedTab == .posts {
                AccountCollectionFavoritePostsView(reader: reader, pageSize: pageSize, onOpenPost: onOpenPost)
            } else {
                AccountCollectionFavoriteTopicsView(reader: reader, onOpenTopic: onOpenTopic, pageSize: pageSize)
            }
        }
        .appNavigationTitle("accountCollection.favorites.title")
    }
}

/// The host resets the whole collection for session revisions. Each tab has its
/// own reader lifecycle, so switching tabs cancels a pending page completion.
@MainActor private struct AccountCollectionFavoriteTopicsView: View {
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
            TopicTotalStops(count: topic.locationCount, identifier: "accountCollection.totalStops.\(topic.id)")
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
    var rewards: (any NonCashRewardReading)? = nil
    var onOpenPost: ((SquareContentRoute) -> Void)? = nil
    var body: some View {
        Section {
            NavigationLink {
                NonCashRewardsView(reader: reader, rewards: rewards).id(reader.scope)
            } label: { Label("rewards.title", systemImage: "gift") }
            .accessibilityIdentifier("rewards.open")
            NavigationLink {
                AccountCollectionFavoritesView(reader: reader, onOpenTopic: onOpenTopic, onOpenPost: onOpenPost).id(reader.scope)
            } label: { Label("accountCollection.favorites.title", systemImage: "heart") }
            .accessibilityIdentifier("accountCollection.openFavorites")
            NavigationLink {
                AccountCollectionCouponsView(reader: reader).id(reader.scope)
            } label: { Label("accountCollection.coupons.title", systemImage: "ticket") }
            .accessibilityIdentifier("accountCollection.openCoupons")
        }
    }
}

@MainActor private struct AccountCollectionFavoritePostsView: View {
    let reader: any AccountCollectionReading
    let pageSize: Int
    let onOpenPost: ((SquareContentRoute) -> Void)?
    @StateObject private var model = AccountCollectionPostsScreenModel()
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
                    ContentUnavailableView("square.empty", systemImage: "bookmark")
                        .accessibilityIdentifier("accountCollection.posts.empty")
                }
                ForEach(model.state.visibleRows(scope: key.scope)) { post in
                    Button {
                        guard reader.isAuthenticated, reader.isConfigured,
                              model.state.loadedScope == reader.scope, post.generation == .legacySquare else { return }
                        onOpenPost?(.init(id: post.id, generation: post.generation))
                    } label: {
                        SquarePostContent(post: post, compact: true, showImages: false)
                    }
                    .buttonStyle(QuestifyCardButtonStyle())
                    .disabled(onOpenPost == nil)
                    .accessibilityIdentifier("accountCollection.post.\(post.id)")
                    .questifyCardListRow()
                    NativeMediaGalleryEntry(sources: post.images, scope: reader.scope, titleKey: "media.destination.squareImages")
                }
                if let issue = model.state.moreIssue {
                    AccountCollectionIssueView(issue: issue, retry: { Task { await loadMore() } })
                } else if model.state.isLoadingMore { ProgressView("accountCollection.loading") }
                else if model.state.pagination.hasMore {
                    Button("accountCollection.loadMore") { Task { await loadMore() } }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("accountCollection.posts.loadMore")
                }
            }
        }
        .listStyle(.insetGrouped)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await refresh() } } label: { Label("accountCollection.refresh", systemImage: "arrow.clockwise") }
                    .disabled(model.state.isLoading || !reader.isAuthenticated || !reader.isConfigured)
                    .accessibilityIdentifier("accountCollection.posts.refresh")
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
