import SwiftUI

@MainActor struct PlayAdvancedView: View {
    @Bindable var model: PlayAdvancedCoordinator
    var device: PlayDeviceCaptureCoordinator? = nil
    var mediaScope: UUID = UUID()
    var makeAudio: (@MainActor () -> PlatformAudioPlayback)? = nil
    var approvedArtworkHosts: Set<String> = []
    var makeSensorProvider: (@MainActor () -> any PlayKitSensorProviding)? = nil
    let onReady: (PlayAdvancedState) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        List {
            Section {
                LabeledContent("playx.state") { PlayRuntimePhaseText(phase: model.phase) }
                if let issue = model.issue { PlayExperienceIssueView(issue: issue) }
                if model.state == nil && ["idle", "rejected", "disabled"].contains(model.phase) { Button("playx.advanced.start") { Task { await model.start() } } }
                if model.state != nil && model.pending == nil { Button("playx.refresh") { Task { await model.refreshAuthoritative() } } }
                if model.phase == "unknown" { Button("playx.reconcile") { Task { await model.recover() } } }
                if model.phase == "retryable" { Button("playx.retryExact") { Task { await model.retryExact() } } }
            }
            if let state = model.state {
                Section("playx.advanced.authority") {
                    LabeledContent("playx.state") { Text(verbatim: state.status) }
                    LabeledContent("playx.advanced.version") { Text(verbatim: String(state.version)) }
                    if let score = state.score { LabeledContent("playx.reward.puzzle") { Text(verbatim: String(score)) } }
                    if state.deadlineAt != nil {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            LabeledContent("playx.advanced.remaining") { Text(verbatim: String(state.remainingSeconds(nowMilliseconds: Int64(context.date.timeIntervalSince1970 * 1000)) ?? 0)) }
                        }
                        Text("playx.advanced.timerNotice").font(.footnote)
                    }
                    if state.readyForBase {
                        Button("playx.advanced.continue") { onReady(state); dismiss() }
                            .disabled(model.pending != nil || !model.isCurrent || model.phase != "ready")
                            .accessibilityIdentifier("playx.advanced.continue")
                    }
                }
                ForEach(PlayKitScreenKind.present(in: state)) { kind in
                    Section {
                        NavigationLink {
                            PlayKitScreen(model: model, kind: kind, device: device, mediaScope: mediaScope,
                                makeAudio: makeAudio, approvedArtworkHosts: approvedArtworkHosts, makeSensorProvider: makeSensorProvider)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(LocalizedStringKey("playkit.kind." + kind.rawValue)).font(.headline)
                                if let title = state.playKit[kind.rawValue]["title"].text, !title.isEmpty { Text(verbatim: title).font(.subheadline) }
                                if PlayKitScreenProjection(kind: kind, segment: state.playKit[kind.rawValue]).complete { Text("playkit.result.recorded").font(.caption) }
                            }
                        }.accessibilityIdentifier("playkit.open." + kind.rawValue)
                    }
                }
                // Existing non-screen kits remain explicitly distinct from this migration.
                ForEach((state.playKit.object ?? [:]).keys.filter { PlayKitScreenKind(rawValue: $0) == nil }.sorted(), id: \.self) { kind in
                    Section {
                        Text(verbatim: state.playKit[kind]["title"].text ?? kind).font(.headline)
                        if let description = state.playKit[kind]["description"].text { Text(verbatim: description) }
                        Text("playx.advanced.specialGate").font(.footnote)
                    }
                }
                if state.isMultiplayer {
                    Section("playx.advanced.roles") {
                        ForEach(Array((state.multiplayer["members"].array ?? []).enumerated()), id: \.offset) { _, member in
                            Text(verbatim: member["name"].text ?? member["memberId"].integer.map(String.init) ?? "—")
                        }
                        Text("playx.advanced.turnsNotice").font(.footnote)
                    }
                }
            }
        }.privacySensitive().navigationTitle("playx.advanced").accessibilityIdentifier("playx.advanced.view")
    }
}
