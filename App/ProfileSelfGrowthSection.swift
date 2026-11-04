import SwiftUI

@MainActor struct ProfileSelfGrowthAccess {
    let reader: any GrowthCenterReading
    let owner: SocialAccountIdentity
    let scope: UUID
    init(reader: any GrowthCenterReading, owner: SocialAccountIdentity) {
        self.reader = reader; self.owner = owner; scope = reader.scope
    }
}
@MainActor struct ProfileSelfGrowthEntry: View {
    let memberID: Int
    let accountReader: any SocialAccountReading
    let access: ProfileSelfGrowthAccess
    let isCurrent: @MainActor () -> Bool
    var body: some View {
        if let context = ProfileSelfGrowthContext.capture(memberID: memberID, accountReader: accountReader,
            growthReader: access.reader, owner: access.owner, ownerScope: access.scope, isCurrent: isCurrent()) {
            ProfileSelfGrowthSection(context: context, accountReader: accountReader, growthReader: access.reader, isCurrent: isCurrent)
                .id(context)
        }
    }
}
@MainActor struct ProfileSelfGrowthSection: View {
    @State private var scopedReader: ProfileSelfGrowthScopedReader
    private var reads: GrowthNormalReadTask { model.overviewReads }
    @StateObject private var model = GrowthCenterScreenModel<GrowthCenterOverview>()
    private var key: GrowthCenterLoadKey { .init(scope: scopedReader.scope) }
    init(context: ProfileSelfGrowthContext, accountReader: any SocialAccountReading,
         growthReader: any GrowthCenterReading, isCurrent: @escaping @MainActor () -> Bool) {
        _scopedReader = State(initialValue: .init(context: context, accountReader: accountReader,
            growthReader: growthReader, isCurrent: isCurrent))
    }
    var body: some View {
        Group {
            if scopedReader.isAuthenticated && scopedReader.isConfigured {
                Section("profile.selfGrowth.title") {
                    if model.isLoading || model.loadedKey != key {
                        ProgressView("growth.loading").frame(maxWidth: .infinity, minHeight: 88)
                            .accessibilityIdentifier("profile.selfGrowth.loading")
                    }
                    else if let issue = model.issue(key: key) {
                        GrowthCenterIssueView(issue: issue, retry: reload)
                    } else if let overview = model.value(key: key) {
                        let summary = ProfileSelfGrowthSummary(overview)
                        GrowthCenterMetricRow("growth.level") { GrowthCenterInteger(value: summary.level) }
                        GrowthCenterMetricRow("growth.experience") { GrowthCenterInteger(value: summary.experience) }
                        GrowthCenterMetricRow("profile.selfGrowth.points") { GrowthCenterInteger(value: summary.points) }
                            .accessibilityIdentifier("profile.selfGrowth.points")
                        if let issue = summary.centerIssue { GrowthCenterIssueView(issue: issue, retry: reload) }
                        GrowthCenterMetricRow("profile.selfGrowth.checkins") { GrowthCenterInteger(value: summary.checkins) }
                        GrowthCenterMetricRow("growth.mileage") {
                            if let mileage = summary.mileage { Text(mileage, format: .number.precision(.fractionLength(0...1))) }
                            else { Text("growth.unknown").accessibilityLabel(Text("growth.unknownValue")) }
                        }
                        GrowthCenterMetricRow("profile.selfGrowth.streak") { GrowthCenterInteger(value: summary.streakDays) }
                        if let issue = summary.progressIssue { GrowthCenterIssueView(issue: issue, retry: reload) }
                    }
                    Button("growth.refresh", action: reload).frame(minHeight: 44).disabled(model.isLoading)
                        .accessibilityIdentifier("profile.selfGrowth.refresh")
                    NavigationLink {
                        ProfileSelfGrowthDestination(reader: scopedReader)
                    } label: { Label("profile.selfGrowth.openCenter", systemImage: "chart.bar.xaxis") }.frame(minHeight: 44)
                        .accessibilityIdentifier("profile.selfGrowth.openCenter")
                }
            }
        }
        .modifier(GrowthCenterReadLifecycle(key: key, refresh: load, cancel: model.cancelPending))
    }
    private func reload() {
        guard !model.isLoading, scopedReader.isAuthenticated, scopedReader.isConfigured else { return }
        reads.start { await readOverview() }
    }
    private func load() async { await reads.run { await readOverview() } }
    private func readOverview() async {
        guard !Task.isCancelled, scopedReader.isAuthenticated, scopedReader.isConfigured else { model.invalidate(); return }
        await model.load(key: key, currentKey: { key }, operation: { try await scopedReader.overview() })
    }
}
@MainActor struct ProfileSelfGrowthDestination: View {
    let reader: ProfileSelfGrowthScopedReader
    var body: some View {
        if reader.isAuthenticated && reader.isConfigured { GrowthCenterView(reader: reader) }
        else {
            ContentUnavailableView {
                Label("social.changed", systemImage: "person.crop.circle.badge.exclamationmark")
            }.appNavigationTitle("growth.title")
        }
    }
}
