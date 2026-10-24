import SwiftUI

/// Leaves the card retired when the page goes away. A late read cannot refill it.
@available(macOS 14.0, *)
@MainActor struct CharacterCardReadbackView: View {
    @ObservedObject var session: AppSession
    let model: CharacterCardReadback
    var body: some View {
        let _ = session.account?.id
        let card = model.cardIfCurrent()
        Group {
            if model.isCurrent, model.availability == .unknown {
                Text("UNKNOWN")
            } else if model.isCurrent, let card {
                List(card.attributes) { attribute in
                    LabeledContent(attribute.label, value: String(attribute.value))
                }
            } else {
                Text("WAITING_SOURCE")
            }
        }
        .task { await model.load() }
        .onDisappear { model.dismiss() }
    }
}
