import SwiftUI

@MainActor private final class IMExpandedViewModel: ObservableObject {
    @Published var state: IMReviewState = .idle
    let owner: IMExpandedCoordinator
    init(_ owner: IMExpandedCoordinator) { self.owner = owner }
    func observe() { owner.onChange = { [weak self] in self?.state = self?.owner.visibleState ?? .idle }; state = owner.visibleState }
}
/// Host presents this only after a successful current-scope history load. It does not replace
/// MessagingHistoryView or SocialMessageMediaView, and does not mark a conversation read on appearance.
@MainActor struct IMConversationControlsView: View {
    @StateObject private var model: IMExpandedViewModel
    let identity: MessagingReadIdentity?
    let onReceipt: (IMMutationReceipt) -> Void
    let uploadOwner: IMImageUploadCoordinator?
    let topicReader: (any TopicReading)?
    @State private var selectedTopic: TopicSummary?
    @State private var showingTopics = false
    @State private var name = ""
    @State private var address = ""
    @State private var latitude = ""
    @State private var longitude = ""
    init(coordinator: IMExpandedCoordinator, identity: MessagingReadIdentity?, uploadOwner: IMImageUploadCoordinator? = nil, topicReader: (any TopicReading)? = nil, onReceipt: @escaping (IMMutationReceipt) -> Void) {
        _model = StateObject(wrappedValue: IMExpandedViewModel(coordinator)); self.identity = identity; self.uploadOwner = uploadOwner; self.topicReader = topicReader; self.onReceipt = onReceipt
    }
    var body: some View {
        Form {
            if !model.owner.writer.isConfigured { Text("im.full.disabled") }
            Section("im.full.conversation") {
                Button("im.full.read") { review(.read(conversationID: model.owner.scope.conversationID)) }
                Button("im.full.mute") { review(.mute(conversationID: model.owner.scope.conversationID, muted: true)) }
                Button("im.full.unmute") { review(.mute(conversationID: model.owner.scope.conversationID, muted: false)) }
            }
            if let uploadOwner {
                Section("im.full.image") {
                    NavigationLink {
                        IMImageComposeView(owner: uploadOwner, identity: identity) { url in
                            guard model.owner.scope == uploadOwner.scope,
                                  let intent = try? IMOutgoingIntent(scope: model.owner.scope, payload: .image(url)) else { return false }
                            return model.owner.review(.send(intent))
                        }
                    } label: { Label("im.full.selectImage", systemImage: "photo") }
                }
            }
            Section("im.full.route") {
                if let selectedTopic { Text(verbatim: selectedTopic.name) }
                Button("context.route.choose") { showingTopics = true }.disabled(topicReader == nil)
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
            Section {
                switch model.state {
                case .reviewing(let mutation):
                    IMMutationSummary(mutation: mutation)
                    Button("im.full.confirm") { Task { await model.owner.confirm() } }.accessibilityIdentifier("im.full.confirm")
                    Button("action.cancel", role: .cancel) { model.owner.cancelReview() }
                case .submitting: ProgressView("im.full.submitting")
                case .outcomeUnknown:
                    Text("im.full.unknown")
                    Button("im.full.retrySame") { Task { await model.owner.retryUnchanged() } }
                case .rejected: Text("im.full.rejected")
                case .closed: Text("im.full.closed")
                case .acknowledged: Text("im.full.acknowledged")
                case .idle: EmptyView()
                }
            }
        }
        .disabled(identity != model.owner.scope.identity)
        .sheet(isPresented: $showingTopics) {
            if let topicReader {
                NavigationStack { ContextualTopicPicker(reader: topicReader) { row in
                    guard identity == model.owner.scope.identity else { return }; selectedTopic = row
                } }
            }
        }
        .navigationTitle(Text("im.full.title")).privacySensitive()
        .accessibilityIdentifier("im.full.controls")
        .onAppear { model.observe() }
        .onChange(of: model.state) { _, state in if case .acknowledged(let receipt) = state { onReceipt(receipt) } }
        .onChange(of: identity) { _, _ in clearDrafts(); model.state = model.owner.visibleState }
        .onDisappear { clearDrafts(); model.owner.cancelReview() }
    }
    private func review(_ mutation: IMMutation) { _ = model.owner.review(mutation) }
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
@MainActor private final class IMUploadViewModel: ObservableObject {
    @Published var state: IMUploadState = .idle
    let owner: IMImageUploadCoordinator
    init(_ owner: IMImageUploadCoordinator) { self.owner = owner }
    func observe() { owner.onChange = { [weak self] in self?.state = self?.owner.visibleState ?? .idle }; state = owner.visibleState }
}
@MainActor struct IMImageComposeView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: IMUploadViewModel
    let identity: MessagingReadIdentity?
    let onReviewImage: (URL) -> Bool
    init(owner: IMImageUploadCoordinator, identity: MessagingReadIdentity?, onReviewImage: @escaping (URL) -> Bool) {
        _model = StateObject(wrappedValue: IMUploadViewModel(owner)); self.identity = identity; self.onReviewImage = onReviewImage
    }
    var body: some View {
        Form {
            Text("im.full.imageConsent")
            if !model.owner.isConfigured { Text("im.full.disabled") }
            switch model.state {
            case .idle, .failed:
                Button("im.full.selectImage") { Task { await model.owner.selectAfterConsent() } }
            case .selected(let selection):
                Text(verbatim: "\(selection.bytes.count) bytes")
                Text("im.full.uploadConsent")
                Button("im.full.upload") { Task { await model.owner.uploadAfterConsent() } }
                Button("action.cancel", role: .cancel) { model.owner.clear() }
            case .selecting, .uploading: ProgressView("im.full.submitting")
            case .uploaded(let url):
                Text("im.full.uploaded")
                Button("im.full.review") { if model.owner.applyLocally(url, consume: onReviewImage) { dismiss() } }
            case .outcomeUnknown: Text("im.full.uploadUnknown")
            }
        }.disabled(identity != model.owner.scope.identity || !model.owner.isConfigured)
        .navigationTitle(Text("im.full.image")).privacySensitive().accessibilityIdentifier("im.full.imageCompose")
        .onAppear { model.observe() }
        .onChange(of: identity) { _, _ in model.owner.clear() }
        .onDisappear { model.owner.clear() }
    }
}
