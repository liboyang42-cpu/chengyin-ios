import SwiftUI

@MainActor struct NativeStepsHostView: View {
    @Bindable var advanced: PlayAdvancedCoordinator
    let segment: PlayWireValue
    @Environment(\.nativePlatformRuntime) private var runtime
    @State private var stage: NativeStepCoordinator?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("nativePlatform.steps.title", systemImage: "figure.walk").font(.title2.bold())
            Text("nativePlatform.steps.boundary").font(.footnote)
            if let goal = segment["goal"].integer { LabeledContent("playkit.walk.goal") { Text(verbatim: String(goal)) } }
            if let stage, let runtime { NativeStepsControls(stage: stage, advanced: advanced, privacyURL: runtime.acceptance.privacyNoticeURL) }
            else { Label("nativePlatform.disabled", systemImage: "lock.shield").accessibilityIdentifier("nativePlatform.steps.disabled") }
        }.accessibilityIdentifier("nativePlatform.steps.host")
        .task(id: advanced.state?.sessionID) { if let id = advanced.state?.sessionID { stage = runtime?.stepModel(for: id) } }
    }
}

@MainActor struct NativeStepsControls: View {
    @Bindable var stage: NativeStepCoordinator
    @Bindable var advanced: PlayAdvancedCoordinator
    let privacyURL: URL?
    @State private var purpose = false
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(LocalizedStringKey("nativePlatform.steps.phase." + stage.phase)).accessibilityIdentifier("nativePlatform.steps.phase")
            if let issue = stage.issue { Text(LocalizedStringKey("nativePlatform.issue." + issue.rawValue)).accessibilityIdentifier("nativePlatform.steps.issue") }
            if stage.phase == "review", let sample = stage.reading, let challenge = stage.challenge {
                Text(verbatim: String(sample.steps)).font(.system(.largeTitle, design: .rounded).bold()).monospacedDigit().accessibilityIdentifier("nativePlatform.steps.count")
                LabeledContent("nativePlatform.timeZone") { Text(verbatim: challenge.timeZone) }
                LabeledContent("nativePlatform.steps.day") { Text(verbatim: challenge.dayKey) }
                Text("nativePlatform.steps.sharePurpose").font(.footnote)
                Button("nativePlatform.steps.send") { Task { await stage.submitReviewed(); await refresh() } }
                    .buttonStyle(.borderedProminent).disabled(!advanced.isCurrent)
                    .accessibilityIdentifier("nativePlatform.steps.send")
                Button("nativePlatform.cancel", role: .cancel) { stage.interrupt() }
            } else if stage.phase == "unknown" {
                Text("nativePlatform.steps.unknownBoundary").font(.footnote)
                Button("nativePlatform.steps.retryExact") { Task { await stage.retryExact(); await refresh() } }
                    .disabled(!advanced.isCurrent).accessibilityIdentifier("nativePlatform.steps.retry")
            } else if ["reading", "signing", "submitting"].contains(stage.phase) {
                ProgressView().accessibilityLabel(Text("nativePlatform.working"))
                Button("nativePlatform.cancel", role: .cancel) { stage.interrupt() }
            } else {
                if let receipt = stage.receipt {
                    if let baseline = receipt["baselineSteps"].integer { LabeledContent("nativePlatform.steps.baseline") { Text(verbatim: String(baseline)) } }
                    if let delta = receipt["acceptedDelta"].integer { LabeledContent("nativePlatform.steps.delta") { Text(verbatim: String(delta)) } }
                }
                Button("nativePlatform.steps.read") { purpose = true }
                    .buttonStyle(.borderedProminent).disabled(!advanced.canInteract || !stage.supported)
                    .accessibilityIdentifier("nativePlatform.steps.read")
                if !stage.supported { Text("nativePlatform.issue.unsupported").font(.footnote) }
            }
        }
        .sheet(isPresented: $purpose) {
            NavigationStack {
                Form {
                    Section("nativePlatform.steps.purposeTitle") {
                        Text("nativePlatform.steps.purpose")
                        Text("nativePlatform.steps.integrity")
                        if let privacyURL { Link("nativePlatform.privacy", destination: privacyURL) }
                    }
                    Button("nativePlatform.steps.continue") {
                        purpose = false
                        guard let state = advanced.state else { return }
                        Task { await stage.read(sessionID: state.sessionID, version: state.version); await refresh() }
                    }.disabled(!advanced.canInteract).accessibilityIdentifier("nativePlatform.steps.consent")
                }.navigationTitle("nativePlatform.steps.purposeTitle")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("nativePlatform.cancel") { purpose = false } } }
            }
        }
        .onChange(of: advanced.state?.version) { _, version in if let version { stage.observeVersion(version) } }
        .onChange(of: advanced.isCurrent) { _, current in if !current { purpose = false; stage.invalidate() } }
        .onChange(of: scenePhase) { _, next in if next == .background { purpose = false; stage.interrupt() } }
        .onDisappear { stage.interrupt() }
    }
    private func refresh() async { if stage.latestState != nil && advanced.isCurrent { await advanced.refreshAuthoritative() } }
}

@MainActor struct NativeTimeWindowHostView: View {
    @Bindable var advanced: PlayAdvancedCoordinator
    let segment: PlayWireValue
    @Environment(\.nativePlatformRuntime) private var runtime
    @Environment(\.scenePhase) private var scenePhase
    @State private var stage: NativeLocalReminderCoordinator?
    @State private var reviewed: NativeTimeWindow?
    @State private var readIssue: NativePlatformIssue?
    @Environment(\.locale) private var locale
    private var active: Bool { runtime?.isCurrent == true }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("nativePlatform.reminder.title", systemImage: "bell").font(.title2.bold())
            if let opens = segment["openFrom"].text { LabeledContent("playkitLegacy.window.opens") { Text(verbatim: opens) } }
            if let closes = segment["openTo"].text { LabeledContent("playkitLegacy.window.closes") { Text(verbatim: closes) } }
            Text("nativePlatform.reminder.boundary").font(.footnote)
            // Legacy subscribed is deliberately neither read nor written here.
            if let stage {
                if let window = stage.window {
                    LabeledContent("nativePlatform.timeZone") { Text(verbatim: window.timeZone) }
                    LabeledContent("nativePlatform.reminder.next") { Text(verbatim: formatted(window.nextOpenAt, zone: window.timeZone)) }
                    Text(LocalizedStringKey(window.openNow ? "nativePlatform.reminder.open" : "nativePlatform.reminder.closed"))
                }
                if let scheduled = stage.scheduled {
                    Label("nativePlatform.reminder.scheduled", systemImage: "bell.badge").accessibilityIdentifier("nativePlatform.reminder.scheduled")
                    Text(verbatim: formatted(scheduled.fireAt, zone: scheduled.timeZone)).font(.footnote)
                    Button("nativePlatform.reminder.cancel", role: .destructive) { stage.cancel() }.accessibilityIdentifier("nativePlatform.reminder.cancel")
                } else {
                    Button("nativePlatform.reminder.enable") { reviewed = stage.window }
                        .buttonStyle(.borderedProminent).disabled(stage.window == nil || stage.phase == "scheduling" || !active)
                        .accessibilityIdentifier("nativePlatform.reminder.enable")
                }
                if let issue = readIssue ?? stage.issue { Text(LocalizedStringKey("nativePlatform.issue." + issue.rawValue)).accessibilityIdentifier("nativePlatform.reminder.issue") }
                Button("nativePlatform.reminder.refresh") { Task { await refresh() } }.disabled(!active)
                    .accessibilityIdentifier("nativePlatform.reminder.refresh")
            } else { Label("nativePlatform.disabled", systemImage: "lock.shield").accessibilityIdentifier("nativePlatform.reminder.disabled") }
        }.accessibilityIdentifier("nativePlatform.reminder.host")
        .task(id: "\(advanced.activityID):\(advanced.topicID):\(advanced.nodeID)") {
            stage = runtime?.reminderModel(activityID: advanced.activityID, topicID: advanced.topicID, nodeID: advanced.nodeID); await refresh()
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                if Task.isCancelled { return }
                if scenePhase == .active, let stage { await stage.refresh(stage.window) }
            }
        }
        .onChange(of: segment) { _, _ in reviewed = nil; Task { await refresh() } }
        .onChange(of: active) { _, current in if !current { reviewed = nil; stage?.invalidate() } }
        .onChange(of: scenePhase) { _, next in if next == .active { Task { await refresh() } } else { reviewed = nil } }
        .sheet(isPresented: Binding(get: { reviewed != nil }, set: { if !$0 { reviewed = nil } })) {
            if let reviewed, let stage {
                NavigationStack {
                    Form {
                        Section("nativePlatform.reminder.purposeTitle") {
                            Text("nativePlatform.reminder.purpose")
                            Text(verbatim: formatted(reviewed.nextOpenAt, zone: reviewed.timeZone))
                            Text(verbatim: reviewed.timeZone)
                            if let url = runtime?.acceptance.privacyNoticeURL { Link("nativePlatform.privacy", destination: url) }
                        }
                        Button("nativePlatform.reminder.confirm") {
                            self.reviewed = nil
                            let title = appLocalized("nativePlatform.reminder.notificationTitle", locale: locale)
                            let body = appLocalized("nativePlatform.reminder.notificationBody", locale: locale)
                            Task { await stage.enable(reviewed: reviewed, title: title, body: body) }
                        }.accessibilityIdentifier("nativePlatform.reminder.consent")
                    }.navigationTitle("nativePlatform.reminder.purposeTitle")
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("nativePlatform.cancel") { self.reviewed = nil } } }
                }
            }
        }
    }
    private func refresh() async {
        guard let runtime, let stage, active else { return }
        do {
            let window = try await runtime.service.timeWindow(activityID: advanced.activityID, topicID: advanced.topicID, nodeID: advanced.nodeID)
            guard active else { stage.invalidate(); return }
            readIssue = nil; await stage.refresh(window)
        } catch { readIssue = error as? NativePlatformIssue ?? .network; await stage.refresh(nil) }
    }
    private func formatted(_ date: Date, zone: String) -> String {
        let formatter = DateFormatter(); formatter.locale = locale; formatter.timeZone = TimeZone(identifier: zone)
        formatter.dateStyle = .medium; formatter.timeStyle = .short; return formatter.string(from: date)
    }
}
