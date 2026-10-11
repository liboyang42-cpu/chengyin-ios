import SwiftUI

@MainActor struct SocialPublicProfileView: View {
    let memberID: Int
    let reader: any SocialAccountReading
    let squareReader: any SquareReading
    var actions: SocialActionCoordinator? = nil
    var isCurrent: @MainActor () -> Bool = { true }
    private enum Tab: String, CaseIterable { case posts, achievements, about }
    @State private var tab = Tab.posts
    var body: some View {
        List {
            if memberID <= 0 { Text("social.incompleteLink") }
            else {
                SocialReadScreen(reader: reader, requestKey: "profile-\(memberID)", load: {
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
                    }.accessibilityIdentifier("social.profile.tabs")
                    switch tab {
                    case .posts:
                        ProfileAuthorPostsSection(memberID: memberID, accountReader: reader, squareReader: squareReader, actions: actions, isCurrent: isCurrent)
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
