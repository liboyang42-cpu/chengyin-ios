import SwiftUI

/// Mode-2 pass/card-pack/store choice. Only these two free-exploration hosts reuse
/// this surface; city orientation retains its own route/task interface.
@MainActor struct FreeExplorationCardBrowser: View {
    let snapshot: PlaySnapshot
    @Binding var packOpen: Bool
    let onSelect: (Int) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        if let presentation = FreeExplorationPresentation(snapshot: snapshot) {
            VStack(alignment: .leading, spacing: 20) {
                Text("playFree.title").font(.caption.bold()).accessibilityIdentifier("playFree.pass")
                if let title = snapshot.result.topicName { Text(verbatim: title).font(.title.bold()) }
                if let description = snapshot.result.topicDescription { Text(verbatim: description) }
                Text("playFree.choiceHint")
                if let done = presentation.redeemed, let total = presentation.total {
                    Text("playFree.redeemed.count \(done) \(total)").accessibilityIdentifier("playFree.redeemed.count")
                }
                if let expiry = snapshot.result.expiresAt { LabeledContent("play.expiresAt") { Text(verbatim: expiry) } }
                if let note = snapshot.result.timeNote { Text(verbatim: note).font(.footnote) }
                if snapshot.availability == .registrationRequired { Text("playFree.registrationRequired") }
                else if !packOpen && !presentation.stores.isEmpty {
                    Button { packOpen = true } label: {
                        VStack(spacing: 18) {
                            Image(systemName: "rectangle.stack.fill").font(.largeTitle)
                            Text("playFree.pack.open").font(.title2.bold())
                        }.frame(maxWidth: .infinity, minHeight: 200).padding()
                            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 24))
                    }.buttonStyle(.plain).accessibilityIdentifier("playFree.pack.open")
                } else {
                    Text("playFree.stores").font(.headline)
                    if presentation.stores.isEmpty { Text("playFree.stores.empty") }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
                        ForEach(presentation.stores) { node in
                            Button { onSelect(node.id) } label: {
                                VStack(alignment: .leading, spacing: 12) {
                                    Image(systemName: "storefront.fill").font(.largeTitle).accessibilityHidden(true)
                                    FreeExplorationStoreName(name: node.name).font(.headline)
                                    if let title = node.gameTitle, !title.isEmpty { Text(verbatim: title).font(.subheadline) }
                                    if let open = node.openStatus, !open.isEmpty { Text(verbatim: open).font(.caption) }
                                    Text(LocalizedStringKey(FreeExplorationPresentation.state(of: node, in: snapshot).titleKey)).font(.caption.bold())
                                }.frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading).padding()
                                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                            }.buttonStyle(.plain).accessibilityIdentifier("playFree.store.\(node.id)")
                        }
                    }
                }
            }
        }
    }
}
struct FreeExplorationStoreName: View {
    let name: String?
    var body: some View {
        Group {
            if let name, !name.isEmpty { Text(verbatim: name) }
            else { Text("playFree.store.untitled") }
        }.fixedSize(horizontal: false, vertical: true)
    }
}

@MainActor struct FreeExplorationExperienceView: View {
    @Bindable var model: PlayExperienceCoordinator
    let storeDestination: (Int) -> AnyView
    @State private var selectedStore: Int?
    @State private var packOpen = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if model.phase == .loading { ProgressView("playx.loading") }
                if let issue = model.issue { PlayExperienceIssueView(issue: issue) }
                if !model.available { Text("playx.disabled") }
                if model.hasCurrentMediaSnapshot, let snapshot = model.snapshot {
                    FreeExplorationCardBrowser(snapshot: snapshot, packOpen: $packOpen) { id in
                        guard model.hasCurrentMediaSnapshot, model.snapshot == snapshot, model.gameplayMode == .freeExploration else { return }
                        selectedStore = id
                    }
                    if model.unresolved { Text(LocalizedStringKey(model.hasModeRecoveryBlock ? "playMode.recoveryBlocked" : "playFree.proof.pending")).font(.footnote) }
                    if FreeExplorationPresentation(snapshot: snapshot)?.isFullyRedeemed == true {
                        Text("playFree.redeemed.title").font(.headline)
                        ForEach(snapshot.visibleNodes.filter(snapshot.isDone)) { node in
                            Label { FreeExplorationStoreName(name: node.name) } icon: { Image(systemName: "checkmark.seal") }
                        }
                        Button("playFree.ending.read") { Task { await model.loadFreeExplorationEnding() } }
                        if let ending = model.ending {
                            if !ending.opener.isEmpty { Text(verbatim: ending.opener) }
                            ForEach(Array(ending.fragments.enumerated()), id: \.offset) { _, fragment in
                                VStack(alignment: .leading) {
                                    Text(verbatim: fragment.name).font(.headline)
                                    if let text = fragment.text, !text.isEmpty { Text(verbatim: text) }
                                }
                            }
                        }
                    }
                }
                Button("playx.refresh", systemImage: "arrow.clockwise") { Task { await model.load() } }
                    .disabled(!model.available || model.phase == .submitting || model.phase == .loading)
                    .accessibilityIdentifier("playFree.refresh")
            }.padding()
        }.accessibilityIdentifier("playFree.overview")
            .navigationDestination(item: $selectedStore) { id in storeDestination(id) }
            .onChange(of: model.identity) { _, _ in selectedStore = nil; packOpen = false }
            .onChange(of: model.gameplayMode) { _, mode in if mode != nil && mode != .freeExploration { selectedStore = nil; packOpen = false } }
    }
}

/// Store visit commands remain check-in/photo evidence, not route completion.
/// In-store games and scoped consent/redemption stay unavailable until migrated.
@MainActor struct FreeExplorationStoreView: View {
    let nodeID: Int
    @Bindable var model: PlayExperienceCoordinator
    let device: PlayDeviceCaptureCoordinator?
    let shopNPC: ShopNPCNodeHost?
    let mediaScope: UUID
    var makeExternalMaps: (@MainActor () -> PlatformExternalMaps)? = nil
    let storyDestination: (PlayNode) -> AnyView?
    @State private var review: PlayCompletionReview?
    @State private var showingReview = false
    @State private var issue: PlayExperienceError?
    private var node: PlayNode? {
        guard model.gameplayMode == .freeExploration else { return nil }
        return model.snapshot?.visibleNodes.first { $0.id == nodeID }
    }
    var body: some View {
        let context = model.interactionContext
        List {
            if let node, let snapshot = model.snapshot {
                Section {
                    FreeExplorationStoreName(name: node.name).font(.title2.bold())
                    Text(LocalizedStringKey(FreeExplorationPresentation.state(of: node, in: snapshot).titleKey))
                }
                if !snapshot.isLocked(node) {
                    if let description = node.description { Section { Text(verbatim: description) } }
                    if let hours = node.businessTime { LabeledContent("play.businessTime") { Text(verbatim: hours) } }
                    if model.hasCurrentMediaSnapshot, node.npc != nil, let shopNPC {
                        Section { ShopNPCNodeEntrance(name: shopNPC.name, makeCoordinator: shopNPC.makeCoordinator, greeting: shopNPC.greeting).id(shopNPC.identity) }
                    }
                    if let story = storyDestination(node) { NavigationLink("playFree.story") { story } }
                    PlatformExternalMapHost(destination: .init(name: node.name ?? "", address: node.address,
                        latitude: node.latitude, longitude: node.longitude), scope: mediaScope, makeModel: makeExternalMaps)
                    FreeExplorationVisitSteps(node: node)
                    if node.done != true {
                        if node.arrived == true, node.hasGame != false, node.gameDone != true { Text("playFree.game.unavailable") }
                        if node.selfReported == true { Text("playFree.redemption.unavailable") }
                        else if let task = FreeExplorationPresentation.evidenceTask(for: node, in: snapshot), let device {
                            PlayDeviceTaskSection(model: device, task: task, interaction: .init(context: context, current: { model.interactionContext }), onEvidence: { prepare($0, context: $1) })
                        } else { Text("playFree.evidence.unavailable") }
                    }
                }
                if model.unresolved { Text(LocalizedStringKey(model.hasModeRecoveryBlock ? "playMode.recoveryBlocked" : "playFree.proof.pending")) }
                if let issue { PlayExperienceIssueView(issue: issue) }
                Button("playx.refresh") { Task { await model.load() } }.disabled(model.phase == .loading || model.phase == .submitting)
            } else if model.phase == .loading || model.phase == .submitting { ProgressView("playx.loading") }
            else { Text("playFree.store.unavailable") }
        }.privacySensitive().navigationTitle("playFree.store.title").accessibilityIdentifier("playFree.store.detail")
            .confirmationDialog("playx.review", isPresented: $showingReview, titleVisibility: .visible) {
                Button("playFree.evidence.submit") { guard let review else { return }; self.review = nil; Task { await model.submit(review) } }
                Button("playx.cancel", role: .cancel) { review = nil; model.cancelReview() }
            } message: { Text("playFree.evidence.notice") }
            .onChange(of: showingReview) { _, visible in if !visible, review != nil { review = nil; model.cancelReview() } }
            .onDisappear { device?.cancel(); review = nil; model.cancelReview() }
    }
    private func prepare(_ evidence: PlayCompletionEvidence, context: PlayInteractionContext?) {
        guard let node, let snapshot = model.snapshot, FreeExplorationPresentation.evidenceTask(for: node, in: snapshot) != nil else { return }
        do { review = try model.review(nodeID: nodeID, evidence: evidence, context: context); showingReview = true; issue = nil }
        catch { issue = error as? PlayExperienceError ?? .invalidAction }
    }
}
struct FreeExplorationVisitSteps: View {
    let node: PlayNode
    var body: some View {
        Section("playx.merchant.steps") {
            Label("playx.merchant.scan", systemImage: node.arrived == true ? "checkmark.circle" : "circle")
            Label("playx.merchant.photo", systemImage: node.selfReported == true ? "checkmark.circle" : "circle")
            Label("playx.merchant.verify", systemImage: node.done == true ? "checkmark.circle" : "circle")
            Text("playx.merchant.notice").font(.footnote)
            if node.arrived == true, let requirement = node.photoRequirement { Text(verbatim: requirement) }
        }
    }
}

/// Ordinary Activity → Play uses a read-only reader when no runtime factory is granted.
@MainActor struct FreeExplorationReadStoreView: View {
    let nodeID: Int
    let model: PlayViewModel
    var body: some View {
        List {
            if let snapshot = model.visibleSnapshot, snapshot.result.mode == 2, snapshot.availability != .registrationRequired,
               let node = snapshot.visibleNodes.first(where: { $0.id == nodeID }) {
                Section {
                    FreeExplorationStoreName(name: node.name).font(.title2.bold())
                    Text(LocalizedStringKey(FreeExplorationPresentation.state(of: node, in: snapshot).titleKey))
                }
                if !snapshot.isLocked(node) {
                    if let address = node.address { Text(verbatim: address) }
                    if let hours = node.businessTime { LabeledContent("play.businessTime") { Text(verbatim: hours) } }
                    if let story = node.storyText { Section("playFree.story") { Text(verbatim: story) } }
                    FreeExplorationVisitSteps(node: node)
                }
                Text("playFree.readOnly").font(.footnote)
                Button("play.refresh") { Task { await model.load(keepingReceipt: true) } }
            } else if model.isLoading { ProgressView("play.loading") }
            else { Text("playFree.store.unavailable") }
        }.privacySensitive().navigationTitle("playFree.store.title").accessibilityIdentifier("playFree.read.store")
    }
}
