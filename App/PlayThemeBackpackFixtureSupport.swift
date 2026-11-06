#if DEBUG
import SwiftUI

/// Synthetic `play/theme/state` views (`--play-backpack-scenario content|zero|failure`). Offline only.
@MainActor final class PlayThemeBackpackFixtureReader: PlayThemeBackpackReading {
    let scenario: String
    init(scenario: String) { self.scenario = scenario }
    func state() async throws -> PlayWireValue {
        if scenario == "failure" { throw PlayExperienceError.rejected(500, nil) }
        let zero = scenario == "zero" ? #","awaitingChallenge":true,"zeroHp":{"phase":"RECOVERING","policy":"STEPS","progress":1200,"required":3000}"# : ""
        let json = #"{"sessionId":61,"used":3,"capacity":6,"hpEnabled":true,"hp":\#(scenario == "zero" ? 0 : 7),"hpMax":10,"hpName":"Stamina","luckEnabled":true,"luck":2,"luckMax":5,"actionLimit":12,"actions":4,"attributes":[{"key":"rep","label":"Reputation","value":3},{"key":"sys.hidden","label":"Hidden","value":1}],"contents":[{"kind":"ITEM","id":"tea","name":"Herbal tea","stat":"sys.hp","delta":2,"quantity":2,"slotCost":1},{"kind":"ITEM","id":"map","quantity":1},{"kind":"NOTE","id":"n1","name":"Torn note","content":"Meet at the pier."}],"pending":{"r1":{"name":"Lantern","quantity":1,"slots":1}},"clues":[{"id":"c1","name":"Harbour rumour","scope":"PUBLIC","sources":[{"title":"Pier 3","blocks":[{"text":"Fog at dawn.","images":["https://backpack.invalid/a.jpg"]}]}]}],"itemCatalog":[{"id":"map","name":"Old map"}]\#(zero)}"#
        return try JSONDecoder().decode(PlayWireValue.self, from: Data(json.utf8))
    }
}

@MainActor struct PlayThemeBackpackFixtureHost: View {
    @State private var model: PlayThemeBackpackCoordinator
    init() {
        let args = ProcessInfo.processInfo.arguments
        let index = args.firstIndex(of: "--play-backpack-scenario")
        let scenario = index.flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } ?? "content"
        _model = State(initialValue: PlayThemeBackpackCoordinator(reader: PlayThemeBackpackFixtureReader(scenario: scenario)))
    }
    var body: some View { NavigationStack { PlayThemeBackpackView(model: model) } }
}
#endif
