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
    @State private var directoryPage: ChannelAdmissionGovernanceView?
    @State private var directoryFailed = false
    @State private var selectedTopic: TopicSummary?
    @State private var showingTopics = false
    @State private var name = ""
    @State private var address = ""
    @State private var latitude = ""
    @State private var longitude = ""
    init(coordinator: IMExpandedCoordinator, identity: MessagingReadIdentity?, uploadOwner: IMImageUploadCoordinator? = nil, topicReader: (any TopicReading)? = nil, replyPolicy: IMConversationReplyPolicy? = nil,
         isConversationCurrent: @escaping () -> Bool = { true }, readCursor: Int? = nil,
         admission: ChannelAdmissionRoute? = nil, directory: ChannelDirectoryAdmissionRequest? = nil, showsAdmissionEntry: Bool = false,
         onConversationMutationAccepted: @escaping (IMScope) -> Void = { _ in }, onReceipt: @escaping (IMMutationReceipt) -> Void) {
        _model = StateObject(wrappedValue: IMExpandedViewModel(coordinator)); self.identity = identity; self.uploadOwner = uploadOwner; self.topicReader = topicReader; self.onReceipt = onReceipt
        self.replyPolicy = replyPolicy ?? .init(conversationID: coordinator.scope.conversationID, conversation: nil)
        self.isConversationCurrent = isConversationCurrent
        self.readCursor = readCursor
        self.admission = admission
        self.directory = directory
        self.showsAdmissionEntry = showsAdmissionEntry
        self.onConversationMutationAccepted = onConversationMutationAccepted
    }
    private var permitsReply: Bool { replyPolicy.permitsReply && isConversationCurrent() && identity == model.owner.scope.identity && model.owner.isCurrent }
    private func permits(_ mutation: IMMutation) -> Bool {
        isConversationCurrent() && identity == model.owner.scope.identity && model.owner.isCurrent && replyPolicy.permits(mutation)
    }
    var body: some View {
        Form {
            if !model.owner.writer.isConfigured { Text("im.full.disabled") }
            Section("im.full.conversation") {
                Button("im.full.read") { review(readMutation()) }
                Button("im.full.mute") { review(.mute(conversationID: model.owner.scope.conversationID, muted: true)) }
                Button("im.full.unmute") { review(.mute(conversationID: model.owner.scope.conversationID, muted: false)) }
            }
            if showsAdmissionEntry {
                Section("admission.title") {
                    if let directoryPage {
                        NavigationLink { directoryPage } label: { Text("admission.title") }
                            .accessibilityIdentifier("admission.entry")
                    } else if let directory, !directoryFailed {
                        Button("admission.title") {
                            Task {
                                do {
                                    directoryPage = try await ChannelAdmissionParent.page(
                                        configuration: directory.configuration, transport: directory.transport,
                                        token: directory.token, accountID: directory.accountID, epoch: directory.epoch,
                                        channelID: directory.channelID, spaceID: directory.spaceID, kind: directory.kind)
                                } catch { directoryFailed = true }
                            }
                        }.accessibilityIdentifier("admission.entry")
                    } else if let admission, let identity, identity.accountID == admission.accountID, identity.epoch == admission.epoch,
                              let page = try? admission.page() {
                        NavigationLink { page } label: { Text("admission.title") }
                            .accessibilityIdentifier("admission.entry")
                    } else {
                        Text("admission.unavailable").accessibilityIdentifier("admission.unavailable")
                    }
                }
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
        .onChange(of: identity) { _, _ in clearDrafts(); model.invalidateQueued(); model.state = model.owner.visibleState }
        .onChange(of: permitsReply) { _, allowed in if !allowed { clearDrafts(); model.invalidateQueued() } }
        .onChange(of: isConversationCurrent()) { _, current in if !current { clearDrafts(); model.invalidateQueued() } }
        .onDisappear { clearDrafts(); model.retire() }
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
struct IMMutationSummary: View {
    let mutation: IMMutation
    var body: some View {
        switch mutation {
        case .start(let id): Text("im.full.start"); Text(verbatim: String(id))
        case .read(let id): Text("im.full.read"); Text(verbatim: String(id))
        case .readCursor(let id, let last, let requestID):
            Text("im.full.read"); Text(verbatim: String(id)); Text(verbatim: String(last)); Text(verbatim: requestID)
        case .mute(let id, let muted): Text(LocalizedStringKey(muted ? "im.full.mute" : "im.full.unmute")); Text(verbatim: String(id))
        case .send(let intent):
            Text("im.full.sendTo"); Text(verbatim: String(intent.scope.conversationID))
            switch intent.payload {
            case .route(let id): Text("im.full.route"); Text(verbatim: String(id))
            case .image: Text("im.full.image")
            case .video(let reference): Text("原视频消息").font(.body).fixedSize(horizontal: false, vertical: true); Text(verbatim: "\(Double(reference.durationMS)/1000) 秒 · \(reference.size) 字节").font(.body).fixedSize(horizontal: false, vertical: true)
            case .file(let reference): Text("原文件消息").font(.body).fixedSize(horizontal: false, vertical: true); Text(verbatim: "\(reference.name) · \(reference.size) 字节").font(.body).fixedSize(horizontal: false, vertical: true)
            case .voice(let reference): Text("原语音消息").font(.body).fixedSize(horizontal: false, vertical: true); Text(verbatim: "\(Double(reference.durationMS)/1000) 秒").font(.body).fixedSize(horizontal: false, vertical: true)
            case .staticLocation(let place):
                Text("静态地点，非实时位置").font(.body).fixedSize(horizontal: false, vertical: true);Text(verbatim:place.name).font(.body).fixedSize(horizontal: false, vertical: true);Text(verbatim:place.address).font(.body).fixedSize(horizontal: false, vertical: true)
                Text(verbatim:"WGS84 · \(place.lat), \(place.lng)（四位小数）").font(.body).fixedSize(horizontal: false, vertical: true)
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


private extension IMOutgoingPayload {
    var isChannelHostSourceCard: Bool {
        switch self { case .route, .staticLocation: return true; default: return false }
    }
}

@MainActor struct IMStaticLocationComposeView: View {
    @StateObject private var model: IMExpandedViewModel
    @Environment(\.scenePhase) private var phase
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
                    Section("选择静态地点") {
                        Button("在地图上点选地点（不使用GPS）") { pickingMap=true }.font(Theme.Font.button)
                        Text("输入已知地点；不会读取设备位置。仅支持明确 WGS84 来源，不能把导航/私有剧情点许可当分享授权。").fixedSize(horizontal: false, vertical: true).font(.footnote)
                        TextField("地点名称",text:$name);TextField("地址（可选）",text:$address)
                        TextField("纬度",text:$latitude).keyboardType(.numbersAndPunctuation)
                        TextField("经度",text:$longitude).keyboardType(.numbersAndPunctuation)
                        Toggle("我确认来源坐标为 WGS84",isOn:$confirmedDatum)
                        Button("确认地点与收件会话") {
                            guard available,confirmedDatum,let lat=Double(latitude),let lng=Double(longitude),
                                  let place=try? IMStaticLocation(name:name,address:address,latitude:lat,longitude:lng,datum:"WGS84"),
                                  let intent=try? IMOutgoingIntent(scope:model.owner.scope,payload:.staticLocation(place)) else { return }
                            _ = model.owner.review(.send(intent))
                        }.font(Theme.Font.button).disabled(!confirmedDatum || !model.owner.writer.canSendStaticLocation)
                    }
                case .reviewing(let mutation):
                    if isLocation(mutation) {
                        IMMutationSummary(mutation:mutation)
                        Text("将向此会话发送上述四位坐标与地址。不是实时位置，也不提供导航。").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
                        Button("确认发送此地点") { submit(.confirm) }.imFlowPrimaryAction()
                        Button("取消",role:.cancel) { model.owner.cancelReview() }.font(Theme.Font.button)
                    } else { Text("请先处理当前会话的原请求").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true) }
                case .outcomeUnknown(let mutation):
                    if isLocation(mutation) {
                        IMMutationSummary(mutation:mutation);Text("结果未知，保留原请求，不自动发送。").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
                        if model.owner.canRecoverStaticLocation { Button("读取原结果，不重发") { submit(.recoverStaticLocation) }.font(Theme.Font.button) }
                        // Recovery never grants new SEND. Explicit retry remains the same original key and bytes.
                        if model.owner.writer.canSendStaticLocation { Button("明确重试同一个原地点请求") { submit(.retry) }.font(Theme.Font.button) }
                    } else { Text("请先恢复当前会话的其他原请求").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true) }
                case .submitting: ProgressView()
                case .acknowledged:
                    Text("原地点消息已确认").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
                    if model.owner.writer.canSendStaticLocation {
                        Button("重新选择另一个地点") { clear();model.owner.finishStaticLocationResult() }.font(Theme.Font.button)
                    }
                case .rejected: Text("请求被拒绝；原记录保留，不替换地点或请求号").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
                case .closed: Text("当前会话不可用").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
                }
            } else { Text("当前身份或会话权限已失效").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true) }
        }.imFlowForm().navigationTitle("静态地点分享").privacySensitive()
         .onChange(of:latitude) { _,_ in if pickedMapSignature != latitude+"|"+longitude { confirmedDatum=false;pickedMapSignature=nil } }
         .onChange(of:longitude) { _,_ in if pickedMapSignature != latitude+"|"+longitude { confirmedDatum=false;pickedMapSignature=nil } }
         .sheet(isPresented:$pickingMap) {
             IMStaticPlaceMapPicker(current:{ available && model.appearance != nil }) { place in
                 guard available,model.appearance != nil else{return}
                 name=place.name;address=place.address;latitude=String(place.lat);longitude=String(place.lng)
                 pickedMapSignature=latitude+"|"+longitude;confirmedDatum=true
             }
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
    var body:some View {
        Form {
            if available {
                Text(verbatim:"目标会话：\(model.owner.scope.conversationID)").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
                switch model.state {
                case .idle:
                    if let selected { Text(verbatim:selected.name).font(Theme.Font.body).fixedSize(horizontal: false, vertical: true) }
                    Button("从原路线列表选择") { picking=true }.font(Theme.Font.button)
                    Text("可查看或导航不代表可公开分享；选择后由原后端核对公开分享来源。").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
                    Button("核对公开分享来源") { reviewSelectedSource() }.font(Theme.Font.button)
                        .disabled(selected == nil || !model.owner.writer.canReadRouteShareSource || !model.owner.writer.canSendRoute)
                    if model.owner.routeShareUnavailable { Text("该路线暂不可分享，不返回隐藏原因或内容。").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true) }
                case .reviewing(let mutation):
                    if isRoute(mutation),let source=model.owner.selectedRouteShareSource {
                        Text(verbatim:source.name).font(Theme.Font.body).fixedSize(horizontal: false, vertical: true);IMMutationSummary(mutation:mutation)
                        Text("只发送路线引用，不复制隐藏节点或轨迹，不附带导航/解锁权限。接收者打开时仍须满足原访问规则。").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
                        Button("确认向此会话发送路线卡") { submit(.confirm) }.imFlowPrimaryAction()
                        Button("取消",role:.cancel) { model.owner.cancelReview() }.font(Theme.Font.button)
                    } else { Text("请先处理此会话的其他原请求").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true) }
                case .outcomeUnknown(let mutation):
                    if isRoute(mutation) {
                        IMMutationSummary(mutation:mutation);Text("结果未知；保留同一个原路线ID与请求号，不自动重发。").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
                        if model.owner.canRecoverRoute { Button("读取原路线卡结果，不重发") { submit(.recoverRoute) }.font(Theme.Font.button) }
                        if model.owner.writer.canSendRoute { Button("明确重试同一个原请求") { submit(.retry) }.font(Theme.Font.button) }
                    } else { Text("请先恢复此会话的其他原请求").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true) }
                case .submitting:ProgressView()
                case .acknowledged:
                    Text("原消息结果已确认；路线是否仍可查看以接收方当前读取为准。").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
                    Button("重新选择另一条路线") { selected=nil;model.owner.finishRouteResult() }.font(Theme.Font.button)
                case .rejected:Text("请求被拒绝，原请求保持不变").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
                case .closed:Text("当前会话不可用").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
                }
            } else { Text("当前身份或会话权限已失效").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true) }
        }.imFlowForm().navigationTitle("分享原路线卡").privacySensitive()
        .sheet(isPresented:$picking) {
            if available { NavigationStack { ContextualTopicPicker(reader:reader) { row in
                guard available,model.appearance != nil else{return};selected=row
            } } }
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
                if !available { Text("当前会话或身份已失效，不能返回地点").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true) }
                else if !consented {
                    Text("打开系统地图后，地图服务会收到你浏览区域的地图请求。此页不读取GPS、当前位置或实时轨迹，不查询业务POI或隐藏路线点。").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
                    Text("地图点选只准备静态地点；返回后仍须单独确认目标会话和发送。").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
                    Button("同意加载地图并手动点选") { if available { consented=true } }.font(Theme.Font.button)
                } else {
                    Text("平移、缩放地图后点选，或使用“选取当前地图中心”。没有默认已选地点。").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
                    MapReader { proxy in
                        Map(position:$position,interactionModes:[.pan,.zoom]) {
                            if let picked { Marker("已选静态地点",coordinate:picked) }
                        }.frame(height:360)
                        .onMapCameraChange(frequency:.onEnd) { context in
                            guard available,consented else{return};renderedCenter=context.region.center
                        }
                        .onTapGesture { point in
                            guard available,consented,let coordinate=proxy.convert(point,from:.local) else { selectionUnavailable=true;return }
                            choose(coordinate)
                        }
                    }
                    Button("选取当前地图中心") { if let renderedCenter { choose(renderedCenter) } }.font(Theme.Font.button)
                        .disabled(renderedCenter == nil)
                    if selectionUnavailable { Text("无法确认此点坐标，请重新点选；不会代填坐标。").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true) }
                    if let picked {
                        Text(verbatim:"MapKit WGS84 · \(picked.latitude), \(picked.longitude)（四位小数）").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
                        TextField("为地点填写名称",text:$name)
                        TextField("地址说明（可选，不自动查询）",text:$address)
                        Text("这是地图上的静态大致位置，不表示你现在位于此处，也不提供导航。").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
                        Button("使用此点并返回确认页") {
                            guard available,consented,let value else{return}
                            selected(value);dismiss()
                        }.font(Theme.Font.button).disabled(value == nil)
                    }
                }
            }.imFlowForm().navigationTitle("地图选择静态地点").privacySensitive()
            .toolbar { ToolbarItem(placement:.cancellationAction) { Button("取消") { dismiss() } } }
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
