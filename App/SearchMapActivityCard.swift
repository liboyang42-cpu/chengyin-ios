import SwiftUI

/// Same source-backed card in both the result list and selected-point summary.
/// This view has no reader, location request, navigation state or write capability.
struct SearchMapActivityCard: View {
    let item: ActivitySummary
    let offline: Bool
    @State private var phoneTimeZone = TimeZone.current
    var presentation: SearchMapActivityPresentation { .init(item) }

    var body: some View {
        let value = presentation
        QuestifyImageEntityCard(imageSource: offline ? nil : item.imageURL, title: item.name,
                               fallbackTitle: "searchMap.untitled", fallbackSymbol: "calendar", minimumHeight: 230) {
            Label(LocalizedStringKey(value.pointLabelKey), systemImage: value.pointKind == .topic ? "point.topleft.down.to.point.bottomright.curvepath" : "calendar")
            if !value.categoryNames.isEmpty {
                QuestifyImageEntityMetadata(label: "mapActivity.categories", value: value.categoryNames.joined(separator: " · "), systemImage: "tag")
            }
            if value.linkedTopicID != nil { Label("mapActivity.relatedRoute", systemImage: "link") }
            if let address = value.address {
                QuestifyImageEntityMetadata(label: "searchMap.address", value: address, systemImage: "mappin.and.ellipse")
            } else { Label("mapActivity.addressUnknown", systemImage: "mappin.slash") }
            timestamp(value.starts, label: "mapActivity.starts")
            timestamp(value.ends, label: "mapActivity.ends")
        }
        .accessibilityElement(children: .combine)
        .onAppear { phoneTimeZone = .current }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in phoneTimeZone = .current }
    }
    private func timestamp(_ time: SearchMapActivityTime, label: LocalizedStringKey) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption)
                if let text = time.display(phoneTimeZone: phoneTimeZone) { Text(verbatim: text) }
                else { Text("mapActivity.timeUnknown") }
            }
        } icon: { Image(systemName: "clock").accessibilityHidden(true) }
        .accessibilityElement(children: .combine)
    }
}
