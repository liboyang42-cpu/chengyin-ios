import SwiftUI
import MapKit

struct IMExpandedSubmission: Equatable {
    enum Operation: Equatable {
        case confirm, retry, recoverImage, retryImage, recoverRoute, recoverStaticLocation
        var isReceiptRecovery: Bool {
            self == .recoverImage || self == .recoverRoute || self == .recoverStaticLocation
        }
    }
    let id: UUID
    let appearance: UUID
    let operation: Operation
    let mutation: IMMutation
}

@MainActor final class IMExpandedViewModel: ObservableObject {
    @Published var state: IMReviewState = .idle
    @Published private(set) var ordinaryReceiptState: OrdinaryIMReceiptReadState = .idle
    @Published private(set) var appearance: UUID?
    let owner: IMExpandedCoordinator
    private var queued: IMExpandedSubmission?
    private var executing: IMExpandedSubmission?
    init(_ owner: IMExpandedCoordinator) { self.owner = owner }
    func observe() {
        appearance = UUID()
        owner.onChange = { [weak self] in
            guard let self, self.appearance != nil else { return }
            if case .acknowledged = self.owner.visibleState,
               self.executing?.appearance != self.appearance { return }
            self.state = self.owner.visibleState; self.ordinaryReceiptState = self.owner.ordinaryReceiptState
        }
        state = owner.visibleState; ordinaryReceiptState = owner.ordinaryReceiptState
    }
    func retire() { appearance = nil; queued = nil; executing = nil; owner.invalidateOrdinaryImageRecovery(); owner.cancelReview() }
    func invalidateQueued() { queued = nil; owner.invalidateOrdinaryImageRecovery() }
    func review(_ mutation: IMMutation, permits: (IMMutation) -> Bool) -> Bool {
        guard appearance != nil, permits(mutation) else { return false }
        return owner.review(mutation)
    }
    func prepare(_ operation: IMExpandedSubmission.Operation,
                 permits: (IMMutation) -> Bool) -> IMExpandedSubmission? {
        guard let appearance, queued == nil, executing == nil, owner.isCurrent,
              operation.isReceiptRecovery || owner.writer.isConfigured else { return nil }
        let mutation: IMMutation
        switch (operation, owner.visibleState) {
        case (.confirm, .reviewing(let pending)), (.retry, .outcomeUnknown(let pending)):
            if operation == .retry, owner.usesOriginalRecovery, owner.pendingOrdinaryImage != nil { return nil }
            mutation = pending
        case (.recoverImage, .outcomeUnknown(let pending)), (.recoverImage, .rejected(let pending)):
            guard owner.canRecoverOrdinaryImage else { return nil }; mutation = pending
        case (.retryImage, .outcomeUnknown(let pending)), (.retryImage, .rejected(let pending)):
            guard owner.canRetryOrdinaryImage else { return nil }; mutation = pending
        case (.recoverRoute, .outcomeUnknown(let pending)):
            guard owner.canRecoverRoute else { return nil }; mutation = pending
        case (.recoverStaticLocation, .outcomeUnknown(let pending)):
            guard owner.canRecoverStaticLocation else { return nil }; mutation = pending
        default: return nil
        }
        guard permits(mutation) else { return nil }
        let token = IMExpandedSubmission(id: UUID(), appearance: appearance, operation: operation, mutation: mutation)
        queued = token; return token
    }
    @discardableResult func perform(_ token: IMExpandedSubmission,
                                    permits: (IMMutation) -> Bool,
                                    onConversationMutationAccepted: (IMScope) -> Void = { _ in }) async -> Bool {
        guard queued == token else { return false }
        queued = nil
        guard appearance == token.appearance, !Task.isCancelled, owner.isCurrent,
              (token.operation.isReceiptRecovery || owner.writer.isConfigured), permits(token.mutation) else { return false }
        switch (token.operation, owner.visibleState) {
        case (.confirm, .reviewing(let pending)), (.retry, .outcomeUnknown(let pending)),
             (.recoverImage, .outcomeUnknown(let pending)), (.recoverImage, .rejected(let pending)),
             (.retryImage, .outcomeUnknown(let pending)), (.retryImage, .rejected(let pending)),
             (.recoverRoute, .outcomeUnknown(let pending)), (.recoverStaticLocation, .outcomeUnknown(let pending)):
            guard pending == token.mutation else { return false }
        default: return false
        }
        executing = token
        defer { if executing == token { executing = nil } }
        switch token.operation {
        case .confirm:
            if owner.usesOriginalRecovery, case .send(let intent) = token.mutation, case .image = intent.payload {
                await owner.confirm(stillAuthorized: { self.appearance == token.appearance && permits(token.mutation) })
            } else if case .send(let intent) = token.mutation,
                      intent.payload.isChannelHostSourceCard {
                await owner.confirm(stillAuthorized: { self.appearance == token.appearance && permits(token.mutation) })
            } else { await owner.confirm() }
        case .retry: await owner.retryUnchanged()
        case .recoverRoute: await owner.recoverRoute()
        case .recoverStaticLocation: await owner.recoverStaticLocation()
        case .recoverImage:
            _ = await owner.recoverOrdinaryImage(stillAuthorized: { self.appearance == token.appearance && permits(token.mutation) })
        case .retryImage:
            guard case .send(let intent) = token.mutation else { return false }
            await owner.retryOrdinaryImageConfirmed(clientMessageID: intent.clientMessageID,
                stillAuthorized: { self.appearance == token.appearance && permits(token.mutation) })
        }
        // A definite response to this already-dispatched operation can stale the
        // retained list after Controls closes. Do not revive the UI or start reads.
        if !Task.isCancelled, owner.isCurrent, owner.writer.isConfigured,
           token.mutation.conversationID == owner.scope.conversationID,
           case .acknowledged(let receipt) = owner.visibleState {
            switch (token.mutation, receipt) {
            case (.read, .read), (.readCursor, .read): onConversationMutationAccepted(owner.scope)
            case (.mute(_, let requested), .muted(let received)) where requested == received:
                onConversationMutationAccepted(owner.scope)
            default: break
            }
        }
        guard appearance == token.appearance, executing == token, !Task.isCancelled,
              owner.isCurrent, permits(token.mutation) else { return false }
        state = owner.visibleState
        if case .acknowledged(let receipt) = state {
            switch (token.mutation, receipt) {
            case (.read, .read), (.readCursor, .read): return true
            case (.mute(_, let requested), .muted(let received)): return requested == received
            case (.read, _), (.readCursor, _), (.mute, _): return false
            default: return true
            }
        }
        return false
    }
}
/// Host presents this only after a successful current-scope history load. It does not replace
/// MessagingHistoryView or SocialMessageMediaView, and does not mark a conversation read on appearance.
@MainActor struct IMConversationControlsView: View {
    @StateObject private var model: IMExpandedViewModel
    let identity: MessagingReadIdentity?
    let onReceipt: (IMMutationReceipt) -> Void
    let onConversationMutationAccepted: (IMScope) -> Void
    let uploadOwner: IMImageUploadCoordinator?
    let topicReader: (any TopicReading)?
    let replyPolicy: IMConversationReplyPolicy
    let isConversationCurrent: () -> Bool
    /// Set only for an already loaded type-5 history. Nil keeps the original conversation-only read.
    let readCursor: Int?
    /// Group management entry. Nil closes this open and does not invent a catalog.
    let admission: ChannelAdmissionRoute?
    let directory: ChannelDirectoryAdmissionRequest?
    let showsAdmissionEntry: Bool
    /// The loaded conversation's muted value. Nil (absent/unknown) shows explicit mute and unmute rows
    /// instead of a toggle, so no state is inferred.
    let isMuted: Bool?
    @State private var directoryPage: ChannelAdmissionGovernanceView?
    @State private var directoryFailed = false
    @State private var selectedTopic: TopicSummary?
    @State private var showingTopics = false
    @State private var acknowledgedMuted: Bool?
    @State private var name = ""
    @State private var address = ""
    @State private var latitude = ""
    @State private var longitude = ""
    init(coordinator: IMExpandedCoordinator, identity: MessagingReadIdentity?, uploadOwner: IMImageUploadCoordinator? = nil, topicReader: (any TopicReading)? = nil, replyPolicy: IMConversationReplyPolicy? = nil,
         isConversationCurrent: @escaping () -> Bool = { true }, readCursor: Int? = nil,
         admission: ChannelAdmissionRoute? = nil, directory: ChannelDirectoryAdmissionRequest? = nil, showsAdmissionEntry: Bool = false,
         isMuted: Bool? = nil,
         onConversationMutationAccepted: @escaping (IMScope) -> Void = { _ in }, onReceipt: @escaping (IMMutationReceipt) -> Void) {
        _model = StateObject(wrappedValue: IMExpandedViewModel(coordinator)); self.identity = identity; self.uploadOwner = uploadOwner; self.topicReader = topicReader; self.onReceipt = onReceipt
        self.replyPolicy = replyPolicy ?? .init(conversationID: coordinator.scope.conversationID, conversation: nil)
        self.isConversationCurrent = isConversationCurrent
        self.readCursor = readCursor
        self.admission = admission
        self.directory = directory
        self.showsAdmissionEntry = showsAdmissionEntry
        self.isMuted = isMuted
        self.onConversationMutationAccepted = onConversationMutationAccepted
    }
    private var permitsReply: Bool { replyPolicy.permitsReply && isConversationCurrent() && identity == model.owner.scope.identity && model.owner.isCurrent }
    private func permits(_ mutation: IMMutation) -> Bool {
        isConversationCurrent() && identity == model.owner.scope.identity && model.owner.isCurrent && replyPolicy.permits(mutation)
    }
    private var writerReady: Bool { model.owner.writer.isConfigured }
    private var hasPendingState: Bool { if case .idle = model.state { return false }; return true }
    private var displayedMuted: Bool? { acknowledgedMuted ?? isMuted }
    var body: some View {
        Form {
            if hasPendingState {
                Section { pendingRows }
            }
            if writerReady {
                Section {
                    Button { review(readMutation()) } label: { Label("d7.chatInfo.markRead", systemImage: "checkmark.message") }
                    if let muted = displayedMuted {
                        Toggle(isOn: Binding(get: { muted }, set: { value in
                            review(.mute(conversationID: model.owner.scope.conversationID, muted: value))
                        })) { Label("d7.chatInfo.mute", systemImage: "bell.slash") }
                    } else {
                        Button { review(.mute(conversationID: model.owner.scope.conversationID, muted: true)) } label: {
                            Label("d7.chatInfo.mute", systemImage: "bell.slash")
                        }
                        Button { review(.mute(conversationID: model.owner.scope.conversationID, muted: false)) } label: {
                            Label("d7.chatInfo.unmute", systemImage: "bell")
                        }
                    }
                }
            }
            if showsAdmissionEntry { admissionSection }
            if replyPolicy.isSystemNotice {
                Section { Text("im.reply.systemNotice").accessibilityIdentifier("im.reply.controlsNotice") }
            }
            if permitsReply && writerReady {
                if let uploadOwner {
                    Section {
                        NavigationLink {
                            IMImageComposeView(owner: uploadOwner, identity: identity, canReply: { permitsReply }) { url in
                                // The child owns its appearance while this navigation parent is offscreen.
                                guard permitsReply, model.owner.scope == uploadOwner.scope,
                                      let intent = try? IMOutgoingIntent(scope: model.owner.scope, payload: .image(url)) else { return false }
                                return model.owner.review(.send(intent))
                            }
                        } label: { Label("d7.chatInfo.sendPhoto", systemImage: "photo") }
                    }
                }
                if topicReader != nil {
                    Section("d7.chatInfo.route") {
                        Button { if model.appearance != nil && permitsReply { showingTopics = true } } label: {
                            if let selectedTopic { Label { Text(verbatim: selectedTopic.name) } icon: { Image(systemName: "map") } }
                            else { Label("context.route.choose", systemImage: "map") }
                        }
                        .accessibilityIdentifier("context.im.chooseRoute")
                        if let selectedTopic {
                            Button("d7.chatInfo.sendRoute") {
                                if let intent = try? IMOutgoingIntent(scope: model.owner.scope, payload: .route(topicID: selectedTopic.id)) { review(.send(intent)) }
                            }
                        }
                    }
                }
                Section("d7.chatInfo.location") {
                    TextField("im.full.name", text: $name)
                    TextField("im.full.address", text: $address)
                    TextField("im.full.latitude", text: $latitude).keyboardType(.numbersAndPunctuation)
                    TextField("im.full.longitude", text: $longitude).keyboardType(.numbersAndPunctuation)
                    Button("d7.chatInfo.sendLocation") {
                        if let lat = Double(latitude), let lng = Double(longitude), (-90...90).contains(lat), (-180...180).contains(lng),
                           let intent = try? IMOutgoingIntent(scope: model.owner.scope, payload: .location(name: name, address: address, latitude: lat, longitude: lng)) { review(.send(intent)) }
                    }
                }
            }
            if !writerReady && !showsAdmissionEntry && !replyPolicy.isSystemNotice && !hasPendingState {
                ContentUnavailableView("d7.chatInfo.unavailable", systemImage: "bubble.left.and.exclamationmark.bubble.right")
            }
        }
        .disabled(identity != model.owner.scope.identity || !isConversationCurrent())
        .sheet(isPresented: $showingTopics) {
            if permitsReply, let topicReader {
                let appearance = model.appearance
                NavigationStack { ContextualTopicPicker(reader: topicReader) { row in
                    guard let appearance, model.appearance == appearance, permitsReply else { return }; selectedTopic = row
                } }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        .navigationTitle(Text("im.full.title")).privacySensitive()
        .accessibilityIdentifier("im.full.controls")
        .onAppear { model.observe() }
        .onChange(of: model.state) { _, state in if case .acknowledged(.muted(let value)) = state { acknowledgedMuted = value } }
        .onChange(of: identity) { _, _ in clearDrafts(); acknowledgedMuted = nil; model.invalidateQueued(); model.state = model.owner.visibleState }
        .onChange(of: permitsReply) { _, allowed in if !allowed { clearDrafts(); model.invalidateQueued() } }
        .onChange(of: isConversationCurrent()) { _, current in if !current { clearDrafts(); model.invalidateQueued() } }
        .onDisappear { clearDrafts(); model.retire() }
    }
    @ViewBuilder private var pendingRows: some View {
        switch model.state {
        case .reviewing(let mutation):
            if permits(mutation) {
                IMMutationSummary(mutation: mutation)
                Button("d7.chatInfo.confirm") { submit(.confirm) }.fontWeight(.semibold).accessibilityIdentifier("im.full.confirm")
                Button("action.cancel", role: .cancel) { model.owner.cancelReview() }
            } else { Text("d7.chatInfo.replyUnavailable") }
        case .submitting: ProgressView("im.full.submitting")
        case .outcomeUnknown(let mutation):
            Text("d7.chatInfo.unknown")
            if permits(mutation) { Button("d7.chatInfo.tryAgain") { submit(.retry) } }
            else { Text("d7.chatInfo.replyUnavailable") }
        case .rejected: Text("d7.chatInfo.rejected")
        case .closed: Text("im.full.closed")
        case .acknowledged: Label("d7.chatInfo.done", systemImage: "checkmark.circle")
        case .idle: EmptyView()
        }
    }
    @ViewBuilder private var admissionSection: some View {
        if let directoryPage {
            Section {
                NavigationLink { directoryPage } label: { Label("d7.chatInfo.members", systemImage: "person.2") }
                    .accessibilityIdentifier("admission.entry")
            }
        } else if let directory, !directoryFailed {
            Section {
                Button {
                    Task {
                        do {
                            directoryPage = try await ChannelAdmissionParent.page(
                                configuration: directory.configuration, transport: directory.transport,
                                token: directory.token, accountID: directory.accountID, epoch: directory.epoch,
                                channelID: directory.channelID, spaceID: directory.spaceID, kind: directory.kind)
                        } catch { directoryFailed = true }
                    }
                } label: { Label("d7.chatInfo.members", systemImage: "person.2") }
                .accessibilityIdentifier("admission.entry")
            }
        } else if let admission, let identity, identity.accountID == admission.accountID, identity.epoch == admission.epoch,
                  let page = try? admission.page() {
            Section {
                NavigationLink { page } label: { Label("d7.chatInfo.members", systemImage: "person.2") }
                    .accessibilityIdentifier("admission.entry")
            }
        } else if directoryFailed, directory != nil {
            Section {
                Text("d7.chatInfo.membersFailed").accessibilityIdentifier("admission.unavailable")
                Button("messaging.retry") { directoryFailed = false }
            }
        }
    }
    /// The loaded history supplies the cursor. Opening this page does not mark it read.
    private func readMutation() -> IMMutation {
        guard let readCursor, readCursor >= 0 else { return .read(conversationID: model.owner.scope.conversationID) }
        return .readCursor(conversationID: model.owner.scope.conversationID, lastMessageID: readCursor,
                           requestID: "ack-" + UUID().uuidString.lowercased())
    }
    private func review(_ mutation: IMMutation) { _ = model.review(mutation, permits: permits) }
    private func submit(_ operation: IMExpandedSubmission.Operation) {
        guard let token = model.prepare(operation, permits: permits) else { return }
        Task {
            let accepted = await model.perform(token, permits: permits,
                onConversationMutationAccepted: onConversationMutationAccepted)
            guard accepted, model.appearance == token.appearance,
                  isConversationCurrent(), identity == model.owner.scope.identity,
                  case .acknowledged(let receipt) = model.state else { return }
            if case .sent = receipt, !permitsReply { return }
            onReceipt(receipt)
        }
    }
    private func clearDrafts() { selectedTopic = nil; showingTopics = false; name = ""; address = ""; latitude = ""; longitude = "" }
}
/// Message duration as m:ss, using the view's locale.
struct IMDurationText: View {
    let milliseconds: Int
    var body: some View { Text(Duration.milliseconds(milliseconds), format: .time(pattern: .minuteSecond)).monospacedDigit() }
}
/// File size in the system's file-size style (KB, MB), using the view's locale.
struct IMByteCountText: View {
    let bytes: Int
    var body: some View { Text(Int64(bytes), format: .byteCount(style: .file)).monospacedDigit() }
}
/// What the pending action will do, in the user's terms. Identifiers and request keys stay internal.
struct IMMutationSummary: View {
    let mutation: IMMutation
    var body: some View {
        switch mutation {
        case .start(let id):
            LabeledContent("d7.imSummary.startWith") { Text(verbatim: String(id)) }
        case .read, .readCursor:
            Label("d7.chatInfo.markRead", systemImage: "checkmark.message")
        case .mute(_, let muted):
            if muted { Label("d7.chatInfo.mute", systemImage: "bell.slash") }
            else { Label("d7.chatInfo.unmute", systemImage: "bell") }
        case .send(let intent):
            switch intent.payload {
            case .route: Label("d7.imSummary.route", systemImage: "map")
            case .image: Label("d7.imSummary.photo", systemImage: "photo")
            case .video(let reference):
                Label("d7.imSummary.video", systemImage: "video")
                LabeledContent("d7.imSummary.duration") { IMDurationText(milliseconds: reference.durationMS) }
                LabeledContent("d7.imSummary.size") { IMByteCountText(bytes: reference.size) }
            case .file(let reference):
                Label { Text(verbatim: reference.name) } icon: { Image(systemName: "doc") }
                LabeledContent("d7.imSummary.size") { IMByteCountText(bytes: reference.size) }
            case .voice(let reference):
                Label("d7.imSummary.voice", systemImage: "waveform")
                LabeledContent("d7.imSummary.duration") { IMDurationText(milliseconds: reference.durationMS) }
            case .staticLocation(let place):
                Label { Text(verbatim: place.name) } icon: { Image(systemName: "mappin.and.ellipse") }
                if !place.address.isEmpty { Text(verbatim: place.address) }
            case .location(let name, let address, let lat, let lng):
                Label {
                    if name.isEmpty { Text(verbatim: "\(lat), \(lng)") } else { Text(verbatim: name) }
                } icon: { Image(systemName: "mappin.and.ellipse") }
                if !address.isEmpty { Text(verbatim: address) }
            }
        }
    }
}
@MainActor struct IMCardActionsView: View {
    let message: MessagingMessage
    let onDestination: (IMCardDestination) -> Void
    var body: some View {
        VStack(alignment: .leading) {
            // Actions this version can't open are left out rather than shown disabled.
            ForEach(Array(IMCardAction.actions(for: message).filter { $0.destination != .unsupported }.enumerated()), id: \.offset) { _, action in
                Button { onDestination(action.destination) } label: {
                    if action.label.hasPrefix("im.full.") { Text(LocalizedStringKey(action.label)) } else { Text(verbatim: action.label) }
                }
                .foregroundStyle(action.isReject ? Color.red : Color.accentColor)
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
            if model.owner.writer.isConfigured {
                Section {
                    TextField("d7.newChat.memberID", text: $target).keyboardType(.numberPad)
                    Button("d7.newChat.next") { if let id = Int(target) { model.owner.review(targetMemberID: id) } }
                        .disabled(Int(target) == nil)
                }
                switch model.state {
                case .reviewing(let mutation):
                    Section {
                        IMMutationSummary(mutation: mutation)
                        Button("d7.newChat.start") { Task { await model.owner.confirm() } }.imFlowPrimaryAction()
                    }
                case .submitting: Section { ProgressView("im.full.submitting") }
                case .outcomeUnknown:
                    Section {
                        Text("d7.chatInfo.unknown")
                        Button("d7.chatInfo.tryAgain") { Task { await model.owner.retryUnchanged() } }
                    }
                case .acknowledged: Section { Label("d7.chatInfo.done", systemImage: "checkmark.circle") }
                default: EmptyView()
                }
            } else {
                ContentUnavailableView("d7.newChat.unavailable", systemImage: "bubble.left.and.bubble.right")
            }
        }.disabled(identity != model.owner.identity || !model.owner.writer.isConfigured)
        .navigationTitle(Text("d7.newChat.title")).privacySensitive().accessibilityIdentifier("im.full.start")
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
            if model.owner.isConfigured {
                Section {
                    switch model.state {
                    case .idle, .failed:
                        if case .failed = model.state {
                            IMFlowStateMessage(text: Text("d7.imPhoto.failed"), symbol: "exclamationmark.circle", tone: .attention)
                        }
                        Button { submit(.select) } label: { Label("d7.imPhoto.choose", systemImage: "photo") }
                    case .selected(let selection):
                        LabeledContent("d7.imSummary.size") { IMByteCountText(bytes: selection.bytes.count) }
                        Button("d7.imCompose.upload") { submit(.upload) }.imFlowPrimaryAction()
                        Button("action.cancel", role: .cancel) { model.invalidateQueued(); model.owner.clear() }
                    case .selecting: ProgressView()
                    case .uploading: ProgressView("d7.imCompose.uploading")
                    case .uploaded(let url):
                        Label("d7.imPhoto.ready", systemImage: "checkmark.circle")
                        Button("d7.imCompose.continue") { if model.apply(url, canReply: canReply(), consume: onReviewImage) { dismiss() } }
                            .imFlowPrimaryAction()
                    case .outcomeUnknown:
                        IMFlowStateMessage(text: Text("d7.imCompose.uploadUnknown"), symbol: "clock.arrow.circlepath")
                    }
                }
            } else {
                ContentUnavailableView("d7.imPhoto.unavailable", systemImage: "photo")
            }
        }.disabled(identity != model.owner.scope.identity || !model.owner.isConfigured || !canReply())
        .navigationTitle(Text("d7.imPhoto.title")).privacySensitive().accessibilityIdentifier("im.full.imageCompose")
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


private extension IMOutgoingPayload {
    var isChannelHostSourceCard: Bool {
        switch self { case .route, .staticLocation: return true; default: return false }
    }
}

@MainActor struct IMStaticLocationComposeView: View {
    @StateObject private var model: IMExpandedViewModel
    @Environment(\.scenePhase) private var phase
    @Environment(\.dismiss) private var dismiss
    @State private var operationTask: Task<Void, Never>?
    @State private var operationID: UUID?
    let current: () -> Bool
    @State private var name=""
    @State private var address=""
    @State private var latitude=""
    @State private var longitude=""
    @State private var confirmedDatum=false
    @State private var pickingMap=false
    @State private var pickedMapSignature:String?
    init(owner: IMExpandedCoordinator,current:@escaping ()->Bool) { _model=StateObject(wrappedValue:IMExpandedViewModel(owner));self.current=current }
    private var available: Bool { phase == .active && current() && model.owner.isCurrent }
    var body: some View {
        Form {
            if available {
                switch model.state {
                case .idle:
                    if model.owner.writer.canSendStaticLocation {
                        Section {
                            Button { pickingMap=true } label: { Label("d7.imLocation.pickOnMap", systemImage: "map") }
                        }
                        Section {
                            TextField("im.full.name",text:$name)
                            TextField("d7.imLocation.addressOptional",text:$address)
                            TextField("im.full.latitude",text:$latitude).keyboardType(.numbersAndPunctuation)
                            TextField("im.full.longitude",text:$longitude).keyboardType(.numbersAndPunctuation)
                            Toggle("d7.imLocation.gpsCoordinates",isOn:$confirmedDatum)
                        }
                        Section {
                            Button("d7.imCompose.continue") {
                                guard available,confirmedDatum,let lat=Double(latitude),let lng=Double(longitude),
                                      let place=try? IMStaticLocation(name:name,address:address,latitude:lat,longitude:lng,datum:"WGS84"),
                                      let intent=try? IMOutgoingIntent(scope:model.owner.scope,payload:.staticLocation(place)) else { return }
                                _ = model.owner.review(.send(intent))
                            }.imFlowPrimaryAction().disabled(!confirmedDatum)
                        }
                    } else {
                        ContentUnavailableView("d7.imLocation.unavailable", systemImage: "mappin.slash")
                    }
                case .reviewing(let mutation):
                    if isLocation(mutation) {
                        Section { IMMutationSummary(mutation:mutation) }
                        Section {
                            Button("d7.imLocation.send") { submit(.confirm) }.imFlowPrimaryAction()
                            Button("action.cancel",role:.cancel) { model.owner.cancelReview() }
                        }
                    } else { Text("d7.imCompose.otherPending") }
                case .outcomeUnknown(let mutation):
                    if isLocation(mutation) {
                        Section {
                            IMMutationSummary(mutation:mutation)
                            IMFlowStateMessage(text: Text("d7.imCompose.sendUnknown"), symbol: "clock.arrow.circlepath")
                        }
                        Section {
                            if model.owner.canRecoverStaticLocation { Button("d7.imCompose.checkSent") { submit(.recoverStaticLocation) } }
                            // Recovery never grants new SEND. Explicit retry remains the same original key and bytes.
                            if model.owner.writer.canSendStaticLocation { Button("d7.chatInfo.tryAgain") { submit(.retry) } }
                        }
                    } else { Text("d7.imCompose.otherPending") }
                case .submitting: ProgressView("d7.imCompose.sending")
                case .acknowledged:
                    Section {
                        IMFlowStateMessage(text: Text("d7.imLocation.sent"), symbol: "checkmark.circle", tone: .success)
                        if model.owner.writer.canSendStaticLocation {
                            Button("d7.imLocation.sendAnother") { clear();model.owner.finishStaticLocationResult() }
                        }
                    }
                case .rejected: IMFlowStateMessage(text: Text("d7.imCompose.rejected"), symbol: "exclamationmark.circle", tone: .attention)
                case .closed: IMFlowStateMessage(text: Text("d7.imCompose.unavailable"), symbol: "lock")
                }
            } else { IMFlowStateMessage(text: Text("d7.imCompose.unavailable"), symbol: "lock") }
        }.imFlowForm().navigationTitle(Text("d7.imLocation.title")).privacySensitive()
         .toolbar { ToolbarItem(placement:.cancellationAction) { Button("action.close") { dismiss() } } }
         .onChange(of:latitude) { _,_ in if pickedMapSignature != latitude+"|"+longitude { confirmedDatum=false;pickedMapSignature=nil } }
         .onChange(of:longitude) { _,_ in if pickedMapSignature != latitude+"|"+longitude { confirmedDatum=false;pickedMapSignature=nil } }
         .sheet(isPresented:$pickingMap) {
             IMStaticPlaceMapPicker(current:{ available && model.appearance != nil }) { place in
                 guard available,model.appearance != nil else{return}
                 name=place.name;address=place.address;latitude=String(place.lat);longitude=String(place.lng)
                 pickedMapSignature=latitude+"|"+longitude;confirmedDatum=true
             }
             .presentationDetents([.large])
             .presentationDragIndicator(.visible)
         }
         .onAppear { if available { model.observe() } }
         .onDisappear { stopOperation();model.retire();clear() }
         .onChange(of:available) { _,valid in if !valid { stopOperation();model.retire();clear() } else if model.appearance == nil { model.observe() } }
    }
    private func submit(_ operation: IMExpandedSubmission.Operation) {
        let permits: (IMMutation) -> Bool = { available && isLocation($0) }
        guard operationTask == nil, let token = model.prepare(operation, permits: permits) else { return }
        let id = UUID(); operationID = id
        operationTask = Task {
            _ = await model.perform(token, permits: permits)
            guard operationID == id else { return }
            operationTask = nil; operationID = nil
        }
    }
    private func stopOperation() {
        operationID = nil; operationTask?.cancel(); operationTask = nil
    }
    private func isLocation(_ mutation:IMMutation)->Bool { if case .send(let intent)=mutation,case .staticLocation=intent.payload{return true};return false }
    private func clear() { name="";address="";latitude="";longitude="";confirmedDatum=false;pickingMap=false;pickedMapSignature=nil }
}

@MainActor struct IMRouteShareComposeView:View {
    @StateObject private var model:IMExpandedViewModel
    @Environment(\.scenePhase) private var phase
    @Environment(\.dismiss) private var dismiss
    @State private var operationTask: Task<Void, Never>?
    @State private var operationID: UUID?
    let reader:any TopicReading
    let current:()->Bool
    @State private var selected:TopicSummary?
    @State private var picking=false
    init(owner:IMExpandedCoordinator,reader:any TopicReading,current:@escaping ()->Bool) {
        _model=StateObject(wrappedValue:IMExpandedViewModel(owner));self.reader=reader;self.current=current
    }
    private var available:Bool { phase == .active && current() && model.owner.isCurrent }
    private var canShare:Bool { model.owner.writer.canReadRouteShareSource && model.owner.writer.canSendRoute }
    var body:some View {
        Form {
            if available {
                switch model.state {
                case .idle:
                    if canShare {
                        Section {
                            Button { picking=true } label: {
                                if let selected { Label { Text(verbatim:selected.name) } icon: { Image(systemName:"map") } }
                                else { Label("context.route.choose", systemImage:"map") }
                            }
                            if model.owner.routeShareUnavailable {
                                IMFlowStateMessage(text: Text("d7.imRoute.notShareable"), symbol: "exclamationmark.circle", tone: .attention)
                            }
                        }
                        if selected != nil {
                            Section {
                                Button("d7.imCompose.continue") { reviewSelectedSource() }.imFlowPrimaryAction()
                            }
                        }
                    } else {
                        ContentUnavailableView("d7.imRoute.unavailable", systemImage: "map")
                    }
                case .reviewing(let mutation):
                    if isRoute(mutation),let source=model.owner.selectedRouteShareSource {
                        Section { Label { Text(verbatim:source.name) } icon: { Image(systemName:"map") } }
                        Section {
                            Button("d7.imRoute.send") { submit(.confirm) }.imFlowPrimaryAction()
                            Button("action.cancel",role:.cancel) { model.owner.cancelReview() }
                        }
                    } else { Text("d7.imCompose.otherPending") }
                case .outcomeUnknown(let mutation):
                    if isRoute(mutation) {
                        Section {
                            IMMutationSummary(mutation:mutation)
                            IMFlowStateMessage(text: Text("d7.imCompose.sendUnknown"), symbol: "clock.arrow.circlepath")
                        }
                        Section {
                            if model.owner.canRecoverRoute { Button("d7.imCompose.checkSent") { submit(.recoverRoute) } }
                            if model.owner.writer.canSendRoute { Button("d7.chatInfo.tryAgain") { submit(.retry) } }
                        }
                    } else { Text("d7.imCompose.otherPending") }
                case .submitting:ProgressView("d7.imCompose.sending")
                case .acknowledged:
                    Section {
                        IMFlowStateMessage(text: Text("d7.imRoute.sent"), symbol: "checkmark.circle", tone: .success)
                        Button("d7.imRoute.sendAnother") { selected=nil;model.owner.finishRouteResult() }
                    }
                case .rejected:IMFlowStateMessage(text: Text("d7.imCompose.rejected"), symbol: "exclamationmark.circle", tone: .attention)
                case .closed:IMFlowStateMessage(text: Text("d7.imCompose.unavailable"), symbol: "lock")
                }
            } else { IMFlowStateMessage(text: Text("d7.imCompose.unavailable"), symbol: "lock") }
        }.imFlowForm().navigationTitle(Text("d7.imRoute.title")).privacySensitive()
        .toolbar { ToolbarItem(placement:.cancellationAction) { Button("action.close") { dismiss() } } }
        .sheet(isPresented:$picking) {
            if available { NavigationStack { ContextualTopicPicker(reader:reader) { row in
                guard available,model.appearance != nil else{return};selected=row
            } }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible) }
        }
        .onAppear { if available { model.observe() } }
        .onDisappear { stopOperation();model.retire();selected=nil;picking=false }
        .onChange(of:available) { _,value in if !value { stopOperation();model.retire();selected=nil;picking=false } else if model.appearance == nil { model.observe() } }
    }
    private func reviewSelectedSource() {
        guard operationTask == nil, available, let appearance = model.appearance, let selected else { return }
        let id = UUID(); operationID = id
        operationTask = Task {
            guard !Task.isCancelled, operationID == id, model.appearance == appearance, available else { return }
            await model.owner.reviewRoute(topicID: selected.id)
            guard operationID == id else { return }
            operationTask = nil; operationID = nil
        }
    }
    private func submit(_ operation: IMExpandedSubmission.Operation) {
        let permits: (IMMutation) -> Bool = { available && isRoute($0) }
        guard operationTask == nil, let token = model.prepare(operation, permits: permits) else { return }
        let id = UUID(); operationID = id
        operationTask = Task {
            _ = await model.perform(token, permits: permits)
            guard operationID == id else { return }
            operationTask = nil; operationID = nil
        }
    }
    private func stopOperation() {
        operationID = nil; operationTask?.cancel(); operationTask = nil
    }
    private func isRoute(_ mutation:IMMutation)->Bool { if case .send(let intent)=mutation,case .route=intent.payload{return true};return false }
}

/// First-party map selection, not a business POI/navigation source and never device location.
/// Apple MapProxy.convert(point, from:) supplies CLLocationCoordinate2D (WGS84); no relabeling of external coordinates.
@MainActor private struct IMStaticPlaceMapPicker:View {
    let current:()->Bool
    let selected:(IMStaticLocation)->Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var consented=false
    @State private var position:MapCameraPosition = .rect(MKMapRect.world)
    @State private var picked:CLLocationCoordinate2D?
    @State private var renderedCenter:CLLocationCoordinate2D?
    @State private var name=""
    @State private var address=""
    @State private var selectionUnavailable=false
    private var available:Bool { current() && scenePhase == .active }
    private var value:IMStaticLocation? {
        guard let picked else{return nil}
        return try? IMStaticLocation(name:name,address:address,latitude:picked.latitude,longitude:picked.longitude,datum:"WGS84")
    }
    var body:some View {
        NavigationStack {
            Form {
                if !available { IMFlowStateMessage(text: Text("d7.imCompose.unavailable"), symbol: "lock") }
                else if !consented {
                    // Loading tiles sends the browsed area to the map service; the consent gate stays explicit.
                    Section {
                        Text("d7.imMap.consent")
                        Button("d7.imMap.load") { if available { consented=true } }
                    }
                } else {
                    Section {
                        MapReader { proxy in
                            Map(position:$position,interactionModes:[.pan,.zoom]) {
                                if let picked { Marker("d7.imMap.selected",coordinate:picked) }
                            }.frame(height:360)
                            .onMapCameraChange(frequency:.onEnd) { context in
                                guard available,consented else{return};renderedCenter=context.region.center
                            }
                            .onTapGesture { point in
                                guard available,consented,let coordinate=proxy.convert(point,from:.local) else { selectionUnavailable=true;return }
                                choose(coordinate)
                            }
                        }
                        .listRowInsets(EdgeInsets())
                        if let renderedCenter {
                            Button { choose(renderedCenter) } label: { Label("d7.imMap.useCenter", systemImage: "scope") }
                        }
                        if selectionUnavailable {
                            IMFlowStateMessage(text: Text("d7.imMap.tapAgain"), symbol: "exclamationmark.circle", tone: .attention)
                        }
                    }
                    if let picked {
                        Section {
                            LabeledContent("d7.imMap.coordinates") { Text(verbatim:"\(picked.latitude), \(picked.longitude)").monospacedDigit() }
                            TextField("im.full.name",text:$name)
                            TextField("d7.imLocation.addressOptional",text:$address)
                        }
                        Section {
                            Button("d7.imMap.use") {
                                guard available,consented,let value else{return}
                                selected(value);dismiss()
                            }.imFlowPrimaryAction().disabled(value == nil)
                        }
                    }
                }
            }.imFlowForm().navigationTitle(Text("d7.imMap.title")).privacySensitive()
            .toolbar { ToolbarItem(placement:.cancellationAction) { Button("action.cancel") { dismiss() } } }
            .onDisappear { retire() }
            .onChange(of:available) { _,valid in if !valid { retire() } }
        }
    }
    private func choose(_ coordinate:CLLocationCoordinate2D) {
        guard available,consented,CLLocationCoordinate2DIsValid(coordinate),
              let coarse=try? IMStaticLocation(name:"地图选点",address:"",latitude:coordinate.latitude,
                                               longitude:coordinate.longitude,datum:"WGS84") else { selectionUnavailable=true;return }
        picked=CLLocationCoordinate2D(latitude:coarse.lat,longitude:coarse.lng);selectionUnavailable=false
    }
    private func retire() {
        consented=false;picked=nil;renderedCenter=nil;name="";address="";position = .rect(MKMapRect.world)
    }
}
