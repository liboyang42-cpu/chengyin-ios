import SwiftUI

@MainActor private final class MessageComposerModel:ObservableObject {
    @Published var draft=""
    @Published private(set) var state:MessageSendState
    let coordinator:MessageActionCoordinator
    init(_ coordinator:MessageActionCoordinator) {
        self.coordinator=coordinator;state=coordinator.visibleState
        coordinator.onStateChange={ [weak self] in
            guard let self else { return };state=coordinator.visibleState
            if state == .sending { draft="" }
        }
    }
    func update() { state=coordinator.visibleState }
}

@MainActor struct MessageActionComposer:View {
    @StateObject private var model:MessageComposerModel
    let identity:MessagingReadIdentity?
    let conversationReady:Bool
    let onAcknowledged:(MessagingMessage)->Void
    @State private var confirmsRetry=false
    @FocusState private var typing:Bool
    init(coordinator:MessageActionCoordinator,identity:MessagingReadIdentity?,conversationReady:Bool,
         onAcknowledged:@escaping (MessagingMessage)->Void) {
        _model=StateObject(wrappedValue:MessageComposerModel(coordinator))
        self.identity=identity;self.conversationReady=conversationReady;self.onAcknowledged=onAcknowledged
    }
    private var ready:Bool { conversationReady && model.coordinator.isConfigured && model.coordinator.isCurrentAccount }
    private var canCompose:Bool {
        ready && model.state != .sending && model.state != .outcomeUnknown && model.state != .closed
    }
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            switch model.state {
            case .sending: ProgressView("message.send.sending")
            case .outcomeUnknown,.rejected:
                Text(LocalizedStringKey(model.state == .outcomeUnknown ? "message.send.unknown" : "message.send.rejected"))
                    .font(.footnote).accessibilityIdentifier("message.send.issue")
                if let text=model.coordinator.pendingText { Text(verbatim:text).font(.footnote).lineLimit(3) }
                Button("message.send.retry") { confirmsRetry=true }.disabled(!ready)
                    .accessibilityIdentifier("message.send.retry")
            case .closed: Text("message.send.closed").font(.footnote)
            case .acknowledged: Text("message.send.accepted").font(.footnote).accessibilityIdentifier("message.send.receipt")
            case .idle: EmptyView()
            }
            HStack(alignment:.bottom) {
                TextField("message.send.placeholder",text:$model.draft,axis:.vertical)
                    .lineLimit(1...5).focused($typing).disabled(!canCompose)
                    .accessibilityIdentifier("message.send.input")
                Button {
                    typing=false
                    let text=model.draft
                    guard let expected=identity else { return }
                    Task { if await model.coordinator.sendNew(text,conversationReady:ready,expectedIdentity:expected),
                              case .acknowledged(let receipt)=model.coordinator.visibleState { onAcknowledged(receipt) } }
                } label: { Label("message.send.button",systemImage:"arrow.up.circle.fill") }
                .disabled(!canCompose || model.draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("message.send.button")
            }
            if !conversationReady { Text("message.send.historyRequired").font(.caption).foregroundStyle(.secondary) }
        }
        .padding().background(.regularMaterial).privacySensitive()
        .onChange(of:identity) { _,_ in model.draft="";confirmsRetry=false;model.update() }
        .onDisappear { model.draft="";typing=false }
        .alert("message.send.retryTitle",isPresented:$confirmsRetry) {
            Button("message.send.retry") {
                guard let expected=identity else { return }
                Task { if await model.coordinator.retry(conversationReady:ready,expectedIdentity:expected),
                          case .acknowledged(let receipt)=model.coordinator.visibleState { onAcknowledged(receipt) } }
            }
            Button("action.cancel",role:.cancel) {}
        } message: { Text("message.send.retryHint") }
    }
}
