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
#endif
