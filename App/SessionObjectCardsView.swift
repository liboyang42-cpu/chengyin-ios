import SwiftUI

/// Observes epoch rotation so navigation detail and selection state are replaced.
@MainActor struct SessionObjectCardsView: View {
    @EnvironmentObject private var session: AppSession
    var body: some View {
        ObjectCardsView(reader: session.objectCardReader).id(session.objectCardReader.scope)
    }
}
