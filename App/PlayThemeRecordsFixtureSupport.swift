#if DEBUG
import SwiftUI

/// Synthetic theme history pages and result cards (`--play-theme-records-scenario content|empty|failure`).
@MainActor final class PlayThemeRecordsFixtureReader: PlayThemeRecordsReading {
    let scenario: String
    private var cardFailures = 0
    init(scenario: String) { self.scenario = scenario }
    func history(topicID: Int, beforeSessionID: Int?) async throws -> [PlayWireValue] {
        if scenario == "failure" { throw PlayExperienceError.unknownResult }
        if scenario == "empty" { return [] }
        let json: String
        if beforeSessionID == nil {
            let rows = (0..<20).map { index -> String in
                let id = 900 - index
                if index == 0 { return #"{"sessionId":\#(id),"topicId":\#(topicID),"sceneName":"Old harbour","result":{"success":true,"summary":"Found the lighthouse key","endedAt":1790000000000}}"# }
                if index == 1 { return #"{"sessionId":\#(id),"topicId":\#(topicID),"result":{"reason":"HP_ZERO"}}"# }
                return #"{"sessionId":\#(id),"topicId":\#(topicID)}"#
            }
            json = "[" + rows.joined(separator: ",") + "]"
        } else {
            json = #"[{"sessionId":\#(beforeSessionID!),"topicId":\#(topicID)},{"sessionId":700,"topicId":\#(topicID),"result":{"title":"A quiet ending"}}]"#
        }
        return try JSONDecoder().decode([PlayWireValue].self, from: Data(json.utf8))
    }
    func card(sessionID: Int) async throws -> PlayWireValue {
        if sessionID == 899, cardFailures == 0 { cardFailures += 1; throw PlayExperienceError.unknownResult }
        let json = #"{"title":"Lighthouse reached","summary":"The keeper's log is yours.","scene":"Old harbour","hp":7,"hpName":"Stamina","luck":3,"actions":12,"items":[{"name":"Brass key","quantity":1}],"unlocks":{"known":[{"id":"e1","title":"Dawn"}]},"nextScene":{"name":"Fish market"}}"#
        return try JSONDecoder().decode(PlayWireValue.self, from: Data(json.utf8))
    }
}

@MainActor struct PlayThemeRecordsFixtureHost: View {
    @State private var model: PlayThemeRecordsCoordinator
    init() {
        let args = ProcessInfo.processInfo.arguments
        let index = args.firstIndex(of: "--play-theme-records-scenario")
        let scenario = index.flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } ?? "content"
        _model = State(initialValue: PlayThemeRecordsCoordinator(topicID: 71, reader: PlayThemeRecordsFixtureReader(scenario: scenario)))
    }
    var body: some View {
        NavigationStack { PlayThemeRecordsView(model: model, title: "Harbour nights") }
    }
}
#endif
