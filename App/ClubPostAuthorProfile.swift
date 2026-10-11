import SwiftUI

/// The ordinary club host supplies its existing public-profile composition.
/// Opening reads public profile data. Existing destination actions retain their own gates.
@MainActor struct ClubPostAuthorProfile: View {
    let post: ClubCommunityPost
    let clubID: Int?
    let identity: ClubReadIdentity
    @ObservedObject var model: ClubCommunityViewModel
    @Environment(\.clubEnrollmentProfile) private var profile
    @State private var selected: ClubPostAuthorRoute?
    @State private var sourceActive = true
    private var context: ClubPostAuthorContext? {
        guard let profile else { return nil }
        return .init(clubID: clubID, identity: identity, readScope: model.imageReadScope,
                     profileIdentity: profile.reader.identity, profileRevision: profile.reader.presentationRevision,
                     profileReader: ObjectIdentifier(profile.reader), squareReader: ObjectIdentifier(profile.squareReader),
                     squareScope: profile.squareReader.scope)
    }
    private var currentPost: Bool {
        (try? model.context.currentSession().identity) == identity &&
        model.snapshot?.posts.filter({ $0.id == post.id }).count == 1 && model.snapshot?.posts.contains(post) == true
    }
    private var route: ClubPostAuthorRoute? {
        guard currentPost, profile?.reader.isConfigured == true, let context, let posts = model.snapshot?.posts else { return nil }
        return .init(post: post, acceptedPosts: posts, context: context)
    }
    var body: some View {
        Group {
            if let target = route {
                Button {
                    guard sourceActive, selected == nil, current(target) else { return }
                    selected = target
                } label: { authorLabel }
                .buttonStyle(.borderless).accessibilityHint("social.profile")
                .accessibilityIdentifier("club.postAuthor.open.\(post.id)")
            } else if let author = post.authorMemberID, author > 0, let open = model.context.onAuthor {
                // Retain explicit callback hosts without manufacturing a default callback.
                Button { if sourceActive && currentPost { open(author) } } label: { authorLabel }
                    .buttonStyle(.borderless)
            } else { authorLabel }
        }
        .sheet(item: $selected) { target in
            if let profile {
                ClubPostAuthorDestination(target: target, identity: identity, profile: profile, model: model)
                    .presentationDetents([.large]).presentationCompactAdaptation(.sheet)
            }
        }
        .onChange(of: context) { _, _ in selected = nil }
        .onChange(of: post) { _, _ in selected = nil }
        .onAppear { sourceActive = true }
        .onDisappear { sourceActive = false }
    }
    private func current(_ target: ClubPostAuthorRoute) -> Bool {
        guard currentPost, profile?.reader.isConfigured == true, let context else { return false }
        return target.isCurrent(acceptedPosts: model.snapshot?.posts, context: context)
    }
    private var authorLabel: some View {
        Group { if post.nickname.isEmpty { Text("club.community.user") } else { Text(verbatim: post.nickname) } }
            .frame(minHeight: 44, alignment: .leading)
    }
}

@MainActor private struct ClubPostAuthorDestination: View {
    let target: ClubPostAuthorRoute
    let identity: ClubReadIdentity
    let profile: ClubEnrollmentProfileContext
    @ObservedObject var model: ClubCommunityViewModel
    @Environment(\.dismiss) private var dismiss
    private var context: ClubPostAuthorContext {
        .init(clubID: target.context.clubID, identity: identity, readScope: model.imageReadScope,
              profileIdentity: profile.reader.identity, profileRevision: profile.reader.presentationRevision,
              profileReader: ObjectIdentifier(profile.reader), squareReader: ObjectIdentifier(profile.squareReader),
              squareScope: profile.squareReader.scope)
    }
    private var current: Bool {
        (try? model.context.currentSession().identity) == identity && profile.reader.isConfigured &&
        target.isCurrent(acceptedPosts: model.snapshot?.posts, context: context)
    }
    var body: some View {
        NavigationStack {
            if current {
                SocialPublicProfileView(memberID: target.memberID, reader: profile.reader,
                                        squareReader: profile.squareReader, actions: profile.actions)
                    .id(target.id)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("action.close") { dismiss() }.accessibilityIdentifier("club.postAuthor.close")
                        }
                    }
            } else { Color.clear.onAppear { dismiss() } }
        }
        .onChange(of: context) { _, _ in dismiss() }
    }
}
