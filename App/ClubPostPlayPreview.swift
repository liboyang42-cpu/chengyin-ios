import SwiftUI

/// Existing host composition only. Constructing this context grants no play reads,
/// answers, run writes, rewards or payments; the runtime retains those decisions.
@MainActor struct ClubPostPlayHost {
    let identity: ClubReadIdentity
    let viewerRevision: UInt64
    let identifier: ObjectIdentifier
    let isCurrent: () -> Bool
    let destination: (PlaySessionScope) -> AnyView?
    static func session(_ session: AppSession?) -> Self? {
        guard let session else { return nil }
        let identity = session.clubIdentity, revision = session.contentDetailRevision
        let current: () -> Bool = { [weak session] in
            session?.clubIdentity == identity && session?.contentDetailRevision == revision
        }
        return .init(identity: identity, viewerRevision: revision, identifier: ObjectIdentifier(session), isCurrent: current,
                     destination: { [weak session] scope in
            guard let session, current(), case .topic = scope, scope.isValid else { return nil }
            return AnyView(ClubPostPlaySessionDestination(session: session, scope: scope, identity: identity, revision: revision))
        })
    }
}
private struct ClubPostPlayHostKey: EnvironmentKey {
    static let defaultValue: ClubPostPlayHost? = nil
}
extension EnvironmentValues {
    var clubPostPlayHost: ClubPostPlayHost? {
        get { self[ClubPostPlayHostKey.self] }
        set { self[ClubPostPlayHostKey.self] = newValue }
    }
}

@MainActor struct ClubPostPlayPreview: View {
    let post: ClubCommunityPost
    let clubID: Int?
    let identity: ClubReadIdentity
    @ObservedObject var model: ClubCommunityViewModel
    let openComments: () -> Void
    @Environment(\.clubPostPlayHost) private var host
    @State private var selected: ClubPostPlayRoute?
    @State private var sourceActive = true
    private var context: ClubPostPlayContext {
        .init(clubID: clubID, identity: identity, readScope: model.imageReadScope,
              hostIdentifier: host?.identifier, viewerRevision: host?.viewerRevision ?? 0)
    }
    private var route: ClubPostPlayRoute? {
        guard (try? model.context.currentSession().identity) == identity, let posts = model.snapshot?.posts else { return nil }
        return .init(post: post, acceptedPosts: posts, context: context)
    }
    private func current(_ target: ClubPostPlayRoute) -> Bool {
        (try? model.context.currentSession().identity) == identity &&
        target.isCurrent(acceptedPosts: model.snapshot?.posts, context: context)
    }
    var body: some View {
        Group {
            if let target = route {
                switch target.destination {
                case .comments:
                    Button {
                        guard sourceActive, current(target) else { return }; openComments()
                    } label: { tryLabel }
                    .accessibilityHint("club.community.comments")
                    .accessibilityIdentifier("club.postPlay.comments.\(post.id)")
                case .gameplay:
                    if let host, host.identity == identity, host.isCurrent() {
                        Button {
                            guard sourceActive, selected == nil, host.identity == identity, host.isCurrent(), current(target) else { return }
                            selected = target
                        } label: { tryLabel }
                        .accessibilityHint("club.postPlay.hint")
                        .accessibilityIdentifier("club.postPlay.open.\(post.id)")
                    }
                }
            }
        }
        .buttonStyle(.borderless)
        .sheet(item: $selected) { target in
            if let host {
                ClubPostPlayDestination(target: target, identity: identity, host: host, model: model)
                    .presentationDetents([.large]).presentationCompactAdaptation(.sheet)
            }
        }
        .onChange(of: context) { _, _ in selected = nil }
        .onChange(of: post) { _, _ in selected = nil }
        .onAppear { sourceActive = true }
        .onDisappear { sourceActive = false }
    }
    private var tryLabel: some View {
        Label("club.postPlay.try", systemImage: "play.circle")
            .frame(minHeight: 44, alignment: .leading)
            .accessibilityValue(Text(verbatim: post.sportName))
    }
}

@MainActor private struct ClubPostPlayDestination: View {
    let target: ClubPostPlayRoute
    let identity: ClubReadIdentity
    let host: ClubPostPlayHost
    @ObservedObject var model: ClubCommunityViewModel
    @Environment(\.dismiss) private var dismiss
    private var context: ClubPostPlayContext {
        .init(clubID: target.context.clubID, identity: identity, readScope: model.imageReadScope,
              hostIdentifier: host.identifier, viewerRevision: host.viewerRevision)
    }
    private var current: Bool {
        host.identity == identity && host.isCurrent() && (try? model.context.currentSession().identity) == identity &&
        target.isCurrent(acceptedPosts: model.snapshot?.posts, context: context)
    }
    var body: some View {
        NavigationStack {
            if current, case let .gameplay(scope) = target.destination, let destination = host.destination(scope) {
                destination.id(target.id)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("action.close") { dismiss() }.accessibilityIdentifier("club.postPlay.close")
                        }
                    }
            } else { Color.clear.onAppear { dismiss() } }
        }
        .onChange(of: context) { _, _ in dismiss() }
    }
}

/// Observes the actual session even while nested gameplay or login is presented.
/// A changed account/epoch/role revision retires this entry; it never replays it.
@MainActor private struct ClubPostPlaySessionDestination: View {
    @ObservedObject var session: AppSession
    let scope: PlaySessionScope
    let identity: ClubReadIdentity
    let revision: UInt64
    @Environment(\.dismiss) private var dismiss
    @State private var showingLogin = false
    private var current: Bool { session.clubIdentity == identity && session.contentDetailRevision == revision }
    var body: some View {
        Group {
            if !current { Color.clear.onAppear { dismiss() } }
            else if session.account == nil {
                VStack(spacing: 16) {
                    PlayIssueView(issue: .init(APIError.unauthorized))
                    Button("auth.signIn") { if current { showingLogin = true } }
                        .accessibilityIdentifier("club.postPlay.signIn")
                }.padding()
            } else {
                SessionPlayRuntimeView(session: session, destination: .journey(scope))
            }
        }
        .privacySensitive()
        .sheet(isPresented: $showingLogin) { LoginView(intent: .player) }
        .onChange(of: current) { _, valid in
            if !valid { showingLogin = false; dismiss() }
        }
    }
}
