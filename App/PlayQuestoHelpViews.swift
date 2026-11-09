import SwiftUI

// Native SwiftUI port of the mini-program help ladder (UG-05..09). Structure follows the
// mini-program panel; visuals follow iOS sheets (system materials, grouped rows, detents).
// Every number and state here is a server fact from PlayHelpView / PlayHelpUse / PlayHelpReceipt.

func questoText(_ key: String) -> Text { Text(LocalizedStringKey("playQuesto." + key), tableName: "PlayQuesto") }

/// Bottom sheet listing the frozen layers in author order. Opened from the node's 提示 row.
@MainActor struct PlayHelpPanelSheet: View {
    enum Load: Equatable { case loading, ready(PlayHelpView), unavailable }
    let load: Load
    /// Content the server already approved for this run (level → use receipt). Re-view is free.
    let revealed: [Int: PlayHelpUse]
    /// Levels whose write result is unknown: only "继续核对" with the same requestId is offered.
    let pending: Set<Int>
    let refusal: PlayHelpRefusal?
    let onUse: (PlayHelpLayer) -> Void
    let onCheck: (Int) -> Void
    let onSkip: () -> Void
    @State private var confirming: PlayHelpLayer?
    @State private var confirmingSkip = false

    var body: some View {
        NavigationStack {
            List {
                switch load {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity)
                case .unavailable:
                    // Panel failure keeps the question; it never blocks answering.
                    questoText("help.unavailable").foregroundStyle(.secondary)
                case .ready(let view):
                    Section {
                        ForEach(view.hintLayers) { layer in row(layer, in: view) }
                    }
                    if let refusal {
                        Section { refusalText(refusal).font(.footnote).foregroundStyle(.red) }
                    }
                    if view.skipAvailable {
                        Section {
                            Button(role: .destructive) { confirmingSkip = true } label: { questoText("skip.action") }
                                .frame(minHeight: 44)
                                .accessibilityIdentifier("playQuesto.skip")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(Text(LocalizedStringKey("playQuesto.help.title"), tableName: "PlayQuesto"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .confirmationDialog(Text(LocalizedStringKey("playQuesto.help.confirmTitle"), tableName: "PlayQuesto"),
                            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                            titleVisibility: .visible, presenting: confirming) { layer in
            Button { onUse(layer); confirming = nil } label: { confirmLabel(layer) }
            Button(role: .cancel) { confirming = nil } label: { questoText("common.cancel") }
        }
        .confirmationDialog(Text(LocalizedStringKey("playQuesto.skip.confirmTitle"), tableName: "PlayQuesto"),
                            isPresented: $confirmingSkip, titleVisibility: .visible) {
            Button(role: .destructive) { onSkip() } label: { questoText("skip.confirm") }
            Button(role: .cancel) {} label: { questoText("common.cancel") }
        } message: { questoText("skip.consequence") }
    }

    @ViewBuilder private func row(_ layer: PlayHelpLayer, in view: PlayHelpView) -> some View {
        let state = view.state(of: layer)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                questoText("help.type." + layer.type.key).font(.body.weight(.semibold))
                Spacer(minLength: 12)
                if pending.contains(layer.level) {
                    Button { onCheck(layer.level) } label: { questoText("unknown.check") }
                        .buttonStyle(.bordered)
                } else {
                    button(layer, state: state)
                }
            }
            if pending.contains(layer.level) {
                questoText("unknown.pending").font(.footnote).foregroundStyle(.secondary)
            } else if let use = revealed[layer.level] {
                PlayHelpContentView(use: use)
            }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("playQuesto.help.level." + String(layer.level))
    }

    @ViewBuilder private func button(_ layer: PlayHelpLayer, state: PlayHelpLayer.ButtonState) -> some View {
        switch state {
        case .review:
            // Re-view is free and never asks to confirm a charge.
            Button { onUse(layer) } label: { questoText("help.review") }.buttonStyle(.bordered)
        case .free:
            Button { confirming = layer } label: { questoText("help.free") }.buttonStyle(.borderedProminent).tint(.green)
        case .cost(let points):
            Button { confirming = layer } label: { Text("playQuesto.help.cost \(points)", tableName: "PlayQuesto") }
                .buttonStyle(.borderedProminent)
        case .needsPrevious:
            questoText("help.needsPrevious").font(.footnote).foregroundStyle(.secondary)
        case .unavailable:
            questoText("help.unavailableLayer").font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func confirmLabel(_ layer: PlayHelpLayer) -> Text {
        if layer.free || layer.costPoints == 0 { return questoText("help.confirmFree") }
        return Text("playQuesto.help.confirmCost \(layer.costPoints)", tableName: "PlayQuesto")
    }

    private func refusalText(_ refusal: PlayHelpRefusal) -> Text {
        if refusal.pointsInsufficient { return questoText("help.pointsInsufficient") }
        // Backend message mirrored verbatim; never reworded.
        if let message = refusal.message, !message.isEmpty { return Text(verbatim: message) }
        return questoText("help.unavailable")
    }
}

/// Renders exactly the approved layer content by server `type`. Unknown types render nothing.
struct PlayHelpContentView: View {
    let use: PlayHelpUse
    var body: some View {
        Group {
            switch use.type {
            case .text, .answer:
                Text(verbatim: use.content).font(.body).textSelection(.enabled)
            case .letter, .digit:
                Text(verbatim: use.content).font(.title2.monospaced().weight(.semibold))
            case .image:
                if let url = PlayChoiceOption.safeImage(use.content, baseURL: nil) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image { image.resizable().scaledToFit() }
                        else if phase.error != nil { questoText("media.imageFailed").font(.footnote).foregroundStyle(.secondary) }
                        else { ProgressView() }
                    }
                    .frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            case .skip, .unsupported:
                EmptyView()
            }
            if use.showsCharge {
                Text("playQuesto.help.charged \(use.chargedPoints)", tableName: "PlayQuesto")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

/// UG-07 score detail, folded. NOT_SCORED never shows 0; points and puzzle score never mix.
struct PlayHelpReceiptSection: View {
    let receipt: PlayHelpReceipt?
    let failed: Bool
    @State private var expanded = false
    var body: some View {
        if failed {
            questoText("receipt.unavailable").foregroundStyle(.secondary)
        } else if let receipt {
            DisclosureGroup(isExpanded: $expanded) {
                if receipt.showsScore {
                    if receipt.baseScore != nil { line("receipt.base", receipt.baseScore) }
                    if let bonus = receipt.bonus, bonus != 0 { line("receipt.bonus", bonus) }
                    if let help = receipt.helpDeduction, help != 0 { line("receipt.helpDeduction", -help) }
                    if let skip = receipt.skipDeduction, skip != 0 { line("receipt.skipDeduction", -skip) }
                } else {
                    questoText("receipt.notScored")
                }
                if let points = receipt.pointsCharged, points > 0 {
                    LabeledContent { Text(verbatim: String(points)).monospacedDigit() } label: { questoText("receipt.pointsCharged") }
                }
                if receipt.skipped { questoText("receipt.skipped") }
                else if receipt.assisted { questoText("receipt.revealed") }
                // Net score present but its breakdown missing: show 明细待补, never fill rows with 0.
                if receipt.showsScore && receipt.baseScore == nil { questoText("receipt.detailPending").foregroundStyle(.secondary) }
            } label: {
                HStack {
                    questoText("receipt.title")
                    Spacer()
                    if receipt.showsScore, let net = receipt.netScore { Text(verbatim: String(net)).monospacedDigit().font(.headline) }
                    else { questoText("receipt.notScoredShort").foregroundStyle(.secondary) }
                }
            }
        }
    }
    private func line(_ key: String, _ value: Int?) -> some View {
        LabeledContent { Text(verbatim: value.map { String($0) } ?? "—").monospacedDigit() } label: { questoText(key) }
    }
}

/// UG-08: the 已跳过 tag on a question card. No success animation or reward copy anywhere.
struct PlaySkippedTag: View {
    var body: some View {
        Label { questoText("skip.tag") } icon: { Image(systemName: "forward.end") }
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(.thinMaterial, in: Capsule())
            .accessibilityIdentifier("playQuesto.skippedTag")
    }
}

#if DEBUG
#Preview("Help panel") {
    let view = try! PlayHelpView(data: .object([
        "runId": .integer(9), "nodeId": .integer(3), "enabled": .bool(true),
        "layers": .array([
            .object(["level": .integer(1), "type": .string("TEXT"), "usable": .bool(true), "unlocked": .bool(true), "free": .bool(true), "costPoints": .integer(0), "freeQuota": .integer(0), "reason": .string("OK")]),
            .object(["level": .integer(2), "type": .string("LETTER"), "usable": .bool(true), "unlocked": .bool(false), "free": .bool(false), "costPoints": .integer(20), "freeQuota": .integer(0), "reason": .string("OK")]),
            .object(["level": .integer(3), "type": .string("ANSWER"), "usable": .bool(true), "unlocked": .bool(false), "free": .bool(false), "costPoints": .integer(40), "freeQuota": .integer(0), "reason": .string("OK")]),
            .object(["level": .integer(4), "type": .string("SKIP"), "usable": .bool(true), "unlocked": .bool(false), "free": .bool(false), "costPoints": .integer(0), "freeQuota": .integer(0), "reason": .string("OK")])
        ])
    ]))
    return Color.black.sheet(isPresented: .constant(true)) {
        PlayHelpPanelSheet(load: .ready(view), revealed: [:], pending: [], refusal: nil, onUse: { _ in }, onCheck: { _ in }, onSkip: {})
    }.preferredColorScheme(.dark)
}
#endif
