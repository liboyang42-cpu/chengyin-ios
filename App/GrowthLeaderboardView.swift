import SwiftUI

@MainActor struct GrowthLeaderboardView: View {
    let reader: any GrowthCenterReading
    @State private var query = GrowthBoardQuery()
    @StateObject private var model = GrowthCenterScreenModel<GrowthLeaderboard>()
    private var key: GrowthCenterLoadKey { GrowthCenterLoadKey(scope: reader.scope, query: query) }
    var body: some View {
        List {
            if reader.isOfflineExample { Text("growth.offlineExample").font(.caption) }
            Section {
                Picker("growth.board.metric", selection: $query.metric) {
                    ForEach(GrowthBoardMetric.allCases) { option in Text(LocalizedStringKey("growth.metric." + option.rawValue)).tag(option) }
                }.pickerStyle(.menu).accessibilityIdentifier("growth.board.metric")
                Picker("growth.board.period", selection: $query.period) {
                    ForEach(GrowthBoardPeriod.allCases) { option in Text(LocalizedStringKey("growth.period." + option.rawValue)).tag(option) }
                }.pickerStyle(.menu).accessibilityIdentifier("growth.board.period")
            }
            if !reader.isAuthenticated { GrowthCenterIssueView(issue: .login) }
            else if !reader.isConfigured { GrowthCenterIssueView(issue: .notConfigured) }
            else if model.isLoading || model.loadedKey != key { ProgressView("growth.loading") }
            else if let issue = model.issue(key: key) { GrowthCenterIssueView(issue: issue, retry: { Task { await load() } }) }
            else if let board = model.value(key: key) {
                if let rank = board.me.rank {
                    Section("growth.myRank") { GrowthLeaderboardRow(entry: board.me, fallback: "growth.me", metric: board.metric).accessibilityIdentifier("growth.board.me.\(rank)") }
                }
                if board.list.isEmpty {
                    ContentUnavailableView("growth.board.empty", systemImage: "list.number", description: Text("growth.board.emptyHint"))
                        .accessibilityIdentifier("growth.board.empty")
                } else {
                    Section("growth.board.leaders") {
                        ForEach(Array(board.list.enumerated()), id: \.offset) { index, row in
                            GrowthLeaderboardRow(entry: row, fallback: "growth.explorer", metric: board.metric)
                                .accessibilityIdentifier("growth.board.row.\(index)")
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .appNavigationTitle("growth.board.title")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await load() } } label: { Label("growth.refresh", systemImage: "arrow.clockwise") }
                    .disabled(model.isLoading || !reader.isAuthenticated || !reader.isConfigured)
                    .accessibilityIdentifier("growth.board.refresh")
            }
        }
        .modifier(GrowthCenterReadLifecycle(key: key, refresh: load, cancel: model.cancelPending))
    }
    private func load() async {
        guard reader.isAuthenticated, reader.isConfigured else { model.invalidate(); return }
        let captured = key, requested = query
        await model.load(key: captured, currentKey: { key }) { try await reader.leaderboard(query: requested) }
    }
}
private struct GrowthLeaderboardRow: View {
    let entry: GrowthLeaderboardEntry
    let fallback: LocalizedStringKey
    let metric: GrowthBoardMetric
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GrowthCenterName(name: entry.nickname, fallback: fallback).font(.headline).fixedSize(horizontal: false, vertical: true)
            LabeledContent("growth.rank") {
                if let rank = entry.rank { Text(rank, format: .number).monospacedDigit() }
                else { Text("growth.unranked") }
            }
            LabeledContent(LocalizedStringKey("growth.unit." + metric.rawValue)) { GrowthCenterInteger(value: entry.score) }
            if let percentage = GrowthCenterFormatting.nonempty(entry.rankPercentage) { Text(verbatim: percentage).font(.caption).foregroundStyle(.secondary) }
        }.accessibilityElement(children: .combine).padding(.vertical, 4)
    }
}
