import SwiftUI

/// The existing phase remains separate from progress. A full bar is not a new success event.
struct PlayTaskSummaryView: View {
    @Environment(\.themeDomain) private var domain
    let snapshot: PlaySnapshot
    let phase: String
    @State private var branchHistorySelection: PlayBranchHistorySelection?
    @QuestifyReduceMotion private var reduceMotion
    @Environment(\.locale) private var locale
    private var summary: PlayTaskSummaryPresentation { .init(snapshot: snapshot) }
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s2) {
            if let title = snapshot.result.topicName { Text(verbatim: title).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader) }
            LabeledContent("playx.state") { PlayRuntimePhaseText(phase: phase) }
                .font(.subheadline).foregroundStyle(.secondary)
            if let done = summary.completed, let total = summary.total, let fraction = summary.fraction {
                Text(verbatim: String(format: appLocalized("referenceTask.completedCount", locale: locale), locale: locale, done, total))
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                    .accessibilityIdentifier("referenceTask.count")
                ProgressView(value: fraction)
                    .accessibilityLabel(Text("playx.progress"))
                    .accessibilityValue(Text(verbatim: String(format: appLocalized("referenceTask.completedCount", locale: locale), locale: locale, done, total)))
                    .accessibilityIdentifier("referenceTask.progress")
                    .transaction { if reduceMotion { $0.animation = nil } }
            } else {
                Text("referenceTask.phaseOnly").font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier("referenceTask.phaseOnly")
            }
            if let selection = PlayBranchHistorySelection(snapshot: snapshot), phase == "ready" || phase == "unknown" {
                Button { branchHistorySelection = selection } label: {
                    Label(branchHistoryLocalized("branchHistory.open", locale: locale), systemImage: "list.bullet.rectangle")
                        .fixedSize(horizontal: false, vertical: true)
                }.accessibilityIdentifier("branchHistory.open")
            }
        }
        .font(Theme.Font.body)
        .foregroundStyle(Theme.Color.textPrimary(in: domain))
        .tint(Theme.Color.accent(in: domain))
        .accessibilityElement(children: .contain)
        .sheet(item: $branchHistorySelection) { selection in
            PlayBranchHistoryView(history: selection.presentation(snapshot: snapshot))
        }
        .onChange(of: PlayBranchHistorySelection(snapshot: snapshot)) { _, current in
            if current != branchHistorySelection { branchHistorySelection = nil }
        }
        .onDisappear { branchHistorySelection = nil }
        .onChange(of: phase) { _, value in
            if value != "ready" && value != "unknown" { branchHistorySelection = nil }
        }
    }
}

struct PlayTaskStatusBadge: View {
    let node: PlayNode
    let snapshot: PlaySnapshot
    private var status: PlayTaskStatusPresentation { .init(node: node, snapshot: snapshot) }
    var body: some View {
        QuestifyStatusBadge(title: LocalizedStringKey(status.labelKey), systemImage: status.symbol,
                            emphasized: status == .available, stateKey: status.rawValue)
            .accessibilityIdentifier("referenceTask.status.\(node.id)")
    }
}
