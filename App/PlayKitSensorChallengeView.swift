import SwiftUI

@MainActor struct PlayKitSensorChallengeView: View {
    let kind: PlayKitScreenKind
    let segment: PlayWireValue
    let enabled: Bool
    let active: Bool
    let onDirty: () -> Void
    let requestReview: PlayKitReviewRequest
    let revisionIdentity: String
    let currentRevisionIdentity: (() -> String)?
    @State private var stage: PlayKitSensorStageModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(kind: PlayKitScreenKind, segment: PlayWireValue, enabled: Bool, active: Bool,
         onDirty: @escaping () -> Void, requestReview: @escaping PlayKitReviewRequest,
         revisionIdentity: String = "", currentRevisionIdentity: (() -> String)? = nil,
         makeSensorProvider: (@MainActor () -> any PlayKitSensorProviding)? = nil) {
        self.kind = kind; self.segment = segment; self.enabled = enabled; self.active = active
        self.onDirty = onDirty; self.requestReview = requestReview
        self.revisionIdentity = revisionIdentity; self.currentRevisionIdentity = currentRevisionIdentity
        // Empty by default. Having a device implementation is not acceptance of
        // a backend contract, a privacy declaration or a sensor grant.
        _stage = State(initialValue: PlayKitSensorStageModel(kind: kind, segment: segment,
            provider: makeSensorProvider?() ?? PlayKitDormantSensorProvider(), revisionIdentity: revisionIdentity))
    }

    var body: some View {
        VStack(spacing: 20) {
            Text(LocalizedStringKey("playkit.sensor.purpose." + kind.rawValue))
                .font(.callout).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("playkit.sensor.purpose")
            if kind == .quietHold || kind == .shout { Text("playkit.sensor.audioPrivacy").font(.footnote).foregroundStyle(.secondary) }
            if kind == .compass { Text("playkit.compass.caution").font(.footnote).foregroundStyle(.secondary) }
            if let error = stage.issue {
                Label(LocalizedStringKey("playkit.sensor.error." + error.rawValue), systemImage: "exclamationmark.triangle")
                    .accessibilityIdentifier("playkit.sensor.issue")
            }
            sensorBoard
            Text(LocalizedStringKey("playkit.sensor.phase." + stage.phase.rawValue))
                .font(.headline).accessibilityIdentifier("playkit.sensor.phase")
            if stage.phase == .calibrating {
                ProgressView().accessibilityLabel(Text("playkit.sensor.calibrating"))
                Text(LocalizedStringKey(kind == .ballShake ? "playkit.ball.calibration" : "playkit.audio.calibration"))
            }
            if stage.phase == .measured {
                Text("playkit.sensor.measuredBoundary").font(.footnote).foregroundStyle(.secondary)
                Button("playkit.review") {
                    guard let payload = stage.payload else { return }
                    requestReview(stage.submitAction, payload, {})
                }.buttonStyle(.borderedProminent).disabled(!enabled || !active || stage.payload == nil)
                    .accessibilityIdentifier("playkit.sensor.review")
            } else if stage.phase == .ready {
                Button("playkit.sensor.reviewStart") {
                    let token = stage.attempt
                    requestReview("START_CHALLENGE", ["game": .string(kind.rawValue)]) {
                        // The parent calls only after a successful, current server
                        // acknowledgement. A stale callback cannot restart sensors.
                        if stage.startAfterAcknowledgement(attempt: token, revisionIdentity: currentRevisionIdentity?() ?? revisionIdentity) { onDirty() }
                    }
                }.buttonStyle(.borderedProminent).disabled(!enabled || !active)
                    .accessibilityIdentifier("playkit.sensor.start")
                Text("playkit.sensor.startBoundary").font(.footnote).foregroundStyle(.secondary)
            } else if stage.phase == .idle || stage.phase == .interrupted {
                Button(LocalizedStringKey(kind == .compass ? "playkit.compass.begin" : "playkit.sensor.calibrate")) {
                    onDirty(); stage.begin(active: active)
                }.buttonStyle(.borderedProminent).disabled(!enabled || !active || !stage.supported)
                    .accessibilityIdentifier("playkit.sensor.calibrate")
            }
            if [.authorizing, .calibrating, .running, .ready].contains(stage.phase) {
                Button("playkit.sensor.stop", role: .cancel) { stage.interrupt(.interrupted) }
                    .accessibilityIdentifier("playkit.sensor.stop")
            }
            if !stage.supported { Text("playkit.sensor.error.configurationUnavailable").font(.footnote) }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical)
        .onAppear { stage.isActive = active }
        .onChange(of: revisionIdentity) { _, next in stage.updateRevision(next, segment: segment) }
        .onChange(of: active) { _, value in stage.isActive = value; if !value { stage.interrupt(.interrupted) } }
        .onChange(of: scenePhase) { _, value in
            // An OS permission prompt can make the scene inactive, before there
            // is any stream. Background always invalidates the whole attempt.
            if value == .background || (value != .active && stage.phase != .authorizing) { stage.interrupt(.interrupted) }
        }
        .onDisappear { stage.interrupt(.interrupted) }
        .accessibilityIdentifier("playkit.sensor." + kind.rawValue)
    }

    @ViewBuilder private var sensorBoard: some View {
        switch kind {
        case .ballShake:
            VStack(spacing: 12) {
                HStack {
                    LabeledContent("playkit.ball.hits") { Text(verbatim: "\(stage.ball.hits) / \(stage.ball.goal)").monospacedDigit() }
                    if stage.ball.limitSeconds > 0 {
                        LabeledContent("playkit.sensor.secondsLeft") { Text(verbatim: decimal(max(0, stage.ball.limitSeconds - stage.ball.elapsedSeconds))).monospacedDigit() }
                    }
                }
                GeometryReader { geometry in
                    ZStack(alignment: .topLeading) {
                        Color(.secondarySystemBackground)
                        Circle().fill(Color.accentColor)
                            .frame(width: geometry.size.width * 26 / 300, height: geometry.size.width * 26 / 300)
                            .position(x: geometry.size.width * stage.ball.x / 300, y: geometry.size.height * stage.ball.y / 420)
                    }.clipped()
                }.aspectRatio(300.0 / 420.0, contentMode: .fit)
                    .accessibilityElement(children: .ignore).accessibilityLabel(Text("playkit.ball.board"))
                Text("playkit.ball.instruction").font(.footnote)
            }
        case .quietHold, .shout:
            let level = kind == .quietHold ? stage.quiet.level : stage.shout.level
            let warning = kind == .quietHold ? stage.quiet.warningThreshold : stage.shout.warningThreshold
            let threshold = kind == .quietHold ? stage.quiet.stopThreshold : stage.shout.loudThreshold
            let held = kind == .quietHold ? stage.quiet.heldSeconds : stage.shout.heldSeconds
            let total = kind == .quietHold ? stage.quiet.targetSeconds : stage.shout.targetSeconds
            let color: Color = level > threshold ? .red : level > warning ? .orange : .green
            VStack(spacing: 12) {
                Text(verbatim: decimal(max(0, total - held))).font(.system(size: 64, weight: .bold, design: .rounded)).monospacedDigit()
                    .accessibilityLabel(Text("playkit.sensor.secondsLeft"))
                    .accessibilityValue(Text(verbatim: decimal(max(0, total - held))))
                Gauge(value: level, in: 0...1) { Text("playkit.audio.livePeak") }.tint(color)
                Label(LocalizedStringKey(level > threshold ? "playkit.audio.hot" : level > warning ? "playkit.audio.warning" : "playkit.audio.quiet"),
                      systemImage: level > threshold ? "waveform" : "waveform.path")
                    .foregroundStyle(color)
                ProgressView(value: held, total: total).accessibilityLabel(Text("playkit.sensor.holdProgress"))
                if kind == .quietHold, stage.quiet.exceeded { Text("playkit.quiet.limitReached") }
                if kind == .shout { Text("playkit.shout.continuous").font(.footnote) }
            }
        case .compass:
            VStack(spacing: 12) {
                ZStack {
                    Circle().stroke(.secondary.opacity(0.4), lineWidth: 2)
                    ForEach(0..<12) { mark in
                        Capsule().fill(Color.secondary).frame(width: 2, height: mark % 3 == 0 ? 18 : 10)
                            .offset(y: -105).rotationEffect(.degrees(Double(mark) * 30))
                    }
                    Image(systemName: "location.north.fill").font(.system(size: 72))
                        .foregroundStyle(stage.compass.aligned ? Color.green : Color.accentColor)
                        .rotationEffect(.degrees(stage.compass.needleDegrees))
                        .opacity(stage.compass.heading == nil ? 0.25 : 1)
                        .animation(reduceMotion ? nil : .linear(duration: 0.1), value: stage.compass.needleDegrees)
                }.frame(width: 240, height: 240).accessibilityHidden(true)
                LabeledContent("playkit.compass.target") { Text(verbatim: "\(Int(stage.compass.target))°").monospacedDigit() }
                if let heading = stage.compass.heading {
                    LabeledContent("playkit.compass.heading") { Text(verbatim: "\(Int(heading.rounded()) % 360)°").monospacedDigit() }
                    if stage.compass.lowAccuracy { Label("playkit.compass.lowAccuracy", systemImage: "exclamationmark.triangle") }
                    else if stage.compass.aligned { Label("playkit.compass.hold", systemImage: "scope") }
                    else {
                        HStack {
                            Text(LocalizedStringKey(stage.compass.signedDelta > 0 ? "playkit.compass.turnRight" : "playkit.compass.turnLeft"))
                            Text(verbatim: "\(Int(abs(stage.compass.signedDelta).rounded()))°").monospacedDigit()
                        }
                    }
                } else { Text("playkit.compass.waitingHeading") }
                ProgressView(value: stage.compass.heldSeconds, total: stage.compass.holdSeconds)
                    .accessibilityLabel(Text("playkit.sensor.holdProgress"))
                LabeledContent("playkit.sensor.secondsLeft") { Text(verbatim: decimal(max(0, stage.compass.holdSeconds - stage.compass.heldSeconds))).monospacedDigit() }
            }
        default: EmptyView()
        }
    }
    private func decimal(_ number: Double) -> String { String(format: "%.1f", number) }
}

/// Sensor values remain local and ephemeral. Review receives only the established
/// UI detail. The host owns wire-unit conversion. No local passed, submitted,
/// completion or reward field is set.
@MainActor @Observable final class PlayKitSensorStageModel {
    enum Phase: String { case idle, authorizing, calibrating, ready, running, measured, interrupted }
    let kind: PlayKitScreenKind
    let provider: any PlayKitSensorProviding
    var phase = Phase.idle
    var issue: PlayKitSensorError?
    var isActive = true
    var attempt = UUID()
    private var revisionIdentity: String
    var quiet: PlayKitQuietRun
    var ball: PlayKitBallRun
    var compass: PlayKitCompassRun
    var shout: PlayKitShoutRun
    private var samplesTask: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    private var continuity: PlayKitSensorContinuity?
    private var streamToken = UUID()

    init(kind: PlayKitScreenKind, segment: PlayWireValue, provider: any PlayKitSensorProviding, revisionIdentity: String = "") {
        self.kind = kind; self.provider = provider; self.revisionIdentity = revisionIdentity
        quiet = Self.makeQuiet(segment)
        ball = Self.makeBall(segment)
        compass = .init(target: segment["bearing"].double ?? 0, tolerance: segment["tolerance"].double ?? 15, holdSeconds: segment["holdSeconds"].double ?? 3)
        shout = .init(seconds: segment["seconds"].double ?? 5)
    }
    private static func makeQuiet(_ segment: PlayWireValue) -> PlayKitQuietRun {
        let seconds = segment["seconds"].double ?? 0
        return .init(seconds: seconds > 0 ? seconds : 15)
    }
    private static func makeBall(_ segment: PlayWireValue) -> PlayKitBallRun {
        let goal = segment["goal"].integer ?? 0
        return .init(goal: goal > 0 ? goal : 30, limitSeconds: segment["timed"].bool == true ? (segment["seconds"].double ?? 0) : 0)
    }
    var sensorKind: PlayKitSensorKind { kind == .ballShake ? .acceleration : kind == .compass ? .heading : .soundPeak }
    var supported: Bool { provider.supported.contains(sensorKind) }
    var submitAction: String {
        switch kind {
        case .ballShake: return "SUBMIT_BALL_SHAKE"
        case .quietHold: return "SUBMIT_QUIET_HOLD"
        case .compass: return "SUBMIT_COMPASS"
        case .shout: return "SUBMIT_SHOUT"
        default: return ""
        }
    }
    var payload: [String: PlayWireValue]? {
        guard phase == .measured else { return nil }
        switch kind {
        case .ballShake: return ["hits": .integer(Int64(ball.hits))]
        case .quietHold: return quiet.reviewDetail
        case .compass:
            guard let bearing = compass.submittedBearing else { return nil }; return ["bearing": .integer(Int64(bearing))]
        case .shout: return ["heldMs": .integer(Int64((shout.heldSeconds * 1000).rounded(.down)))]
        default: return nil
        }
    }
    func begin(active: Bool) {
        guard active, supported, [.idle, .interrupted].contains(phase) else { return }
        isActive = active; attempt = UUID(); issue = nil
        openStream(afterAcknowledgement: false)
    }
    @discardableResult func startAfterAcknowledgement(attempt token: UUID, revisionIdentity: String) -> Bool {
        guard attempt == token, isActive, phase == .ready else { return false }
        self.revisionIdentity = revisionIdentity
        openStream(afterAcknowledgement: true); return true
    }
    func updateRevision(_ next: String, segment: PlayWireValue) {
        guard revisionIdentity != next else { return }
        interrupt(.interrupted); revisionIdentity = next
        quiet = Self.makeQuiet(segment)
        ball = Self.makeBall(segment)
        compass = .init(target: segment["bearing"].double ?? 0, tolerance: segment["tolerance"].double ?? 15, holdSeconds: segment["holdSeconds"].double ?? 3)
        shout = .init(seconds: segment["seconds"].double ?? 5)
    }
    private func openStream(afterAcknowledgement: Bool) {
        stopStream(); phase = .authorizing
        let token = UUID(); streamToken = token
        samplesTask = Task { [weak self] in
            guard let self else { return }
            do {
                if let authorizing = self.provider as? any PlayKitSensorAuthorizing { try await authorizing.prepare(self.sensorKind) }
                guard !Task.isCancelled, self.streamToken == token, self.isActive else { return }
                if self.kind == .compass { self.compass.begin(); self.phase = .running }
                else if afterAcknowledgement {
                    switch self.kind {
                    case .ballShake: self.ball.beginAfterAcknowledgement()
                    case .quietHold: self.quiet.beginAfterAcknowledgement()
                    case .shout: self.shout.beginAfterAcknowledgement()
                    default: break
                    }
                    self.phase = .running
                } else {
                    switch self.kind {
                    case .ballShake: self.ball.calibrate()
                    case .quietHold: self.quiet.calibrate()
                    case .shout: self.shout.calibrate()
                    default: break
                    }
                    self.phase = .calibrating
                }
                self.continuity = .init(kind: self.sensorKind, now: ProcessInfo.processInfo.systemUptime)
                self.startWatchdog(token: token)
                for try await sample in self.provider.samples(self.sensorKind) {
                    guard !Task.isCancelled, self.streamToken == token, self.isActive else { return }
                    guard self.continuity?.accept(sample, now: ProcessInfo.processInfo.systemUptime) == true else {
                        self.interrupt(.missingSamples); return
                    }
                    self.ingest(sample)
                    if self.phase == .ready || self.phase == .measured { self.stopStream(); return }
                    if self.phase == .interrupted { return }
                }
                guard self.streamToken == token, !Task.isCancelled else { return }
                self.interrupt(.missingSamples)
            } catch {
                guard self.streamToken == token, !Task.isCancelled else { return }
                self.interrupt(error as? PlayKitSensorError ?? .sensorUnavailable)
            }
        }
    }
    private func ingest(_ sample: PlayKitSensorSample) {
        switch sample {
        case let .acceleration(x, y, _, timestamp) where kind == .ballShake:
            ball.ingest(x: x, y: y, timestamp: timestamp, randomUnit: Double.random(in: 0...1)); phase = Phase(rawValue: ball.phase.rawValue) ?? .interrupted
        case let .soundPeak(peak, timestamp) where kind == .quietHold:
            quiet.ingest(peak: peak, timestamp: timestamp); phase = Phase(rawValue: quiet.phase.rawValue) ?? .interrupted
        case let .soundPeak(peak, timestamp) where kind == .shout:
            shout.ingest(peak: peak, timestamp: timestamp); phase = Phase(rawValue: shout.phase.rawValue) ?? .interrupted
        case let .heading(bearing, accuracy, timestamp) where kind == .compass:
            compass.ingest(bearing: bearing, accuracy: accuracy, timestamp: timestamp); phase = Phase(rawValue: compass.phase.rawValue) ?? .interrupted
        default: interrupt(.sensorUnavailable)
        }
        if phase == .interrupted { interrupt(.missingSamples) }
    }
    private func startWatchdog(token: UUID) {
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 100_000_000) } catch { return }
                guard let self, self.streamToken == token else { return }
                if self.continuity?.expired(now: ProcessInfo.processInfo.systemUptime) == true { self.interrupt(.missingSamples); return }
            }
        }
    }
    func interrupt(_ error: PlayKitSensorError) {
        attempt = UUID(); stopStream()
        // Even a measured result is discarded on navigation/session interruption;
        // no old sensor evidence can be reviewed in a new session or retry.
        quiet = .init(seconds: quiet.targetSeconds)
        ball = .init(goal: ball.goal, limitSeconds: ball.limitSeconds)
        compass = .init(target: compass.target, tolerance: compass.tolerance, holdSeconds: compass.holdSeconds)
        shout = .init(seconds: shout.targetSeconds)
        if phase != .idle { phase = .interrupted; issue = error }
    }
    private func stopStream() {
        streamToken = UUID(); samplesTask?.cancel(); samplesTask = nil
        watchdog?.cancel(); watchdog = nil; continuity = nil; provider.cancel()
    }
}
