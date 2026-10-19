#if DEBUG
import SwiftUI

/// w2-19 offline fixture router: `--uitesting-module merchant-city-npc --w2-19-page <page> --w2-19-scenario <scenario>`.
@MainActor struct MerchantCityNPCParityFixtureHost: View {
    private let page: String
    private let scenario: String
    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        func value(_ flag: String) -> String? {
            guard let i = arguments.firstIndex(of: flag), arguments.indices.contains(i + 1) else { return nil }
            return arguments[i + 1]
        }
        page = value("--w2-19-page") ?? "coopCenter"; scenario = value("--w2-19-scenario") ?? "normal"
    }
    var body: some View {
        switch page {
        case "cityNode": MerchantCityNodeHubFixtureHost(scenario: scenario)
        case "cityNodeCreate": MerchantCityNodeCreateFixtureHost(scenario: scenario)
        case "aiNPC": MerchantStoreCharacterFixtureHost(scenario: scenario)
        case "playMerchant": PlayStoreDayMerchantFixtureHost(scenario: scenario)
        default: MerchantCoopCenterFixtureHost(scenario: scenario)
        }
    }
}
#endif
