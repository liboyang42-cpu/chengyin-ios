import SwiftUI

extension PlayKitScreen {
    @ViewBuilder var legacyBody: some View {
        switch kind {
        case .blindTaste: blindTasteBody
        case .diyName: namingBody
        case .slowTask: PlayKitSlowTaskBody(segment: raw, enabled: enabled, requestReview: prepare)
        case .musicCorner:
            if let track = raw["trackName"].text { Text(verbatim: track).font(.title2.bold()) }
            if let seconds = raw["durationSeconds"].integer, seconds > 0 { LabeledContent("playkitLegacy.music.duration") { Text(verbatim: "\(seconds) s") } }
            PlatformAudioHost(rawURL: raw["audioUrl"].text, scope: mediaScope, makeModel: makeAudio)
            Text("playkitLegacy.music.boundary").font(.footnote)
        case .silentOrder:
            PlayKitSilentOrderBody(segment: raw, active: model.isCurrent, onDirty: { dirty = true })
            if let qr = raw["qrUrl"].text, !qr.isEmpty { artwork(qr) }
            else { Label("playkitLegacy.silent.noWitnessCode", systemImage: "qrcode") }
        case .timeWindow:
            LabeledContent("playkitLegacy.window.opens") { Text(verbatim: raw["openFrom"].text ?? "—") }
            LabeledContent("playkitLegacy.window.closes") { Text(verbatim: raw["openTo"].text ?? "—") }
            Text("playkitLegacy.window.authority").font(.footnote)
            if raw["subscribed"].bool == true { Label("playkitLegacy.window.subscribed", systemImage: "bell.badge") }
            Text("playkitLegacy.window.providerGate").font(.footnote)
            Button("playkitLegacy.window.subscribe") {}.disabled(true)
        default: EmptyView()
        }
    }
    @ViewBuilder private var blindTasteBody: some View {
        if let steps = raw["steps"].text, !steps.isEmpty { Text(verbatim: steps) }
        if let steps = raw["steps"].array {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, value in
                if let line = value.text { HStack(alignment: .top) { Text(verbatim: String(index + 1)); Text(verbatim: line) } }
            }
        }
        Text("playkitLegacy.blind.instructions").font(.footnote)
        ForEach(projection.options) { option in
            Button { selected = [option.id]; dirty = true } label: {
                HStack { Image(systemName: selected.contains(option.id) ? "checkmark.circle.fill" : "circle"); Text(verbatim: option.label) }
            }.buttonStyle(.bordered).disabled(!enabled)
        }
        if raw["solved"].bool == true { Text("playkit.result.passed") }
        else if (raw["attempts"].integer ?? 0) > 0 { Text("playkitLegacy.blind.tryAgain") }
        attempts
        submitButton("SUBMIT_BLIND_TASTE", payload: ["key": .string(selected.first ?? "")], valid: !selected.isEmpty)
    }
    @ViewBuilder private var namingBody: some View {
        let maxLength = max(1, raw["maxLength"].integer ?? 16)
        ForEach(Array((raw["suggestions"].array ?? []).enumerated()), id: \.offset) { _, value in
            if let suggestion = value.text { Button { text = PlayKitInputContract.limitText(suggestion, toUTF16: maxLength); dirty = true } label: { Text(verbatim: suggestion) }.disabled(!enabled) }
        }
        TextField("playkitLegacy.name.placeholder", text: textBinding(limit: maxLength), axis: .vertical).textFieldStyle(.roundedBorder).disabled(!enabled)
        LabeledContent("playkit.characters") { Text(verbatim: "\(text.utf16.count) / \(maxLength)") }
        Text("playkitLegacy.name.audience").font(.footnote)
        submitButton("SUBMIT_DIY_NAME", payload: ["name": .string(text.trimmingCharacters(in: .whitespacesAndNewlines))], valid: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}

@MainActor struct PlayKitSlowTaskBody: View {
    let segment: PlayWireValue; let enabled: Bool; let requestReview: PlayKitReviewRequest
    @State private var revealed = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if segment["claimed"].bool == true {
                if revealed {
                    if let text = segment["unlockText"].text, !text.isEmpty { Text(verbatim: text).font(.title3) }
                    else { Text("playkitLegacy.slow.emptyReadback") }
                } else { Button("playkitLegacy.slow.reveal") { revealed = true }.buttonStyle(.borderedProminent) }
            } else if segment["started"].bool == true {
                if let days = segment["daysLeft"].integer, days > 0 {
                    LabeledContent("playkitLegacy.slow.daysLeft") { Text(verbatim: String(days)) }
                    if let hint = segment["waitHint"].text, !hint.isEmpty { Text(verbatim: hint) }
                } else if segment["daysLeft"].integer == 0 {
                    Text("playkitLegacy.slow.ready")
                    Button { requestReview("CLAIM_SLOW_TASK", [:], {}) } label: {
                        if let label = segment["unlockLabel"].text, !label.isEmpty { Text(verbatim: label) } else { Text("playkitLegacy.slow.claim") }
                    }.buttonStyle(.borderedProminent).disabled(!enabled)
                } else { Text("playkit.configurationInvalid") }
            } else {
                if let hint = segment["startHint"].text, !hint.isEmpty { Text(verbatim: hint) }
                Button { requestReview("START_SLOW_TASK", [:], {}) } label: {
                    if let label = segment["startLabel"].text, !label.isEmpty { Text(verbatim: label) } else { Text("playkitLegacy.slow.start") }
                }.buttonStyle(.borderedProminent).disabled(!enabled)
            }
            Text("playkitLegacy.slow.authority").font(.footnote)
        }
    }
}

/// A foreground companion clock, not challenge evidence. There is intentionally
/// no action callback and no completion, score or reward mutation.
@MainActor struct PlayKitSilentOrderBody: View {
    let segment: PlayWireValue; let active: Bool; let onDirty: () -> Void
    @State private var startedAt: TimeInterval?
    @State private var elapsed = 0
    @State private var gaveUp = false
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let rule = segment["rule"].text, !rule.isEmpty { Text(verbatim: rule).font(.title3) }
            Text("playkitLegacy.silent.boundary").font(.footnote)
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let seconds = elapsed + (startedAt.map { Int(max(0, ProcessInfo.processInfo.systemUptime - $0)) } ?? 0)
                LabeledContent("playkitLegacy.silent.elapsed") { Text(verbatim: String(format: "%02d:%02d", seconds / 60, seconds % 60)).monospacedDigit() }
            }
            if gaveUp { Text("playkitLegacy.silent.stopped") }
            else if startedAt == nil {
                Button("playkitLegacy.silent.start") { startedAt = ProcessInfo.processInfo.systemUptime; onDirty() }.disabled(!active)
            } else {
                Button("playkitLegacy.silent.giveUp", role: .destructive) { stop(); gaveUp = true }.disabled(!active)
            }
        }
        .onAppear { elapsed = max(0, segment["elapsedSeconds"].integer ?? 0) }
        .onChange(of: active) { _, value in if !value { stop() } }
        .onChange(of: scenePhase) { _, value in if value != .active { stop() } }
        .onDisappear { stop() }
    }
    private func stop() { if let startedAt { elapsed += Int(max(0, ProcessInfo.processInfo.systemUptime - startedAt)); self.startedAt = nil } }
}
