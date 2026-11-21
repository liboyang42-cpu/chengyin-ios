import SwiftUI
import UIKit

/// A chapter belongs to the live play session. Native scrolling, type scaling and Back
/// replace source animation chrome; gameplay stays embedded when the server says inline.
@MainActor struct ChapterStoryView: View {
    let chapterID: Int
    let nodeID: Int
    @Bindable var model: PlayExperienceCoordinator
    var advancedModel: ((Int) -> PlayAdvancedCoordinator?)? = nil
    var journeyModel: ((Int) -> JourneyCheckCoordinator?)? = nil
    var deviceModel: ((Int) -> PlayDeviceCaptureCoordinator)? = nil
    var mediaScope: UUID = UUID()
    var makeAudio: (@MainActor () -> PlatformAudioPlayback)? = nil
    var approvedArtworkHosts: Set<String> = []
    var makeSensorProvider: (@MainActor () -> any PlayKitSensorProviding)? = nil
    var spatialApproval = PlayKitSpatialApproval()
    var imageReader: (any RetainedPublicImageReading)? = nil
    let nodeDestination: (Int) -> AnyView
    @State private var advancedVariables: [String: PlayWireValue] = [:]
    @State private var dirtyNodes = Set<Int>()
    @State private var confirmLeave = false
    @State private var activeInlineNodeID: Int?
    @State private var audioURL: String?
    @State private var castCard: CastCardTarget?
    /// Leading reading-column margin that holds speaker names (≈26pt each side in the spec).
    @ScaledMetric(relativeTo: .caption2) private var nameMargin: CGFloat = 52
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale
    private var chapter: ChapterStoryDocument? { model.chapterStories[chapterID] }
    private var visible: Bool {
        guard model.hasCurrentMediaSnapshot, let snapshot = model.snapshot,
              snapshot.availability == .active || snapshot.availability == .completed,
              let node = snapshot.visibleNodes.first(where: { $0.id == nodeID && $0.chapterID == chapterID }) else { return false }
        return !snapshot.isLocked(node)
    }
    private var segments: [ChapterStorySegment] {
        guard visible, let chapter, let snapshot = model.snapshot else { return [] }
        return ChapterStoryProjection.segments(chapter: chapter, snapshot: snapshot,
            variables: model.storyVariables.merging(advancedVariables) { _, new in new },
            thoughts: model.storyThoughts, storyVoices: model.storyVoices, activeInlineNodeID: activeInlineNodeID,
            cast: castContext)
    }
    private var castContext: CastStoryContext? {
        model.castConfig.map { CastStoryContext(config: $0, profile: model.castProfile, picks: model.castStoryPicks) }
    }
    /// Once any paragraph carries a margin name, every paragraph shares the same column.
    private var usesNameMargin: Bool {
        segments.contains { if case .line(let line) = $0.content { return line.speaker != nil }; return false }
    }
    private var reachedChapters: Set<Int> {
        guard let snapshot = model.snapshot else { return [] }
        return Set(snapshot.visibleNodes.filter { !snapshot.isLocked($0) }.compactMap { $0.chapterID })
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if visible, let chapter {
                    if let title = chapter.title { Text(verbatim: title).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader) }
                    if segments.isEmpty { ContentUnavailableView("chapterStory.empty", systemImage: "book.closed") }
                    ForEach(segments) { segment in
                        segmentBody(segment).frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("chapterStory.segment." + segment.id)
                    }
                    if model.thoughtSyncPhase == .syncing { ProgressView("chapterStory.thought.syncing") }
                    if model.thoughtSyncPhase == .disabled { Text("chapterStory.thought.disabled").font(.footnote).foregroundStyle(.secondary) }
                    if model.thoughtSyncPhase == .needsReadback {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("chapterStory.thought.readback")
                            Button("playx.refresh") { Task { await model.load() } }
                        }.accessibilityIdentifier("chapterStory.thought.readback")
                    }
                    audioSelection
                    if audioURL != nil { PlatformAudioHost(rawURL: audioURL, scope: mediaScope, makeModel: makeAudio) }
                    Text("chapterStory.end").font(.footnote).foregroundStyle(.secondary)
                    Button("chapterStory.return") { leave() }.buttonStyle(.borderedProminent)
                } else {
                    ContentUnavailableView("chapterStory.unavailable", systemImage: "lock", description: Text("chapterStory.unavailable.detail"))
                }
            }.padding().frame(maxWidth: 720).frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("chapterStory.title").navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(!dirtyNodes.isEmpty)
        .toolbar {
            if !dirtyNodes.isEmpty {
                ToolbarItem(placement: .topBarLeading) { Button("chapterStory.back", systemImage: "chevron.left") { leave() } }
            }
        }
        .environment(\.questifyCast, castContext)
        .sheet(item: $castCard) { target in
            if let member = model.castConfig?.member(target.castID) {
                CastCharacterCard(member: member, trust: model.castTrust[member.id], reachedChapters: reachedChapters,
                    line: target.line, chapterID: chapterID, model: model, mediaScope: mediaScope, makeAudio: makeAudio, imageReader: imageReader)
            }
        }
        .privacySensitive().accessibilityIdentifier("chapterStory.body")
        .interactiveDismissDisabled(!dirtyNodes.isEmpty)
        .confirmationDialog("chapterStory.discardQuestion", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("chapterStory.discard", role: .destructive) { dirtyNodes = []; dismiss() }
            Button("chapterStory.keepEditing", role: .cancel) {}
        } message: { Text("chapterStory.discardBody") }
        .task(id: "\(model.identity ?? ""):chapter=\(chapterID)") { if visible { await model.claimVisibleThoughts(chapterID: chapterID) } }
        .onChange(of: model.snapshot) { _, _ in if visible { Task { await model.claimVisibleThoughts(chapterID: chapterID) } } }
        .onChange(of: model.storyVariables) { _, next in advancedVariables.merge(next) { _, new in new } }
        .onChange(of: model.identity) { _, _ in advancedVariables = [:]; dirtyNodes = []; activeInlineNodeID = nil; audioURL = nil; castCard = nil }
        .onChange(of: scenePhase) { _, phase in if phase != .active { audioURL = nil } }
        .onDisappear { audioURL = nil; advancedVariables = [:]; dirtyNodes = [] }
    }
    @ViewBuilder private func segmentBody(_ segment: ChapterStorySegment) -> some View {
        switch segment.content {
        case .text(let text):
            Text(verbatim: text).font(.body).lineSpacing(8).textSelection(.enabled)
                .padding(.leading, usesNameMargin ? nameMargin : 0)
        case .line(let line):
            VStack(spacing: 6) {
                ChapterStoryLineView(name: speakerName(line.speaker), text: line.text, margin: nameMargin,
                    onTapName: castID(line.speaker).map { id -> () -> Void in { castCard = CastCardTarget(castID: id, line: line) } })
                // D1: a line with the author's own recording gets a small centred control.
                if line.audioURL != nil {
                    CastVoiceButton(line: line, member: model.castConfig?.member(castID(line.speaker)), chapterID: chapterID,
                        model: model, mediaScope: mediaScope, makeAudio: makeAudio, compact: true)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                // E3: after a story-branch pick, the characters whose trust it moved remember it.
                ForEach(line.rememberedBy.compactMap { model.castConfig?.member($0) }) { member in
                    Text("cast.branch.remembers \(member.name)").font(.caption).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .accessibilityIdentifier("chapterStory.remembers")
                }
            }
        case .choice(let choice):
            ChapterStoryChoiceView(choice: choice, margin: usesNameMargin ? nameMargin : 0) { index in
                Task { await model.pickStoryBranch(choice, optionIndex: index) }
            }
        case .image(let url): ChapterStoryArtwork(url: url, reader: imageReader)
        case .audio(let url): Button("chapterStory.listen", systemImage: "speaker.wave.2") { audioURL = url }
        case .voice(let speaker, let text):
            VStack(alignment: .leading, spacing: 8) {
                if !speaker.isEmpty { Text(verbatim: speaker).font(.caption.weight(.semibold)) }
                Text(verbatim: text).font(.body).italic()
            }.padding().background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
        case .reveal(let speaker, let lines):
            DisclosureGroup {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in Text(verbatim: line).padding(.vertical, 4) }
            } label: {
                if speaker.isEmpty { Label("chapterStory.reveal", systemImage: "text.bubble") }
                else { Text(verbatim: speaker) }
            }
        case .dream(let title, let images):
            VStack(alignment: .leading, spacing: 12) {
                if let title { Text(verbatim: title).font(.headline) }
                ForEach(Array(images.enumerated()), id: \.offset) { _, item in
                    ChapterStoryArtwork(url: item.url, reader: imageReader)
                    if let line = item.line, !line.isEmpty { Text(verbatim: line).font(.subheadline) }
                }
            }
        case .optionalReading(let subtitle, let paragraphs):
            ChapterOptionalReadingCard(id: segment.id, subtitle: subtitle, paragraphs: paragraphs)
        case .thought(let name, let description):
            VStack(alignment: .leading, spacing: 8) {
                Label { Text(verbatim: name).font(.headline) } icon: { Image(systemName: "lightbulb") }
                if let description { Text(verbatim: description) }
            }.padding().background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
        case .game(let id):
            if let journey = journeyModel?(id) {
                JourneyRoleViewInlineHost(model: journey.roleContent, sessionIdentity: model.identity,
                    runID: model.snapshot?.route?.sessionID, stateVersion: model.snapshot?.route?.version)
            }
            if let node = model.snapshot?.visibleNodes.first(where: { $0.id == id }),
               node.hasAdvancedPrerequisite, let advanced = advancedModel?(id) {
                PlayInteractionBoundContent(context: model.interactionContext) { advancedContext in
                ChapterStoryGameHost(advanced: advanced, device: deviceModel?(id), mediaScope: mediaScope,
                    makeAudio: makeAudio, approvedArtworkHosts: approvedArtworkHosts, makeSensorProvider: makeSensorProvider, spatialApproval: spatialApproval, fallback: { nodeDestination(id) },
                    variables: { advancedVariables.merge($0) { _, new in new } },
                    ready: { try? model.acceptAdvanced($0, context: advancedContext) },
                    inline: { activeInlineNodeID = id },
                    dirty: { value in if value { dirtyNodes.insert(id) } else { dirtyNodes.remove(id) } })
                }.id(id)
            } else {
                NavigationLink { nodeDestination(id) } label: { Label("chapterStory.play", systemImage: "play.circle") }
            }
        }
    }
    @ViewBuilder private var audioSelection: some View {
        if let selection = PlatformChapterAudioSelection.resolve(snapshot: model.snapshot, nodeID: nodeID, extras: model.extras, currentRead: visible) {
            VStack(alignment: .leading, spacing: 12) {
                if let url = selection.narrationURL { Button("chapterStory.narration", systemImage: "headphones") { audioURL = url } }
                if let url = selection.guideURL { Button("chapterStory.guide", systemImage: "location.circle") { audioURL = url } }
            }
        }
    }
    private func castID(_ speaker: ChapterStoryLine.Speaker?) -> String? {
        if case .cast(let id) = speaker { return id }; return nil
    }
    private func speakerName(_ speaker: ChapterStoryLine.Speaker?) -> String? {
        switch speaker {
        case .cast(let id): return model.castConfig?.member(id)?.name
        case .player: return model.castProfile?.name ?? appLocalized("cast.player.you", locale: locale)
        case .named(let name): return name
        case nil: return nil
        }
    }
    private func leave() { if dirtyNodes.isEmpty { dismiss() } else { confirmLeave = true } }
}

/// E3 story branch: the question, then 1–3 numbered choices inside the reading column,
/// separated by hairlines. Not a pop-up and not a card.
private struct ChapterStoryChoiceView: View {
    let choice: ChapterStoryChoice
    let margin: CGFloat
    let pick: (Int) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let question = choice.question { Text(verbatim: question).font(.body).lineSpacing(8) }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(choice.options.enumerated()), id: \.offset) { index, option in
                    if index > 0 { Divider() }
                    Button { pick(index) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(verbatim: "\(index + 1).").font(.system(size: 16).monospacedDigit()).foregroundStyle(.secondary)
                            Text(verbatim: option.text).font(.system(size: 16)).multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 12).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: option.text))
                    .accessibilityIdentifier("chapterStory.choice.\(index + 1)")
                }
            }
        }
        .padding(.leading, margin)
        .accessibilityIdentifier("chapterStory.choice")
    }
}

private struct CastCardTarget: Identifiable {
    let castID: String
    let line: ChapterStoryLine?
    var id: String { castID + ":" + (line?.blockKey ?? line?.text ?? "") }
}

@MainActor private struct ChapterStoryGameHost: View {
    @Bindable var advanced: PlayAdvancedCoordinator
    @Environment(\.questifyCast) private var cast
    let device: PlayDeviceCaptureCoordinator?
    let mediaScope: UUID
    let makeAudio: (@MainActor () -> PlatformAudioPlayback)?
    var approvedArtworkHosts: Set<String> = []
    var makeSensorProvider: (@MainActor () -> any PlayKitSensorProviding)? = nil
    var spatialApproval = PlayKitSpatialApproval()
    let fallback: () -> AnyView
    let variables: ([String: PlayWireValue]) -> Void
    let ready: (PlayAdvancedState) -> Void
    let inline: () -> Void
    let dirty: (Bool) -> Void
    @State private var selection = ChapterInlineKitSelection()
    @State private var hasDraft = false
    @State private var requestedKind: PlayKitScreenKind?
    @State private var confirmSwitch = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let state = advanced.state, advanced.isCurrent {
                if state.inline, let kind = selection.selected ?? ChapterInlineKitSelection.preferred(in: state) {
                    kindNavigation(state, current: kind)
                    PlayKitInlineHost(model: advanced, kind: kind, device: device, mediaScope: mediaScope,
                        makeAudio: makeAudio, approvedArtworkHosts: approvedArtworkHosts, reportDirty: { value in
                            // A disappearing previous form must not clear a newer form's draft flag.
                            guard selection.sessionID == state.sessionID, selection.selected == kind else { return }
                            hasDraft = value; dirty(value)
                        }, makeSensorProvider: makeSensorProvider, spatialApproval: spatialApproval)
                        .id("\(state.sessionID):\(kind.rawValue)")
                } else {
                    if state.inline && !state.isMultiplayer && state.config["leaderboard"]["enabled"].bool != true {
                        ContentUnavailableView("playkit.unavailable", systemImage: "rectangle.slash")
                    }
                    NavigationLink { fallback() } label: { Label("chapterStory.play", systemImage: "play.circle") }
                }
                if state.inline && (state.isMultiplayer || state.config["leaderboard"]["enabled"].bool == true) {
                    PlayAdvancedInlineTeamHost(model: advanced)
                }
                // Cast v1: a station choice that moved trust (`trustChanged`, action response only).
                if let cast {
                    ForEach(state.trustChanged.compactMap { cast.config.member($0) }) { member in
                        Text("cast.branch.remembers \(member.name)").font(.caption).foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .accessibilityIdentifier("chapterStory.station.remembers")
                    }
                }
            } else if advanced.phase == "loading" { ProgressView("chapterStory.loadingGame") }
            else {
                if let issue = advanced.issue { PlayExperienceIssueView(issue: issue) }
                Button("chapterStory.loadGame") { Task { await advanced.start() } }
            }
        }
        .task { await advanced.start(); publish() }
        .onChange(of: advanced.state) { _, _ in publish() }
        .confirmationDialog("chapterStory.switchQuestion", isPresented: $confirmSwitch, titleVisibility: .visible) {
            Button("chapterStory.switchDiscard", role: .destructive) {
                if let requestedKind { switchKind(requestedKind) }
                requestedKind = nil
            }
            Button("chapterStory.keepEditing", role: .cancel) { requestedKind = nil }
        } message: { Text("chapterStory.switchBody") }
        .onDisappear { device?.cancel(); dirty(false) }
    }
    @ViewBuilder private func kindNavigation(_ state: PlayAdvancedState, current: PlayKitScreenKind) -> some View {
        let kinds = PlayKitScreenKind.present(in: state)
        if !kinds.isEmpty && (kinds.count > 1 || !kinds.contains(current)) {
            Menu {
                ForEach(kinds) { kind in
                    Button { requestKind(kind) } label: {
                        Label(LocalizedStringKey("playkit.kind." + kind.rawValue), systemImage: kind == current ? "circle.inset.filled" : ChapterInlineKitSelection.complete(kind, in: state) ? "checkmark.circle" : "circle")
                    }
                }
            } label: { Label("chapterStory.chooseTask", systemImage: "list.bullet") }
                .disabled(advanced.pending != nil || advanced.phase != "ready")
                .accessibilityIdentifier("chapterStory.chooseTask")
            if ChapterInlineKitSelection.complete(current, in: state),
               let next = ChapterInlineKitSelection.preferred(in: state, excluding: current) {
                Button("chapterStory.nextTask") { requestKind(next) }
                    .disabled(advanced.pending != nil || advanced.phase != "ready")
                    .accessibilityIdentifier("chapterStory.nextTask")
            }
        }
    }
    private func requestKind(_ kind: PlayKitScreenKind) {
        guard kind != selection.selected, advanced.isCurrent, advanced.pending == nil, advanced.phase == "ready" else { return }
        if hasDraft { requestedKind = kind; confirmSwitch = true }
        else { switchKind(kind) }
    }
    private func switchKind(_ kind: PlayKitScreenKind) {
        guard advanced.isCurrent, advanced.pending == nil, advanced.phase == "ready", let state = advanced.state,
              selection.select(kind, in: state) else { return }
        device?.cancel(); hasDraft = false; dirty(false)
        // Only this local form's identity changes. The authoritative state and pending journal are untouched.
    }
    private func publish() {
        guard advanced.isCurrent, let state = advanced.state else { return }
        if selection.sessionID != state.sessionID { hasDraft = false; requestedKind = nil; confirmSwitch = false; dirty(false) }
        // Keep the frozen action's recovery screen even if a readback removes its segment.
        selection.reconcile(state, preservingDraft: hasDraft || advanced.pending != nil)
        if state.inline { inline() }
        variables(state.storyVariables)
        if state.readyForBase { ready(state) }
    }
}
@MainActor private struct ChapterStoryArtwork: View {
    let url: String
    let reader: (any RetainedPublicImageReading)?
    @State private var image: UIImage?
    @State private var loading = false
    @State private var failed = false
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit().accessibilityLabel(Text("chapterStory.artwork")) }
            else if loading { ProgressView("chapterStory.loadingImage") }
            else { Label(failed ? "chapterStory.imageFailed" : "chapterStory.imageGated", systemImage: "photo") }
        }.frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 18))
        .task(id: url) {
            image = nil; failed = false
            guard let reader, reader.enabled, let source = URL(string: url) else { return }
            loading = true
            defer { loading = false }
            do {
                let bytes = try await reader.image(url: source)
                let sanitized = try RetainedImageSanitizer.sanitize(bytes)
                try Task.checkCancellation(); image = UIImage(data: sanitized.jpeg)
            } catch { if !Task.isCancelled { failed = true } }
        }.onDisappear { image = nil }
    }
}

/// Optional chapter text (`optional: true`): a collapsed 「延伸阅读」 card, expanded on tap.
@MainActor struct ChapterOptionalReadingCard: View {
    let id: String
    let subtitle: String?
    let paragraphs: [String]
    @State private var expanded = false
    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, line in
                    Text(verbatim: line).font(.body).lineSpacing(8).textSelection(.enabled)
                }
            }.padding(.top, 8)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Label("chapterStory.optionalReading", systemImage: "book")
                    .font(.headline)
                if let subtitle { Text(verbatim: subtitle).font(.subheadline).foregroundStyle(.secondary) }
            }
        }
        .padding().background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityIdentifier("chapterStory.optional." + id)
    }
}
