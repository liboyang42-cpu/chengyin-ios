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
    @FocusState private var typing: Bool
    @Environment(\.scenePhase) private var scenePhase
    private var canCompose: Bool {
        coordinator.active && coordinator.grants.textAllowed && !sending && !recording && coordinator.pending == nil
    }
    var body: some View {
        let _ = revision
        VStack(spacing: 0) {
            // The identity/disclosure stays visible when the transcript scrolls.
            VStack(alignment: .leading, spacing: 4) {
                if coordinator.active { Label(name, systemImage: "person.crop.circle").font(.headline) }
                else { Text("shopNPC.stale") }
                Text("shopNPC.disclosure").font(.footnote).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal).padding(.vertical, 8)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if coordinator.active, let greeting, !greeting.isEmpty { Text(verbatim: greeting) }
                        if !coordinator.grants.textAllowed { Text("shopNPC.disabled").accessibilityIdentifier("shopNPC.disabled") }
                        ForEach(coordinator.messages) { message in
                            VStack(alignment: .leading, spacing: 4) {
                                ChatMessageBubble(isOwn: message.mine) {
                                    Text(message.mine ? "shopNPC.you" : "shopNPC.assistant")
                                } content: {
                                    Text(verbatim: message.text).textSelection(.enabled)
                                }
                                if !message.mine {
                                    Button { typing = false; attempt { try coordinator.reviewRegeneration(answerID: message.id) } } label: {
                                        Text("shopNPC.regenerate").frame(minHeight: 44).contentShape(Rectangle())
                                    }
                                        .disabled(sending || recording || coordinator.pending != nil || !coordinator.active || !coordinator.grants.textAllowed)
                                        .accessibilityIdentifier("shopNPC.regenerate")
                                }
                            }.accessibilityElement(children: .contain)
                        }
                        if sending { ProgressView("shopNPC.busy").accessibilityIdentifier("shopNPC.busy") }
                        if let review = coordinator.pending { reviewPanel(review).id("shopNPC.review") }
                        if let error = localFailure ?? coordinator.failure {
                            Group {
                                if case .server(_, let message) = error, let message, !message.isEmpty { Text(verbatim: message) }
                                else { Text(LocalizedStringKey(error.key)) }
                            }.accessibilityIdentifier("shopNPC.error")
                        }
                        Text("shopNPC.voiceDisclosure").font(.footnote).foregroundStyle(.secondary)
                        Color.clear.frame(height: 1).id("referenceNPC.bottom").accessibilityHidden(true)
                    }.padding()
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: coordinator.pending?.id) { _, id in
                    if id != nil { proxy.scrollTo("shopNPC.review", anchor: .top) }
                }
                .onChange(of: coordinator.messages.count) { _, _ in proxy.scrollTo("referenceNPC.bottom", anchor: .bottom) }
            }
        }
        .safeAreaInset(edge: .bottom) { composer }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("action.done") { typing = false }.accessibilityIdentifier("shopNPC.keyboard.done")
            }
        }
        .navigationTitle("shopNPC.title").navigationBarTitleDisplayMode(.inline).privacySensitive()
        .onDisappear { invalidate() }
        .onChange(of: coordinator.active) { _, active in if !active { clearTransient() } }
        .onChange(of: coordinator.scope) { _, _ in clearTransient() }
        .onChange(of: coordinator.grants) { _, _ in clearTransient() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { invalidate() } }
    }
    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("shopNPC.question", text: $draft, axis: .vertical)
                .lineLimit(1...3).textFieldStyle(.roundedBorder).focused($typing)
                .disabled(!canCompose).accessibilityIdentifier("shopNPC.input")
            ViewThatFits(in: .horizontal) {
                HStack { textReviewButton; voiceButton }
                VStack(alignment: .leading) { textReviewButton; voiceButton }
            }
            if recording {
                Button { capture?.cancel(); recording = false } label: {
                    Text("shopNPC.discard").frame(minHeight: 44).contentShape(Rectangle())
                }
                    .accessibilityIdentifier("shopNPC.discard")
            }
        }.padding().background(.regularMaterial)
    }
    private var textReviewButton: some View {
        Button("shopNPC.reviewText") { typing = false; attempt { try coordinator.reviewText(draft) } }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(!canCompose || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("shopNPC.reviewText")
    }
    private var voiceButton: some View {
        Button {
            typing = false
            attempt {
                guard let capture else { throw ShopNPCFailure.disabled }
                if recording { recording = false; try coordinator.reviewVoice(capture.stopForReview()) }
                else { try capture.startAfterExplicitMicrophoneIntent(grants: coordinator.grants, onEnded: { recording = false }); recording = true }
            }
        } label: {
            Text(recording ? "shopNPC.stopReview" : "shopNPC.record").frame(minHeight: 44).contentShape(Rectangle())
        }
            .disabled(sending || coordinator.pending != nil || !coordinator.active || capture == nil || !coordinator.grants.voiceAllowed || !coordinator.grants.microphone)
            .accessibilityIdentifier("shopNPC.record")
    }
    private func reviewPanel(_ review: ShopNPCReview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("shopNPC.review").font(.headline).accessibilityAddTraits(.isHeader)
            switch review.content {
            case .text(let text): Text(verbatim: text).textSelection(.enabled)
            case .voice(let clip): Text("shopNPC.voiceReview"); Text(verbatim: "\(clip.bytes.count) bytes · \(Int(clip.duration)) s")
            }
            Text("shopNPC.transmissionDisclosure").font(.footnote)
            Button("shopNPC.confirmSend") {
                typing = false; sending = true; localFailure = nil
                Task {
                    await coordinator.transmit(reviewID: review.id)
                    guard coordinator.active, coordinator.scope == review.scope else { return }
                    sending = false
                    // Clear only this accepted draft, never on cancel, failure or an uncertain result.
                    if coordinator.pending == nil, coordinator.failure == nil, review.replacing == nil,
                       case .text(let text) = review.content, draft.trimmingCharacters(in: .whitespacesAndNewlines) == text { draft = "" }
                    revision += 1
                }
            }.buttonStyle(.borderedProminent).controlSize(.large).disabled(sending || recording || !coordinator.active)
                .accessibilityIdentifier("shopNPC.confirmSend")
            Button(role: .cancel) { coordinator.cancelReview(); revision += 1 } label: {
                Text("shopNPC.cancel").frame(minHeight: 44).contentShape(Rectangle())
            }
                .disabled(sending).accessibilityIdentifier("shopNPC.cancel")
        }.padding().frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }
    private func attempt(_ action: () throws -> Void) {
        do { try action(); localFailure = nil } catch { localFailure = error as? ShopNPCFailure ?? .invalid }
        revision += 1
    }
    private func clearTransient() { capture?.cancel(); typing = false; recording = false; sending = false; draft = ""; localFailure = nil; revision += 1 }
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
