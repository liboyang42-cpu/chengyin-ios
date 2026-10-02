import SwiftUI

/// Integration entry for migrated runtime. Factories are scope-specific, optional, and
/// never create provider/network permissions as a side effect of opening the screen.
@MainActor struct PlayExperienceView: View {
    @Bindable var model: PlayExperienceCoordinator
    var deviceModel: ((Int) -> PlayDeviceCaptureCoordinator)? = nil
    var advancedModel: ((Int) -> PlayAdvancedCoordinator?)? = nil
    var motionModel: ((Int, PlayStillnessConfiguration) -> PlayStillnessCoordinator?)? = nil
    var preferenceModel: ((Int) -> PlayPreferenceCoordinator?)? = nil
    var summaryModel: ((Int) -> PlayOperatingSummaryCoordinator?)? = nil
    var playerModel: PlayPlayerGameCoordinator? = nil
    var circleModel: PlayCircleCoordinator? = nil
    var prefabModel: PlayPrefabRuntimeCoordinator? = nil
    var journeyModel: ((Int) -> JourneyCheckCoordinator?)? = nil
    var ambientModel: JourneyAmbientCoordinator? = nil
    var shopNPCModel: ((Int) -> ShopNPCNodeHost?)? = nil
    var invalidateShopNPC: (() -> Void)? = nil
    var mediaScope: UUID = UUID()
    var makeAudio: (@MainActor () -> PlatformAudioPlayback)? = nil
    var makeExternalMaps: (@MainActor () -> PlatformExternalMaps)? = nil
    @State private var selectedNode: Int?
    @State private var confirmEnd = false
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        List {
            Section {
                Label("playx.title", systemImage: "figure.walk")
                    .font(.title2.bold()).accessibilityAddTraits(.isHeader)
                if let snapshot = model.snapshot {
                    if let title = snapshot.result.topicName { Text(verbatim: title).font(.headline) }
                    LabeledContent("playx.state") { PlayRuntimePhaseText(phase: model.phase.rawValue) }
                    if let total = snapshot.result.total, let done = snapshot.displayedDoneCount { LabeledContent("playx.progress") { Text(verbatim: "\(done) / \(total)") } }
                    if let note = snapshot.result.timeNote { Text(verbatim: note).foregroundStyle(.secondary) }
                }
                if !model.available { Text("playx.disabled").accessibilityIdentifier("playx.disabled") }
                if model.phase == .loading { ProgressView("playx.loading") }
                if let issue = model.issue { PlayExperienceIssueView(issue: issue) }
                Button("playx.refresh", systemImage: "arrow.clockwise") { Task { await model.load() } }
                    .disabled(model.phase == .submitting || !model.available).accessibilityIdentifier("playx.refresh")
            }
            if model.unresolved {
                Section("playx.unknown.title") {
                    Text("playx.unknown.body")
                    Button("playx.reconcile") { Task { await model.load() } }.accessibilityIdentifier("playx.reconcile")
                    if model.canRetryExactBranch {
                        Button("playx.retryExact") { Task { await model.retryExactBranchAfterReadback() } }
                            .accessibilityIdentifier("playx.retryExact")
                    }
                }
            }
            if let ambientModel { PlayAmbientView(model: ambientModel) }
            if model.snapshot != nil {
                Section("playx.run.title") {
                    LabeledContent("playx.run.elapsed") { Text(verbatim: "\(model.clock.elapsedSeconds) s").monospacedDigit() }
                    if model.clock.phase == .running {
                        Button("playx.run.pause") { Task { await model.pauseRun(now: ProcessInfo.processInfo.systemUptime, savedAt: Self.milliseconds) } }
                            .accessibilityIdentifier("playx.run.pause")
                    } else if model.clock.phase != .ended {
                        Button("playx.run.resume") { model.startRun(now: ProcessInfo.processInfo.systemUptime) }.accessibilityIdentifier("playx.run.resume")
                    }
                    Button("playx.run.end", role: .destructive) { confirmEnd = true }.accessibilityIdentifier("playx.run.end")
                    if model.remoteRunSaveFailed { Text("playx.run.saveFailed").foregroundStyle(.orange) }
                }
                if let snapshot = model.snapshot, model.hasCurrentMediaSnapshot {
                    Section("chapterStory.title") {
                        ForEach(snapshot.result.chapters) { chapter in
                            if let node = snapshot.visibleNodes.first(where: { $0.chapterID == chapter.id && !snapshot.isLocked($0) }),
                               model.chapterStories[chapter.id] != nil {
                                NavigationLink {
                                    ChapterStoryView(chapterID: chapter.id, nodeID: node.id, model: model,
                                        advancedModel: advancedModel, deviceModel: deviceModel, mediaScope: mediaScope,
                                        makeAudio: makeAudio, nodeDestination: { AnyView(nodeDestination($0)) })
                                } label: {
                                    if let title = chapter.name { Label { Text(verbatim: title) } icon: { Image(systemName: "book") } }
                                    else { Label("chapterStory.title", systemImage: "book") }
                                }.accessibilityIdentifier("chapterStory.open.\(chapter.id)")
                            }
                        }
                    }
                }
                Section("playx.nodes") {
                    ForEach(model.snapshot?.visibleNodes ?? []) { node in
                        Button { selectedNode = node.id } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(verbatim: node.name ?? "#\(node.id)").font(.headline)
                                Text(LocalizedStringKey("playx.task." + PlayNodeTask.resolve(mode: model.snapshot?.result.mode, node: node).rawValue))
                                    .foregroundStyle(.secondary)
                                if let reason = model.snapshot?.lockReason(node) { Text(verbatim: reason).font(.footnote) }
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                        }.accessibilityIdentifier("playx.node.\(node.id)")
                    }
                }
                Section("playx.results") {
                    Button("playx.results.load") { Task { await model.loadEndingAndLeaderboard() } }.accessibilityIdentifier("playx.results.load")
                    NavigationLink("playx.stopwatch") { PlayStopwatchView() }
                    if let topicID = model.snapshot?.result.topicID, let factory = summaryModel, let summary = factory(topicID) {
                        NavigationLink("playx.os.title") { PlayOperatingSummaryView(model: summary) }
                    }
                    if PrefabPreviewState.isPrefabTopic(name: model.snapshot?.result.topicName), let prefabModel {
                        NavigationLink("playx.prefab.title") { PlayPrefabRuntimeView(model: prefabModel) }
                    }
                    if let playerModel { NavigationLink("playx.player.title") { PlayPlayerSessionView(model: playerModel) } }
                    if let circleModel { NavigationLink("playx.circle.title") { PlayCircleView(model: circleModel) } }
                }
                if let reward = model.reward { PlayRewardSection(reward: reward) }
                if let ending = model.ending {
                    Section("playx.ending") {
                        if ending.hasStory {
                            if !ending.opener.isEmpty { Text(verbatim: ending.opener) }
                            ForEach(Array(ending.fragments.enumerated()), id: \.offset) { _, fragment in
                                VStack(alignment: .leading) { Text(verbatim: fragment.name).font(.headline); if let text = fragment.text, !text.isEmpty { Text(verbatim: text) } }
                            }
                        } else { Text("playx.ending.empty").accessibilityIdentifier("playx.ending.empty") }
                    }
                }
                if let board = model.leaderboard {
                    Section("playx.leaderboard") {
                        Text("playx.leaderboard.metric").font(.footnote)
                        ForEach(board.entries) { row in
                            LabeledContent { Text(verbatim: String(row.score)) } label: { Text(verbatim: "\(row.rank.map(String.init) ?? "—") · \(row.name ?? "#\(row.id)")") }
                        }
                        LabeledContent("playx.leaderboard.me") { Text(verbatim: "\(board.me.rank.map(String.init) ?? "—") · \(board.me.score)") }
                    }
                }
                if case .activity = model.scope { PlayLeadSection(model: model) }
            }
        }
        .privacySensitive().navigationTitle("playx.title").navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("playx.overview")
        .navigationDestination(item: $selectedNode) { id in nodeDestination(id) }
        .confirmationDialog("playx.run.end", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("playx.run.end", role: .destructive) { Task { await model.endRun(now: ProcessInfo.processInfo.systemUptime, savedAt: Self.milliseconds) } }
        } message: { Text("playx.run.end.detail") }
        .task(id: model.identity) { selectedNode = nil; await model.load(); await model.restoreRun(); projectAmbient() }
        .onChange(of: model.snapshot?.result) { _, _ in projectAmbient() }
        .onChange(of: model.snapshot) { _, _ in invalidateShopNPC?() }
        .onChange(of: model.hasCurrentMediaSnapshot) { _, current in if !current { invalidateShopNPC?() } }
        .onChange(of: scenePhase) { _, next in
            if next != .active, model.clock.phase == .running { Task { await model.pauseRun(now: ProcessInfo.processInfo.systemUptime, savedAt: Self.milliseconds) } }
        }
    }
    private func nodeDestination(_ id: Int) -> some View {
        let configuration = try? PlayStillnessConfiguration(raw: model.extras[id]?.sensorConfig ?? .null)
        return PlayExperienceNodeView(nodeID: id, model: model, device: deviceModel?(id), advanced: advancedModel.flatMap { $0(id) },
            stillness: configuration.flatMap { configuration in motionModel.flatMap { $0(id, configuration) } },
            preference: preferenceModel.flatMap { $0(id) }, journey: journeyModel.flatMap { $0(id) }, shopNPC: shopNPCModel?(id),
            mediaScope: mediaScope, makeAudio: makeAudio, makeExternalMaps: makeExternalMaps)
    }
    private func projectAmbient() {
        guard let result = model.snapshot?.result else { return }
        ambientModel?.project(eggs: result.eggs, topicID: result.topicID)
    }
    private static var milliseconds: Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
}

@MainActor private struct PlayExperienceNodeView: View {
    let nodeID: Int
    @Bindable var model: PlayExperienceCoordinator
    let device: PlayDeviceCaptureCoordinator?
    let advanced: PlayAdvancedCoordinator?
    let stillness: PlayStillnessCoordinator?
    let preference: PlayPreferenceCoordinator?
    let journey: JourneyCheckCoordinator?
    let shopNPC: ShopNPCNodeHost?
    let mediaScope: UUID
    var makeAudio: (@MainActor () -> PlatformAudioPlayback)? = nil
    var makeExternalMaps: (@MainActor () -> PlatformExternalMaps)? = nil
    @State private var answer = ""
    @State private var review: PlayCompletionReview?
    @State private var showReview = false
    @State private var showHint = false
    @State private var localIssue: PlayExperienceError?
    private var node: PlayNode? { model.snapshot?.visibleNodes.first { $0.id == nodeID } }
    var body: some View {
        List {
            if let node {
                if let journey { PlayJourneyCheckView(model: journey, nodeDone: node.done == true) }
                Section {
                    Text(verbatim: node.name ?? "#\(node.id)").font(.title2.bold())
                    if let body = node.storyText ?? node.description { Text(verbatim: body) }
                    if let instructions = node.ruleInstructions { Text(verbatim: instructions) }
                    if let question = node.question { Text(verbatim: question).font(.headline) }
                    PlatformChapterAudioHost(selection: PlatformChapterAudioSelection.resolve(snapshot: model.snapshot, nodeID: nodeID, extras: model.extras, currentRead: model.hasCurrentMediaSnapshot), scope: mediaScope, makeModel: makeAudio)
                    if model.hasCurrentMediaSnapshot, model.snapshot?.isLocked(node) == false {
                        if let audio = node.questionAudio, !audio.isEmpty { PlatformAudioHost(rawURL: audio, scope: mediaScope, makeModel: makeAudio) }
                        PlatformExternalMapHost(destination: .init(name: node.name ?? "#\(node.id)", address: node.address, latitude: node.latitude, longitude: node.longitude), scope: mediaScope, makeModel: makeExternalMaps)
                    }
                    if node.questionImage?.isEmpty == false || model.extras[nodeID]?.storyImage?.isEmpty == false { Label("playx.media.image", systemImage: "photo") }
                    if model.snapshot?.isLocked(node) == true { Label("playx.locked", systemImage: "lock") }
                    if model.snapshot?.isDone(node) == true { Label("playx.completed", systemImage: "checkmark.circle") }
                }
                if model.hasCurrentMediaSnapshot, model.snapshot?.isLocked(node) == false, node.npc != nil, let shopNPC {
                    Section {
                        ShopNPCNodeEntrance(name: shopNPC.name, makeCoordinator: shopNPC.makeCoordinator, greeting: shopNPC.greeting)
                            .id(shopNPC.identity)
                    }
                }
                if model.snapshot?.result.mode == 2 {
                    Section("playx.merchant.steps") {
                        stateRow("playx.merchant.scan", done: node.arrived == true)
                        stateRow("playx.merchant.photo", done: node.selfReported == true)
                        stateRow("playx.merchant.verify", done: node.done == true)
                        Text("playx.merchant.notice").font(.footnote)
                        if node.arrived == true, let requirement = node.photoRequirement { Text(verbatim: requirement) }
                    }
                }
                if PlayNodeTask.resolve(mode: model.snapshot?.result.mode, node: node) == .answer {
                    Section("playx.answer") {
                        if let options = node.options, node.validationMethod == 3 {
                            Picker("playx.answer", selection: $answer) {
                                Text("playx.choose").tag("")
                                ForEach(options.keys.sorted(), id: \.self) { key in Text(verbatim: options[key] ?? key).tag(key) }
                            }.accessibilityIdentifier("playx.answer.options")
                        } else { TextField("playx.answer.placeholder", text: $answer, axis: .vertical).accessibilityIdentifier("playx.answer.field") }
                        Button("playx.review") { prepare(.answer(answer)) }.disabled(!model.canWrite || answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("playx.answer.review")
                    }
                }
                if let extra = model.extras[nodeID], extra.hintLocked == true || extra.puzzleScoring == true {
                    Section("playx.hints") {
                        if let cost = extra.hintCost { LabeledContent("playx.hints.cost") { Text(verbatim: String(cost)) } }
                        if let cap = extra.puzzleScoreCap { LabeledContent("playx.hints.cap") { Text(verbatim: String(cap)) } }
                        ForEach(Array(extra.usedHints.enumerated()), id: \.offset) { _, text in Text(verbatim: text) }
                        Button("playx.hints.request") { showHint = true }
                            .disabled(!model.canWrite || (extra.puzzleScoring != true && extra.hintCost == nil))
                            .accessibilityIdentifier("playx.hints.request")
                    }
                }
                if let hint = model.hint { Section("playx.hints") { ForEach(Array(hint.hints.enumerated()), id: \.offset) { _, text in Text(verbatim: text) } } }
                if let preference, node.validationMethod == 6 {
                    NavigationLink("playx.preference.title") { PlayPreferenceView(model: preference) { Task { await model.load() } } }
                }
                if let stillness, node.sensorType == "still" {
                    NavigationLink("playx.stillness") { PlayStillnessStreamView(model: stillness) { prepare(.sensor(type: "still", payload: $0)) } }
                }
                if let advanced, node.hasAdvancedPrerequisite { NavigationLink("playx.advanced") { PlayAdvancedView(model: advanced, device: device, mediaScope: mediaScope, makeAudio: makeAudio) { state in try? model.acceptAdvanced(state) } } }
                if let device { PlayDeviceTaskSection(model: device, task: PlayNodeTask.resolve(mode: model.snapshot?.result.mode, node: node),
                    photoFilter: node.sensorType == "filter_shot" ? PlayPhotoFilter(rawValue: model.extras[nodeID]?.sensorConfig["filterStyle"].text ?? "") : nil,
                    unsupportedPhotoSubtype: node.validationMethod == 2 && node.sensorType?.isEmpty == false && (node.sensorType != "filter_shot" || PlayPhotoFilter(rawValue: model.extras[nodeID]?.sensorConfig["filterStyle"].text ?? "") == nil), onEvidence: prepare) }
                else if PlayNodeTask.resolve(mode: model.snapshot?.result.mode, node: node) != .answer { Text("playx.device.disabled") }
            } else { Text("playx.node.unavailable") }
            if let localIssue { PlayExperienceIssueView(issue: localIssue) }
        }
        .privacySensitive().navigationTitle("playx.task.title")
        .confirmationDialog("playx.review", isPresented: $showReview, titleVisibility: .visible) {
            Button("playx.submit") { if let review { Task { await model.submit(review); self.review = nil } } }.accessibilityIdentifier("playx.confirm")
            Button("playx.cancel", role: .cancel) { model.cancelReview(); review = nil }
        } message: { Text("playx.review.detail") }
        .confirmationDialog("playx.hints.request", isPresented: $showHint, titleVisibility: .visible) {
            Button("playx.hints.confirm") {
                let extra = model.extras[nodeID]
                Task { await model.requestHint(nodeID: nodeID, level: extra?.puzzleScoring == true ? min(2, (extra?.puzzleHintLevel ?? 0) + 1) : nil) }
            }
        } message: { Text("playx.hints.consequence") }
        .onDisappear { device?.cancel(); model.cancelReview(); review = nil; answer = "" }
    }
    private func stateRow(_ key: String, done: Bool) -> some View { Label(LocalizedStringKey(key), systemImage: done ? "checkmark.circle.fill" : "circle") }
    private func prepare(_ evidence: PlayCompletionEvidence) {
        do { review = try model.review(nodeID: nodeID, evidence: evidence); showReview = true; localIssue = nil }
        catch { localIssue = error as? PlayExperienceError ?? .invalidAction }
    }
}

struct PlayExperienceIssueView: View {
    let issue: PlayExperienceError
    var body: some View {
        VStack(alignment: .leading) {
            if case .rejected(let code, let message) = issue {
                Text("playx.rejected").font(.headline)
                Text(verbatim: message ?? String(code))
            } else { Text(LocalizedStringKey(issue == .disabled ? "playx.disabled" : issue == .staleSession ? "playx.session.changed" : issue == .unsupported ? "playx.unsupported" : "playx.error")) }
        }.foregroundStyle(.secondary).accessibilityIdentifier("playx.issue")
    }
}
struct PlayRewardSection: View {
    let reward: PlayWireValue
    var body: some View {
        Section("playx.reward") {
            Text("playx.reward.authority").font(.footnote)
            if let xp = reward["xp"].tolerantInteger ?? reward["score"].tolerantInteger { LabeledContent("playx.reward.xp") { Text(verbatim: String(xp)) } }
            if let score = reward["puzzleScore"].tolerantInteger { LabeledContent("playx.reward.puzzle") { Text(verbatim: String(score)) } }
            if let mode = reward["completionMode"].text { LabeledContent("playx.reward.mode") { Text(verbatim: mode) } }
            if let medal = reward["medalName"].text { Text(verbatim: medal) }
        }.accessibilityIdentifier("playx.reward")
    }
}
@MainActor private struct PlayLeadSection: View {
    @Bindable var model: PlayExperienceCoordinator
    @State private var text = ""
    @State private var action: PlayLeadAction?
    @State private var review = false
    var body: some View {
        Section("playx.lead.title") {
            Button("playx.lead.load") { Task { await model.loadLead() } }.accessibilityIdentifier("playx.lead.load")
            if let lead = model.lead {
                if !lead.exists { Text("playx.lead.notStarted") }
                if let broadcast = lead.broadcast { Text(verbatim: broadcast) }
                if let chapter = lead.chapterName { Text(verbatim: chapter) }
                if let arrived = lead.arrived, !lead.members.isEmpty { LabeledContent("playx.lead.arrived") { Text(verbatim: "\(arrived) / \(lead.members.count)") } }
                ForEach(lead.members) { member in Label(member.name ?? "#\(member.id)", systemImage: member.arrived ? "checkmark.circle" : "circle") }
                if lead.exists && !lead.meArrived { actionButton(.arrive) }
                if lead.isLeader {
                    TextField("playx.lead.text", text: $text, axis: .vertical).accessibilityIdentifier("playx.lead.text")
                    if !lead.exists { actionButton(.start) }
                    else { actionButton(.broadcast); actionButton(.unlockChapter); actionButton(.settle) }
                }
                if model.leaderOutcomeUnknown { Text("playx.lead.unknown") }
            }
        }
        .confirmationDialog("playx.review", isPresented: $review, titleVisibility: .visible) {
            Button("playx.submit") { if let action { Task { await model.performLead(action, text: action == .broadcast ? text : nil) } } }
        } message: { Text(LocalizedStringKey(action == .settle ? "playx.lead.settle.consequence" : "playx.lead.review")) }
    }
    private func actionButton(_ value: PlayLeadAction) -> some View {
        Button(LocalizedStringKey("playx.lead." + value.rawValue)) { action = value; review = true }
            .disabled(!model.canWrite || model.leaderOutcomeUnknown || (value == .unlockChapter && model.lead?.allArrived != true) || (value == .broadcast && text.isEmpty))
            .accessibilityIdentifier("playx.lead." + value.rawValue)
    }
}

struct PlayRuntimePhaseText: View {
    let phase: String
    var body: some View { Text(LocalizedStringKey("playx.phase." + phase)) }
}
