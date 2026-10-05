import SwiftUI

@MainActor struct PlayDeviceTaskSection: View {
    @Bindable var model: PlayDeviceCaptureCoordinator
    let task: PlayNodeTask
    var photoFilter: PlayPhotoFilter? = nil
    var unsupportedPhotoSubtype = false
    let onEvidence: (PlayCompletionEvidence) -> Void
    private var kind: PlayDeviceKind? {
        switch task { case .scan, .merchantScan: return .scan
        case .arrive: return .location
        case .photo, .merchantPhoto: return .photo
        case .sensor: return .motion
        default: return nil }
    }
    var body: some View {
        Section("playx.device.title") {
            if let kind {
                Text(LocalizedStringKey("playx.device." + kind.rawValue)).font(.headline)
                if unsupportedPhotoSubtype { Text("playhost.photo.unsupported") }
                if !model.supports(kind) { Text("playx.device.disabled") }
                Button("playx.device.capture") { Task { await model.capture(kind, photoFilter: photoFilter) } }
                    .disabled(model.busy || !model.supports(kind) || unsupportedPhotoSubtype).accessibilityIdentifier("playx.device.capture")
                if model.busy { ProgressView("playx.loading") }
                if let output = model.output {
                    switch output {
                    case .scan(let code):
                        Text("playx.device.scanCaptured")
                        Button("playx.review") { onEvidence(.scan(code)) }.accessibilityIdentifier("playx.device.review")
                    case .location(let longitude, let latitude, let coordinateSystem):
                        Text("playx.device.locationCaptured")
                        Text(verbatim: coordinateSystem).font(.caption)
                        Button("playx.review") { onEvidence(.location(longitude: longitude, latitude: latitude, coordinateSystem: coordinateSystem)) }
                            .disabled(coordinateSystem != "GCJ02").accessibilityIdentifier("playx.device.review")
                    case .photo(let bytes, let mime):
                        Text("playx.device.photoCaptured")
                        LabeledContent("playx.media.size") { Text(verbatim: "\(bytes.count) · \(mime)") }
                        if let image = UIImage(data: bytes) { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 240).accessibilityLabel(Text("playhost.photo.preview")) }
                        Text("playhost.photo.notice")
                        Button("playhost.photo.upload") { Task { await model.uploadPhoto() } }
                            .disabled(!model.canUpload).accessibilityIdentifier("playhost.photo.upload")
                        if model.uploadedPhoto != nil {
                            Button("playx.review") { if let evidence = model.reviewedPhoto() { onEvidence(evidence) } }
                                .accessibilityIdentifier("playhost.photo.review")
                        } else { Text("playx.media.uploadGate") }
                    case .sample: Text("playx.device.motionCaptured")
                    case .unavailable: Text("playx.device.disabled")
                    }
                }
                if let issue = model.issue { PlayExperienceIssueView(issue: issue) }
                Button("playx.cancel", role: .cancel) { model.cancel() }
            } else if task == .merchantVerify { Text("playx.merchant.consentGate") }
            else { Text("playx.unsupported") }
        }.onDisappear { model.cancel() }
    }
}

@MainActor struct PlayStopwatchView: View {
    @State private var machine = PlayStopwatchMachine()
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        List {
            Section("playx.stopwatch") {
                Text("playx.stopwatch.local").font(.footnote)
                LabeledContent("playx.stopwatch.target") { Text(verbatim: String(format: "%.2f s", machine.target)) }
                TimelineView(.periodic(from: .now, by: 0.05)) { _ in
                    Text(verbatim: machine.visibleElapsed(now: ProcessInfo.processInfo.systemUptime).map { String(format: "%.2f", $0) } ?? "—.—")
                        .font(.system(.largeTitle, design: .rounded).monospacedDigit())
                        .accessibilityLabel(Text("playx.stopwatch.clock"))
                        .accessibilityValue(Text(LocalizedStringKey(machine.phase == .running ? "playx.stopwatch.running" : "playx.stopwatch.ready")))
                }
                Button(LocalizedStringKey(machine.phase == .running ? "playx.stopwatch.stop" : "playx.stopwatch.start")) {
                    if machine.phase == .running { machine.stop(now: ProcessInfo.processInfo.systemUptime) }
                    else { machine.begin(now: ProcessInfo.processInfo.systemUptime) }
                }.buttonStyle(.borderedProminent).accessibilityIdentifier("playx.stopwatch.toggle")
                if let result = machine.result {
                    LabeledContent("playx.stopwatch.stars") { Text(verbatim: String(result.stars)) }
                    LabeledContent("playx.stopwatch.diff") { Text(verbatim: String(format: "%.2f s", result.difference)) }
                    Text(LocalizedStringKey(result.late ? "playx.stopwatch.late" : "playx.stopwatch.early"))
                }
                LabeledContent("playx.stopwatch.rounds") { Text(verbatim: String(machine.rounds)) }
                if let best = machine.bestDifference { LabeledContent("playx.stopwatch.best") { Text(verbatim: String(format: "%.2f s", best)) } }
            }
        }.navigationTitle("playx.stopwatch").accessibilityIdentifier("playx.stopwatch.view")
            .onChange(of: scenePhase) { _, phase in if phase != .active { machine.interrupt() } }
            .onDisappear { machine.interrupt() }
    }
}

@MainActor struct PlayStillnessStreamView: View {
    @Bindable var model: PlayStillnessCoordinator
    let onCompleted: ([String: PlayWireValue]) -> Void
    @State private var delivered = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        List {
            Section("playx.stillness") {
                Text("playx.stillness.instructions")
                ProgressView(value: model.machine.stableSeconds, total: Double(model.machine.configuration.durationSeconds))
                    .accessibilityLabel(Text("playx.stillness.progress"))
                PlayRuntimePhaseText(phase: model.machine.phase.rawValue)
                if let issue = model.issue { PlayExperienceIssueView(issue: issue) }
                if !model.available { Text("playx.device.disabled") }
                Button("playx.stillness.start") { Task { await model.start() } }
                    .disabled(!model.available || model.running || model.machine.phase == .completed || model.machine.phase == .failed)
                    .accessibilityIdentifier("playx.stillness.start")
                if model.running { Button("playx.run.pause") { model.pause() } }
                if let payload = model.machine.sourcePayload {
                    Button("playx.review") { delivered = true; dismiss(); onCompleted(payload) }.disabled(delivered)
                        .accessibilityIdentifier("playx.stillness.review")
                }
            }
        }.navigationTitle("playx.stillness").accessibilityIdentifier("playx.stillness.stream")
            .onChange(of: scenePhase) { _, phase in if phase != .active { model.pause() } }
            .onDisappear { model.pause() }
    }
}
