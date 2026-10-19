import SwiftUI

/// The missing-parameter state of the retired circle page (探索链接不完整 / 返回首页).
@MainActor struct PlayCircleRetiredLinkView: View {
    let goHome: () -> Void
    var body: some View {
        ContentUnavailableView {
            Label("playx.circleLink.title", systemImage: "link.badge.plus")
        } description: {
            Text("playx.circleLink.subtitle")
        } actions: {
            Button("playx.circleLink.home", action: goHome)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("playx.circleLink.home")
        }
        .accessibilityIdentifier("playx.circleLink.missing")
    }
}

#if DEBUG
/// `--play-circle-link-query "topicId=12&inviteCode=AB12"`; an empty query shows the missing state.
@MainActor struct PlayCircleLegacyLinkFixtureHost: View {
    @State private var link: PlayCircleLegacyLink
    @State private var wentHome = false
    init() {
        let args = ProcessInfo.processInfo.arguments
        let index = args.firstIndex(of: "--play-circle-link-query")
        let raw = index.flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } ?? ""
        var query: [String: String] = [:]
        for item in URLComponents(string: "?" + raw)?.queryItems ?? [] { query[item.name] = item.value ?? "" }
        _link = State(initialValue: PlayCircleLegacyLink.resolve(query))
    }
    var body: some View {
        NavigationStack {
            switch link {
            case .missingParameter:
                if wentHome { Text("playx.circleLink.fixtureHome").accessibilityIdentifier("playx.circleLink.fixtureHome") }
                else { PlayCircleRetiredLinkView { wentHome = true } }
            case .play(let topicID, let invite, let registration):
                VStack {
                    Text(verbatim: "topic \(topicID)").accessibilityIdentifier("playx.circleLink.redirect.topic")
                    Text(verbatim: "invite \(invite ?? "-")").accessibilityIdentifier("playx.circleLink.redirect.invite")
                    Text(verbatim: "registration \(registration.map(String.init) ?? "-")").accessibilityIdentifier("playx.circleLink.redirect.registration")
                }
            }
        }
    }
}
#endif
