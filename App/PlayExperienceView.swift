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
    var narrativeModel: ((JourneyNarrativeQuery) -> JourneyNarrativeCoordinator?)? = nil
    var narrativeImageReader: (any RetainedPublicImageReading)? = nil
    var shopNPCModel: ((Int) -> ShopNPCNodeHost?)? = nil
    var invalidateShopNPC: (() -> Void)? = nil
    var mediaScope: UUID = UUID()
    var makeAudio: (@MainActor () -> PlatformAudioPlayback)? = nil
    var makeExternalMaps: (@MainActor () -> PlatformExternalMaps)? = nil
    var approvedArtworkHosts: Set<String> = []
    var makeSensorProvider: (@MainActor () -> any PlayKitSensorProviding)? = nil
    var spatialApproval = PlayKitSpatialApproval()
    var rewardCollectionDestination: ((PlayRewardBadgeTarget) -> AnyView)? = nil
    @State private var selectedNode: Int?
    @State private var showRouteMap = false
    @State private var confirmEnd = false
    @State private var presentedMode: PlayGameplayMode?
    @State private var presentationMount = PlayExperiencePresentationMount()
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Group {
            if model.gameplayMode == .freeExploration || (model.snapshot == nil && presentedMode == .freeExploration) {
                FreeExplorationExperienceView(model: model, storeDestination: { AnyView(freeStoreDestination($0)) }, rewardCollectionDestination: rewardCollectionDestination)
            } else if model.gameplayMode == .cityOrientation {
                orientationContent
            } else if model.snapshot == nil {
                VStack(spacing: 12) {
                    if model.phase == .loading { ProgressView("playx.loading").accessibilityIdentifier("playMode.loading") }
                    if let issue = model.issue { PlayExperienceIssueView(issue: issue) }
                    if !model.available { Text("playx.disabled").accessibilityIdentifier("playx.disabled") }
                    Button("playx.refresh") { Task { await model.load() } }
                        .disabled(!model.available || model.phase == .loading || model.phase == .submitting)
                }.padding()
            } else { ContentUnavailableView("playMode.unavailable", systemImage: "questionmark.circle") }
        }
        .privacySensitive().appNavigationTitle(key: model.gameplayMode == .freeExploration ? "playFree.title" : "playx.title")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedNode) { id in nodeDestination(id) }
        .navigationDestination(isPresented: $showRouteMap) {
            PlayRouteMapView(model: model, nodeDestination: { AnyView(nodeDestination($0)) })
        }
        .confirmationDialog("playx.run.end", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("playx.run.end", role: .destructive) { Task { await model.endRun(now: ProcessInfo.processInfo.systemUptime, savedAt: Self.milliseconds) } }
        } message: { Text("playx.run.end.detail") }
        .task(id: PlayExperiencePresentationKey(model: model)) {
            // This task also restarts when returning from a pushed store. Preserve
            // the same owner's mode host through refresh so its open card pack survives.
            if presentationMount.enter(model) { selectedNode = nil; presentedMode = nil }
            await model.load()
        }
        .onChange(of: model.gameplayMode) { _, mode in
            let previous = presentedMode
            if let mode { presentedMode = mode }
            if mode == .cityOrientation, previous != .cityOrientation {
                Task { await model.restoreRun(); projectAmbient() }
            }
            if let mode, mode != .cityOrientation { selectedNode = nil; confirmEnd = false }
        }
        .onChange(of: model.gameplayMode) { _, mode in
            if let mode, mode != .cityOrientation { showRouteMap = false }
        }
        .onChange(of: PlayExperiencePresentationKey(model: model)) { _, _ in showRouteMap = false }
        .onChange(of: model.snapshot?.result) { _, _ in if model.gameplayMode == .cityOrientation { projectAmbient() } }
        .onChange(of: model.snapshot) { _, _ in invalidateShopNPC?() }
        .onChange(of: model.hasCurrentMediaSnapshot) { _, current in if !current { invalidateShopNPC?() } }
        .onChange(of: scenePhase) { _, next in
            if model.gameplayMode == .cityOrientation, next != .active, model.clock.phase == .running {
                Task { await model.pauseRun(now: ProcessInfo.processInfo.systemUptime, savedAt: Self.milliseconds) }
            }
        }
    }
    private var orientationContent: some View {
        List {
            Section {
                Label("playx.title", systemImage: "figure.walk")
                    .font(.title2.bold()).accessibilityAddTraits(.isHeader)
                if let snapshot = model.snapshot {
                    PlayTaskSummaryView(snapshot: snapshot, phase: model.phase.rawValue)
                    if let note = snapshot.result.timeNote { Text(verbatim: note).foregroundStyle(.secondary) }
                }
                if !model.available { Text("playx.disabled").accessibilityIdentifier("playx.disabled") }
                if model.phase == .loading { ProgressView("playx.loading") }
                if let issue = model.issue { PlayExperienceIssueView(issue: issue) }
                Button("playx.refresh", systemImage: "arrow.clockwise") { Task { await model.load() } }
                    .disabled(model.phase == .submitting || !model.available).accessibilityIdentifier("playx.refresh")
            }
            if model.hasCurrentMediaSnapshot, !model.unresolved, let snapshot = model.snapshot,
               let id = PlayTaskSummaryPresentation(snapshot: snapshot).currentNodeID,
               let node = snapshot.visibleNodes.first(where: { $0.id == id }) {
                Section("referenceTask.current") {
                    Text(verbatim: node.name ?? "#\(node.id)").font(.headline).fixedSize(horizontal: false, vertical: true)
                    Text(LocalizedStringKey("playx.task." + PlayNodeTask.resolve(mode: snapshot.result.mode, node: node).rawValue))
                    PlayTaskStatusBadge(node: node, snapshot: snapshot)
                    Button("referenceTask.open") { selectedNode = id }
                        .buttonStyle(.borderedProminent).accessibilityIdentifier("referenceTask.open")
                }
            }
            if !model.unresolved, model.interactionContext != nil, let snapshot = model.snapshot,
               PlayRouteMapPresentation(snapshot: snapshot) != nil {
                Section {
                    Button("playRoute.open", systemImage: "map") { showRouteMap = true }
                        .accessibilityIdentifier("playRoute.open")
                    Text("playRoute.entryHint").font(.footnote).foregroundStyle(.secondary)
                }
            }
            if model.unresolved {
                Section("playx.unknown.title") {
                    Text(LocalizedStringKey(model.hasModeRecoveryBlock ? "playMode.recoveryBlocked" : "playx.unknown.body"))
                    Button("playx.reconcile") { Task { await model.load() } }.accessibilityIdentifier("playx.reconcile")
                    if model.canRetryExactBranch {
                        Button("playx.retryExact") { Task { await model.retryExactBranchAfterReadback() } }
                            .accessibilityIdentifier("playx.retryExact")
                    }
                }
            }
            if let ambientModel { PlayAmbientView(model: ambientModel) }
            if model.snapshot != nil {
                if let snapshot = model.snapshot, model.hasCurrentMediaSnapshot {
                    Section("journey.record.title") {
                        narrativeLink(.casebook); narrativeLink(.backpack)
                        ForEach(snapshot.result.chapters) { chapter in
                            let nodes = snapshot.visibleNodes.filter { $0.chapterID == chapter.id }
                            if !nodes.isEmpty, nodes.allSatisfy({ snapshot.isDone($0) && !snapshot.isLocked($0) }) {
                                narrativeLink(.stage(chapterID: chapter.id), subtitle: chapter.name)
                            }
                        }
                        if snapshot.availability == .completed { narrativeLink(.ending) }
                    }
                }
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
                }.disabled(!model.canManageRun)
                if let snapshot = model.snapshot, model.hasCurrentMediaSnapshot {
                    Section("chapterStory.title") {
                        ForEach(snapshot.result.chapters) { chapter in
                            if let node = snapshot.visibleNodes.first(where: { $0.chapterID == chapter.id && !snapshot.isLocked($0) }),
                               model.chapterStories[chapter.id] != nil {
                                NavigationLink {
                                    ChapterStoryView(chapterID: chapter.id, nodeID: node.id, model: model,
                                        advancedModel: advancedModel, journeyModel: journeyModel, deviceModel: deviceModel, mediaScope: mediaScope,
                                        makeAudio: makeAudio, approvedArtworkHosts: approvedArtworkHosts, makeSensorProvider: makeSensorProvider, spatialApproval: spatialApproval, nodeDestination: { AnyView(nodeDestination($0)) })
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
                                if let snapshot = model.snapshot { PlayTaskStatusBadge(node: node, snapshot: snapshot) }
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
                            .accessibilityIdentifier("playx.os.open")
                    }
                    if PrefabPreviewState.isPrefabTopic(name: model.snapshot?.result.topicName), let prefabModel {
                        NavigationLink("playx.prefab.title") { PlayPrefabRuntimeView(model: prefabModel) }
                    }
                    if let playerModel { NavigationLink("playx.player.title") { PlayPlayerSessionView(model: playerModel, deviceModel: deviceModel) } }
                    if let circleModel { NavigationLink("playx.circle.title") { PlayCircleView(model: circleModel) } }
                }
                if let reward = model.reward { PlayRewardSection(reward: reward, collectionDestination: rewardCollectionDestination) }
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
        .accessibilityIdentifier("playx.overview")
    }
    @ViewBuilder private func freeStoreDestination(_ id: Int) -> some View {
        if model.gameplayMode == .freeExploration {
            FreeExplorationStoreView(nodeID: id, model: model, device: deviceModel?(id), shopNPC: shopNPCModel?(id), mediaScope: mediaScope,
                makeExternalMaps: makeExternalMaps, storyDestination: { node in
                    guard model.hasCurrentMediaSnapshot, let chapterID = node.chapterID,
                          model.chapterStories[chapterID] != nil else { return nil }
                    return AnyView(ChapterStoryView(chapterID: chapterID, nodeID: node.id, model: model,
                        mediaScope: mediaScope, makeAudio: makeAudio, approvedArtworkHosts: approvedArtworkHosts,
                        nodeDestination: { AnyView(freeStoreDestination($0)) }))
                })
        } else { Text("playMode.unavailable") }
    }
    @ViewBuilder private func narrativeLink(_ query: JourneyNarrativeQuery, subtitle: String? = nil) -> some View {
        if let narrative = narrativeModel?(query) {
            NavigationLink {
                JourneyNarrativeView(model: narrative, imageReader: narrativeImageReader, makeAudio: makeAudio, mediaScope: mediaScope)
            } label: {
                VStack(alignment: .leading) { Text(LocalizedStringKey(query.titleKey)); if let subtitle { Text(verbatim: subtitle).font(.caption) } }
            }.accessibilityIdentifier("journey.record.open." + query.key)
        }
    }
    @ViewBuilder private func nodeDestination(_ id: Int) -> some View {
        if model.gameplayMode == .cityOrientation {
        let configuration = try? PlayStillnessConfiguration(raw: model.extras[id]?.sensorConfig ?? .null)
        PlayExperienceNodeView(nodeID: id, model: model, device: deviceModel?(id), advanced: advancedModel.flatMap { $0(id) },
            stillness: configuration.flatMap { configuration in motionModel.flatMap { $0(id, configuration) } },
            preference: preferenceModel.flatMap { $0(id) }, journey: journeyModel.flatMap { $0(id) }, narrative: narrativeModel?(.questions(nodeID: id)), shopNPC: shopNPCModel?(id),
            mediaScope: mediaScope, makeAudio: makeAudio, makeExternalMaps: makeExternalMaps, approvedArtworkHosts: approvedArtworkHosts, makeSensorProvider: makeSensorProvider, spatialApproval: spatialApproval)
        } else { Text("playMode.unavailable") }
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
    let narrative: JourneyNarrativeCoordinator?
    let shopNPC: ShopNPCNodeHost?
    let mediaScope: UUID
    var makeAudio: (@MainActor () -> PlatformAudioPlayback)? = nil
    var makeExternalMaps: (@MainActor () -> PlatformExternalMaps)? = nil
    var approvedArtworkHosts: Set<String> = []
    var makeSensorProvider: (@MainActor () -> any PlayKitSensorProviding)? = nil
    var spatialApproval = PlayKitSpatialApproval()
    @State private var answer = ""
    @State private var review: PlayCompletionReview?
    @State private var showReview = false
    @State private var showHint = false
    @State private var hintContext: PlayInteractionContext?
    @State private var hintLevel: Int?
    @State private var localIssue: PlayExperienceError?
    private var node: PlayNode? { model.snapshot?.visibleNodes.first { $0.id == nodeID } }
    var body: some View {
        let context = model.interactionContext
        List {
            if let node {
                if let journey { PlayJourneyCheckView(model: journey, nodeDone: node.done == true) }
                if let narrative, model.hasCurrentMediaSnapshot, model.snapshot?.isLocked(node) == false {
                    NavigationLink("journey.record.questions") {
                        JourneyNarrativeView(model: narrative, onChanged: { await model.load() })
                    }.accessibilityIdentifier("journey.record.open.questions.\(nodeID)")
                }
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
                    if let snapshot = model.snapshot { PlayTaskStatusBadge(node: node, snapshot: snapshot) }
                }
                if model.hasCurrentMediaSnapshot, model.snapshot?.isLocked(node) == false, node.npc != nil, let shopNPC {
                    Section {
                        ShopNPCNodeEntrance(name: shopNPC.name, makeCoordinator: shopNPC.makeCoordinator, greeting: shopNPC.greeting,
                            makeScriptedGuide: { scope in ShopNPCScriptedGuideSource(runtime: model, nodeID: nodeID, conversation: scope) })
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
                        Button("playx.review") { prepare(.answer(answer), context: context) }.disabled(!model.canWrite || answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("playx.answer.review")
                    }
                }
                if let extra = model.extras[nodeID], extra.hintLocked == true || extra.puzzleScoring == true {
                    Section("playx.hints") {
                        if let cost = extra.hintCost { LabeledContent("playx.hints.cost") { Text(verbatim: String(cost)) } }
                        if let cap = extra.puzzleScoreCap { LabeledContent("playx.hints.cap") { Text(verbatim: String(cap)) } }
                        ForEach(Array(extra.usedHints.enumerated()), id: \.offset) { _, text in Text(verbatim: text) }
                        Button("playx.hints.request") {
                            hintContext = context
                            hintLevel = extra.puzzleScoring == true ? min(2, (extra.puzzleHintLevel ?? 0) + 1) : nil
                            showHint = true
                        }
                            .disabled(!model.canWrite || (extra.puzzleScoring != true && extra.hintCost == nil))
                            .accessibilityIdentifier("playx.hints.request")
                    }
                }
                if let hint = model.hint { Section("playx.hints") { ForEach(Array(hint.hints.enumerated()), id: \.offset) { _, text in Text(verbatim: text) } } }
                if let preference, node.validationMethod == 6 {
                    NavigationLink("playx.preference.title") { PlayPreferenceView(model: preference) { Task { await model.load() } } }
                        .accessibilityIdentifier("playx.preference.open")
                }
                if let stillness, node.sensorType == "still" {
                    NavigationLink("playx.stillness") {
                        PlayInteractionBoundContent(context: model.interactionContext) { issuedContext in
                            PlayStillnessStreamView(model: stillness) { prepare(.sensor(type: "still", payload: $0), context: issuedContext) }
                        }
                    }
                }
                if let advanced, node.hasAdvancedPrerequisite {
                    NavigationLink("playx.advanced") {
                        PlayInteractionBoundContent(context: model.interactionContext) { advancedContext in
                            PlayAdvancedView(model: advanced, device: device, mediaScope: mediaScope, makeAudio: makeAudio, approvedArtworkHosts: approvedArtworkHosts, makeSensorProvider: makeSensorProvider, spatialApproval: spatialApproval) { state in
                                try? model.acceptAdvanced(state, context: advancedContext)
                            }
                        }
                    }
                }
                if let device { PlayDeviceTaskSection(model: device, task: PlayNodeTask.resolve(mode: model.snapshot?.result.mode, node: node),
                    photoFilter: node.sensorType == "filter_shot" ? PlayPhotoFilter(rawValue: model.extras[nodeID]?.sensorConfig["filterStyle"].text ?? "") : nil,
                    unsupportedPhotoSubtype: node.validationMethod == 2 && node.sensorType?.isEmpty == false && (node.sensorType != "filter_shot" || PlayPhotoFilter(rawValue: model.extras[nodeID]?.sensorConfig["filterStyle"].text ?? "") == nil), interaction: .init(context: context, current: { model.interactionContext }), onEvidence: { prepare($0, context: $1) }) }
                else if PlayNodeTask.resolve(mode: model.snapshot?.result.mode, node: node) != .answer { Text("playx.device.disabled") }
            } else { Text("playx.node.unavailable") }
            if let localIssue { PlayExperienceIssueView(issue: localIssue) }
        }
        .privacySensitive().navigationTitle("playx.task.title")
        .modifier(JourneyCheckReviewPresentation(model: journey))
        // The optional check initially renders no rows, so its probe belongs to this stable host.
        .task(id: [model.identity, node.map { String($0.id) }, (model.snapshot?.route?.sessionID).map(String.init), (model.snapshot?.route?.version).map(String.init)]) {
            if let node {
                await journey?.probe(nodeDone: node.done == true)
                guard !Task.isCancelled, self.node?.id == node.id, model.hasCurrentMediaSnapshot else { journey?.roleContent.close(); return }
                await journey?.roleContent.load(expectedRunID: model.snapshot?.route?.sessionID, minimumStateVersion: model.snapshot?.route?.version)
            } else { journey?.roleContent.close() }
        }
        .onChange(of: node?.done) { _, _ in
            if let node { journey?.updateNodeDone(node.done == true) }
        }
        .confirmationDialog("playx.review", isPresented: $showReview, titleVisibility: .visible) {
            Button("playx.submit") {
                guard let review else { return }
                self.review = nil // Consume before adaptive dismissal, which otherwise means cancellation.
                Task { await model.submit(review) }
            }.accessibilityIdentifier("playx.confirm")
            Button("playx.cancel", role: .cancel) { model.cancelReview(); review = nil }
        } message: { Text("playx.review.detail") }
        .onChange(of: showReview) { _, visible in
            // A popover's outside-tap dismissal has no visible Cancel button.
            if !visible, review != nil { model.cancelReview(); review = nil }
        }
        .confirmationDialog("playx.hints.request", isPresented: $showHint, titleVisibility: .visible) {
            Button("playx.hints.confirm") {
                let context = hintContext, level = hintLevel
                hintContext = nil
                Task { await model.requestHint(nodeID: nodeID, level: level, context: context) }
            }
        } message: { Text("playx.hints.consequence") }
        .onDisappear { journey?.roleContent.close(); device?.cancel(); model.cancelReview(); review = nil; hintContext = nil; answer = "" }
    }
    private func stateRow(_ key: String, done: Bool) -> some View { Label(LocalizedStringKey(key), systemImage: done ? "checkmark.circle.fill" : "circle") }
    private func prepare(_ evidence: PlayCompletionEvidence, context: PlayInteractionContext?) {
        do { review = try model.review(nodeID: nodeID, evidence: evidence, context: context); showReview = true; localIssue = nil }
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
@MainActor struct PlayRewardSection: View {
    let reward: PlayWireValue
    var collectionDestination: ((PlayRewardBadgeTarget) -> AnyView)? = nil
    var body: some View {
        Section("playx.reward") {
            Text("playx.reward.authority").font(.footnote)
            if let xp = reward["xp"].tolerantInteger ?? reward["score"].tolerantInteger { LabeledContent("playx.reward.xp") { Text(verbatim: String(xp)) } }
            if let score = reward["puzzleScore"].tolerantInteger { LabeledContent("playx.reward.puzzle") { Text(verbatim: String(score)) } }
            if let mode = reward["completionMode"].text { LabeledContent("playx.reward.mode") { Text(verbatim: mode) } }
            if let medal = reward["medalName"].text { Text(verbatim: medal) }
            PlayRewardBadgeRows(targets: PlayRewardBadgeTarget.targets(in: reward), destination: collectionDestination)
                .id(PlayRewardBadgeTarget.targets(in: reward))
        }.accessibilityIdentifier("playx.reward")
    }
}
@MainActor private struct PlayLeadSection: View {
    @Bindable var model: PlayExperienceCoordinator
    @State private var text = ""
    @State private var action: PlayLeadAction?
    @State private var review = false
    @State private var actionContext: PlayInteractionContext?
    var body: some View {
        let context = model.interactionContext
        Section("playx.lead.title") {
            Button("playx.lead.load") { Task { await model.loadLead(context: context) } }.accessibilityIdentifier("playx.lead.load")
            if let lead = model.lead {
                if !lead.exists { Text("playx.lead.notStarted") }
                if let broadcast = lead.broadcast { Text(verbatim: broadcast) }
                if let chapter = lead.chapterName { Text(verbatim: chapter) }
                if let arrived = lead.arrived, !lead.members.isEmpty { LabeledContent("playx.lead.arrived") { Text(verbatim: "\(arrived) / \(lead.members.count)") } }
                ForEach(lead.members) { member in Label(member.name ?? "#\(member.id)", systemImage: member.arrived ? "checkmark.circle" : "circle") }
                if lead.exists && !lead.meArrived { actionButton(context: context, .arrive) }
                if lead.isLeader {
                    TextField("playx.lead.text", text: $text, axis: .vertical).accessibilityIdentifier("playx.lead.text")
                    if !lead.exists { actionButton(context: context, .start) }
                    else { actionButton(context: context, .broadcast); actionButton(context: context, .unlockChapter); actionButton(context: context, .settle) }
                }
                if model.leaderOutcomeUnknown { Text("playx.lead.unknown") }
            }
        }
        .confirmationDialog("playx.review", isPresented: $review, titleVisibility: .visible) {
            Button("playx.submit") {
                if let action {
                    let context = actionContext, message = action == .broadcast ? text : nil
                    actionContext = nil
                    Task { await model.performLead(action, text: message, context: context) }
                }
            }
        } message: { Text(LocalizedStringKey(action == .settle ? "playx.lead.settle.consequence" : "playx.lead.review")) }
    }
    private func actionButton(context: PlayInteractionContext?, _ value: PlayLeadAction) -> some View {
        Button(LocalizedStringKey("playx.lead." + value.rawValue)) { action = value; actionContext = context; review = true }
            .disabled(!model.canWrite || model.leaderOutcomeUnknown || (value == .unlockChapter && model.lead?.allArrived != true) || (value == .broadcast && text.isEmpty))
            .accessibilityIdentifier("playx.lead." + value.rawValue)
    }
}

struct PlayRuntimePhaseText: View {
    let phase: String
    var body: some View { Text(LocalizedStringKey("playx.phase." + phase)) }
}

/// Freeze authority when this interaction is mounted. A redraw must not bind
/// an old child operation to a newly loaded mode or request generation.
@MainActor struct PlayInteractionBoundContent<Content: View>: View {
    @State private var context: PlayInteractionContext?
    private let currentContext: PlayInteractionContext?
    private let content: (PlayInteractionContext?) -> Content
    init(context: PlayInteractionContext?, @ViewBuilder content: @escaping (PlayInteractionContext?) -> Content) {
        _context = State(initialValue: context); currentContext = context; self.content = content
    }
    @ViewBuilder var body: some View {
        if context != nil, context == currentContext { content(context) }
        else { Text("playMode.unavailable") }
    }
}

/// Session AND coordinator identity delimit one visible runtime. Retaining the previous
/// coordinator prevents pointer reuse from making a replacement look like the old owner.
struct PlayExperiencePresentationKey: Hashable {
    let coordinator: ObjectIdentifier
    let session: String?
    @MainActor init(model: PlayExperienceCoordinator) { coordinator = ObjectIdentifier(model); session = model.identity }
}
@MainActor final class PlayExperiencePresentationMount {
    private var model: PlayExperienceCoordinator?
    private var session: String?
    func enter(_ next: PlayExperienceCoordinator) -> Bool {
        guard model !== next || session != next.identity else { return false }
        model = next; session = next.identity; return true
    }
}
