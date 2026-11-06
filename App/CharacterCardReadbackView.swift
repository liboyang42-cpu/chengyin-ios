import SwiftUI

/// Leaves the card retired when the page goes away. A late read cannot refill it.
@available(macOS 14.0, *)
@MainActor struct CharacterCardReadbackView: View {
    @ObservedObject var session: AppSession
    let model: CharacterCardReadback
    var body: some View {
        let _ = session.account?.id
        let card = model.cardIfCurrent()
        // Mini-program subpackageMember/character: 我的角色卡 with the run's traits; states are user words, never raw availability codes.
        Group {
            if model.isCurrent, model.availability == .unknown {
                ContentUnavailableView {
                    Label("characterCard.unavailable", systemImage: "person.text.rectangle")
                } actions: {
                    Button("characterCard.refresh") { Task { await model.load() } }
                }
            } else if model.isCurrent, let card {
                if card.attributes.isEmpty {
                    ContentUnavailableView("characterCard.empty", systemImage: "person.text.rectangle")
                } else {
                    List {
                        Section("characterCard.traits") {
                            ForEach(card.attributes) { attribute in
                                LabeledContent(attribute.label, value: String(attribute.value))
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable { await model.load() }
                }
            } else {
                ProgressView("characterCard.loading")
            }
        }
        .appNavigationTitle("characterCard.title")
        .task { await model.load() }
        .onDisappear { model.dismiss() }
    }
}
