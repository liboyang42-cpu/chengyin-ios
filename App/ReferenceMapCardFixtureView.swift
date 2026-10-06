#if DEBUG
import SwiftUI

/// Synthetic typography only. No reference artwork, location, or external image request.
struct ReferenceMapCardFixtureView: View {
    static let longTitle = "A very long neighborhood discovery walk with the complete destination name · 城市街区探索漫步与完整目的地名称，重要信息保留到最后"
    static let longSubtitle = "Meet beside the accessible entrance near the public square. Keep the complete meeting instructions visible at every text size. 请在公共广场附近的无障碍入口集合，所有字号都应完整显示集合说明，不能省略最后一段。"
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                QuestifyImageEntityCard(imageSource: nil, title: Self.longTitle, subtitle: Self.longSubtitle, minimumHeight: 230) {
                    QuestifyImageEntityMetadata(label: "searchMap.kind.merchant", value: "Synthetic merchant · 合成商户", systemImage: "storefront")
                }.accessibilityIdentifier("reference.card.missing")
                QuestifyImageEntityCard(imageSource: "http://invalid.example/image.png", title: "", subtitle: Self.longSubtitle,
                                        fallbackTitle: "searchMap.untitled", minimumHeight: 230) {
                    Text("searchMap.kind.club")
                }.accessibilityIdentifier("reference.card.invalid")
            }.padding()
        }.appNavigationTitle("searchMap.citySearch")
    }
}
/// Offline marker rendering fixture: never mounts MapKit or requests tiles.
struct MapMarkerStyleFixtureView: View {
    @State private var selectedID: String?
    private let area = RoamSearchArea(coordinate: RoamCoordinate(latitude: 1, longitude: 1)!, label: "Synthetic area")
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SearchMapCanvas(area: area, pins: [
                    SearchMapPin(id: "style-merchant", title: "Synthetic merchant · 合成商户", coordinate: area.coordinate, symbol: "storefront"),
                    SearchMapPin(id: "style-activity", title: ReferenceMapCardFixtureView.longTitle, coordinate: area.coordinate, symbol: "calendar")
                ], selectedID: selectedID, offline: true) { selectedID = $0 }
                Button("searchMap.clearSelection") { selectedID = nil }
                    .frame(minHeight: 44).accessibilityIdentifier("mapStyle.fixture.clear")
            }.padding()
        }
    }
}
/// The production alternative-list component with an offline selection witness.
/// This does not mount MapKit, fetch tiles, or claim provider/VoiceOver acceptance.
struct MapAlternativeListFixtureView: View {
    @State private var selectedID: String?
    @State private var revision = 0
    @State private var mode = "normal"
    private let coordinate = RoamCoordinate(latitude: 1, longitude: 1)!
    private var pins: [SearchMapPin] {
        let first = SearchMapPin(id: "list-first", title: ReferenceMapCardFixtureView.longTitle,
            coordinate: coordinate, symbol: "storefront")
        let second = SearchMapPin(id: "list-second", title: "Same public entrance · 相同公开入口 1234567890",
            coordinate: coordinate, symbol: "calendar")
        if mode == "empty" { return [] }
        if mode == "removed" { return [second] }
        if mode == "duplicates" {
            return [first, SearchMapPin(id: first.id, title: "Duplicate identity must not be selectable",
                coordinate: coordinate, symbol: "flag"), second]
        }
        if mode == "refreshed" {
            return [SearchMapPin(id: first.id, title: "Refreshed public entrance · 更新后的公开入口",
                coordinate: coordinate, symbol: "storefront"), second]
        }
        return [first, second]
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Mirrors a parent receiving a point-selection event without
                // depending on platform projection or an online provider.
                Button("Synthetic point selects second") { selectedID = "list-second" }
                    .frame(minHeight: 44).accessibilityIdentifier("mapList.fixture.pointSecond")
                Button("Clear selection") { selectedID = nil }
                    .frame(minHeight: 44).accessibilityIdentifier("mapList.fixture.clear")
                Text(verbatim: selectedID ?? "none").accessibilityIdentifier("mapList.fixture.selection")
                ForEach(["removed", "duplicates", "refreshed", "empty", "normal", "readOnly"], id: \.self) { value in
                    Button(value) { mode = value; revision += 1 }
                        .frame(minHeight: 44).accessibilityIdentifier("mapList.fixture.\(value)")
                }
                NavigationLink("Synthetic departure") {
                    Text("Synthetic away screen").accessibilityIdentifier("mapList.fixture.away")
                }.frame(minHeight: 44).accessibilityIdentifier("mapList.fixture.depart")
                QuestifyMapAlternativeList(pins: pins, selectedID: selectedID, interactionID: revision,
                    onSelect: mode == "readOnly" ? nil : { selectedID = $0 })
            }.padding()
        }
    }
}
#endif
