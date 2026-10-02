import SwiftUI

@MainActor struct GrowthCenterView: View {
    let reader: any GrowthCenterReading
    @StateObject private var model = GrowthCenterScreenModel<GrowthCenterOverview>()
    private var key: GrowthCenterLoadKey { GrowthCenterLoadKey(scope: reader.scope) }
    var body: some View {
        List {
            if reader.isOfflineExample { Text("growth.offlineExample").font(.caption) }
            if !reader.isAuthenticated { GrowthCenterIssueView(issue: .login) }
            else if !reader.isConfigured { GrowthCenterIssueView(issue: .notConfigured) }
            else if model.isLoading || model.loadedKey != key { ProgressView("growth.loading") }
            else if let issue = model.issue(key: key) { GrowthCenterIssueView(issue: issue, retry: { Task { await load() } }) }
            else if let overview = model.value(key: key) {
                score(overview)
                footprint(overview)
                badges(overview)
                if let center = overview.center.value, !center.missions.isEmpty {
                    Section {
                        ForEach(Array(center.missions.enumerated()), id: \.offset) { _, mission in
                            VStack(alignment: .leading, spacing: 6) {
                                GrowthCenterName(name: mission.name, fallback: "growth.mission.unnamed").font(.headline)
                                if let text = GrowthCenterFormatting.nonempty(mission.description) { Text(verbatim: text).foregroundStyle(.secondary) }
                                LabeledContent("growth.mission.experience") { GrowthCenterInteger(value: mission.experienceReward) }
                            }.fixedSize(horizontal: false, vertical: true)
                        }
                    } header: { Text("growth.missions") } footer: { Text("growth.missions.readOnly") }
                }
            }
        }
        .listStyle(.insetGrouped)
        .appNavigationTitle("growth.title")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await load() } } label: { Label("growth.refresh", systemImage: "arrow.clockwise") }
                    .disabled(model.isLoading || !reader.isAuthenticated || !reader.isConfigured)
                    .accessibilityIdentifier("growth.refresh")
            }
        }
        .modifier(GrowthCenterReadLifecycle(key: key, refresh: load, cancel: model.cancelPending))
    }
    @ViewBuilder private func score(_ overview: GrowthCenterOverview) -> some View {
        Section("growth.score") {
            if let board = overview.rank.value {
                LabeledContent("growth.currentPoints") { GrowthCenterInteger(value: board.me.score).font(.title2.bold()) }
                    .accessibilityIdentifier("growth.points")
                LabeledContent("growth.myRank") {
                    if let rank = board.me.rank { Text(rank, format: .number).monospacedDigit() }
                    else { Text("growth.unranked") }
                }.accessibilityIdentifier("growth.myRank")
                if let percentage = GrowthCenterFormatting.nonempty(board.me.rankPercentage) { Text(verbatim: percentage).font(.caption) }
            } else if let issue = overview.rank.issue { GrowthCenterIssueView(issue: issue) }
            NavigationLink { GrowthLeaderboardView(reader: reader) } label: {
                Label("growth.board.title", systemImage: "list.number")
            }.accessibilityIdentifier("growth.openLeaderboard")
        }
    }
    @ViewBuilder private func footprint(_ overview: GrowthCenterOverview) -> some View {
        Section("growth.overview") {
            LabeledContent("growth.level") { GrowthCenterInteger(value: GrowthCenterFormatting.nonnegative(overview.center.value?.level).map { max(1, $0) }) }
            LabeledContent("growth.experience") { GrowthCenterInteger(value: overview.center.value?.experience) }.accessibilityIdentifier("growth.experience")
            LabeledContent("growth.badgeCount") { GrowthCenterInteger(value: overview.center.value?.badges.count) }
            LabeledContent("growth.completedTopics") { GrowthCenterInteger(value: overview.completedTopicCount) }.accessibilityIdentifier("growth.completedTopics")
            LabeledContent("growth.mileage") {
                if let mileage = GrowthCenterFormatting.mileage(overview.progress.value?.totalMileage) {
                    Text(mileage, format: .number.precision(.fractionLength(0...1))).monospacedDigit()
                } else { Text("growth.unknown").accessibilityLabel(Text("growth.unknownValue")) }
            }.accessibilityIdentifier("growth.mileage")
            if let issue = overview.progress.issue { GrowthCenterIssueView(issue: issue) }
            if let issue = overview.completed.issue { GrowthCenterIssueView(issue: issue) }
        }
    }
    @ViewBuilder private func badges(_ overview: GrowthCenterOverview) -> some View {
        Section("growth.badges") {
            if let issue = overview.center.issue { GrowthCenterIssueView(issue: issue, retry: { Task { await load() } }) }
            else if let center = overview.center.value {
                if center.badges.isEmpty { Text("growth.badges.empty").foregroundStyle(.secondary).accessibilityIdentifier("growth.badges.empty") }
                ForEach(Array(center.badges.enumerated()), id: \.offset) { index, badge in
                    if let moment = GrowthCenterFormatting.badgeMoment(badge.obtainedAt) {
                        DisclosureGroup {
                            LabeledContent("growth.badge.obtained") { Text(verbatim: moment).monospacedDigit() }
                            Text("growth.badge.timezone").font(.caption).foregroundStyle(.secondary)
                        } label: {
                            Label { GrowthCenterName(name: badge.displayName, fallback: "growth.badge.unnamed") } icon: { Image(systemName: "medal").accessibilityHidden(true) }
                        }.accessibilityIdentifier("growth.badge.\(index)")
                    } else {
                        Label { GrowthCenterName(name: badge.displayName, fallback: "growth.badge.unnamed") } icon: { Image(systemName: "medal").accessibilityHidden(true) }
                            .accessibilityIdentifier("growth.badge.\(index)")
                    }
                }
            }
        }
    }
    private func load() async {
        guard reader.isAuthenticated, reader.isConfigured else { model.invalidate(); return }
        let captured = key
        await model.load(key: captured, currentKey: { key }) { try await reader.overview() }
    }
}
