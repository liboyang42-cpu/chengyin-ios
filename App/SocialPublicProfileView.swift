import SwiftUI

@MainActor struct SocialPublicProfileView: View {
    let memberID: Int
    let reader: any SocialAccountReading
    let squareReader: any SquareReading
    var actions: SocialActionCoordinator? = nil
    var selfOrdersAccess: ProfileSelfOrdersAccess? = nil
    var selfProjectsAccess: ProfileSelfProjectsAccess? = nil
    var selfGrowthAccess: ProfileSelfGrowthAccess? = nil
    var selfMedalsReader: (any ProfileReading)? = nil
    var selfEditAccess: ProfileSelfEditAccess? = nil
    var localCoverOwner: ProfileLocalCoverOwner? = nil
    var isCurrent: @MainActor () -> Bool = { true }
    private enum Tab: String, CaseIterable { case posts, achievements, about, projects, orders }
    @State private var tab = Tab.posts
    @State private var selfEditNavigation = ProfileSelfEditNavigation()
    private var selfEditContext: ProfileSelfEditContext? {
        selfEditAccess?.context(memberID: memberID, reader: reader, isCurrent: isCurrent())
    }
    private var selfEditBinding: Binding<ProfileSelfEditTicket?> {
        let captured = selfEditNavigation.ticket
        return Binding(get: { selfEditNavigation.ticket }, set: { next in
            if next == nil, let captured { selfEditNavigation.finish(captured.id, context: selfEditContext) }
        })
    }
    var body: some View {
        List {
            if localCoverOwner?.accountID == memberID {
                ProfileLocalCoverSection(owner: localCoverOwner, reader: reader, isCurrent: isCurrent)
            }
            if memberID <= 0 { Text("social.incompleteLink") }
            else {
                SocialReadScreen(reader: reader, requestKey: "profile-\(memberID)-\(selfEditNavigation.refreshID)", load: {
                    // A scoped parent may retire before SwiftUI unmounts this screen.
                    // Do not start a replacement-account read for that old route.
                    guard isCurrent() else { throw CancellationError() }
                    let loaded = try await reader.publicProfile(memberID: memberID)
                    guard isCurrent() else { throw CancellationError() }
                    return loaded
                }) { profile in
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
                        ProfileAuthorPostsSection(memberID: memberID, accountReader: reader, squareReader: squareReader, actions: actions, isCurrent: isCurrent)
                    case .achievements:
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
        }.appNavigationTitle("social.profile").navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: selfEditBinding) { ticket in
                ProfileSelfEditDestination(ticket: ticket, access: selfEditAccess,
                    isCurrent: { selfEditNavigation.isCurrent(ticket, context: selfEditContext) })
            }
            .accessibilityIdentifier("social.profile")
            .onChange(of: selfOrdersAccess?.context(memberID: memberID, social: reader, isCurrent: isCurrent())) { _, context in
                if context == nil && tab == .orders { tab = .posts }
            }
    }
}
