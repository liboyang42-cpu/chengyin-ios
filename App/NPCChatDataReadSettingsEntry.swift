import SwiftUI

struct NPCChatDataReadPresentation: Identifiable {
    let id = UUID()
    let identity: AppSession.NPCChatDataReadIdentity
    let coordinator: NPCChatDataCoordinator
}
/// A persistent entry even with no lease; the disabled reader explains unavailability without requiring a write journal.
@MainActor struct NPCChatDataReadSettingsEntry: View {
    @ObservedObject var session: AppSession
    @Environment(\.scenePhase) private var scene
    @State private var presentation: NPCChatDataReadPresentation?
    var body: some View {
        let renderedIdentity = session.npcChatDataReadIdentity
        Section {
            Button("npcData.title") {
                guard scene == .active, session.npcChatDataReadIdentity == renderedIdentity else { return }
                retire()
                presentation = .init(identity: renderedIdentity, coordinator: session.makeNPCChatDataReadCoordinator())
            }.accessibilityIdentifier("npcData.open")
        }
        .sheet(item: $presentation) { NPCChatDataReadVisit(presentation: $0, session: session) }
        .onChange(of: session.npcChatDataReadIdentity) { _, _ in retire() }
        .onDisappear { retire() }
    }
    private func retire() { presentation?.coordinator.invalidate(); presentation = nil }
}
/// The visible sheet independently observes identity; its hidden Settings parent is not the privacy fence.
@MainActor struct NPCChatDataReadVisit: View {
    let presentation: NPCChatDataReadPresentation
    @ObservedObject var session: AppSession
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Group {
            if session.npcChatDataReadIdentity == presentation.identity {
                NPCChatDataView(coordinator: presentation.coordinator)
            } else {
                NavigationStack {
                    Text("npcData.contentCleared")
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("action.done") { dismiss() } } }
                }
            }
        }
        .privacySensitive()
        .onChange(of: session.npcChatDataReadIdentity) { _, _ in presentation.coordinator.invalidate() }
        .onDisappear { presentation.coordinator.invalidate() }
    }
}
