#if DEBUG
import SwiftUI

/// DEBUG-only `--roam-subpage-fixture <scenario>` host for the subpackageRoam parity pieces.
/// Synthetic data only; no session, network, location, camera or write path.
@MainActor struct RoamSubpageFixtureHost: View {
    static let argument = "--roam-subpage-fixture"
    static var selected: Bool { ProcessInfo.processInfo.arguments.contains(argument) }
    static let nodeJSON = #"{"poiId":7101,"name":"Demo courtyard","status":0,"validationMethod":1,"completed":false,"favorited":true,"needRedeem":true,"couponId":88,"templateTitle":"Courtyard clue"}"#
    static let liveNodeJSON = #"{"poiId":7102,"name":"Demo lane","status":1,"validationMethod":3,"completed":false,"favorited":false,"needRedeem":false}"#
    static let exchangedJSON = #"{"exchanged":true,"stamp":{"id":12345,"picUrl":"","caption":"Soy milk opens at seven","checkState":1,"createTime":"2026-10-18T09:30:00"}}"#
    static let noExchangeJSON = #"{"exchanged":false}"#
    let scenario: String
    @State private var historyReader = RoamExperienceFixtureReader(scenario: .content)
    @State private var shareReader = RoamShareSnapshotFixtureReader()
    @State private var toolsReader = RoamPassportToolsFixtureReader(scenario: .content)
    init() {
        let args = ProcessInfo.processInfo.arguments
        let index = args.firstIndex(of: Self.argument)
        scenario = index.flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } ?? "history"
    }
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) -> T? { try? JSONDecoder().decode(type, from: Data(json.utf8)) }
    var body: some View {
        NavigationStack {
            switch scenario {
            case "history": RoamHistoryView(reader: historyReader, toolsReader: toolsReader)
            case "sharedReady": RoamSharedFootprintView(token: RoamShareSnapshotFixtureReader.readyToken, reader: shareReader)
            case "sharedGone": RoamSharedFootprintView(token: RoamShareSnapshotFixtureReader.goneToken, reader: shareReader, onOpenRoam: {})
            case "sharedError": RoamSharedFootprintView(token: String(repeating: "a", count: 32), reader: shareReader)
            case "sharedUnavailable": RoamSharedFootprintView(token: RoamShareSnapshotFixtureReader.readyToken, reader: nil)
            case "poiOffline", "poiLive":
                List {
                    if let node = decode(RoamNodeDetail.self, scenario == "poiOffline" ? Self.nodeJSON : Self.liveNodeJSON) {
                        RoamPOINodeParityCard(node: node)
                    }
                }.navigationTitle(Text(verbatim: "POI"))
            case "poiUnavailable": RoamPOIUnavailableView(onBack: {})
            case "poiMissing": RoamPOIMissingView(onBack: {})
            case "voucherMissing": RoamCityVoucherCodeView(poiID: nil)
            case "voucherDisabled": RoamCityVoucherCodeView(poiID: 7101, name: "Demo courtyard")
            case "stampExchanged", "stampNoExchange":
                RoamCityStampFlowView(kind: "sticker", place: "Demo lane",
                                      fixtureReceipt: decode(RoamStampExchangeReceipt.self, scenario == "stampExchanged" ? Self.exchangedJSON : Self.noExchangeJSON))
            default: RoamCityStampFlowView(kind: nil, place: nil)
            }
        }
    }
}
#endif
