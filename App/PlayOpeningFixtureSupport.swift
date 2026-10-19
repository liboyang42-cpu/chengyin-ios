#if DEBUG
import SwiftUI

/// Synthetic route-state for the opening 出发 flow
/// (`--play-opening-scenario notReady|ready|conflict|lost`). Nothing leaves the process.
@MainActor final class PlayOpeningFixtureClient: PlayOpeningCompleting {
    let scenario: String
    private(set) var completed = false
    private(set) var submissions = 0
    init(scenario: String) { self.scenario = scenario }
    func route() async throws -> PlayRouteState {
        let ready = scenario != "notReady"
        let version = completed ? 8 : 7
        let json = #"{"routeMode":"LINEAR","version":\#(version),"currentNodeId":31,"opening":{"chapterId":5,"ready":\#(ready),"complete":\#(completed)}}"#
        return try JSONDecoder().decode(PlayRouteState.self, from: Data(json.utf8))
    }
    func complete(chapterID: Int, expectedVersion: Int) async throws {
        submissions += 1
        switch scenario {
        case "conflict": throw PlayExperienceError.rejected(500, "路线已更新，请刷新后重试")
        case "lost": completed = true; throw PlayExperienceError.unknownResult
        default: completed = true
        }
    }
}

@MainActor struct PlayOpeningFixtureHost: View {
    @State private var model: PlayOpeningCompletionCoordinator
    init() {
        let args = ProcessInfo.processInfo.arguments
        let index = args.firstIndex(of: "--play-opening-scenario")
        let scenario = index.flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } ?? "ready"
        _model = State(initialValue: PlayOpeningCompletionCoordinator(client: scenario == "disabled" ? nil : PlayOpeningFixtureClient(scenario: scenario)))
    }
    var body: some View {
        NavigationStack {
            List { PlayOpeningCompletionSection(model: model) }
                .task { await model.load() }
        }
    }
}
#endif
