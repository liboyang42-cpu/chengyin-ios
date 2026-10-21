import SwiftUI

@MainActor struct AccountCollectionFavoritesView: View {
    let reader: any AccountCollectionReading
    let onOpenTopic: (Int) -> Void
    var pageSize = 10
    var onOpenPost: ((SquareContentRoute) -> Void)? = nil
    var favoriteRemoval: ProfileFavoriteRemovalController? = nil
    var communityGate: (any SquareCommunityFeatureReading)? = nil
    @State private var selectedTab: Tab = .posts
    @State private var gateModel = AccountCollectionCommunityGateModel()
    private enum Tab: Hashable { case posts, topics }
    /// Nil gate fails closed. Only the single gate model may open posts.
    private var postsAllowed: Bool {
        gateModel.postsAllowed(hasGate: communityGate != nil, currentScope: communityGate?.scope)
    }
    var body: some View {
        VStack(spacing: 0) {
            if postsAllowed {
                Picker("accountCollection.favorites.title", selection: $selectedTab) {
                    Text("social.posts").tag(Tab.posts)
                    Text("searchMap.kind.topic").tag(Tab.topics)
                }
                .pickerStyle(.segmented).padding()
                .accessibilityIdentifier("accountCollection.favorites.tabs")
            }
            if postsAllowed && selectedTab == .posts {
                AccountCollectionFavoritePostsView(reader: reader, pageSize: pageSize, onOpenPost: onOpenPost, favoriteRemoval: favoriteRemoval)
            } else {
                AccountCollectionFavoriteTopicsView(reader: reader, onOpenTopic: onOpenTopic, pageSize: pageSize, retryGate: {
                    if gateModel.failed || gateModel.resolvedScope != communityGate?.scope { await loadGate() }
                })
            }
        }
        .appNavigationTitle("accountCollection.favorites.title")
        .task(id: communityGate?.scope) { await loadGate() }
        .onChange(of: communityGate?.scope) { _, next in
            if gateModel.resolvedScope != next { gateModel.invalidate() }
        }
        .onChange(of: reader.scope) { _, _ in
            gateModel.invalidate()
        }
    }
    private func loadGate() async {
        await gateModel.load(gate: communityGate, isAuthenticated: reader.isAuthenticated, isConfigured: reader.isConfigured)
    }
}

/// The host resets the whole collection for session revisions. Each tab has its
/// own reader lifecycle, so switching tabs cancels a pending page completion.
@MainActor private struct AccountCollectionFavoriteTopicsView: View {
    let reader: any AccountCollectionReading
    let onOpenTopic: (Int) -> Void
    var pageSize = 10
    var retryGate: (() async -> Void)? = nil
    @StateObject private var model = AccountCollectionFavoritesScreenModel()
    @Environment(\.topicUnlikeController) private var unlike
    @State private var unliked: Set<Int> = []
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
                if model.state.visibleRows(scope: key.scope).filter({ !unliked.contains($0.id) }).isEmpty {
                    ContentUnavailableView("accountCollection.favorites.empty", systemImage: "heart",
                                           description: Text("accountCollection.favorites.emptyHint"))
                        .accessibilityIdentifier("accountCollection.favorites.empty")
                }
                ForEach(model.state.visibleRows(scope: key.scope).filter { !unliked.contains($0.id) }) { topic in
                    Button { onOpenTopic(topic.id) } label: { AccountCollectionFavoriteCard(topic: topic) }
                        .buttonStyle(QuestifyCardButtonStyle())
                        .accessibilityIdentifier("accountCollection.favorite.\(topic.id)")
                        .overlay(alignment: .topTrailing) {
                            if let unlike, unlike.isAvailable { TopicUnlikeButton(topicID: topic.id, controller: unlike).padding(8) }
                        }
                        .questifyCardListRow()
                }
                if let issue = model.state.moreIssue {
                    AccountCollectionIssueView(issue: issue, retry: { Task { await loadMore() } })
                } else if model.state.isLoadingMore { ProgressView("accountCollection.loading") }
                else if model.state.pagination.hasMore {
                    Button("accountCollection.loadMore") { Task { await loadMore() } }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("accountCollection.favorites.loadMore")
                } else if !model.state.visibleRows(scope: key.scope).isEmpty {
                    Text("member.favorites.topicsEnd", tableName: "MemberProfile").font(.footnote).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).accessibilityIdentifier("accountCollection.favorites.end")
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
        .modifier(TopicUnlikeFlow(controller: unlike) { unliked.insert($0) })
    }
    private func refresh() async {
        guard reader.isAuthenticated, reader.isConfigured else { model.invalidate(); return }
        unliked = []
        await retryGate?()
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
            if let categories = topic.favoriteCategoryText {
                QuestifyImageEntityMetadata(label: "accountCollection.favorites.categories", value: categories, systemImage: "tag")
                    .lineLimit(1).truncationMode(.tail)
                    .accessibilityIdentifier("accountCollection.favorite.categories.\(topic.id)")
            }
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
    var favoriteRemoval: ProfileFavoriteRemovalController? = nil
    var couponReader: (any AccountCollectionReading)? = nil
    private var ownedCouponReader: any AccountCollectionReading { couponReader ?? reader }
    var favoritesReader: (any AccountCollectionReading)? = nil
    private var savedReader: any AccountCollectionReading { favoritesReader ?? reader }
    var rewardMerchant: PublicMerchantHomeContext? = nil
    var communityGate: (any SquareCommunityFeatureReading)? = nil
    var body: some View {
        let saved = savedReader, renderedScope = saved.scope
        Section {
            NavigationLink {
                NonCashRewardsView(reader: reader, rewards: rewards, merchantHome: rewardMerchant).id(reader.scope)
            } label: { Label("rewards.title", systemImage: "gift") }
            .accessibilityIdentifier("rewards.open")
            NavigationLink {
                AccountCollectionFavoritesView(reader: saved, onOpenTopic: { id in
                    guard saved.isAuthenticated, saved.isConfigured, saved.scope == renderedScope else { return }
                    onOpenTopic(id)
                }, onOpenPost: onOpenPost.map { open in { route in
                    guard saved.isAuthenticated, saved.isConfigured, saved.scope == renderedScope else { return }
                    open(route)
                } }, favoriteRemoval: favoriteRemoval, communityGate: communityGate).id(renderedScope)
            } label: { Label("accountCollection.favorites.title", systemImage: "heart") }
            .accessibilityIdentifier("accountCollection.openFavorites")
            NavigationLink {
                AccountCollectionCouponsView(reader: ownedCouponReader).id(ownedCouponReader.scope)
            } label: { Label("accountCollection.coupons.title", systemImage: "ticket") }
            .accessibilityIdentifier("accountCollection.openCoupons")
        }
    }
}

@MainActor private struct AccountCollectionFavoritePostsView: View {
    let reader: any AccountCollectionReading
    let pageSize: Int
    let onOpenPost: ((SquareContentRoute) -> Void)?
    let favoriteRemoval: ProfileFavoriteRemovalController?
    @StateObject private var model = AccountCollectionPostsScreenModel()
    private var key: AccountCollectionLoadKey { AccountCollectionLoadKey(reader: reader) }
    var body: some View {
        let renderedScope = key.scope
        List {
            if let favoriteRemoval, reader.isAuthenticated, reader.isConfigured {
                ProfileFavoriteRecoverySection(scope: renderedScope, controller: favoriteRemoval,
                    isCurrent: { reader.isAuthenticated && reader.isConfigured && reader.scope == renderedScope },
                    onRemoved: { await refresh() })
            }
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
                    if let favoriteRemoval {
                        ProfileFavoriteRemovalEntry(post: post, scope: key.scope, controller: favoriteRemoval,
                            isCurrent: { reader.isAuthenticated && reader.isConfigured && reader.scope == renderedScope && model.state.loadedScope == renderedScope },
                            onRemoved: { await refresh() })
                    }
                    NativeMediaGalleryEntry(sources: post.images, scope: reader.scope, titleKey: "media.destination.squareImages")
                }
                if let issue = model.state.moreIssue {
                    AccountCollectionIssueView(issue: issue, retry: { Task { await loadMore() } })
                } else if model.state.isLoadingMore { ProgressView("accountCollection.loading") }
                else if model.state.pagination.hasMore {
                    Button("accountCollection.loadMore") { Task { await loadMore() } }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("accountCollection.posts.loadMore")
                } else if !model.state.visibleRows(scope: key.scope).isEmpty {
                    Text("member.favorites.postsEnd", tableName: "MemberProfile").font(.footnote).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).accessibilityIdentifier("accountCollection.posts.end")
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
