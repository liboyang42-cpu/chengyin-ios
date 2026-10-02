import SwiftUI

@MainActor final class MerchantNPCChatModel: ObservableObject {
    let coordinator: MerchantNPCChatCoordinator
    @Published var revision = 0
    init(_ coordinator: MerchantNPCChatCoordinator) { self.coordinator = coordinator; coordinator.onChange = { [weak self] in self?.revision += 1 } }
}
@MainActor struct MerchantNPCChatView: View {
    @StateObject private var model: MerchantNPCChatModel
    @State private var text = ""
    @Environment(\.scenePhase) private var scenePhase
    init(coordinator: MerchantNPCChatCoordinator) { _model = StateObject(wrappedValue: .init(coordinator)) }
    var body: some View {
        List {
            Text("merchantNPC.chatDisclosure")
            if model.coordinator.isCurrent {
                if let message = model.coordinator.message { Text(verbatim: message).textSelection(.enabled) }
                if let reply = model.coordinator.reply {
                    if let safe = reply.safeText, !safe.isEmpty { Text(verbatim: safe).textSelection(.enabled).accessibilityIdentifier("merchantNPC.reply") }
                    else { Text("merchantNPC.noReply") }
                    Text(verbatim: reply.outcomeStatus)
                    if reply.successAudioURL != nil { Text("merchantNPC.playbackOff") }
                }
                TextField("merchantNPC.message", text: $text, axis: .vertical).accessibilityIdentifier("merchantNPC.input")
                Button("merchantNPC.send") { Task { await model.coordinator.send(text); text = "" } }.disabled(!model.coordinator.canSend || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("merchantNPC.send")
                if model.coordinator.requestID != nil {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Button("merchantNPC.retry") { Task { await model.coordinator.retry() } }.disabled(!model.coordinator.canRetry)
                    }
                    Button("merchantNPC.abandon") { model.coordinator.abandon() }.disabled(model.coordinator.sending)
                }
                if model.coordinator.sending { ProgressView("merchantNPC.pending") }
                MerchantNPCIssue(failure: model.coordinator.failure)
            } else { Text("merchantNPC.sessionChanged") }
        }
        .navigationTitle("merchantNPC.chatTitle").privacySensitive()
        .onDisappear { text = ""; model.coordinator.invalidate() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { text = ""; model.coordinator.invalidate() } }
    }
}
@MainActor final class MerchantNPCResourceModel: ObservableObject {
    let coordinator: MerchantNPCResourcesCoordinator
    @Published var revision = 0
    init(_ coordinator: MerchantNPCResourcesCoordinator) { self.coordinator = coordinator; coordinator.onChange = { [weak self] in self?.revision += 1 } }
}
/// Inputs come exclusively from a separately approved bounded media consumer; no arbitrary URL fields.
@MainActor struct MerchantNPCResourceEditor: View {
    @StateObject private var model: MerchantNPCResourceModel
    let samples: [MerchantNPCMediaReference]
    let voiceSamples: MerchantNPCVoiceSamplesCoordinator?
    let image: MerchantNPCMediaReference?
    let imageContext: RetainedImageSelectionContext?
    let imageRealm: String?
    let approvedImageHosts: Set<String>
    @State private var selectedImage: MerchantNPCMediaReference?
    private var currentImage: MerchantNPCMediaReference? { selectedImage ?? image }
    @State private var ownsVoice = false
    @State private var consent = false
    @State private var style = ""
    @State private var localFailure: MerchantNPCFailure?
    @Environment(\.scenePhase) private var scenePhase
    init(coordinator: MerchantNPCResourcesCoordinator, samples: [MerchantNPCMediaReference] = [], image: MerchantNPCMediaReference? = nil, imageContext: RetainedImageSelectionContext? = nil, imageRealm: String? = nil, approvedImageHosts: Set<String> = [], makeVoiceSamples: ((MerchantNPCResourcesCoordinator) -> MerchantNPCVoiceSamplesCoordinator)? = nil) {
        _model = StateObject(wrappedValue: .init(coordinator)); self.samples = samples; self.image = image
        self.imageContext = imageContext; self.imageRealm = imageRealm; self.approvedImageHosts = approvedImageHosts
        self.voiceSamples = makeVoiceSamples?(coordinator)
    }
    var body: some View {
        List {
            Text("merchantNPC.providerOff")
            if let voiceSamples { MerchantNPCVoiceSamplesView(coordinator: voiceSamples) }
            else {
                Section("merchantVoice.title") {
                    Text("merchantVoice.disclosure")
                    Text("merchantVoice.configurationRequired")
                        .accessibilityIdentifier("merchantVoice.configurationRequired")
                }
            }
            if model.coordinator.isCurrent, let resources = model.coordinator.resources {
                Section("merchantNPC.voice") {
                    Text(LocalizedStringKey(resources.voice.statusKey))
                    if let script = model.coordinator.script, script.isUsable {
                        ForEach(Array(script.script.enumerated()), id: \.offset) { index, line in
                            VStack(alignment: .leading) {
                                if index == 0 { Label("merchantNPC.authorizationFirst", systemImage: "checkmark.shield").font(.headline) }
                                Text(verbatim: "\(index + 1). \(line)").textSelection(.enabled)
                                Text(samples.contains { $0.kind == .voiceSample(index: index) } ? "merchantNPC.sampleReady" : "merchantNPC.sampleMissing")
                            }.accessibilityElement(children: .combine)
                        }
                    } else { Text("merchantNPC.recordingUnavailable") }
                    Toggle("merchantNPC.ownsVoice", isOn: $ownsVoice).accessibilityIdentifier("merchantNPC.ownsVoice")
                    Toggle("merchantNPC.consent", isOn: $consent).accessibilityIdentifier("merchantNPC.consent")
                    Button("merchantNPC.reviewEnroll") { prepare(.enroll(samples: samples, requestID: UUID())) }
                        .disabled(!model.coordinator.canEnroll || samples.count != 5 || !ownsVoice || !consent)
                        .accessibilityIdentifier("merchantNPC.reviewEnroll")
                    Button("merchantNPC.reviewRevoke", role: .destructive) { prepare(.revoke(requestID: UUID())) }.disabled(!consent)
                }
                Section("merchantNPC.avatar") {
                    Text(resources.avatar.available ? "merchantNPC.available" : "merchantNPC.unavailable")
                    if let job = resources.avatar.job {
                        Text(LocalizedStringKey(job.statusKey))
                        if let reason = job.failReason { Text(verbatim: reason) }
                    }
                    Picker("merchantNPC.style", selection: $style) {
                        Text("merchantNPC.chooseStyle").tag("")
                        ForEach(resources.avatar.styles, id: \.self) { Text(verbatim: $0).tag($0) }
                    }
                    if let imageContext, let imageRealm {
                        RetainedImageSelectionView(context: imageContext) { proof in
                            guard model.coordinator.isCurrent, imageContext.currentScope() == proof.scope else { return false }
                            do {
                                selectedImage = try proof.npcAvatar(scope: model.coordinator.scope, realm: imageRealm, approvedHosts: approvedImageHosts)
                                model.coordinator.discardReview(); localFailure = nil
                                return selectedImage != nil
                            } catch { localFailure = .invalid; return false }
                        }.id(imageContext.scope.accessRevision)
                    }
                    Text(currentImage == nil ? "merchantNPC.imageMissing" : "merchantNPC.imageReady")
                    Button("merchantNPC.reviewAvatar") { if let image = currentImage { prepare(.avatar(image: image, style: style)) } }
                        .disabled(!model.coordinator.canGenerate || currentImage == nil || style.isEmpty || !consent)
                }
            }
            if model.coordinator.isCurrent, let review = model.coordinator.review {
                Section("merchantNPC.review") {
                    reviewBody(review)
                    Text("merchantNPC.reviewWarning")
                    Button("merchantNPC.confirm") { Task { await model.coordinator.confirm(review.id) } }.accessibilityIdentifier("merchantNPC.confirm")
                    Button("merchantNPC.cancel") { model.coordinator.discardReview() }
                }
            }
            outcome
            MerchantNPCIssue(failure: localFailure ?? model.coordinator.failure)
            Button("merchantNPC.refresh") { Task { await model.coordinator.refresh() } }.disabled(model.coordinator.refreshing)
        }
        .navigationTitle("merchantNPC.resourcesTitle").privacySensitive()
        .task(id: model.coordinator.reader.scope) {
            await model.coordinator.refresh()
        }
        .task(id: model.coordinator.shouldPoll) {
            while !Task.isCancelled && model.coordinator.shouldPoll {
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                await model.coordinator.refresh()
            }
        }
        .onChange(of: ownsVoice) { _, _ in model.coordinator.discardReview() }
        .onChange(of: consent) { _, _ in model.coordinator.discardReview() }
        .onChange(of: style) { _, _ in model.coordinator.discardReview() }
        .onDisappear { voiceSamples?.invalidate(); model.coordinator.invalidate(); imageContext?.picker.cancel(); imageContext?.uploads.clear(); selectedImage = nil; ownsVoice = false; consent = false }
        .onChange(of: scenePhase) { _, phase in if phase != .active { voiceSamples?.invalidate(); model.coordinator.invalidate(); imageContext?.picker.cancel(); imageContext?.uploads.clear(); selectedImage = nil; ownsVoice = false; consent = false } }
    }
    @ViewBuilder private func reviewBody(_ review: MerchantNPCResourceReview) -> some View {
        switch review.action {
        case .enroll(let samples, _):
            Text("merchantNPC.reviewEnroll")
            ForEach(Array(samples.enumerated()), id: \.offset) { index, sample in Text(verbatim: "\(index + 1). \(sample.url.host ?? "")").accessibilityLabel(Text("merchantNPC.sampleReady")) }
        case .revoke: Text("merchantNPC.revokeWarning")
        case .avatar(_, let style): Text("merchantNPC.reviewAvatar"); Text(verbatim: style)
        }
    }
    @ViewBuilder private var outcome: some View {
        switch model.coordinator.outcome {
        case .sending: ProgressView("merchantNPC.pending")
        case .unknown: Text("merchantNPC.unknown").accessibilityIdentifier("merchantNPC.unknown")
        case .accepted(let receipt):
            Text("merchantNPC.accepted")
            if case .accepted(let message) = receipt, let message { Text(verbatim: message) }
            if case .avatarJob(let job) = receipt { Text(verbatim: job.status) }
        default: EmptyView()
        }
    }
    private func prepare(_ action: MerchantNPCResourceAction) {
        do { try model.coordinator.prepare(action, ownsVoice: ownsVoice, explicitConsent: consent); localFailure = nil }
        catch { localFailure = error as? MerchantNPCFailure ?? .invalid }
    }
}
struct MerchantNPCIssue: View {
    let failure: MerchantNPCFailure?
    var body: some View {
        if let failure {
            if case .rejected(_, let message) = failure, let message { Text(verbatim: message).accessibilityIdentifier("merchantNPC.error") }
            else { Text(failure == .unknownOutcome ? "merchantNPC.unknown" : "merchantNPC.unavailable").accessibilityIdentifier("merchantNPC.error") }
        }
    }
}

extension PublicMerchantHomeContext {
    /// Existing `shopNpcChat` is a source feature-flag name, not permission to use ShopNPC APIs.
    mutating func installMerchantNPC(grants: @escaping () -> MerchantNPCGrants, scopeForRow: @escaping (PublicMerchantRowID) -> MerchantNPCScope?, currentScope: @escaping (PublicMerchantRowID) -> MerchantNPCScope?, client: MerchantNPCHTTPClient, register: @escaping (MerchantNPCChatCoordinator) -> Void = { _ in }) {
        shopNpcChat = grants().chatAllowed
        npcDestination = { row, _ in
            guard grants().chatAllowed, let scope = scopeForRow(row), scope.merchantRowID == row else { return AnyView(Text("merchantNPC.unavailable")) }
            let coordinator = MerchantNPCChatCoordinator(scope: scope, client: client, currentScope: { currentScope(row) }, grants: grants)
            register(coordinator)
            return AnyView(MerchantNPCChatView(coordinator: coordinator))
        }
    }
}
