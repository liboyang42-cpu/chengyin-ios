import SwiftUI

/// Registered by the host's offline --uitesting-module objectCards branch only.
@MainActor struct ObjectCardFixtureHostView: View {
    @State private var reader = ObjectCardFixtureReader()
    @State private var revision = 0
    var body: some View {
        NavigationStack {
            ObjectCardsView(reader: reader)
                .id("\(revision)-\(reader.scope)")
                .safeAreaInset(edge: .bottom) {
                    VStack {
                        Text("objects.offline").font(.caption)
                        HStack {
                            Button("Fail next read") { reader.failNext = true }.accessibilityIdentifier("objects.fixture.fail")
                            Button("Change session") { reader.rotateScope(); revision += 1 }.accessibilityIdentifier("objects.fixture.session")
                        }.font(.caption)
                    }.padding(8).background(.regularMaterial)
                }
        }
    }
}
