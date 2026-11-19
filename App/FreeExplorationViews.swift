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
                if let unlocked = presentation.storyUnlocked, let chapters = presentation.storyTotal {
                    Label("playFree.story.unlocked.count \(unlocked) \(chapters)", systemImage: "books.vertical")
                        .font(.headline).accessibilityIdentifier("playFree.story.unlocked.count")
                }
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
                    }.buttonStyle(QuestifyCardButtonStyle()).accessibilityIdentifier("playFree.pack.open")
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
                                    FreeExplorationStoryBadge(node: node, snapshot: snapshot).font(.caption)
                                }.frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading).padding()
                                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                            }.buttonStyle(QuestifyCardButtonStyle()).accessibilityIdentifier("playFree.store.\(node.id)")
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
    var rewardCollectionDestination: ((PlayRewardBadgeTarget) -> AnyView)? = nil
    @State private var selectedStore: Int?
    @State private var packOpen = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if model.phase == .loading { ProgressView("playx.loading") }
                // FE-STORY: an offline or expired read shows the read-only archive instead of a bare error.
                if let issue = model.issue, model.storyArchive == nil { PlayExperienceIssueView(issue: issue) }
                if !model.available { Text("playx.disabled") }
                if let archive = model.storyArchive, let source = model.storyArchiveSource {
                    FreeExplorationArchiveView(archive: archive, source: source)
                } else if model.hasCurrentMediaSnapshot, let snapshot = model.snapshot {
                    FreeExplorationCardBrowser(snapshot: snapshot, packOpen: $packOpen) { id in
                        guard model.hasCurrentMediaSnapshot, model.snapshot == snapshot, model.gameplayMode == .freeExploration else { return }
                        selectedStore = id
                    }
                    if let reward = model.reward {
                        PlayRewardBadgeRows(targets: PlayRewardBadgeTarget.targets(in: reward), destination: rewardCollectionDestination)
                            .id(PlayRewardBadgeTarget.targets(in: reward))
                    }
                    if model.unresolved { Text(LocalizedStringKey(model.hasModeRecoveryBlock ? "playMode.recoveryBlocked" : "playFree.proof.pending")).font(.footnote) }
                    if FreeExplorationPresentation(snapshot: snapshot)?.isFullyRedeemed == true {
                        Text("playFree.redeemed.title").font(.headline)
                        ForEach(snapshot.visibleNodes.filter(snapshot.isDone)) { node in
                            Label { FreeExplorationStoreName(name: node.name) } icon: { Image(systemName: "checkmark.seal") }
                        }
                    }
                    // FE-STORY: the ending opens once every place was visited, in any order.
                    if FreeExplorationPresentation(snapshot: snapshot)?.isFullyVisited == true {
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
    /// Fixture-only seam; production reads one foreground fix through CoreLocation.
    var makeArrivalLocation: (@MainActor () -> any RoamDeviceLocationProviding)? = nil
    @State private var review: PlayCompletionReview?
    @State private var showingReview = false
    @State private var issue: PlayExperienceError?
    @State private var arrival: PlayArrivalService?
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
                    FreeExplorationStoryBadge(node: node, snapshot: snapshot)
                }
                if !snapshot.isLocked(node), snapshot.isStoryLocked(node) {
                    // FE-STORY locked card: only what finds the place; no chapter text or NPC.
                    FreeExplorationLockedCard(node: node)
                    PlatformExternalMapHost(destination: .init(name: node.name ?? "", address: node.address,
                        latitude: node.latitude, longitude: node.longitude), scope: mediaScope, makeModel: makeExternalMaps)
                    if node.visitCheck == .scan {
                        Section { Label("playFree.story.scanUnlock", systemImage: "qrcode.viewfinder").font(.headline) }
                    } else if let arrival {
                        PlayArrivalControl(arrival: arrival, nodeID: nodeID, context: context, canSubmit: model.canSubmitArrival, visitRadius: node.visitRadius)
                    }
                }
                if !snapshot.isLocked(node) {
                    if !snapshot.isStoryLocked(node) {
                        if let description = node.description { Section { Text(verbatim: description) } }
                        if let hours = node.businessTime { LabeledContent("play.businessTime") { Text(verbatim: hours) } }
                        if model.hasCurrentMediaSnapshot, node.npc != nil, let shopNPC {
                            Section {
                                ShopNPCNodeEntrance(name: shopNPC.name, makeCoordinator: shopNPC.makeCoordinator, greeting: shopNPC.greeting,
                                    makeScriptedGuide: { scope in ShopNPCScriptedGuideSource(runtime: model, nodeID: nodeID, conversation: scope) }).id(shopNPC.identity)
                            }
                        }
                        if let story = storyDestination(node) { NavigationLink("playFree.story") { story } }
                        PlatformExternalMapHost(destination: .init(name: node.name ?? "", address: node.address,
                            latitude: node.latitude, longitude: node.longitude), scope: mediaScope, makeModel: makeExternalMaps)
                    }
                    FreeExplorationVisitSteps(node: node, visited: snapshot.isVisited(node))
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
            .onAppear {
                guard arrival == nil else { return }
                let location: any RoamDeviceLocationProviding
                if let makeArrivalLocation { location = makeArrivalLocation() }
                else { location = RuntimeNativeLocationProvider(enabled: device?.supports(.location) == true) }
                arrival = PlayArrivalService(runtime: model, location: location)
            }
            .onDisappear { device?.cancel(); review = nil; model.cancelReview(); arrival?.cancel() }
    }
    private func prepare(_ evidence: PlayCompletionEvidence, context: PlayInteractionContext?) {
        guard let node, let snapshot = model.snapshot, FreeExplorationPresentation.evidenceTask(for: node, in: snapshot) != nil else { return }
        do { review = try model.review(nodeID: nodeID, evidence: evidence, context: context); showingReview = true; issue = nil }
        catch { issue = error as? PlayExperienceError ?? .invalidAction }
    }
}
/// FE-STORY: 「到访」(GPS or scan) then 「核销」. Each row states done/not done in text, not icon only.
struct FreeExplorationVisitSteps: View {
    let node: PlayNode
    let visited: Bool
    var body: some View {
        Section("playFree.steps") {
            step("playFree.steps.visit", done: visited)
            step("playFree.steps.redeem", done: node.done == true)
            Text("playFree.steps.notice").font(.footnote)
            if node.arrived == true, let requirement = node.photoRequirement { Text(verbatim: requirement) }
        }
    }
    private func step(_ key: LocalizedStringKey, done: Bool) -> some View {
        HStack {
            Label(key, systemImage: done ? "checkmark.circle.fill" : "circle")
            Spacer()
            Text(LocalizedStringKey(done ? "playFree.steps.done" : "playFree.steps.pending")).font(.caption).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine)
    }
}
/// Lock state for one place card: lock icon plus 「到访后解锁」, or the visit date once unlocked.
struct FreeExplorationStoryBadge: View {
    let node: PlayNode
    let snapshot: PlaySnapshot
    var body: some View {
        if snapshot.isStoryLocked(node) {
            // VoiceOver hears the whole rule, not only the short visual label.
            Label("playFree.story.locked", systemImage: "lock.fill")
                .accessibilityLabel(Text("playFree.story.locked.a11y"))
                .accessibilityIdentifier("playFree.story.locked.\(node.id)")
        } else if snapshot.result.mode == 2 {
            if node.visitedByTeam == true {
                // FE-STORY 5.5: a teammate's visit unlocked it; `visitTime` may be null.
                Label("playFree.story.visitedByTeam", systemImage: "person.2.fill").accessibilityIdentifier("playFree.story.team.\(node.id)")
            } else {
                Label { visitText } icon: { Image(systemName: "book.pages") }.accessibilityIdentifier("playFree.story.unlocked.\(node.id)")
            }
        }
    }
    @ViewBuilder private var visitText: some View {
        switch node.visitTime {
        case .epochMilliseconds(let millis)?:
            Text("playFree.story.visitedOn \(Date(timeIntervalSince1970: Double(millis) / 1000).formatted(date: .abbreviated, time: .omitted))")
        case .text(let text)?: Text("playFree.story.visitedOn \(text)")
        case nil: Text("playFree.story.unlocked")
        }
    }
}
/// Name is in the header section. Shows only address, a spoiler-free hook and how to unlock.
struct FreeExplorationLockedCard: View {
    let node: PlayNode
    var body: some View {
        Section("playFree.story.lockedCard") {
            if let hook = node.hookText, !hook.isEmpty { Text(verbatim: hook) }
            if let address = node.address, !address.isEmpty { Label { Text(verbatim: address) } icon: { Image(systemName: "mappin") } }
            if let hours = node.businessTime { LabeledContent("play.businessTime") { Text(verbatim: hours) } }
            if node.visitCheck == .scan { Text("playFree.story.unlock.scan") }
            else { Text("playFree.story.unlock.gps \(PlayArrivalPolicy.visitRadiusMeters(configured: node.visitRadius))") }
        }.accessibilityIdentifier("playFree.story.lockedCard")
    }
}

/// FE-STORY 6.2 / 7.3 / 7.4: chapters already unlocked, read-only. Offline it is this device's
/// copy for this account and run; after expiry it is the server's history. Locked places name
/// why they stay locked and offer no visit control.
@MainActor struct FreeExplorationArchiveView: View {
    let archive: FreeExplorationStoryArchive
    let source: FreeExplorationArchiveSource
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(LocalizedStringKey(source == .offline ? "playFree.archive.offline" : "playFree.archive.expired"),
                  systemImage: source == .offline ? "wifi.slash" : "clock.badge.xmark")
                .font(.headline).accessibilityIdentifier("playFree.archive.notice")
            if let title = archive.topicName { Text(verbatim: title).font(.title2.bold()) }
            if let unlocked = archive.storyUnlocked, let total = archive.storyTotal {
                Label("playFree.story.unlocked.count \(unlocked) \(total)", systemImage: "books.vertical").font(.subheadline)
            }
            ForEach(archive.chapters) { chapter in
                VStack(alignment: .leading, spacing: 10) {
                    Group {
                        if let name = chapter.name { Text(verbatim: name) } else { Text("playFree.archive.untitledChapter") }
                    }.font(.headline).accessibilityAddTraits(.isHeader)
                    paragraphs(chapter.paragraphs)
                    ForEach(archive.places(in: chapter.id)) { place($0) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding()
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .accessibilityIdentifier("playFree.archive.chapter.\(chapter.id)")
            }
            ForEach(archive.placesWithoutChapter) { place($0) }
            ForEach(archive.lockedPlaces) { locked in
                VStack(alignment: .leading, spacing: 6) {
                    FreeExplorationStoreName(name: locked.name).font(.headline)
                    Label(LocalizedStringKey(source == .offline ? "playFree.archive.lockedOffline" : "playFree.archive.lockedExpired"), systemImage: "lock.fill")
                        .font(.subheadline)
                }.frame(maxWidth: .infinity, alignment: .leading).padding()
                    .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("playFree.archive.locked.\(locked.id)")
            }
            Text("playFree.archive.readOnly").font(.footnote).foregroundStyle(.secondary)
        }.accessibilityIdentifier("playFree.archive")
    }
    @ViewBuilder private func paragraphs(_ values: [String]) -> some View {
        ForEach(Array(values.enumerated()), id: \.offset) { _, text in Text(verbatim: text).fixedSize(horizontal: false, vertical: true) }
    }
    private func place(_ place: FreeExplorationStoryArchive.Place) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            FreeExplorationStoreName(name: place.name).font(.subheadline.bold())
            if place.visitedByTeam {
                Label("playFree.story.visitedByTeam", systemImage: "person.2.fill").font(.caption)
            } else if let time = place.visitTime {
                Label { FreeExplorationVisitTimeText(time: time) } icon: { Image(systemName: "book.pages") }.font(.caption)
            }
            if let address = place.address { Label { Text(verbatim: address) } icon: { Image(systemName: "mappin") }.font(.caption) }
            paragraphs(place.paragraphs)
        }.accessibilityIdentifier("playFree.archive.place.\(place.id)")
    }
}
struct FreeExplorationVisitTimeText: View {
    let time: PlayVisitTime
    var body: some View {
        switch time {
        case .epochMilliseconds(let millis):
            Text("playFree.story.visitedOn \(Date(timeIntervalSince1970: Double(millis) / 1000).formatted(date: .abbreviated, time: .omitted))")
        case .text(let text): Text("playFree.story.visitedOn \(text)")
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
                    // FE-STORY: chapter text only after a visit, even if a stale field arrives.
                    if snapshot.isVisited(node), !snapshot.isStoryLocked(node), let story = node.storyText { Section("playFree.story") { Text(verbatim: story) } }
                    else if snapshot.isStoryLocked(node), let hook = node.hookText, !hook.isEmpty { Section("playFree.story.lockedCard") { Text(verbatim: hook) } }
                    FreeExplorationVisitSteps(node: node, visited: snapshot.isVisited(node))
                }
                Text("playFree.readOnly").font(.footnote)
                Button("play.refresh") { Task { await model.load(keepingReceipt: true) } }
            } else if model.isLoading { ProgressView("play.loading") }
            else { Text("playFree.store.unavailable") }
        }.privacySensitive().navigationTitle("playFree.store.title").accessibilityIdentifier("playFree.read.store")
    }
}
