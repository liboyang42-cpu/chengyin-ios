#if DEBUG
import SwiftUI

@MainActor private final class PublishingFixturePlaces: PublishingPlaceSearching {
    func search(_ query: String) async throws -> [PublishingPlace] {
        [try PublishingPlace(id: "synthetic-place", name: "Synthetic place", address: "Synthetic street", latitude: 31.2, longitude: 121.4)]
    }
}
/// Mount only for --ui-publishing-modes. It never creates a network service or account.
@MainActor struct PublishingModesFixtureHost: View {
    @State private var seed: ProjectEditDraft?
    var body: some View {
        NavigationStack {
            PublishingModesView(service: nil, account: nil, placeSearch: PublishingFixturePlaces(), openProfessional: { seed = $0 }, openResource: { _ in })
                .sheet(isPresented: Binding(get: { seed != nil }, set: { if !$0 { seed = nil } })) {
                    if let seed { List { Text("Synthetic editor seed; nothing published"); Text(seed.name).accessibilityIdentifier("publishModes.fixture.seed"); Text(seed.preserved["publishMode"] == .string("ai_simple") ? "ai_simple" : "unexpected") } }
                }
        }
    }
}
#endif
