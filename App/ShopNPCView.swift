import SwiftUI

@MainActor struct ShopNPCView: View {
    @Bindable var coordinator: ShopNPCCoordinator
    let name: String
    let greeting: String?
    var capture: (any ShopNPCVoiceCapturing)? = nil
    @State private var draft = ""
    @State private var revision = 0
    @State private var sending = false
    @State private var recording = false
    @State private var localFailure: ShopNPCFailure?
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        let _ = revision
        Form {
            Section {
                if coordinator.active {
                    Label(name, systemImage: "person.crop.circle").font(.title2)
                    if let greeting, !greeting.isEmpty { Text(verbatim: greeting) }
                } else { Text("shopNPC.stale") }
                Text("shopNPC.disclosure")
            }
            if !coordinator.grants.textAllowed { Text("shopNPC.disabled").accessibilityIdentifier("shopNPC.disabled") }
            Section("shopNPC.conversation") {
                ForEach(coordinator.messages) { message in
                    VStack(alignment: .leading) {
                        Text(message.mine ? "shopNPC.you" : "shopNPC.assistant").font(.caption)
                        Text(verbatim: message.text).textSelection(.enabled)
                        if !message.mine {
                            Button("shopNPC.regenerate") { attempt { try coordinator.reviewRegeneration(answerID: message.id) } }
                                .disabled(sending).accessibilityIdentifier("shopNPC.regenerate")
                        }
                    }.accessibilityElement(children: .contain)
                }
                if sending { ProgressView("shopNPC.busy").accessibilityIdentifier("shopNPC.busy") }
            }
            Section("shopNPC.question") {
                TextField("shopNPC.question", text: $draft, axis: .vertical).disabled(!coordinator.active).accessibilityIdentifier("shopNPC.input")
                Button("shopNPC.reviewText") { attempt { try coordinator.reviewText(draft) } }
                    .disabled(sending || recording || !coordinator.active || !coordinator.grants.textAllowed || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("shopNPC.reviewText")
                Text("shopNPC.voiceDisclosure")
                Button(recording ? "shopNPC.stopReview" : "shopNPC.record") {
                    attempt {
                        guard let capture else { throw ShopNPCFailure.disabled }
                        if recording { recording = false; try coordinator.reviewVoice(capture.stopForReview()) }
                        else { try capture.startAfterExplicitMicrophoneIntent(grants: coordinator.grants, onEnded: { recording = false }); recording = true }
                    }
                }.disabled(sending || !coordinator.active || capture == nil || !coordinator.grants.voiceAllowed || !coordinator.grants.microphone)
                    .accessibilityIdentifier("shopNPC.record")
                if recording { Button("shopNPC.discard") { capture?.cancel(); recording = false } }
            }
            if let review = coordinator.pending {
                Section("shopNPC.review") {
                    switch review.content {
                    case .text(let text): Text(verbatim: text)
                    case .voice(let clip): Text("shopNPC.voiceReview"); Text(verbatim: "\(clip.bytes.count) bytes · \(Int(clip.duration)) s")
                    }
                    Text("shopNPC.transmissionDisclosure")
                    Button("shopNPC.confirmSend") {
                        sending = true; localFailure = nil
                        Task { await coordinator.transmit(reviewID: review.id); sending = false; revision += 1 }
                    }.disabled(sending || recording).accessibilityIdentifier("shopNPC.confirmSend")
                    Button("shopNPC.cancel", role: .cancel) { coordinator.cancelReview(); revision += 1 }.disabled(sending)
                }
            }
            if let error = localFailure ?? coordinator.failure {
                Section {
                    if case .server(_, let message) = error, let message, !message.isEmpty { Text(verbatim: message) }
                    else { Text(LocalizedStringKey(error.key)) }
                }.accessibilityIdentifier("shopNPC.error")
            }
        }
        .navigationTitle("shopNPC.title").privacySensitive()
        .onDisappear { invalidate() }
        .onChange(of: coordinator.active) { _, active in if !active { clearTransient() } }
        .onChange(of: coordinator.scope) { _, _ in clearTransient() }
        .onChange(of: coordinator.grants) { _, _ in clearTransient() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { invalidate() } }
    }
    private func attempt(_ action: () throws -> Void) {
        do { try action(); localFailure = nil } catch { localFailure = error as? ShopNPCFailure ?? .invalid }
        revision += 1
    }
    private func clearTransient() { capture?.cancel(); recording = false; sending = false; draft = ""; localFailure = nil; revision += 1 }
    private func invalidate() { coordinator.invalidate(); clearTransient() }
}

/// Add to the authoritative free-explore node's detail. Host supplies fresh scoped bindings.
/// Missing/unnamed NPCs never offer an entrance. This is not a merchant-row bridge.
@MainActor struct ShopNPCNodeEntrance: View {
    let name: String?
    let makeCoordinator: (() -> ShopNPCCoordinator)?
    var greeting: String? = nil
    var body: some View {
        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let makeCoordinator {
            NavigationLink("shopNPC.open") { ShopNPCOwnedDestination(makeCoordinator: makeCoordinator, name: name, greeting: greeting) }
                .accessibilityIdentifier("shopNPC.open")
        }
    }
}
