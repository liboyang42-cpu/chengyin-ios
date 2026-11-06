#if DEBUG
import SwiftUI

/// Synthetic `api/activity/list` page for the finish-sheet card
/// (`--play-finish-route-scenario content|sameTopic|disabled|noOrigin`). Offline only.
@MainActor final class PlayFinishRouteFixtureReader: PlayFinishRouteReading {
    let scenario: String
    init(scenario: String) { self.scenario = scenario }
    func rows(origin: PlayFinishOrigin) async throws -> [PlayFinishRouteRow] {
        let rows = scenario == "sameTopic"
            ? #"[{"id":41,"name":"Current route","topicId":9},{"id":42,"topicId":9}]"#
            : #"[{"id":41,"name":"Current route","topicId":9},{"id":43,"name":"Harbour lights walk","topicId":10,"distance":1250,"addressName":"Pier 3","minAmout":39,"imgUrl":"https://finish-route.invalid/a.jpg,https://finish-route.invalid/b.jpg"}]"#
        return try JSONDecoder().decode([PlayFinishRouteRow].self, from: Data(rows.utf8))
    }
}

@MainActor struct PlayFinishRouteFixtureHost: View {
    @State private var model: PlayFinishRouteRecommendationCoordinator
    private let origin: PlayFinishOrigin?
    init() {
        let args = ProcessInfo.processInfo.arguments
        let index = args.firstIndex(of: "--play-finish-route-scenario")
        let scenario = index.flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } ?? "content"
        _model = State(initialValue: PlayFinishRouteRecommendationCoordinator(featureEnabled: scenario != "disabled",
            reader: PlayFinishRouteFixtureReader(scenario: scenario), currentActivityID: 41, currentTopicID: 9))
        origin = scenario == "noOrigin" ? nil : PlayFinishOrigin(latitude: 31.2, longitude: 121.5)
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("playx.finishRoute.fixtureLoaded").accessibilityIdentifier("playx.finishRoute.fixture")
                    if let card = model.card {
                        PlayFinishRouteCardView(card: card) { id in AnyView(Text(verbatim: "activity \(id)").accessibilityIdentifier("playx.finishRoute.destination")) }
                    }
                }
            }
            .task { await model.show(origin: origin) }
        }
    }
}
#endif
