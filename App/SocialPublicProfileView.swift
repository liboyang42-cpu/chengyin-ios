import SwiftUI

@MainActor struct SocialPublicProfileView: View {
    let memberID: Int
    let reader: any SocialAccountReading
    let squareReader: any SquareReading
    var actions: SocialActionCoordinator? = nil
    private enum Tab: String, CaseIterable { case posts, achievements, about }
    @State private var tab = Tab.posts
    var body: some View {
        List {
            if memberID <= 0 { Text("social.incompleteLink") }
            else {
                SocialReadScreen(reader: reader, requestKey: "profile-\(memberID)", load: { try await reader.publicProfile(memberID: memberID) }) { profile in
                    Section {
                        if let name = profile.nickname { Text(verbatim: name).font(.title2.bold()) }
                        else { Text("square.unknownAuthor").font(.title2.bold()) }
                        if let avatar = profile.avatar { SquareImage(source: avatar).frame(maxHeight: 120) }
                        SocialOptionalCount(title: "social.level", count: profile.level)
                        LabeledContent("social.followStatus") {
                            switch profile.isFollowed {
                            case true: Text("social.following")
                            case false: Text("social.notFollowing")
                            case nil: Text("social.relationshipUnknown")
                            }
                        }
                        if let actions, actions.identity.accountID != profile.id {
                            NavigationLink { SocialActionEditorView(purpose: .toggleFollow, target: .member(profile.id), coordinator: actions) } label: { Text("social.editor.toggleFollow") }
                            NavigationLink { SocialActionEditorView(purpose: .startChat, target: .member(profile.id), coordinator: actions) } label: { Text("social.editor.startChat") }
                        }
                        Text("social.profileActionsDisabled").font(.footnote).foregroundStyle(.secondary)
                    }
                    Picker("social.profileSection", selection: $tab) {
                        Text("social.posts").tag(Tab.posts)
                        Text("social.achievements").tag(Tab.achievements)
                        Text("social.about").tag(Tab.about)
                    }.accessibilityIdentifier("social.profile.tabs")
                    switch tab {
                    case .posts:
                        SocialAuthorPostsSection(memberID: memberID, accountReader: reader, squareReader: squareReader, actions: actions)
                    case .achievements:
                        Section("social.achievements") {
                            SocialOptionalCount(title: "social.published", count: profile.published)
                            SocialOptionalCount(title: "social.likes", count: profile.likes)
                            SocialOptionalCount(title: "social.followers", count: profile.followers)
                            SocialOptionalCount(title: "social.followingCount", count: profile.following)
                        }
                    case .about:
                        Section("social.introduction") {
                            if let introduction = profile.introduction { Text(verbatim: introduction).textSelection(.enabled) }
                            else { Text("social.noIntroduction").foregroundStyle(.secondary) }
                        }
                        Section("social.interests") {
                            if profile.interests.isEmpty { Text("social.noInterests").foregroundStyle(.secondary) }
                            ForEach(profile.interests) { item in Label { Text(verbatim: item.name) } icon: { Image(systemName: "tag") } }
                        }
                        if !profile.workImages.isEmpty {
                            Section("social.portfolio") {
                                ForEach(Array(profile.workImages.enumerated()), id: \.offset) { _, source in SquareImage(source: source) }
                            }
                        }
                    }
                }
            }
        }.appNavigationTitle("social.profile").navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("social.profile")
    }
}
@MainActor private struct SocialAuthorPostsSection: View {
    let memberID: Int
    let accountReader: any SocialAccountReading
    let squareReader: any SquareReading
    let actions: SocialActionCoordinator?
    @State private var pagination = SquareFeedPagination()
    @State private var error: Error?
    @State private var busy = false
    @State private var generation = 0
    @State private var loadedIdentity: SocialAccountIdentity?
    var body: some View {
        Section("social.posts") {
            if accountReader.identity.accountID == nil { Text("social.postsSignIn").accessibilityIdentifier("social.profile.postsSignIn") }
            else if busy && pagination.items.isEmpty { ProgressView("social.loading") }
            else if loadedIdentity == accountReader.identity {
                if let error { SocialIssueView(error: error) { Task { await load(reset: !pagination.hasLoadedPage) } } }
                ForEach(pagination.items) { post in
                    NavigationLink {
                        SquareDetailView(id: post.id, contentGeneration: post.generation, reader: squareReader, accountReader: accountReader, actions: actions)
                    } label: { SquarePostContent(post: post, showImages: false) }
                    NativeMediaGalleryEntry(sources: post.images, scope: squareReader.scope, titleKey: "media.destination.squareImages")
                }
                if pagination.hasLoadedPage && pagination.items.isEmpty { Text("social.noPosts") }
                if pagination.continuationInvalid { Text("square.invalidCursor") }
                if pagination.hasMore && error == nil {
                    Button("square.loadMore") { Task { await load(reset: false) } }.disabled(busy)
                }
            }
        }
        .task(id: accountReader.identity) { await load(reset: true) }
        .onDisappear { generation += 1; busy = false }
    }
    private func load(reset: Bool) async {
        guard !busy || reset else { return }
        generation += 1; let run = generation, identity = accountReader.identity, scope = squareReader.scope
        if reset { pagination = SquareFeedPagination(); loadedIdentity = nil }; error = nil
        guard identity.accountID != nil else { busy = false; return }
        busy = true; loadedIdentity = identity
        defer { if generation == run { busy = false } }
        do {
            let cursor = pagination.nextCursor
            let page = try await squareReader.squareFeed(query: .init(authorID: memberID), cursor: cursor)
            try Task.checkCancellation()
            guard run == generation, identity == accountReader.identity, scope == squareReader.scope else { return }
            try pagination.accept(page, requestedCursor: cursor)
        } catch is CancellationError { }
        catch { if run == generation, identity == accountReader.identity, scope == squareReader.scope { self.error = error } }
    }
}
