import SwiftUI

/// A frozen action review is the only write outlet for all specialized native kits.
typealias PlayKitReviewRequest = (String, [String: PlayWireValue], @escaping () -> Void) -> Void

enum PlayKitNativePresentation: Equatable { case navigation, inline }

@MainActor struct PlayKitScreen: View {
    @Bindable var model: PlayAdvancedCoordinator
    let kind: PlayKitScreenKind
    var presentation: PlayKitNativePresentation = .navigation
    var reportDirty: ((Bool) -> Void)? = nil
    var device: PlayDeviceCaptureCoordinator? = nil
    var mediaScope: UUID = UUID()
    var makeAudio: (@MainActor () -> PlatformAudioPlayback)? = nil
    // Empty by default. Backend/device/media acceptance is independent of having UI.
    var approvedArtworkHosts: Set<String> = []
    var makeSensorProvider: (@MainActor () -> any PlayKitSensorProviding)? = nil
    var spatialApproval = PlayKitSpatialApproval()
    @State var text = ""
    @State var selected = Set<String>()
    @State var answers: [String: String] = [:]
    @State var avatarURL = ""
    @State var dirty = false
    @State var review: PlayKitActionReview?
    @State var reviewedCompletion: (() -> Void)?
    @State var issue: PlayExperienceError?
    @State var leaveReview = false
    @State var childReset = UUID()
    @State var sessionIdentity: Int?
    @State var loaded = false
    @State var lifetime = UUID()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    private var segment: PlayWireValue {
        guard let state = model.state else { return .null }
        return ChapterInlineKitSelection.segment(kind, in: state)
    }
    var projection: PlayKitScreenProjection { .init(kind: kind, segment: segment) }
    var raw: PlayWireValue { segment }
    var runtimeIdentity: String { model.state.map { "\($0.sessionID):\($0.version)" } ?? "" }
    var enabled: Bool { model.canInteract && !projection.complete && review == nil }
    var body: some View {
        screenContainer
        .scrollDismissesKeyboard(.interactively)
        .modifier(PlayKitScreenChrome(presentation: presentation, kind: kind, close: {
            if dirty { leaveReview = true } else { dismiss() }
        }))
        .privacySensitive()
        .accessibilityIdentifier("playkit.screen." + kind.rawValue)
        .sheet(item: $review) { item in
            NavigationStack {
                Form {
                    Section("playkit.review") {
                        Text(LocalizedStringKey("playkit.kind." + kind.rawValue))
                        Text(verbatim: item.action).font(.caption)
                        Text("playkit.reviewBoundary")
                        if let question = item.compareQuestion { PlayCompareReview(question: question, marked: (item.payload["marked"]?.array ?? []).compactMap(\.text)) }
                        else { PlayKitPayloadReadback(payload: item.payload) }
                        LabeledContent("playkit.version") { Text(verbatim: String(item.version)) }
                        Button("playkit.confirm") {
                            let completion = reviewedCompletion
                            let expectedLifetime = lifetime
                            review = nil; reviewedCompletion = nil
                            Task {
                                if await model.submit(item), lifetime == expectedLifetime { issue = nil; dirty = false; completion?() }
                            }
                        }.disabled(!model.canInteract || model.state?.version != item.version || model.state?.sessionID != item.sessionID)
                            .accessibilityIdentifier("playkit.review.confirm")
                    }
                }.navigationTitle("playkit.review")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("playkit.cancel") { review = nil; reviewedCompletion = nil } } }
            }.privacySensitive()
        }
        .confirmationDialog("playkit.discardQuestion", isPresented: $leaveReview, titleVisibility: .visible) {
            Button("playkit.discard", role: .destructive) { clearTransient(); dismiss() }
            Button("playkit.keepEditing", role: .cancel) {}
        } message: { Text("playkit.discardBoundary") }
        .onAppear { loadInitial() }
        .onChange(of: dirty) { _, next in reportDirty?(next) }
        .onChange(of: model.state?.sessionID) { _, next in
            if sessionIdentity != next { clearTransient(); sessionIdentity = next; loaded = false; loadInitial() }
        }
        .onChange(of: model.isCurrent) { _, current in if !current { clearTransient() } }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                review = nil; reviewedCompletion = nil
                if phase == .background || device?.isAuthorizing != true { device?.cancel() }
                // Specialized children own interruption semantics. Destroying a sensor
                // child on OS-permission inactivity would cancel its first-use grant.
                if phase == .background { childReset = UUID() }
            }
        }
        .onDisappear { clearTransient() }
    }
    @ViewBuilder private var screenContainer: some View {
        if presentation == .inline { contents }
        else { ScrollView { contents.padding().frame(maxWidth: 720).frame(maxWidth: .infinity) } }
    }
    private var contents: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            if let issue { PlayExperienceIssueView(issue: issue) }
            if let modelIssue = model.issue { PlayExperienceIssueView(issue: modelIssue) }
            if !model.isCurrent { Text("playkit.sessionChanged") }
            else if segment.object == nil { ContentUnavailableView("playkit.unavailable", systemImage: "rectangle.slash") }
            else { content; authoritativeResult }
            recovery
        }
    }
    @ViewBuilder private var header: some View {
        if !projection.title.isEmpty { Text(verbatim: projection.title).font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true) }
        ForEach(["lead", "prompt", "hint", "sub"], id: \.self) { key in
            if let value = segment[key].text, !value.isEmpty { Text(verbatim: value).foregroundStyle(.secondary) }
        }
        if let state = model.state, state.deadlineAt != nil {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                LabeledContent("playkit.sessionRemaining") { Text(verbatim: String(state.remainingSeconds(nowMilliseconds: Int64(context.date.timeIntervalSince1970 * 1000)) ?? 0)).monospacedDigit() }
            }
        }
    }
    @ViewBuilder private var content: some View {
        switch kind {
        case .qa: qaForm
        case .branch: branchForm
        case .estimate: estimateForm
        case .pricePair: pricePairForm
        case .hiddenObject: hiddenObjectForm
        case .predict: predictForm
        case .profile: profileForm
        case .note: noteForm
        case .photoCheck: photoCheckForm
        case .scan: scanForm
        case .bingo: bingoBoard
        case .walk: walkProgress
        case .steps:
            NativeStepsHostView(advanced: model, segment: raw)
        case .coinFlip: coinFace
        case .diceRoll: diceFaces
        case .dailySign: dailySignForm
        case .random: randomDeck
        case .reaction, .countdown, .stopwatch, .typeIn:
            PlayKitTimedChallengeView(kind: kind, segment: segment, enabled: enabled, active: model.isCurrent,
                onDirty: { dirty = true }, requestReview: prepare,
                revisionIdentity: runtimeIdentity, currentRevisionIdentity: { model.state.map { "\($0.sessionID):\($0.version)" } ?? "" })
                .id(childReset)
        case .sort, .match, .classify: reasoningForm
        case .compare:
            PlayCompareView(segment: segment, revision: runtimeIdentity, enabled: enabled,
                currentRevision: { runtimeIdentity }, onDirty: { dirty = true }, requestReview: prepare)
                .id(childReset)
        case .blindTaste, .diyName, .silentOrder, .slowTask, .musicCorner, .timeWindow: legacyBody
        case .ballShake, .quietHold, .compass, .shout:
            PlayKitSensorChallengeView(kind: kind, segment: segment, enabled: enabled, active: model.isCurrent,
                onDirty: { dirty = true }, requestReview: prepare,
                revisionIdentity: runtimeIdentity, currentRevisionIdentity: { model.state.map { "\($0.sessionID):\($0.version)" } ?? "" },
                makeSensorProvider: makeSensorProvider)
                .id(childReset)
        }
    }
    @ViewBuilder var authoritativeResult: some View {
        if kind == .photoCheck, segment["degraded"].bool == true {
            Label("playkit.photo.noVerdict", systemImage: "exclamationmark.bubble")
        } else if let passed = projection.reportedPass {
            Label(passed ? "playkit.result.passed" : "playkit.result.notPassed", systemImage: passed ? "checkmark.circle" : "info.circle")
        } else if projection.complete { Label("playkit.result.recorded", systemImage: "checkmark.circle") }
        if let feedback = projection.feedback, !feedback.isEmpty { Text(verbatim: feedback) }
        if projection.complete { Text("playkit.result.authority").font(.footnote).foregroundStyle(.secondary) }
    }
    @ViewBuilder private var recovery: some View {
        if model.phase == "submitting" || model.phase == "loading" { ProgressView("playkit.sending") }
        if model.pending != nil { Text("playkit.pendingBoundary").font(.footnote) }
        if model.phase == "unknown" { Button("playkit.reconcile") { Task { await model.recover() } }.accessibilityIdentifier("playkit." + kind.rawValue + ".reconcile") }
        if model.phase == "retryable" { Button("playkit.retryExact") { Task { await model.retryExact() } }.accessibilityIdentifier("playkit." + kind.rawValue + ".retryExact") }
        if model.pending == nil && model.isCurrent && model.phase != "submitting" {
            Button("playkit.refresh") { Task { await model.refreshAuthoritative() } }.accessibilityIdentifier("playkit." + kind.rawValue + ".refresh")
        }
    }
    func prepare(_ action: String, _ payload: [String: PlayWireValue] = [:], _ completion: @escaping () -> Void = {}) {
        do { review = try model.review(kind: kind.rawValue, action: action, detail: payload); reviewedCompletion = completion; issue = nil }
        catch { issue = error as? PlayExperienceError ?? .invalidAction }
    }
    func submitButton(_ action: String, payload: [String: PlayWireValue], valid: Bool = true) -> some View {
        Button("playkit.review") { prepare(action, payload) }
            .buttonStyle(.borderedProminent).disabled(!enabled || !valid)
            .accessibilityIdentifier("playkit.submit." + kind.rawValue)
    }
    func artwork(_ url: String?) -> some View {
        PlayKitArtwork(source: url, approvedHosts: approvedArtworkHosts)
    }
    func textBinding(limit: Int = 4096) -> Binding<String> {
        Binding(get: { text }, set: { text = PlayKitInputContract.limitText($0, toUTF16: max(1, limit)); dirty = true })
    }
    private func loadInitial() {
        guard !loaded else { return }; loaded = true; sessionIdentity = model.state?.sessionID
        if kind == .note { text = segment["mine"].text ?? segment["mine"]["text"].text ?? "" }
        if kind == .diyName { text = segment["name"].text ?? "" }
        if kind == .dailySign { text = segment["myText"].text ?? "" }
        if kind == .profile { answers = (segment["answers"].object ?? [:]).compactMapValues(\.text); avatarURL = segment["avatarUrl"].text ?? "" }
    }
    private func clearTransient() {
        lifetime = UUID(); review = nil; reviewedCompletion = nil; text = ""; selected = []; answers = [:]; avatarURL = ""
        dirty = false; childReset = UUID(); device?.cancel()
    }
}

@MainActor struct PlayKitPayloadReadback: View {
    let payload: [String: PlayWireValue]
    var body: some View {
        ForEach(payload.keys.sorted(), id: \.self) { key in
            if let value = payload[key] { VStack(alignment: .leading) { Text(verbatim: key).font(.caption).foregroundStyle(.secondary); Text(verbatim: display(value)).textSelection(.enabled) } }
        }
    }
    private func display(_ value: PlayWireValue) -> String {
        switch value {
        case .string(let text): return text
        case .integer(let number): return String(number)
        case .number(let number): return String(number)
        case .bool(let value): return String(value)
        case .array(let values): return values.map(display).joined(separator: ", ")
        case .object(let values): return values.keys.sorted().map { "\($0): \(display(values[$0]!))" }.joined(separator: "\n")
        case .null: return "—"
        }
    }
}

/// Transport is permitted only for independently approved exact hosts. No account
/// headers, arbitrary scheme, local file path or hard-coded media origin is accepted.
@MainActor struct PlayKitArtwork: View {
    let source: String?; let approvedHosts: Set<String>
    var body: some View {
        if let url = QuestifyCardArtwork.safeURL(source), let host = url.host, approvedHosts.contains(host) {
            AsyncImage(url: url) { phase in
                if let image = phase.image { image.resizable().scaledToFit().accessibilityLabel(Text("playkit.image")) }
                else if phase.error != nil { Label("playkit.imageUnavailable", systemImage: "photo.badge.exclamationmark") }
                else { ProgressView("playkit.imageLoading") }
            }
        } else if source?.isEmpty == false { Label("playkit.imageGated", systemImage: "photo") }
    }
}

private struct PlayKitScreenChrome: ViewModifier {
    let presentation: PlayKitNativePresentation; let kind: PlayKitScreenKind; let close: () -> Void
    @ViewBuilder func body(content: Content) -> some View {
        if presentation == .inline { content }
        else {
            content.navigationTitle(Text(LocalizedStringKey("playkit.kind." + kind.rawValue)))
                .navigationBarTitleDisplayMode(.inline).navigationBarBackButtonHidden(true)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("playkit.close", action: close).accessibilityIdentifier("playkit.close") } }
        }
    }
}

/// Actual story-flow body: no nested ScrollView, List, navigation container or chrome.
@MainActor struct PlayKitInlineHost: View {
    let model: PlayAdvancedCoordinator; let kind: PlayKitScreenKind
    var device: PlayDeviceCaptureCoordinator? = nil
    var mediaScope: UUID = UUID()
    var makeAudio: (@MainActor () -> PlatformAudioPlayback)? = nil
    var approvedArtworkHosts: Set<String> = []
    var reportDirty: ((Bool) -> Void)? = nil
    var makeSensorProvider: (@MainActor () -> any PlayKitSensorProviding)? = nil
    var spatialApproval = PlayKitSpatialApproval()
    var body: some View {
        PlayKitScreen(model: model, kind: kind, presentation: .inline, reportDirty: reportDirty,
            device: device, mediaScope: mediaScope, makeAudio: makeAudio, approvedArtworkHosts: approvedArtworkHosts, makeSensorProvider: makeSensorProvider, spatialApproval: spatialApproval)
    }
}
