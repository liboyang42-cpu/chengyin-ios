import SwiftUI

@MainActor struct PlayKitTimedChallengeView: View {
    let kind: PlayKitScreenKind; let segment: PlayWireValue
    let enabled: Bool; let active: Bool; let onDirty: () -> Void; let requestReview: PlayKitReviewRequest
    let revisionIdentity: String
    let currentRevisionIdentity: (() -> String)?
    @State private var expectedRevision = ""
    @State private var timing = PlayKitTimingRun()
    @State private var reaction: PlayKitReactionRun
    @State private var elapsed = 0
    @State private var input = ""
    @State private var ticker = UUID()
    @State private var mounted = false
    @State private var expired = false
    @FocusState private var typingFocused: Bool
    @Environment(\.scenePhase) private var scenePhase
    init(kind: PlayKitScreenKind, segment: PlayWireValue, enabled: Bool, active: Bool, onDirty: @escaping () -> Void, requestReview: @escaping PlayKitReviewRequest, revisionIdentity: String = "", currentRevisionIdentity: (() -> String)? = nil) {
        self.kind = kind; self.segment = segment; self.enabled = enabled; self.active = active; self.onDirty = onDirty; self.requestReview = requestReview
        self.revisionIdentity = revisionIdentity; self.currentRevisionIdentity = currentRevisionIdentity
        let rounds = segment["rounds"].integer ?? 3
        _reaction = State(initialValue: PlayKitReactionRun(rounds: rounds > 0 ? rounds : 3))
    }
    private var seconds: Double { segment[kind == .stopwatch ? "targetSeconds" : "seconds"].double ?? 0 }
    private var running: Bool { timing.phase == .running || [.waiting, .signal].contains(reaction.phase) }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("playkit.challenge.authority").font(.footnote).foregroundStyle(.secondary)
            if kind == .reaction { reactionStage }
            else { timedStage }
            if timing.phase == .interrupted || reaction.phase == .interrupted { Label("playkit.challenge.interrupted", systemImage: "pause.circle") }
            if expired { Text("playkit.challenge.expired") }
            if running { Button("playkit.challenge.abort", role: .destructive) { interrupt() } }
        }
        .onAppear { mounted = true; expectedRevision = currentRevisionIdentity?() ?? revisionIdentity }
        .task(id: ticker) {
            while mounted && active && running && !Task.isCancelled {
                let now = ProcessInfo.processInfo.systemUptime
                if kind == .reaction { reaction.tick(now: now) }
                else {
                    elapsed = timing.elapsed(now: now)
                    if kind == .countdown, elapsed >= Int(max(0, seconds) * 1000) { timing.measure(now: now) }
                    if kind == .typeIn, seconds > 0, elapsed >= Int(seconds * 1000) { timing.measure(now: now); typingFocused = false; expired = true }
                    if kind == .stopwatch, elapsed > Int((max(0, seconds) + 30) * 1000) { interrupt(); expired = true }
                }
                do { try await Task.sleep(for: .milliseconds(20)) } catch { break }
            }
        }
        .onChange(of: revisionIdentity) { _, next in
            if !expectedRevision.isEmpty && next != expectedRevision {
                interrupt(); timing = PlayKitTimingRun(); reaction = PlayKitReactionRun(rounds: reaction.rounds)
                elapsed = 0; input = ""; expectedRevision = next
            }
        }
        .onChange(of: active) { _, value in if !value { interrupt() } }
        .onChange(of: scenePhase) { _, value in if value != .active { interrupt() } }
        .onDisappear { mounted = false; interrupt() }
    }
    @ViewBuilder private var timedStage: some View {
        if seconds > 0 { LabeledContent("playkit.challenge.target") { Text(verbatim: String(format: "%.2f s", seconds)).monospacedDigit() } }
        if kind == .stopwatch, let tolerance = segment["toleranceMs"].integer { LabeledContent("playkit.stopwatch.tolerance") { Text(verbatim: "±\(tolerance) ms") } }
        if kind == .typeIn {
            Text(verbatim: segment["target"].text ?? "").font(.title2.monospaced()).textSelection(.disabled)
            Text(segment["caseSensitive"].bool == true ? "playkit.type.caseSensitive" : "playkit.type.caseInsensitive").font(.footnote)
            TextField("playkit.type.input", text: $input, axis: .vertical)
                .textFieldStyle(.roundedBorder).textInputAutocapitalization(.never).autocorrectionDisabled()
                .focused($typingFocused).disabled(timing.phase != .running || !enabled)
                .onChange(of: input) { _, value in if value.count > 4096 { input = String(value.prefix(4096)) }; onDirty() }
            if let attempts = segment["attempts"].integer { LabeledContent("playkit.attempts") { Text(verbatim: String(attempts)) } }
        }
        Text(verbatim: clockLabel).font(.system(.largeTitle, design: .rounded).monospacedDigit())
            .accessibilityLabel(Text(kind == .stopwatch && running && elapsed >= 1000 ? "playkit.stopwatch.hidden" : "playkit.challenge.clock"))
        if timing.phase == .idle || timing.phase == .interrupted {
            Button("playkit.challenge.start") { start() }.buttonStyle(.borderedProminent)
                .disabled(!enabled || !validConfiguration).accessibilityIdentifier("playkit.challenge.start")
        }
        if timing.phase == .running && kind != .countdown {
            Button(kind == .stopwatch ? "playkit.stopwatch.stop" : "playkit.type.finish") {
                timing.measure(now: ProcessInfo.processInfo.systemUptime); elapsed = timing.elapsedMilliseconds; typingFocused = false
            }.buttonStyle(.borderedProminent).disabled(!enabled).accessibilityIdentifier("playkit.challenge.measure")
        }
        if timing.phase == .measured {
            Text("playkit.challenge.measurementOnly").font(.footnote)
            Button("playkit.review") { reviewMeasurement() }.buttonStyle(.borderedProminent)
                .disabled(!enabled || (kind == .typeIn && input.isEmpty)).accessibilityIdentifier("playkit.challenge.submit")
        }
        if !validConfiguration { Text("playkit.configurationInvalid") }
    }
    private var validConfiguration: Bool {
        if kind == .reaction { return true }
        if kind == .typeIn { return seconds.isFinite && seconds >= 0 && seconds <= 3600 && !(segment["target"].text ?? "").isEmpty }
        return seconds.isFinite && seconds > 0 && seconds <= 3600
    }
    private var clockLabel: String {
        if kind == .stopwatch && timing.phase == .running && elapsed >= 1000 { return "—.—" }
        if kind == .countdown || kind == .typeIn {
            if seconds <= 0 { return String(format: "%.2f s", Double(elapsed) / 1000) }
            return String(format: "%.1f s", max(0, seconds - Double(elapsed) / 1000))
        }
        return String(format: "%.2f s", Double(elapsed) / 1000)
    }
    @ViewBuilder private var reactionStage: some View {
        LabeledContent("playkit.reaction.round") { Text(verbatim: "\(reaction.roundsMilliseconds.count) / \(reaction.rounds)").monospacedDigit() }
        if let goal = segment["goalMs"].integer, goal > 0 { LabeledContent("playkit.reaction.goal") { Text(verbatim: "\(goal) ms") } }
        if reaction.phase == .idle || reaction.phase == .interrupted {
            Button("playkit.challenge.start") { start() }.buttonStyle(.borderedProminent).disabled(!enabled)
        } else if reaction.phase == .waiting || reaction.phase == .signal {
            Button {
                reaction.tap(now: ProcessInfo.processInfo.systemUptime); onDirty()
            } label: {
                VStack(spacing: 12) {
                    Image(systemName: reaction.phase == .signal ? "hand.tap.fill" : "hourglass")
                    Text(reaction.phase == .signal ? "playkit.reaction.tap" : "playkit.reaction.wait")
                }.font(.largeTitle.bold()).frame(maxWidth: .infinity, minHeight: 240)
            }.buttonStyle(.borderedProminent).tint(reaction.phase == .signal ? .green : .orange)
                .disabled(!enabled).accessibilityIdentifier("playkit.reaction.target")
        } else if reaction.phase == .early || reaction.phase == .betweenRounds {
            if reaction.phase == .early { Label("playkit.reaction.early", systemImage: "exclamationmark.circle") }
            Button("playkit.reaction.next") { reaction.arm(now: ProcessInfo.processInfo.systemUptime, randomUnit: Double.random(in: 0...1)); ticker = UUID() }.disabled(!enabled)
        }
        ForEach(Array(reaction.roundsMilliseconds.enumerated()), id: \.offset) { index, ms in
            HStack { Text(verbatim: String(index + 1)); Spacer(); Text(verbatim: "\(ms) ms").monospacedDigit() }
        }
        if reaction.phase == .measured {
            Text("playkit.challenge.measurementOnly").font(.footnote)
            Button("playkit.review") { requestReview("SUBMIT_REACTION", ["times": .array(reaction.roundsMilliseconds.map(PlayWireValue.int))], {}) }
                .buttonStyle(.borderedProminent).disabled(!enabled)
        }
    }
    private func start() {
        guard enabled, validConfiguration else { return }
        requestReview("START_CHALLENGE", ["game": .string(kind.rawValue)]) {
            guard mounted, active, scenePhase == .active else { return }
            expectedRevision = currentRevisionIdentity?() ?? revisionIdentity
            expired = false; onDirty()
            if kind == .reaction { reaction.beginAfterAcknowledgement(now: ProcessInfo.processInfo.systemUptime, randomUnit: Double.random(in: 0...1)) }
            else { input = ""; elapsed = 0; timing.beginAfterAcknowledgement(now: ProcessInfo.processInfo.systemUptime); typingFocused = kind == .typeIn }
            ticker = UUID()
        }
    }
    private func reviewMeasurement() {
        guard timing.phase == .measured else { return }
        switch kind {
        case .countdown: requestReview("SUBMIT_COUNTDOWN", [:], {})
        case .stopwatch: requestReview("SUBMIT_STOPWATCH", ["stoppedMs": .int(timing.elapsedMilliseconds)], {})
        case .typeIn: requestReview("SUBMIT_TYPE_IN", ["text": .string(input), "elapsedMs": .int(timing.elapsedMilliseconds)], {})
        default: break
        }
    }
    private func interrupt() {
        timing.interrupt(); reaction.interrupt(); typingFocused = false; ticker = UUID()
    }
}
