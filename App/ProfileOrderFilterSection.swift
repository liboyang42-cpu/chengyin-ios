import SwiftUI

/// Uses only the enclosing screen's already-read rows. A filter selection never reloads.
struct ProfileOrderFilterSection: View {
    @Binding var selection: ProfileOrderHistoryFilter
    let isEmpty: Bool
    var body: some View {
        Section {
            Picker("profile.orderFilter.title", selection: $selection) {
                ForEach(ProfileOrderHistoryFilter.allCases) { filter in
                    Text(LocalizedStringKey(filter.titleKey)).tag(filter)
                }
            }.pickerStyle(.menu).accessibilityIdentifier("profile.orderFilter.picker")
            if isEmpty {
                Text("profile.orderFilter.empty").accessibilityIdentifier("profile.orderFilter.empty")
                Button("profile.orderFilter.clear") { selection = .all }
                    .accessibilityIdentifier("profile.orderFilter.clear")
            }
        } footer: {
            Text("profile.orderFilter.localHint")
        }
    }
}
