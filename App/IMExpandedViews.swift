import SwiftUI

struct IMExpandedSubmission: Equatable {
    enum Operation: Equatable { case confirm, retry }
    let id: UUID
    let appearance: UUID
    let operation: Operation
    let mutation: IMMutation
}

@MainActor final class IMExpandedViewModel: ObservableObject {
    @Published var state: IMReviewState = .idle
    @Published private(set) var appearance: UUID?
    let owner: IMExpandedCoordinator
    private var queued: IMExpandedSubmission?
    private var executing: IMExpandedSubmission?
    init(_ owner: IMExpandedCoordinator) { self.owner = owner }
    func observe() {
        appearance = UUID()
        owner.onChange = { [weak self] in self?.state = self?.owner.visibleState ?? .idle }
        state = owner.visibleState
    }
    func retire() { appearance = nil; queued = nil; executing = nil; owner.cancelReview() }
    func invalidateQueued() { queued = nil }
    func review(_ mutation: IMMutation, permits: (IMMutation) -> Bool) -> Bool {
        guard appearance != nil, permits(mutation) else { return false }
        return owner.review(mutation)
    }
    func prepare(_ operation: IMExpandedSubmission.Operation,
                 permits: (IMMutation) -> Bool) -> IMExpandedSubmission? {
        guard let appearance, queued == nil, executing == nil, owner.isCurrent,
              owner.writer.isConfigured else { return nil }
        let mutation: IMMutation
        switch (operation, owner.visibleState) {
        case (.confirm, .reviewing(let pending)), (.retry, .outcomeUnknown(let pending)):
            mutation = pending
        default: return nil
        }
        guard permits(mutation) else { return nil }
        let token = IMExpandedSubmission(id: UUID(), appearance: appearance, operation: operation, mutation: mutation)
        queued = token; return token
    }
    @discardableResult func perform(_ token: IMExpandedSubmission,
                                    permits: (IMMutation) -> Bool) async -> Bool {
        guard queued == token else { return false }
        queued = nil
        guard appearance == token.appearance, !Task.isCancelled, owner.isCurrent,
              owner.writer.isConfigured, permits(token.mutation) else { return false }
        switch (token.operation, owner.visibleState) {
        case (.confirm, .reviewing(let pending)), (.retry, .outcomeUnknown(let pending)):
            guard pending == token.mutation else { return false }
        default: return false
        }
        executing = token
        defer { if executing == token { executing = nil } }
        switch token.operation {
        case .confirm: await owner.confirm()
        case .retry: await owner.retryUnchanged()
        }
        guard appearance == token.appearance, executing == token, !Task.isCancelled,
              owner.isCurrent, permits(token.mutation) else { return false }
        state = owner.visibleState
        if case .acknowledged = state { return true }
        return false
    }
}
/// Host presents this only after a successful current-scope history load. It does not replace
/// MessagingHistoryView or SocialMessageMediaView, and does not mark a conversation read on appearance.
@MainActor struct IMConversationControlsView: View {
    @StateObject private var model: IMExpandedViewModel
    let identity: MessagingReadIdentity?
    let onReceipt: (IMMutationReceipt) -> Void
    let uploadOwner: IMImageUploadCoordinator?
    let topicReader: (any TopicReading)?
    let replyPolicy: IMConversationReplyPolicy
    let isConversationCurrent: () -> Bool
    @State private var selectedTopic: TopicSummary?
    @State private var showingTopics = false
    @State private var name = ""
    @State private var address = ""
    @State private var latitude = ""
    @State private var longitude = ""
    init(coordinator: IMExpandedCoordinator, identity: MessagingReadIdentity?, uploadOwner: IMImageUploadCoordinator? = nil, topicReader: (any TopicReading)? = nil, replyPolicy: IMConversationReplyPolicy? = nil,
         isConversationCurrent: @escaping () -> Bool = { true }, onReceipt: @escaping (IMMutationReceipt) -> Void) {
        _model = StateObject(wrappedValue: IMExpandedViewModel(coordinator)); self.identity = identity; self.uploadOwner = uploadOwner; self.topicReader = topicReader; self.onReceipt = onReceipt
        self.replyPolicy = replyPolicy ?? .init(conversationID: coordinator.scope.conversationID, conversation: nil)
        self.isConversationCurrent = isConversationCurrent
    }
    private var permitsReply: Bool { replyPolicy.permitsReply && isConversationCurrent() && identity == model.owner.scope.identity && model.owner.isCurrent }
    private func permits(_ mutation: IMMutation) -> Bool {
        isConversationCurrent() && identity == model.owner.scope.identity && model.owner.isCurrent && replyPolicy.permits(mutation)
    }
    var body: some View {
        Form {
            if !model.owner.writer.isConfigured { Text("im.full.disabled") }
            Section("im.full.conversation") {
                Button("im.full.read") { review(.read(conversationID: model.owner.scope.conversationID)) }
                Button("im.full.mute") { review(.mute(conversationID: model.owner.scope.conversationID, muted: true)) }
                Button("im.full.unmute") { review(.mute(conversationID: model.owner.scope.conversationID, muted: false)) }
            }
            if replyPolicy.isSystemNotice {
                Section { Text("im.reply.systemNotice").accessibilityIdentifier("im.reply.controlsNotice") }
            }
            if permitsReply {
                if let uploadOwner {
                    Section("im.full.image") {
                        NavigationLink {
                            IMImageComposeView(owner: uploadOwner, identity: identity, canReply: { permitsReply }) { url in
                                // The child owns its appearance while this navigation parent is offscreen.
                                guard permitsReply, model.owner.scope == uploadOwner.scope,
                                      let intent = try? IMOutgoingIntent(scope: model.owner.scope, payload: .image(url)) else { return false }
                                return model.owner.review(.send(intent))
                            }
                        } label: { Label("im.full.selectImage", systemImage: "photo") }
                    }
                }
                Section("im.full.route") {
                    if let selectedTopic { Text(verbatim: selectedTopic.name) }
                    Button("context.route.choose") { if model.appearance != nil && permitsReply { showingTopics = true } }.disabled(topicReader == nil)
                        .accessibilityIdentifier("context.im.chooseRoute")
                    Button("im.full.review") {
                        if let row = selectedTopic, let intent = try? IMOutgoingIntent(scope: model.owner.scope, payload: .route(topicID: row.id)) { review(.send(intent)) }
                    }.disabled(selectedTopic == nil || !model.owner.writer.isConfigured)
                }
                Section("im.full.location") {
                    TextField("im.full.name", text: $name)
                    TextField("im.full.address", text: $address)
                    TextField("im.full.latitude", text: $latitude).keyboardType(.numbersAndPunctuation)
                    TextField("im.full.longitude", text: $longitude).keyboardType(.numbersAndPunctuation)
                    Text("im.full.locationConsent").font(.footnote)
                    Button("im.full.review") {
                        if let lat = Double(latitude), let lng = Double(longitude), (-90...90).contains(lat), (-180...180).contains(lng),
                           let intent = try? IMOutgoingIntent(scope: model.owner.scope, payload: .location(name: name, address: address, latitude: lat, longitude: lng)) { review(.send(intent)) }
                    }
                }
            }
            Section {
                switch model.state {
                case .reviewing(let mutation):
                    if permits(mutation) {
                        IMMutationSummary(mutation: mutation)
                        Button("im.full.confirm") { submit(.confirm) }.accessibilityIdentifier("im.full.confirm")
                        Button("action.cancel", role: .cancel) { model.owner.cancelReview() }
                    } else { Text("im.reply.unavailable") }
                case .submitting: ProgressView("im.full.submitting")
                case .outcomeUnknown(let mutation):
                    Text("im.full.unknown")
                    if permits(mutation) { Button("im.full.retrySame") { submit(.retry) } }
                    else { Text("im.reply.unavailable") }
                case .rejected: Text("im.full.rejected")
                case .closed: Text("im.full.closed")
                case .acknowledged: Text("im.full.acknowledged")
                case .idle: EmptyView()
                }
            }
        }
        .disabled(identity != model.owner.scope.identity || !isConversationCurrent())
        .sheet(isPresented: $showingTopics) {
            if permitsReply, let topicReader {
                let appearance = model.appearance
                NavigationStack { ContextualTopicPicker(reader: topicReader) { row in
                    guard let appearance, model.appearance == appearance, permitsReply else { return }; selectedTopic = row
                } }
            }
        }
        .navigationTitle(Text("im.full.title")).privacySensitive()
        .accessibilityIdentifier("im.full.controls")
        .onAppear { model.observe() }
        .onChange(of: model.state) { _, state in
            guard model.appearance != nil, isConversationCurrent(), identity == model.owner.scope.identity else { return }
            if case .acknowledged(let receipt) = state {
                if case .sent = receipt, !permitsReply { return }
                onReceipt(receipt)
            }
        }
        .onChange(of: identity) { _, _ in clearDrafts(); model.invalidateQueued(); model.state = model.owner.visibleState }
        .onChange(of: permitsReply) { _, allowed in if !allowed { clearDrafts(); model.invalidateQueued() } }
        .onChange(of: isConversationCurrent()) { _, current in if !current { clearDrafts(); model.invalidateQueued() } }
        .onDisappear { clearDrafts(); model.retire() }
    }
    private func review(_ mutation: IMMutation) { _ = model.review(mutation, permits: permits) }
    private func submit(_ operation: IMExpandedSubmission.Operation) {
        guard let token = model.prepare(operation, permits: permits) else { return }
        Task { await model.perform(token, permits: permits) }
    }
    private func clearDrafts() { selectedTopic = nil; showingTopics = false; name = ""; address = ""; latitude = ""; longitude = "" }
}
private struct IMMutationSummary: View {
    let mutation: IMMutation
    var body: some View {
        switch mutation {
        case .start(let id): Text("im.full.start"); Text(verbatim: String(id))
        case .read(let id): Text("im.full.read"); Text(verbatim: String(id))
        case .mute(let id, let muted): Text(LocalizedStringKey(muted ? "im.full.mute" : "im.full.unmute")); Text(verbatim: String(id))
        case .send(let intent):
            Text("im.full.sendTo"); Text(verbatim: String(intent.scope.conversationID))
            switch intent.payload {
            case .route(let id): Text("im.full.route"); Text(verbatim: String(id))
            case .image: Text("im.full.image")
            case .location(let name, let address, let lat, let lng): Text(verbatim: name); Text(verbatim: address); Text(verbatim: "\(lat), \(lng)")
            }
        }
    }
}
@MainActor struct IMCardActionsView: View {
    let message: MessagingMessage
    let onDestination: (IMCardDestination) -> Void
    var body: some View {
        VStack(alignment: .leading) {
            ForEach(Array(IMCardAction.actions(for: message).enumerated()), id: \.offset) { _, action in
                Button { onDestination(action.destination) } label: {
                    if action.label.hasPrefix("im.full.") { Text(LocalizedStringKey(action.label)) } else { Text(verbatim: action.label) }
                }
                .disabled(action.destination == .unsupported)
                .foregroundStyle(action.isReject ? Color.red : Color.accentColor)
                if action.destination == .unsupported { Text("im.full.unsupportedAction").font(.caption) }
            }
        }.accessibilityIdentifier("im.full.cardActions")
    }
}

@MainActor private final class IMStartViewModel: ObservableObject {
    @Published var state: IMReviewState = .idle
    let owner: IMConversationStarter
    init(_ owner: IMConversationStarter) { self.owner = owner }
    func observe() { owner.onChange = { [weak self] in self?.state = self?.owner.visibleState ?? .idle }; state = owner.visibleState }
}
@MainActor struct IMStartConversationView: View {
    @StateObject private var model: IMStartViewModel
    @State private var target = ""
    let identity: MessagingReadIdentity?
    let onStarted: (Int) -> Void
    init(owner: IMConversationStarter, identity: MessagingReadIdentity?, onStarted: @escaping (Int) -> Void) {
        _model = StateObject(wrappedValue: IMStartViewModel(owner)); self.identity = identity; self.onStarted = onStarted
    }
    var body: some View {
        Form {
            if !model.owner.writer.isConfigured { Text("im.full.disabled") }
            TextField("im.full.memberID", text: $target).keyboardType(.numberPad)
            Button("im.full.review") { if let id = Int(target) { model.owner.review(targetMemberID: id) } }
            switch model.state {
            case .reviewing(let mutation): IMMutationSummary(mutation: mutation); Button("im.full.confirm") { Task { await model.owner.confirm() } }
            case .submitting: ProgressView("im.full.submitting")
            case .outcomeUnknown: Text("im.full.unknown"); Button("im.full.retrySame") { Task { await model.owner.retryUnchanged() } }
            case .acknowledged: Text("im.full.acknowledged")
            default: EmptyView()
            }
        }.disabled(identity != model.owner.identity || !model.owner.writer.isConfigured)
        .navigationTitle(Text("im.full.start")).privacySensitive().accessibilityIdentifier("im.full.start")
        .onAppear { model.observe() }
        .onChange(of: model.state) { _, state in if case .acknowledged(.started(let id)) = state { onStarted(id) } }
        .onChange(of: identity) { _, _ in target = ""; model.state = model.owner.visibleState }
        .onDisappear { target = ""; model.owner.cancelReview() }
    }
}
struct IMUploadSubmission: Equatable {
    enum Operation: Equatable { case select, upload }
    let id: UUID
    let appearance: UUID
    let operation: Operation
    let state: IMUploadState
}
@MainActor final class IMUploadViewModel: ObservableObject {
    @Published var state: IMUploadState = .idle
    @Published private(set) var appearance: UUID?
    let owner: IMImageUploadCoordinator
    private var queued: IMUploadSubmission?
    init(_ owner: IMImageUploadCoordinator) { self.owner = owner }
    func observe() {
        appearance = UUID()
        owner.onChange = { [weak self] in self?.state = self?.owner.visibleState ?? .idle }
        state = owner.visibleState
    }
    func retire() { appearance = nil; queued = nil; owner.clear() }
    func invalidateQueued() { queued = nil }
    func prepare(_ operation: IMUploadSubmission.Operation, canReply: Bool) -> IMUploadSubmission? {
        guard let appearance, queued == nil, canReply, owner.isCurrent, owner.isConfigured else { return nil }
        switch (operation, owner.visibleState) {
        case (.select, .idle), (.select, .failed), (.upload, .selected): break
        default: return nil
        }
        let token = IMUploadSubmission(id: UUID(), appearance: appearance, operation: operation, state: owner.visibleState)
        queued = token; return token
    }
    func perform(_ token: IMUploadSubmission, canReply: () -> Bool) async {
        guard queued == token else { return }
        queued = nil
        guard appearance == token.appearance, !Task.isCancelled, canReply(), owner.isCurrent,
              owner.isConfigured, owner.visibleState == token.state else { return }
        switch token.operation {
        case .select: await owner.selectAfterConsent()
        case .upload: await owner.uploadAfterConsent()
        }
        guard appearance == token.appearance, canReply(), !Task.isCancelled else { return }
        state = owner.visibleState
    }
    func apply(_ url: URL, canReply: Bool, consume: (URL) -> Bool) -> Bool {
        guard appearance != nil, canReply, owner.isCurrent else { return false }
        return owner.applyLocally(url, consume: consume)
    }
}
@MainActor struct IMImageComposeView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: IMUploadViewModel
    let identity: MessagingReadIdentity?
    let onReviewImage: (URL) -> Bool
    let canReply: () -> Bool
    init(owner: IMImageUploadCoordinator, identity: MessagingReadIdentity?, canReply: @escaping () -> Bool = { true }, onReviewImage: @escaping (URL) -> Bool) {
        _model = StateObject(wrappedValue: IMUploadViewModel(owner)); self.identity = identity; self.canReply = canReply; self.onReviewImage = onReviewImage
    }
    var body: some View {
        Form {
            Text("im.full.imageConsent")
            if !model.owner.isConfigured { Text("im.full.disabled") }
            switch model.state {
            case .idle, .failed:
                Button("im.full.selectImage") { submit(.select) }
            case .selected(let selection):
                Text(verbatim: "\(selection.bytes.count) bytes")
                Text("im.full.uploadConsent")
                Button("im.full.upload") { submit(.upload) }
                Button("action.cancel", role: .cancel) { model.invalidateQueued(); model.owner.clear() }
            case .selecting, .uploading: ProgressView("im.full.submitting")
            case .uploaded(let url):
                Text("im.full.uploaded")
                Button("im.full.review") { if model.apply(url, canReply: canReply(), consume: onReviewImage) { dismiss() } }
            case .outcomeUnknown: Text("im.full.uploadUnknown")
            }
        }.disabled(identity != model.owner.scope.identity || !model.owner.isConfigured || !canReply())
        .navigationTitle(Text("im.full.image")).privacySensitive().accessibilityIdentifier("im.full.imageCompose")
        .onAppear { model.observe() }
        .onChange(of: identity) { _, _ in model.invalidateQueued(); model.owner.clear() }
        .onChange(of: canReply()) { _, allowed in if !allowed { model.invalidateQueued(); model.owner.clear() } }
        .onDisappear { model.retire() }
    }
    private func submit(_ operation: IMUploadSubmission.Operation) {
        guard identity == model.owner.scope.identity,
              let token = model.prepare(operation, canReply: canReply()) else { return }
        Task { await model.perform(token, canReply: { identity == model.owner.scope.identity && canReply() }) }
    }
}
