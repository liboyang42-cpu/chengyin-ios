import SwiftUI

/// Optional ordinary-home navigation supplied by the account host. Nil leaves
/// the read surface usable without pretending to navigate or acquire location.
private struct GrowthExploreHomeActionKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}
extension EnvironmentValues {
    var growthExploreHomeAction: (() -> Void)? {
        get { self[GrowthExploreHomeActionKey.self] }
        set { self[GrowthExploreHomeActionKey.self] = newValue }
    }
}

@MainActor struct GrowthCenterView: View {
    let reader: any GrowthCenterReading
    @Environment(\.growthExploreHomeAction) private var onExploreHome
    @Environment(\.scenePhase) private var scenePhase
    @State private var badgePresentationID = UUID()
    @State private var badgeVisible = false
    @State private var badgeExploreConsumed = false
    @State private var latestReaderID: ObjectIdentifier?
    @State private var unlockTracker = GrowthBadgeUnlockTracker()
    @State private var unlockTrackerKey: GrowthCenterLoadKey?
    @State private var newlyLitBadges: [String] = []
    private var reads: GrowthNormalReadTask { model.overviewReads }
    @StateObject private var model = GrowthCenterScreenModel<GrowthCenterOverview>()
    private var key: GrowthCenterLoadKey { GrowthCenterLoadKey(scope: reader.scope) }
    var body: some View {
        List {
            if reader.isOfflineExample { Text("growth.offlineExample").font(.caption) }
            if !reader.isAuthenticated { GrowthCenterIssueView(issue: .login) }
            else if !reader.isConfigured { GrowthCenterIssueView(issue: .notConfigured) }
            else if model.isLoading || model.loadedKey != key {
                ProgressView("growth.loading").frame(maxWidth: .infinity, minHeight: 88).accessibilityIdentifier("growth.loading")
            }
            else if let issue = model.issue(key: key) { GrowthCenterIssueView(issue: issue, retry: reload) }
            else if let overview = model.value(key: key) {
                if !newlyLitBadges.isEmpty {
                    Section {
                        HStack(alignment: .top) {
                            Image(systemName: "sparkles").accessibilityHidden(true)
                            GrowthNewlyLitBadges(names: newlyLitBadges)
                        }
                        // The whole status is one announcement, never the SF Symbol's
                        // default "Sparkle" label instead of the newly earned badge names.
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(Text("growth.badges.newlyLit") + Text(verbatim: ": " + newlyLitBadges.formatted(.list(type: .and))))
                        .accessibilityIdentifier("growth.badges.newlyLit")
                    }
                }
                score(overview)
                footprint(overview)
                badges(overview)
                if let center = overview.center.value {
                    Section {
                        if center.missions.isEmpty {
                            Text("growthNormalEntry.missions.empty", tableName: "GrowthNormalEntry").foregroundStyle(.secondary)
                                .accessibilityIdentifier("growth.missions.empty")
                        }
                        ForEach(Array(center.missions.enumerated()), id: \.offset) { _, mission in
                            VStack(alignment: .leading, spacing: 6) {
                                GrowthCenterName(name: mission.name, fallback: "growth.mission.unnamed").font(.headline)
                                if let text = GrowthCenterFormatting.nonempty(mission.description) { Text(verbatim: text).foregroundStyle(.secondary) }
                                GrowthCenterMetricRow("growth.mission.experience") { GrowthCenterInteger(value: mission.experienceReward) }
                            }.fixedSize(horizontal: false, vertical: true)
                        }
                    } header: { Text("growth.missions") }
                }
            }
        }
        .listStyle(.insetGrouped)
        .appNavigationTitle("growth.title")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: reload) { Label("growth.refresh", systemImage: "arrow.clockwise") }
                    .disabled(model.isLoading || !reader.isAuthenticated || !reader.isConfigured)
                    .accessibilityIdentifier("growth.refresh")
            }
        }
        .modifier(GrowthCenterReadLifecycle(key: key, refresh: load, cancel: model.cancelPending))
        .onAppear { badgeVisible = true; badgeExploreConsumed = false; badgePresentationID = UUID(); latestReaderID = ObjectIdentifier(reader) }
        .onDisappear { badgeVisible = false; badgePresentationID = UUID() }
        .onChange(of: scenePhase) { _, _ in badgePresentationID = UUID() }
        .onChange(of: ObjectIdentifier(reader)) { _, value in latestReaderID = value; badgePresentationID = UUID() }
    }
    @ViewBuilder private func score(_ overview: GrowthCenterOverview) -> some View {
        Section("growth.score") {
            if let board = overview.rank.value {
                // Mini-program score card: the points are the one number that matters.
                LabeledContent("growth.currentPoints") {
                    GrowthCenterInteger(value: board.me.score).font(.system(size: 40, weight: .heavy, design: .rounded))
                        .lineLimit(1).minimumScaleFactor(0.5)
                }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("growth.currentPoints"))
                    .accessibilityValue(pointsValue(board.me.score))
                    .accessibilityIdentifier("growth.points")
                LabeledContent("growth.myRank") {
                    if let rank = board.me.rank { Text(rank, format: .number).monospacedDigit() }
                    else { Text("growth.unranked") }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("growth.myRank"))
                .accessibilityValue(rankValue(board.me.rank))
                .accessibilityIdentifier("growth.myRank")
                if let percentage = GrowthCenterFormatting.nonempty(board.me.rankPercentage) { Text(verbatim: percentage).font(.caption) }
            } else if let issue = overview.rank.issue {
                // Own-center points are not leaderboard score/rank and do not fall back
                // to the legacy identity-bearing leaderboard while that producer is HOLD.
                GrowthCenterMetricRow("profile.selfGrowth.points") { GrowthCenterInteger(value: overview.center.value?.points) }
                    .accessibilityIdentifier("growth.normal.points")
                if issue == .notConfigured { GrowthNormalLeaderboardHoldView() }
                else { GrowthCenterIssueView(issue: issue, retry: reload) }
            }
            NavigationLink { GrowthLeaderboardView(reader: reader) } label: {
                Label("growth.board.link", systemImage: "list.number")
            }.frame(minHeight: 44).accessibilityIdentifier("growth.openLeaderboard")
        }
    }
    @ViewBuilder private func footprint(_ overview: GrowthCenterOverview) -> some View {
        // 我的足迹 in the mini-program order: 探索值, 徽章, 完成主题, 累计距离; level sits in the header.
        Section {
            GrowthCenterMetricRow("growth.experience") { GrowthCenterInteger(value: overview.center.value?.experience) }.accessibilityIdentifier("growth.experience")
            GrowthCenterMetricRow("growth.badgeCount") { GrowthCenterInteger(value: overview.center.value?.badges.count) }
            GrowthCenterMetricRow("growth.completedTopics") { GrowthCenterInteger(value: overview.completedTopicCount) }.accessibilityIdentifier("growth.completedTopics")
            GrowthCenterMetricRow("growth.mileage") {
                if let mileage = GrowthCenterFormatting.mileage(overview.progress.value?.totalMileage) {
                    Text(mileage, format: .number.precision(.fractionLength(0...1))).monospacedDigit()
                } else { Text("growth.unknown").accessibilityLabel(Text("growth.unknownValue")) }
            }.accessibilityIdentifier("growth.mileage")
            GrowthCenterMetricRow("profile.selfGrowth.checkins") { GrowthCenterInteger(value: overview.progress.value?.totalCheckins) }
                .accessibilityIdentifier("growth.checkins")
            GrowthCenterMetricRow("profile.selfGrowth.streak") { GrowthCenterInteger(value: overview.progress.value?.streakDays) }
                .accessibilityIdentifier("growth.streak")
            if let issue = overview.progress.issue { GrowthCenterIssueView(issue: issue, retry: reload) }
            if let issue = overview.completed.issue { GrowthCenterIssueView(issue: issue, retry: reload) }
            else if let completed = overview.completed.value, completed.isEmpty {
                Text("growthNormalEntry.completed.empty", tableName: "GrowthNormalEntry").foregroundStyle(.secondary)
                    .accessibilityIdentifier("growth.completed.empty")
            }
        } header: {
            HStack {
                Text("growth.overview")
                Spacer(minLength: 8)
                if let level = GrowthCenterFormatting.nonnegative(overview.center.value?.level) {
                    Text("growth.level.value \(max(1, level))").monospacedDigit()
                }
            }
        }
    }
    @ViewBuilder private func badges(_ overview: GrowthCenterOverview) -> some View {
        Section("growth.badges") {
            if let issue = overview.center.issue { GrowthCenterIssueView(issue: issue, retry: reload) }
            else if let center = overview.center.value {
                if center.badges.isEmpty {
                    Text("growth.badges.empty").foregroundStyle(.secondary).accessibilityIdentifier("growth.badges.empty")
                    if let onExploreHome {
                        let selection = GrowthBadgeExploreSelection(readerID: ObjectIdentifier(reader), key: key,
                            center: center, presentationID: badgePresentationID)
                        Button("growthExplore.openHome") {
                            guard !badgeExploreConsumed, scenePhase == .active,
                                  selection.accepts(readerID: latestReaderID, key: key, center: model.value(key: key)?.center.value,
                                      presentationID: badgePresentationID, visible: badgeVisible,
                                      authenticated: reader.isAuthenticated, configured: reader.isConfigured,
                                      loading: model.isLoading, hasIssue: model.issue(key: key) != nil || model.value(key: key)?.center.issue != nil) else { return }
                            badgeExploreConsumed = true; badgePresentationID = UUID()
                            onExploreHome()
                        }.buttonStyle(.bordered).frame(minHeight: 44)
                            .disabled(badgeExploreConsumed || !badgeVisible || scenePhase != .active)
                            .accessibilityIdentifier("growthExplore.badges.openHome")
                    }
                }
                ForEach(Array(center.badges.enumerated()), id: \.offset) { index, badge in
                    if let moment = GrowthCenterFormatting.badgeMoment(badge.obtainedAt) {
                        DisclosureGroup {
                            LabeledContent("growth.badge.obtained") { Text(verbatim: moment).monospacedDigit() }
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
    private func pointsValue(_ value: Int?) -> Text {
        if let value = GrowthCenterFormatting.nonnegative(value) { return Text(value, format: .number) }
        return Text("growth.unknownValue")
    }
    private func rankValue(_ rank: Int?) -> Text {
        if let rank { return Text(rank, format: .number) }
        return Text("growth.unranked")
    }
    private func reload() { reads.start { await readOverview() } }
    private func load() async { await reads.run { await readOverview() } }
    private func readOverview() async {
        guard !Task.isCancelled else { return }
        badgePresentationID = UUID(); badgeExploreConsumed = false; latestReaderID = ObjectIdentifier(reader)
        guard reader.isAuthenticated, reader.isConfigured else { model.invalidate(); return }
        let captured = key, presentation = badgePresentationID
        if unlockTrackerKey != captured { unlockTracker.reset(); unlockTrackerKey = captured }
        newlyLitBadges = []
        await model.load(key: captured, currentKey: { key }) { try await reader.overview() }
        // Only a successful center section in the same scope can light a badge; failures keep the baseline.
        guard !Task.isCancelled, captured == key, presentation == badgePresentationID,
              let center = model.value(key: captured)?.center.value else { return }
        newlyLitBadges = unlockTracker.observe(center.badges).compactMap(\.displayName)
    }
}

/// Only an explicitly decoded successful center record can establish no badges.
/// Missing/failed center sections never become an empty array or a navigation receipt.
struct GrowthBadgeExploreSelection {
    let readerID: ObjectIdentifier
    let key: GrowthCenterLoadKey
    let center: GrowthCenterRecord
    let presentationID: UUID
    func accepts(readerID: ObjectIdentifier?, key: GrowthCenterLoadKey, center: GrowthCenterRecord?,
                 presentationID: UUID, visible: Bool, authenticated: Bool, configured: Bool,
                 loading: Bool, hasIssue: Bool) -> Bool {
        visible && authenticated && configured && !loading && !hasIssue &&
            self.readerID == readerID && self.key == key && self.presentationID == presentationID &&
            self.center.badges.isEmpty && self.center == center
    }
}

/// Mirrors the source's 新徽章已点亮：A、B status line for badges new since the previous read.
struct GrowthNewlyLitBadges: View {
    let names: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("growth.badges.newlyLit").font(.headline)
            Text(verbatim: names.formatted(.list(type: .and))).fixedSize(horizontal: false, vertical: true)
        }.accessibilityElement(children: .combine)
    }
}
