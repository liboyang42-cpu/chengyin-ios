import SwiftUI

struct ClubCommunityFeedSourceEntry: View {
    let name: String
    let itemID: String
    var openClub: (() -> Void)? = nil
    var body: some View {
        if let openClub {
            Button(action: openClub) { label }.buttonStyle(.borderless)
                .frame(minHeight: 44, alignment: .leading)
                .accessibilityIdentifier("club.feed.source.\(itemID)")
        } else if !name.isEmpty { label }
    }
    private var label: some View {
        Label {
            if name.isEmpty { Text("club.detail") } else { Text(verbatim: name) }
        } icon: { Image(systemName: "person.3") }
        .font(Theme.Font.label).fixedSize(horizontal: false, vertical: true)
    }
}
