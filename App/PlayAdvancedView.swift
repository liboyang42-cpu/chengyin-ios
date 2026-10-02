import SwiftUI

@MainActor struct PlayAdvancedView: View {
    @Bindable var model: PlayAdvancedCoordinator
    let onReady: (PlayAdvancedState) -> Void
    @State private var reviewAction: String?
    @State private var reviewKind: String?
    @State private var reviewPayload: [String: PlayWireValue] = [:]
    @State private var showReview = false
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
                    if state.needsUnverifiedSteps { Text("playx.advanced.stepsGate") }
                    if state.readyForBase {
                        Button("playx.advanced.continue") { onReady(state); dismiss() }.accessibilityIdentifier("playx.advanced.continue")
                    }
                }
                ForEach(Array(state.draws.enumerated()), id: \.offset) { _, draw in
                    Section { if let label = draw["label"].text { Text(verbatim: label).font(.headline) }; if let content = draw["content"].text { Text(verbatim: content) } }
                }
                if state.config["random"]["enabled"].bool == true { Section { actionButton("playx.advanced.draw", kind: "random", action: "DRAW") } }
                if state.config["branch"]["enabled"].bool == true {
                    Section("playx.advanced.branch") {
                        if let title = state.branch["currentStep"]["title"].text { Text(verbatim: title).font(.headline) }
                        if let body = state.branch["currentStep"]["body"].text { Text(verbatim: body) }
                        ForEach(Array((state.branch["currentStep"]["options"].array ?? []).enumerated()), id: \.offset) { _, option in
                            if let id = option["id"].text, let label = option["label"].text {
                                Button { prepare(kind: "branch", action: "CHOOSE", payload: ["optionId": .string(id)]) } label: { Text(verbatim: label) }
                                    .disabled(model.phase != "ready").accessibilityIdentifier("playx.advanced.choice.\(id)")
                            }
                        }
                    }
                }
                ForEach((state.playKit.object ?? [:]).keys.sorted(), id: \.self) { kind in
                    Section {
                        Text(verbatim: state.playKit[kind]["title"].text ?? kind).font(.headline)
                        if let description = state.playKit[kind]["description"].text { Text(verbatim: description) }
                        if kind == "coinFlip" { actionButton("playx.advanced.coin", kind: kind, action: "FLIP_COIN") }
                        else if kind == "diceRoll" { actionButton("playx.advanced.dice", kind: kind, action: "ROLL_DICE") }
                        else if kind == "dailySign" { actionButton("playx.advanced.sign", kind: kind, action: "CLAIM_DAILY_SIGN") }
                        else { Text("playx.advanced.specialGate").font(.footnote) }
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
            .confirmationDialog("playx.review", isPresented: $showReview, titleVisibility: .visible) {
                Button("playx.submit") {
                    if let kind = reviewKind, let action = reviewAction { Task { await model.submit(kind: kind, action: action, detail: reviewPayload) } }
                }
            } message: { Text("playx.advanced.review") }
    }
    private func actionButton(_ title: String, kind: String, action: String) -> some View {
        Button(LocalizedStringKey(title)) { prepare(kind: kind, action: action) }.disabled(model.phase != "ready")
    }
    private func prepare(kind: String, action: String, payload: [String: PlayWireValue] = [:]) {
        reviewKind = kind; reviewAction = action; reviewPayload = payload; showReview = true
    }
}
