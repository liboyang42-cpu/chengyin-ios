import SwiftUI

@MainActor struct SocialPublicProfileView: View {
    let memberID: Int
    let reader: any SocialAccountReading
    let squareReader: any SquareReading
    var actions: SocialActionCoordinator? = nil
    var selfOrdersAccess: ProfileSelfOrdersAccess? = nil
    var selfProjectsAccess: ProfileSelfProjectsAccess? = nil
    var selfGrowthAccess: ProfileSelfGrowthAccess? = nil
    var weeklyPointsAccess: ProfileWeeklyPointsAccess? = nil
    var personalToolsAccess: ProfilePersonalToolsAccess? = nil
    var selfCouponAccess: ProfileSelfCouponAccess? = nil
    var selfObjectCardsAccess: ProfileObjectCardsAccess? = nil
    var selfMedalsReader: (any ProfileReading)? = nil
    var selfEditAccess: ProfileSelfEditAccess? = nil
    var selfEditDiagnostics: (@MainActor (ProfileSelfEditTicket?, ProfileSelfEditTicket, ProfileSelfEditContext?) -> String)? = nil
    var localCoverOwner: ProfileLocalCoverOwner? = nil
    var isCurrent: @MainActor () -> Bool = { true }
    private enum Tab: String, CaseIterable { case posts, achievements, about, projects, orders }
    @State private var authorPosts = ProfileAuthorPostsRefreshController()
    @State private var authorPostTicket: ProfileAuthorPostTicket?
    @State private var tab = Tab.posts
    @State private var selfEditNavigation = ProfileSelfEditNavigation()
    @StateObject private var identityShareOwner = ProfileIdentitySharePageOwner()
    private var selfEditContext: ProfileSelfEditContext? {
        selfEditAccess?.context(memberID: memberID, reader: reader, isCurrent: isCurrent())
    }
    private var selfEditBinding: Binding<ProfileSelfEditTicket?> {
        let captured = selfEditNavigation.ticket
        return Binding(get: { selfEditNavigation.ticket }, set: { next in
            if next == nil, let captured { selfEditNavigation.finish(captured.id, context: selfEditContext) }
        })
    }
    private func selfEditDiagnostic(for ticket: ProfileSelfEditTicket) -> (@MainActor () -> String)? {
        guard let selfEditDiagnostics else { return nil }
        return { selfEditDiagnostics(selfEditNavigation.ticket, ticket, selfEditContext) }
    }
    var body: some View {
        ProfileIdentitySharePageHost(owner: identityShareOwner,
            context: .init(memberID: memberID, reader: reader, isCurrent: isCurrent())) {
        List {
            if localCoverOwner?.accountID == memberID {
                ProfileLocalCoverSection(owner: localCoverOwner, reader: reader, isCurrent: isCurrent)
            }
            // The owner-only read is independent of the public profile response.
            if let weeklyPointsAccess {
                ProfileWeeklyPointsEntry(memberID: memberID, accountReader: reader,
                    access: weeklyPointsAccess, isCurrent: isCurrent)
            }
            if memberID <= 0 { Text("social.incompleteLink") }
            else {
                SocialReadScreen(reader: reader, requestKey: "profile-\(memberID)-\(selfEditNavigation.refreshID)", load: {
                    // A scoped parent may retire before SwiftUI unmounts this screen.
                    // Do not start a replacement-account read for that old route.
                    guard isCurrent() else { throw CancellationError() }
                    let shareContext = ProfileIdentitySharePageContext(memberID: memberID, reader: reader, isCurrent: isCurrent())
                    let shareRead = identityShareOwner.beginSourceRead(shareContext)
                    let headerKey = SocialReadPresentationKey(reader: reader,
                        request: "profile-\(memberID)-\(selfEditNavigation.refreshID)", requiresSignIn: false)
                    let feedContext = authorPostsContext
                    let loaded: SocialPublicProfile
                    do { loaded = try await reader.publicProfile(memberID: memberID) }
                    catch {
                        let currentKey = SocialReadPresentationKey(reader: reader,
                            request: "profile-\(memberID)-\(selfEditNavigation.refreshID)", requiresSignIn: false)
                        if !Task.isCancelled, isCurrent(), headerKey == currentKey,
                           feedContext == authorPostsContext,
                           authorPosts.rejectHeader(error, context: feedContext) {
                            if authorPostTicket?.context == feedContext { authorPostTicket = nil }
                        }
                        throw error
                    }
                    guard isCurrent() else { throw CancellationError() }
                    guard !Task.isCancelled else { throw CancellationError() }
                    identityShareOwner.acceptSource(loaded, reader: reader, expected: shareContext,
                                                    readID: shareRead, isCurrent: isCurrent())
                    return loaded
                }) { profile in
                    Section {
                        if let name = profile.nickname { Text(verbatim: name).font(.title2.bold()) }
                        else { Text("square.unknownAuthor").font(.title2.bold()) }
                        if let avatar = profile.avatar { SquareImage(source: avatar).frame(maxHeight: 120) }
                        if profile.id == memberID, reader.identity.accountID == memberID {
                            ProfileIdentityShareSection(profile: profile, reader: reader, isCurrent: isCurrent, owner: identityShareOwner)
                                .id(ProfileIdentityShareViewIdentity(profile: profile, reader: reader))
                        }
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
                        if let selfOrdersAccess, selfOrdersAccess.context(memberID: memberID, social: reader, isCurrent: isCurrent()) != nil {
                            Text("profile.selfOrders.title").tag(Tab.orders)
                        }
                        if let selfProjectsAccess, selfProjectsAccess.context(memberID: memberID, accountReader: reader, isCurrent: isCurrent()) != nil {
                            Text("profile.selfProjects.title").tag(Tab.projects)
                        }
                    }.accessibilityIdentifier("social.profile.tabs")
                    switch tab {
                    case .orders:
                        if let selfOrdersAccess {
                            ProfileSelfOrdersEntry(memberID: memberID, social: reader, access: selfOrdersAccess, isCurrent: isCurrent)
                        }
                    case .projects:
                        if let selfProjectsAccess {
                            ProfileSelfProjectsEntry(memberID: memberID, accountReader: reader, access: selfProjectsAccess, isCurrent: isCurrent)
                        }
                    case .posts:
                        ProfileAuthorPostsSection(memberID: memberID, accountReader: reader, squareReader: squareReader,
                            actions: actions, isCurrent: isCurrent, retainedModel: authorPosts, onOpenPost: openAuthorPost)
                    case .achievements:
                        if let selfObjectCardsAccess {
                            ProfileObjectCardsEntry(memberID: memberID, accountReader: reader,
                                access: selfObjectCardsAccess, isCurrent: isCurrent)
                        }
                        if let selfMedalsReader {
                            ProfileSelfMedalsSection(memberID: memberID, accountReader: reader,
                                profileReader: selfMedalsReader, isCurrent: isCurrent)
                        }
                        if let selfGrowthAccess {
                            ProfileSelfGrowthEntry(memberID: memberID, accountReader: reader,
                                access: selfGrowthAccess, isCurrent: isCurrent)
                        }
                        Section("social.achievements") {
                            SocialOptionalCount(title: "social.published", count: profile.published)
                            SocialOptionalCount(title: "social.likes", count: profile.likes)
                            SocialOptionalCount(title: "social.followers", count: profile.followers)
                            SocialOptionalCount(title: "social.followingCount", count: profile.following)
                        }
                    case .about:
                        if let personalToolsAccess {
                            ProfilePersonalToolsEntry(memberID: memberID, social: reader,
                                access: personalToolsAccess, isCurrent: isCurrent)
                        }
                        if let selfCouponAccess {
                            ProfileSelfCouponEntry(memberID: memberID, accountReader: reader,
                                access: selfCouponAccess, isCurrent: isCurrent)
                        }
                        Section("social.introduction") {
                            if let introduction = profile.introduction { Text(verbatim: introduction).textSelection(.enabled) }
                            else { Text("social.noIntroduction").foregroundStyle(.secondary) }
                            if selfEditContext != nil {
                                Button("profile.selfEdit.open") { selfEditNavigation.open(selfEditContext) }
                                    .accessibilityIdentifier("profile.selfEdit.open")
                            }
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
        }
        }.appNavigationTitle("social.profile").navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: selfEditBinding) { ticket in
                ProfileSelfEditDestination(ticket: ticket, access: selfEditAccess,
                    isCurrent: { selfEditNavigation.isCurrent(ticket, context: selfEditContext) },
                    diagnosticText: selfEditDiagnostic(for: ticket))
            }
            .navigationDestination(isPresented: authorPostBinding) {
                if let ticket = authorPostTicket, ticket.context == authorPostsContext,
                   isCurrent(), ticket.context.isConfigured, ticket.context.isSignedIn {
                    SquareDetailView(id: ticket.postID, contentGeneration: ticket.contentGeneration,
                        reader: squareReader, accountReader: reader, actions: actions).id(ticket.id)
                } else { Text("social.changed") }
            }
            .onChange(of: authorPostsContext) { _, context in
                if authorPosts.context != context { authorPosts.retire() }
                if let ticket = authorPostTicket, ticket.context != context { authorPostTicket = nil }
            }
            .accessibilityIdentifier("social.profile")
            .onChange(of: selfOrdersAccess?.context(memberID: memberID, social: reader, isCurrent: isCurrent())) { _, context in
                if context == nil && tab == .orders { tab = .posts }
            }
    }
    private var authorPostsContext: ProfileAuthorPostsContext {
        .init(memberID: memberID, accountReader: reader, squareReader: squareReader)
    }
    private func openAuthorPost(_ post: SquarePost) {
        let context = authorPostsContext
        guard authorPostTicket == nil, authorPosts.canOpen(post, context: context, isCurrent: isCurrent()) else { return }
        authorPostTicket = .init(postID: post.id, contentGeneration: post.generation, context: context)
        authorPosts.suspend()
    }
    private var authorPostBinding: Binding<Bool> {
        let id = authorPostTicket?.id
        return Binding(get: { authorPostTicket != nil }, set: { shown in
            guard !shown, let id, authorPostTicket?.id == id else { return }
            authorPostTicket = nil
        })
    }

}


struct ProfileAuthorPostTicket: Identifiable {
    let id = UUID()
    let postID: Int
    let contentGeneration: SquareContentGeneration
    let context: ProfileAuthorPostsContext
}

/// Optional self-profile metadata entry. Captured scopes never authorize coupon codes.
@MainActor struct ProfileSelfCouponAccess {
    let reader: ProfileOwnedCouponReader
    let owner: SocialAccountIdentity
    let scope: UUID
    init(reader: ProfileOwnedCouponReader, owner: SocialAccountIdentity) {
        self.reader = reader; self.owner = owner; scope = reader.scope
    }
}

struct ProfileSelfCouponContext: Hashable {
    let memberID: Int
    let viewer: SocialAccountIdentity
    let viewerRevision: UInt64
    let accountReaderID: ObjectIdentifier
    let couponReaderID: ObjectIdentifier
    let couponScope: UUID
    @MainActor static func capture(memberID: Int, accountReader: any SocialAccountReading,
        access: ProfileSelfCouponAccess, isCurrent: Bool) -> Self? {
        guard isCurrent, memberID > 0, access.owner.accountID == memberID,
              accountReader.identity == access.owner, accountReader.isConfigured,
              ["player", "club"].contains(access.owner.role ?? ""),
              access.reader.isAuthenticated, access.reader.isConfigured,
              access.reader.scope == access.scope else { return nil }
        return .init(memberID: memberID, viewer: access.owner,
            viewerRevision: accountReader.presentationRevision,
            accountReaderID: ObjectIdentifier(accountReader),
            couponReaderID: ObjectIdentifier(access.reader), couponScope: access.scope)
    }
}

@MainActor final class ProfileSelfCouponScopedReader: AccountCollectionReading {
    // Keep the underlying scope so the existing operation lifetime remains valid.
    let scope: UUID
    private let expected: ProfileSelfCouponContext
    private let accountReader: any SocialAccountReading
    private let access: ProfileSelfCouponAccess
    private let current: @MainActor () -> Bool
    init(context: ProfileSelfCouponContext, accountReader: any SocialAccountReading,
         access: ProfileSelfCouponAccess, isCurrent: @escaping @MainActor () -> Bool) {
        expected = context; scope = context.couponScope
        self.accountReader = accountReader; self.access = access; current = isCurrent
    }
    var associationIsCurrent: Bool {
        ProfileSelfCouponContext.capture(memberID: expected.memberID, accountReader: accountReader,
            access: access, isCurrent: current()) == expected
    }
    var isAuthenticated: Bool { associationIsCurrent && access.reader.isAuthenticated }
    var isConfigured: Bool { associationIsCurrent && access.reader.isConfigured }
    var isOfflineExample: Bool { false }
    func favoriteTopics(pageNumber: Int, pageSize: Int) async throws -> TopicPage { throw APIError.notConfigured }
    func favoritePosts(pageNumber: Int, pageSize: Int) async throws -> AccountCollectionPostPage { throw APIError.notConfigured }
    func ownedCoupons(keyword: String?) async throws -> [AccountCollectionCoupon] {
        try await read { try await self.access.reader.ownedCoupons(keyword: keyword, associationIsCurrent: { self.associationIsCurrent }) }
    }
    func ownedCoupon(id: Int) async throws -> AccountCollectionCoupon {
        try await read { try await self.access.reader.ownedCoupon(id: id, associationIsCurrent: { self.associationIsCurrent }) }
    }
    func ownedCoupons(keyword: String?, lifetime: OwnedCouponReadLifetime) async throws -> [AccountCollectionCoupon] {
        try await read { try await self.access.reader.ownedCoupons(keyword: keyword, lifetime: lifetime, associationIsCurrent: { self.associationIsCurrent }) }
    }
    func ownedCoupon(id: Int, lifetime: OwnedCouponReadLifetime) async throws -> AccountCollectionCoupon {
        try await read { try await self.access.reader.ownedCoupon(id: id, lifetime: lifetime, associationIsCurrent: { self.associationIsCurrent }) }
    }
    private func read<T>(_ operation: () async throws -> T) async throws -> T {
        try Task.checkCancellation()
        guard associationIsCurrent else { throw CancellationError() }
        do {
            let value = try await operation()
            try Task.checkCancellation()
            guard associationIsCurrent else { throw CancellationError() }
            return value
        } catch {
            guard !Task.isCancelled, associationIsCurrent else { throw CancellationError() }
            throw error
        }
    }
}

@MainActor private struct ProfileSelfCouponEntry: View {
    let memberID: Int
    let accountReader: any SocialAccountReading
    let access: ProfileSelfCouponAccess
    let isCurrent: @MainActor () -> Bool
    var body: some View {
        if let context = ProfileSelfCouponContext.capture(memberID: memberID,
            accountReader: accountReader, access: access, isCurrent: isCurrent()) {
            Section {
                NavigationLink {
                    ProfileSelfCouponDestination(context: context, accountReader: accountReader,
                        access: access, isCurrent: isCurrent).id(context)
                } label: { Label("accountCollection.coupons.title", systemImage: "ticket") }
                    .accessibilityIdentifier("profile.selfCoupons")
            }.id(context)
        }
    }
}

@MainActor private struct ProfileSelfCouponDestination: View {
    @EnvironmentObject private var session: AppSession
    @State private var reader: ProfileSelfCouponScopedReader
    init(context: ProfileSelfCouponContext, accountReader: any SocialAccountReading,
         access: ProfileSelfCouponAccess, isCurrent: @escaping @MainActor () -> Bool) {
        _reader = State(initialValue: .init(context: context, accountReader: accountReader,
            access: access, isCurrent: isCurrent))
    }
    var body: some View {
        Group {
            if reader.associationIsCurrent { AccountCollectionCouponsView(reader: reader) }
            else { Text("social.changed") }
        }
        .environment(\.couponCodeFactory, nil)
        .id(session.profileOwnedCouponReader.scope)
    }
}
