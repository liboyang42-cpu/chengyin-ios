import SwiftUI

/// Leaves the card retired when the page goes away. A late read cannot refill it.
@available(macOS 14.0, *)
@MainActor struct CharacterCardReadbackView: View {
    let model: CharacterCardReadback
    var body: some View {
        Group {
            if model.availability == .waitingSource {
                Text("WAITING_SOURCE")
            } else if let card = model.card {
                List(card.attributes) { attribute in
                    LabeledContent(attribute.label, value: String(attribute.value))
                }
            } else {
                Text("UNKNOWN")
            }
        }
        .task { await model.load() }
        .onDisappear { model.dismiss() }
    }
}
