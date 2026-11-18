import SwiftUI

/// F01 hint ladder panel: level 1, level 2, answer in author order; skip alone on the
/// last row. Every content line comes from a server receipt. Re-reading is free.
@MainActor struct PlayHelpPanelView: View {
    let help: PlayHelpCoordinator
    var approvedArtworkHosts: Set<String> = []
    var onSkipped: (PlayHelpSkipReceipt) -> Void = { _ in }
    @State private var confirmSkip = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let left = help.view?.remainingFreeUses, left > 0 {
                    Text("playhelp.freeLeft \(left)").font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    ForEach(help.view?.rows ?? []) { row in
                        Button { Task { await help.use(row) } } label: { rowLabel(row) }
                            .disabled(help.busy || !(row.canRequest || help.unknownLevels.contains(row.level)))
                            .accessibilityIdentifier("playhelp.row.\(row.level)")
                    }
                }
                if let notice = help.notice {
                    Text(verbatim: notice).font(.footnote).foregroundStyle(.red)
                        .accessibilityIdentifier("playhelp.notice")
                }
                if help.view?.skipLevel != nil || help.skipUnknown {
                    Section {
                        Button(role: .destructive) { confirmSkip = true } label: {
                            HStack {
                                Text("playhelp.skip")
                                Spacer()
                                if help.skipUnknown { Text("playhelp.action.unknown").foregroundStyle(.secondary) }
                            }
                        }
                        .disabled(help.busy)
                        .accessibilityIdentifier("playhelp.skip")
                    }
                }
            }
            .navigationTitle(Text("playhelp.title"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("playhelp.close") { dismiss() } } }
            .confirmationDialog("playhelp.skip.title", isPresented: $confirmSkip, titleVisibility: .visible) {
                Button("playhelp.skip.confirm", role: .destructive) {
                    Task { if let receipt = await help.skip() { onSkipped(receipt); dismiss() } }
                }
                Button("playhelp.cancel", role: .cancel) {}
            } message: { Text("playhelp.skip.message") }
            .task { await help.load() }
        }
        .privacySensitive()
    }

    @ViewBuilder private func rowLabel(_ row: PlayHelpRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(LocalizedStringKey("playhelp.type." + row.type))
                Spacer()
                actionText(row).foregroundStyle(.secondary)
            }
            if let content = help.contents[row.level] {
                if row.type == "IMAGE" { PlayKitArtwork(source: content, approvedHosts: approvedArtworkHosts) }
                else { Text(verbatim: content).textSelection(.enabled) }
            }
        }
    }

    private func actionText(_ row: PlayHelpRow) -> Text {
        if help.unknownLevels.contains(row.level) { return Text("playhelp.action.unknown") }
        switch row.state {
        case .review: return Text("playhelp.action.review")
        case .gated: return Text("playhelp.action.gated")
        case .free: return Text("playhelp.action.free")
        case .cost: return Text("playhelp.action.cost \(row.cost)")
        case .unavailable: return Text("playhelp.action.unavailable")
        }
    }
}
