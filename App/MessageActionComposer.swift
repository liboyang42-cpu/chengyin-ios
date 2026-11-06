import SwiftUI

/// A token is created by the visible button, never by its queued Task.
struct MessageComposerSubmission: Equatable {
    enum Operation: Equatable { case send(String), retry(String) }
    let id: UUID
    let appearance: UUID
    let identity: MessagingReadIdentity
    let operation: Operation
}

@MainActor final class MessageComposerModel: ObservableObject {
    @Published var draft = ""
    @Published private(set) var state: MessageSendState
    @Published private(set) var appearance: UUID?
    let coordinator: MessageActionCoordinator
    private var queued: MessageComposerSubmission?
    private var executing: MessageComposerSubmission?
    init(_ coordinator: MessageActionCoordinator) {
        self.coordinator = coordinator; state = coordinator.visibleState
    }
    func observe() {
        appearance = UUID()
        coordinator.onStateChange = { [weak self] in self?.update() }
        update()
    }
    func update() {
        state = coordinator.visibleState
        if state == .sending, let executing, appearance == executing.appearance,
           case .send = executing.operation { draft = "" }
    }
    func retire() { appearance = nil; queued = nil; executing = nil; draft = "" }
    func invalidateQueued() { queued = nil }
    func prepare(_ operation: MessageComposerSubmission.Operation,
                 identity: MessagingReadIdentity?, canReply: Bool) -> MessageComposerSubmission? {
        guard let appearance, let identity, canReply, queued == nil, executing == nil,
              coordinator.isConfigured, coordinator.isCurrentAccount,
              identity.accountID == coordinator.accountID else { return nil }
        switch operation {
        case .send(let text):
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  state != .sending, state != .outcomeUnknown, state != .closed else { return nil }
        case .retry(let clientID):
            guard state == .outcomeUnknown || state == .rejected,
                  coordinator.pendingClientMessageID == clientID else { return nil }
        }
        let token = MessageComposerSubmission(id: UUID(), appearance: appearance,
            identity: identity, operation: operation)
        queued = token; return token
    }
    @discardableResult func perform(_ token: MessageComposerSubmission,
                                    canReply: () -> Bool) async -> Bool {
        guard queued == token else { return false }
        // Consume even a denied token. Restored authority needs a new user action.
        queued = nil
        guard appearance == token.appearance, !Task.isCancelled, canReply(),
              coordinator.isConfigured, coordinator.isCurrentAccount else { return false }
        executing = token
        defer { if executing == token { executing = nil } }
        let accepted: Bool
        switch token.operation {
        case .send(let text):
            accepted = await coordinator.sendNew(text, conversationReady: true, expectedIdentity: token.identity)
        case .retry(let clientID):
            guard coordinator.pendingClientMessageID == clientID else { return false }
            accepted = await coordinator.retry(conversationReady: true, expectedIdentity: token.identity)
        }
        guard appearance == token.appearance, executing == token, canReply(), !Task.isCancelled else { return false }
        if case .send(let text) = token.operation,
           coordinator.pendingText == text.trimmingCharacters(in: .whitespacesAndNewlines) { draft = "" }
        update(); return accepted
    }
}

@MainActor struct MessageActionComposer:View {
    @StateObject private var model:MessageComposerModel
    let identity:MessagingReadIdentity?
    let conversationReady:Bool
    let canReply: () -> Bool
    let onAcknowledged:(MessagingMessage)->Void
    /// The view's existing poll entry, shown as the leading `+` when the history offers it.
    let createPoll:(() -> Void)?
    @Environment(\.themeDomain) private var domain
    @State private var confirmsRetry=false
    @FocusState private var typing:Bool
    init(coordinator:MessageActionCoordinator,identity:MessagingReadIdentity?,conversationReady:Bool,
         canReply: @escaping () -> Bool = { true },
         createPoll: (() -> Void)? = nil,
         onAcknowledged:@escaping (MessagingMessage)->Void) {
        self.createPoll=createPoll
        _model=StateObject(wrappedValue:MessageComposerModel(coordinator))
        self.identity=identity;self.conversationReady=conversationReady;self.canReply=canReply;self.onAcknowledged=onAcknowledged
    }
    private var ready:Bool { conversationReady && canReply() && model.appearance != nil && model.coordinator.isConfigured && model.coordinator.isCurrentAccount }
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
            // `+` on the left, then a rounded field with the send control inside it.
            HStack(alignment:.bottom,spacing:Theme.Space.s2) {
                if let createPoll {
                    Button(action: createPoll) {
                        Label("poll.create",systemImage:"plus").labelStyle(.iconOnly)
                            .font(.title3.weight(.medium)).frame(minWidth:44,minHeight:44).contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("poll.createEntry")
                }
                HStack(alignment:.bottom,spacing:4) {
                    TextField("message.send.placeholder",text:$model.draft,axis:.vertical)
                        .lineLimit(1...5).textFieldStyle(.plain).padding(.vertical,11).padding(.leading,16).focused($typing).disabled(!canCompose)
                        .accessibilityIdentifier("message.send.input")
                    let draftIsEmpty = model.draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty
                    Button {
                        typing=false
                        guard let token = model.prepare(.send(model.draft), identity: identity, canReply: ready) else { return }
                        Task { await model.perform(token, canReply: { ready }) }
                    } label: {
                        Label("message.send.button",systemImage:"arrow.up.circle.fill").labelStyle(.iconOnly)
                            .font(.title2).frame(minWidth:44,minHeight:44).contentShape(Rectangle())
                            // Quiet while there is nothing to send; the accent returns with text.
                            .foregroundStyle(draftIsEmpty || !canCompose ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.tint))
                    }
                    .buttonStyle(.borderless)
                    .disabled(!canCompose || draftIsEmpty)
                    .accessibilityIdentifier("message.send.button")
                }
                .frame(minHeight:44)
                .background(Theme.Color.bgRaised(in:domain),in:RoundedRectangle(cornerRadius:22,style:.continuous))
            }
            if !conversationReady { Text("message.send.historyRequired").font(.caption).foregroundStyle(.secondary) }
        }
        // Same surface as the page, so the composer doesn't read as a separate band.
        .padding(.horizontal,Theme.Space.pageX).padding(.vertical,Theme.Space.s2).background(.background).privacySensitive()
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("action.done") { typing = false }.accessibilityIdentifier("message.send.keyboard.done")
            }
        }
        .onAppear { model.observe() }
        .onChange(of:model.state) { _,state in
            // The currently visible history owns readback, even after dismiss/reopen.
            if ready, case .acknowledged(let receipt)=state { onAcknowledged(receipt) }
        }
        .onChange(of:identity) { _,_ in let visible = model.appearance != nil; model.retire(); model.draft="";confirmsRetry=false; if visible { model.observe() } }
        .onChange(of:canReply()) { _, allowed in if !allowed { model.invalidateQueued(); confirmsRetry=false } }
        .onDisappear { model.retire(); confirmsRetry=false; typing=false }
        .alert("message.send.retryTitle",isPresented:$confirmsRetry) {
            Button("message.send.retry") {
                guard let clientID = model.coordinator.pendingClientMessageID,
                      let token = model.prepare(.retry(clientID), identity: identity, canReply: ready) else { return }
                Task { await model.perform(token, canReply: { ready }) }
            }
            Button("action.cancel",role:.cancel) {}
        } message: { Text("message.send.retryHint") }
    }
}
