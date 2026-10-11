import SwiftUI

/// P108 author-feed refresh is independent of profile editing and profile-header reads.
@MainActor struct ProfileAuthorPostsSection: View {
    let memberID: Int
    let accountReader: any SocialAccountReading
    let squareReader: any SquareReading
    var actions: SocialActionCoordinator? = nil
    var isCurrent: @MainActor () -> Bool = { true }
    @State private var model = ProfileAuthorPostsRefreshController()
    private var context: ProfileAuthorPostsContext {
        .init(memberID: memberID, accountReader: accountReader, squareReader: squareReader)
    }
    var body: some View {
        Section("social.posts") {
            if !isCurrent() { Text("social.changed") }
            else if !context.isSignedIn { Text("social.postsSignIn").accessibilityIdentifier("social.profile.postsSignIn") }
            else if !context.isConfigured { SocialIssueView(error: APIError.notConfigured) }
            else {
                Button { Task { await refresh() } } label: {
                    Label("profile.postsRefresh.refresh", systemImage: "arrow.clockwise")
                }
                .disabled(model.isBusy)
                .accessibilityIdentifier("profile.postsRefresh.refresh")
                if model.context != context || (model.isBusy && !model.pagination.hasLoadedPage) {
                    ProgressView("social.loading")
                } else {
                    if model.activeOperation == .refresh && model.pagination.hasLoadedPage {
                        ProgressView("profile.postsRefresh.refreshing")
                            .accessibilityIdentifier("profile.postsRefresh.refreshing")
                    }
                    if model.retainsPreviousResult {
                        Text("profile.postsRefresh.retained").font(.footnote).foregroundStyle(.secondary)
                            .accessibilityIdentifier("profile.postsRefresh.retained")
                    }
                    if let error = model.error {
                        SocialIssueView(error: error)
                        if model.failedOperation != nil {
                            Button("action.retry") { Task { await model.retry(memberID: memberID, accountReader: accountReader, squareReader: squareReader, isCurrent: isCurrent) } }
                                .disabled(model.isBusy)
                                .accessibilityIdentifier("profile.postsRefresh.retry")
                        }
                    }
                    ForEach(model.visibleRows(for: context, isCurrent: isCurrent())) { post in
                        NavigationLink {
                            if model.canOpen(post, context: context, isCurrent: isCurrent()) {
                                SquareDetailView(id: post.id, contentGeneration: post.generation, reader: squareReader, accountReader: accountReader, actions: actions)
                            } else { Text("social.changed") }
                        } label: { SquarePostContent(post: post, showImages: false) }
                        .accessibilityIdentifier("profile.postsRefresh.post.\(post.id)")
                        NativeMediaGalleryEntry(sources: post.images, scope: squareReader.scope, titleKey: "media.destination.squareImages")
                    }
                    if model.pagination.hasLoadedPage && model.pagination.items.isEmpty {
                        Text("social.noPosts").accessibilityIdentifier("profile.postsRefresh.empty")
                    }
                    if model.pagination.continuationInvalid {
                        Text("square.invalidCursor").accessibilityIdentifier("profile.postsRefresh.invalidCursor")
                    }
                    if model.activeOperation == .more { ProgressView("social.loading") }
                    else if model.pagination.hasLoadedPage && model.pagination.hasMore && model.error == nil {
                        Button("square.loadMore") { Task { await model.loadMore(memberID: memberID, accountReader: accountReader, squareReader: squareReader, isCurrent: isCurrent) } }
                            .disabled(model.isBusy)
                            .accessibilityIdentifier("profile.postsRefresh.more")
                    }
                }
            }
        }
        .task(id: context) { await refresh() }
        .onDisappear { model.suspend() }
    }
    private func refresh() async {
        await model.refresh(memberID: memberID, accountReader: accountReader, squareReader: squareReader, isCurrent: isCurrent)
    }
}
