import SwiftUI

/// The opt-in game-session leaderboard is distinct from the companion and
/// advanced-game boards. It has no team drill-down or reward action.
struct PlayPlayerLeaderboardView: View {
    let state: PlayPlayerLeaderboardState
    var body: some View {
        Group {
            switch state {
            case .hidden: EmptyView()
            case .unconfirmed:
                Section("playerLeaderboard.title") {
                    Text("playerLeaderboard.unconfirmed").font(.footnote).foregroundStyle(.secondary)
                        .accessibilityIdentifier("playerLeaderboard.unconfirmed")
                }
            case .empty:
                Section("playerLeaderboard.title") {
                    Text("playerLeaderboard.empty").foregroundStyle(.secondary)
                        .accessibilityIdentifier("playerLeaderboard.empty")
                }
            case .entries(let entries):
                Section {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 6) {
                            LabeledContent("playerLeaderboard.rank") { Text(verbatim: String(entry.rank)) }
                            if let name = entry.displayName { Text(verbatim: name).font(.headline) }
                            else { Text("playerLeaderboard.team").font(.headline) }
                            LabeledContent("playerLeaderboard.score") { Text(verbatim: String(entry.score)) }
                        }.fixedSize(horizontal: false, vertical: true)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("playerLeaderboard.team.\(entry.id)")
                    }
                } header: {
                    Text("playerLeaderboard.title")
                } footer: {
                    Text("playerLeaderboard.metric")
                }
            }
        }.privacySensitive().accessibilityIdentifier("playerLeaderboard.readback")
    }
}
