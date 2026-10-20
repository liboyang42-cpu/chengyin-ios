import SwiftUI
import Observation

/// A captured Settings destination, never an approval to read or modify favorites.
@MainActor struct ProfileSettingsFavoritesAccess {
    struct Key: Hashable {
        let identity: SocialAccountIdentity
        let viewerRevision: UInt64
        let dependency: ObjectIdentifier
        let scope: UUID
        let configured: Bool
        let removal: ObjectIdentifier?
    }
    let key: Key
    let reader: ProfileFavoritesReader
    let removal: ProfileFavoriteRemovalController?
    let communityGate: (any SquareCommunityFeatureReading)?

    init?(accountID: Int, identity: SocialAccountIdentity, viewerRevision: UInt64,
          reader: ProfileFavoritesReader, removal: ProfileFavoriteRemovalController? = nil,
          communityGate: (any SquareCommunityFeatureReading)? = nil) {
        guard accountID > 0, identity.accountID == accountID, reader.isAuthenticated else { return nil }
        key = .init(identity: identity, viewerRevision: viewerRevision,
            dependency: ObjectIdentifier(reader), scope: reader.scope, configured: reader.isConfigured, removal: removal.map(ObjectIdentifier.init))
        self.reader = reader; self.removal = removal; self.communityGate = communityGate
    }
    static func current(_ session: AppSession) -> Self? {
        guard let account = session.account else { return nil }
        return .init(accountID: account.id, identity: session.socialAccountReader.identity,
            viewerRevision: session.contentDetailRevision, reader: session.profileFavoritesReader,
            removal: session.makeProfileFavoriteRemovalController(scope: session.profileFavoritesReader.scope),
            communityGate: session.squareReader)
    }
}

struct ProfileSettingsFavoritesRoute: Identifiable, Hashable {
    let id = UUID()
    let access: ProfileSettingsFavoritesAccess
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Lives on the Settings NavigationStack, not on a lazy row or a covered list.
/// Popping the collection consumes its route; stale callbacks cannot open its successor.
@MainActor @Observable final class ProfileSettingsFavoritesOwner {
    private(set) var route: ProfileSettingsFavoritesRoute?
    let posts = ProfileFavoriteNavigationOwner()
    let topics = ProfileFavoriteTopicNavigationOwner()
    private var key: ProfileSettingsFavoritesAccess.Key?
    private var mounted = false
    private var retired = false
    private var foreground = false

    func appear(current: ProfileSettingsFavoritesAccess?, foreground: Bool) {
        guard !retired else { return }
        mounted = true
        synchronize(current)
        setForeground(foreground)
    }
    func synchronize(_ current: ProfileSettingsFavoritesAccess?) {
        guard !retired else { return }
        if key != current?.key { retireRoute(); key = current?.key }
    }
    func setForeground(_ value: Bool) {
        foreground = value && mounted && !retired
        posts.setForeground(foreground); topics.setForeground(foreground)
    }
    func retire() {
        retired = true; mounted = false; foreground = false
        retireRoute(); key = nil
    }
    @discardableResult func open(_ access: ProfileSettingsFavoritesAccess?) -> Bool {
        guard mounted, !retired, foreground, route == nil, let access, key == access.key else { return false }
        route = .init(access: access)
        posts.appear(scope: access.key.scope, foreground: foreground)
        topics.appear(scope: access.key.scope, foreground: foreground)
        return true
    }
    func accepts(_ offered: ProfileSettingsFavoritesRoute, current: ProfileSettingsFavoritesAccess?) -> Bool {
        mounted && !retired && route?.id == offered.id && key == offered.access.key && current?.key == offered.access.key
    }
    @discardableResult func close(_ id: UUID) -> Bool {
        guard route?.id == id else { return false }
        retireRoute(); return true
    }
    func binding(for offered: ProfileSettingsFavoritesRoute) -> Binding<ProfileSettingsFavoritesRoute?> {
        Binding(get: { self.route?.id == offered.id ? self.route : nil }, set: { next in
            if next == nil { _ = self.close(offered.id) }
        })
    }
    @discardableResult func openPost(_ post: SquareContentRoute, from offered: ProfileSettingsFavoritesRoute,
                                    current: ProfileSettingsFavoritesAccess?) -> Bool {
        guard foreground, accepts(offered, current: current), posts.selection == nil, topics.selection == nil,
              let selected = offered.access.reader.selectPost(post, renderedScope: offered.access.key.scope) else { return false }
        guard posts.open(selected, scope: offered.access.key.scope) else { selected.retire(); return false }
        return true
    }
    @discardableResult func openTopic(_ topicID: Int, from offered: ProfileSettingsFavoritesRoute,
                                     current: ProfileSettingsFavoritesAccess?) -> Bool {
        guard foreground, accepts(offered, current: current), posts.selection == nil, topics.selection == nil,
              let selected = offered.access.reader.selectTopic(topicID, renderedScope: offered.access.key.scope) else { return false }
        guard topics.open(selected, scope: offered.access.key.scope) else { selected.retire(); return false }
        return true
    }
    private func retireRoute() {
        posts.disappear(); topics.disappear(); route = nil
    }
}

@MainActor struct ProfileSettingsFavoritesEntry: View {
    @ObservedObject var session: AppSession
    let owner: ProfileSettingsFavoritesOwner
    var body: some View {
        if ProfileSettingsFavoritesAccess.current(session) != nil {
            Section {
                Button { owner.open(.current(session)) } label: {
                    Label("accountCollection.favorites.title", systemImage: "heart")
                }
                .accessibilityHint(Text("settingsNative.favorites.openHint", tableName: "ProfileSettingsFavorites"))
                .accessibilityIdentifier("settingsNative.openFavorites")
            }
        }
    }
}

@MainActor struct ProfileSettingsFavoritesNavigation: ViewModifier {
    @ObservedObject var session: AppSession
    let owner: ProfileSettingsFavoritesOwner
    func body(content: Content) -> some View {
        content.background {
            if let route = owner.route {
                Color.clear.navigationDestination(item: owner.binding(for: route)) { offered in
                    ProfileSettingsFavoritesDestination(route: offered, owner: owner, current: { .current(session) })
                }.id(route.id)
            }
            ProfileFavoriteNavigationLayer(owner: owner.posts) { selected in
                ProfileFavoriteDetailDestination(selection: selected,
                    makeReader: { session.makeProfileFavoriteDetailReader(selected) },
                    accountReader: session.socialAccountReader, actions: session.socialActionCoordinator).id(selected.id)
            }
            ProfileFavoriteTopicNavigationLayer(owner: owner.topics) { selected in
                ProfileFavoriteTopicDestination(selection: selected, session: session,
                    makeReader: { session.makeProfileFavoriteTopicReader(selected) }).id(selected.id)
            }
        }
    }
}

@MainActor struct ProfileSettingsFavoritesDestination: View {
    let route: ProfileSettingsFavoritesRoute
    let owner: ProfileSettingsFavoritesOwner
    let current: () -> ProfileSettingsFavoritesAccess?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Group {
            if owner.accepts(route, current: current()) {
                AccountCollectionFavoritesView(reader: route.access.reader,
                    onOpenTopic: { owner.openTopic($0, from: route, current: current()) },
                    onOpenPost: { owner.openPost($0, from: route, current: current()) },
                    favoriteRemoval: route.access.removal,
                    communityGate: route.access.communityGate).id(route.id)
            } else {
                ContentUnavailableView {
                    Label { Text("settingsNative.favorites.changed", tableName: "ProfileSettingsFavorites") } icon: { Image(systemName: "person.crop.circle.badge.exclamationmark") }
                } actions: {
                    Button("action.close") { dismiss() }.accessibilityIdentifier("settingsNative.favorites.closeChanged")
                }
            }
        }.accessibilityIdentifier("settingsNative.favorites.destination")
    }
}

/// Attach to the whole stack: pushing details, authors or chapters must not retire it.
@MainActor struct ProfileSettingsFavoritesLifecycle: ViewModifier {
    @ObservedObject var session: AppSession
    let owner: ProfileSettingsFavoritesOwner
    @Environment(\.scenePhase) private var scenePhase
    func body(content: Content) -> some View {
        content
            .onAppear { owner.appear(current: .current(session), foreground: scenePhase == .active) }
            .onChange(of: ProfileSettingsFavoritesAccess.current(session)?.key) { _, _ in owner.synchronize(.current(session)) }
            .onChange(of: scenePhase) { _, phase in owner.setForeground(phase == .active) }
            .onDisappear { owner.retire() }
    }
}
