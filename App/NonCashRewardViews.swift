import SwiftUI

/// Normal account destination; its live service remains explicitly unconfigured in AppSession.
@MainActor struct NonCashRewardsView: View {
    let reader: any NonCashRewardReading
    @StateObject private var model = NonCashRewardCollectionScreenModel()
    private var key: AccountCollectionLoadKey { .init(rewardReader: reader) }
    init(reader identity: any AccountCollectionReading, rewards: (any NonCashRewardReading)? = nil) {
        #if DEBUG
        if let scenario = NonCashRewardDemo.scenario {
            reader = NonCashRewardFixtureReader(identity: identity, scenario: scenario)
            return
        }
        #endif
        reader = rewards ?? UnconfiguredNonCashRewardReader(identity: identity)
    }
    var body: some View {
        List {
            if reader.isOfflineExample { Text("rewards.demo").font(.footnote).accessibilityIdentifier("rewards.demo") }
            if !reader.isAuthenticated { AccountCollectionIssueView(issue: .login) }
            else if !reader.isConfigured {
                ContentUnavailableView("rewards.unavailable", systemImage: "gift", description: Text("rewards.unavailableHint"))
                    .accessibilityIdentifier("rewards.unavailable")
            } else if model.state.isLoading || model.state.loadedScope != key.scope {
                ProgressView("accountCollection.loading")
            } else if let issue = model.state.issue {
                AccountCollectionIssueView(issue: issue)
                if issue != .login {
                    Button("accountCollection.refresh") { Task { await refresh() } }.accessibilityIdentifier("rewards.retry")
                }
            } else {
                if let asOf = model.state.asOf { LabeledContent("rewards.asOf") { Text(asOf, format: .dateTime) } }
                if model.state.visibleRows(scope: key.scope).isEmpty {
                    ContentUnavailableView("rewards.empty", systemImage: "gift")
                }
                ForEach(model.state.visibleRows(scope: key.scope)) { reward in
                    NavigationLink {
                        NonCashRewardDetailView(reference: NonCashRewardReference(reward), reader: reader).id(reader.scope)
                    } label: { NonCashRewardCard(reward: reward) }
                    .buttonStyle(QuestifyCardButtonStyle()).questifyCardListRow()
                    .accessibilityIdentifier("rewards.row.\(reward.id)")
                }
                if model.state.isLoadingMore { ProgressView("accountCollection.loading") }
                else if let issue = model.state.moreIssue {
                    AccountCollectionIssueView(issue: issue, retry: { Task { await model.loadMore(reader: reader) } })
                } else if model.state.nextCursor != nil {
                    Button("accountCollection.loadMore") { Task { await model.loadMore(reader: reader) } }
                        .accessibilityIdentifier("rewards.loadMore")
                }
            }
        }
        .listStyle(.insetGrouped).appNavigationTitle("rewards.title")
        .modifier(AccountCollectionReadLifecycle(key: key, refresh: refresh, cancel: model.cancelPending))
    }
    private func refresh() async {
        guard reader.isAuthenticated, reader.isConfigured else { model.invalidate(); return }
        await model.refresh(reader: reader)
    }
}

private struct NonCashRewardCard: View {
    let reward: NonCashReward
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(LocalizedStringKey("rewards.state." + reward.state.rawValue), systemImage: "gift")
                .font(.caption.weight(.semibold))
            Text(verbatim: reward.rewardTitle).font(.title3.weight(.semibold))
            LabeledContent("rewards.quantity", value: String(reward.quantity))
            LabeledContent("rewards.validUntil") { Text(reward.validUntil, style: .date) }
        }
        .fixedSize(horizontal: false, vertical: true)
        .questifyCardSurface()
        .accessibilityElement(children: .combine)
    }
}

@MainActor private struct NonCashRewardDetailView: View {
    let reference: NonCashRewardReference
    let reader: any NonCashRewardReading
    @StateObject private var model = AccountCollectionScreenModel<NonCashReward>()
    private var key: AccountCollectionLoadKey { .init(rewardReader: reader, awardId: reference.awardId) }
    var body: some View {
        List {
            if !reader.isAuthenticated { AccountCollectionIssueView(issue: .login) }
            else if !reader.isConfigured { AccountCollectionIssueView(issue: .notConfigured) }
            else if model.isLoading || model.loadedScope != key.scope { ProgressView("accountCollection.loading") }
            else if let issue = model.issue(scope: key.scope) {
                AccountCollectionIssueView(issue: issue, retry: { Task { await refresh() } })
            } else if let reward = model.value(scope: key.scope) {
                NonCashRewardDetailContent(reward: reward, reader: reader)
            }
        }
        .listStyle(.insetGrouped).appNavigationTitle("rewards.detail")
        .modifier(AccountCollectionReadLifecycle(key: key, refresh: refresh, cancel: model.cancelPending))
    }
    private func refresh() async {
        guard reader.isAuthenticated, reader.isConfigured else { model.invalidate(); return }
        await model.load(scope: key.scope, currentScope: { reader.scope }) { try await reader.reward(reference) }
    }
}

@MainActor private struct NonCashRewardDetailContent: View {
    let reward: NonCashReward
    let reader: any NonCashRewardReading
    @Environment(\.scenePhase) private var scenePhase
    @State private var presenting = false
    var body: some View {
        Group {
            if reader.isOfflineExample { Text("rewards.demo").font(.footnote) }
            NonCashRewardCard(reward: reward).questifyCardListRow()
            Section("rewards.conditions") {
                LabeledContent("rewards.reference", value: reward.awardId)
                LabeledContent("rewards.merchant", value: reward.merchantId)
                LabeledContent("rewards.store", value: reward.storeId)
                Text(verbatim: reward.redemptionConditions)
                Text("rewards.bound").font(.footnote)
                Text(LocalizedStringKey("rewards.fulfillment." + reward.fulfillmentStatus.rawValue))
            }
            Section("accountCollection.coupon.validity") {
                LabeledContent("accountCollection.coupon.validFrom") { Text(reward.validFrom, format: .dateTime) }
                LabeledContent("accountCollection.coupon.validUntil") { Text(reward.validUntil, format: .dateTime) }
                LabeledContent("rewards.asOf") { Text(reward.asOf, format: .dateTime) }
                Text(LocalizedStringKey("rewards.validity." + reward.validityStatus.rawValue))
                Text("rewards.expiryHint").font(.footnote)
            }
            Section {
                if reader.isOfflineExample, reward.canPresent(at: NonCashRewardDemo.now) {
                    Button("rewards.present") { presenting = true }.accessibilityIdentifier("rewards.present")
                } else if !reader.isOfflineExample {
                    Text("rewards.redemptionUnavailable").accessibilityIdentifier("rewards.redemptionUnavailable")
                } else {
                    Text("rewards.notPresentable").accessibilityIdentifier("rewards.notPresentable")
                }
                Text("rewards.support").font(.footnote)
            }
        }
        .sheet(isPresented: $presenting) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 24) {
                    Label("rewards.demo", systemImage: "eye.slash").font(.headline)
                    Text("rewards.presentationHint"); Text("rewards.singleUse"); Text("rewards.noCredential").font(.footnote)
                }.padding().accessibilityIdentifier("rewards.presentation")
                    .appNavigationTitle("rewards.present")
                    .toolbar { ToolbarItem(placement: .cancellationAction) {
                        Button("action.close") { presenting = false }.accessibilityIdentifier("rewards.close")
                    } }
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { presenting = false } }
        .onChange(of: reader.scope) { _, _ in presenting = false }
        .onChange(of: reader.isAuthenticated) { _, authenticated in if !authenticated { presenting = false } }
        .onDisappear { presenting = false }
    }
}

/// Only DEBUG can select example data. No real credential, issuance or local redeem mutation.
private enum NonCashRewardDemo {
    static var scenario: String? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--uitesting-rewards-scenario"), args.indices.contains(index + 1),
              ["content", "empty", "failure"].contains(args[index + 1]) else { return nil }
        return args[index + 1]
        #else
        return nil
        #endif
    }
    static let now = Date(timeIntervalSince1970: 1_791_072_000) // Fixed synthetic 2026-10-04 UTC.
    static var rows: [NonCashReward] {
        #if DEBUG
        return [NonCashReward.State.awarded, .redeemed, .expired, .reversed].enumerated().map { index, state in
            NonCashReward(awardId: "example-\(index)", contextType: .map, contextId: "example-map",
                          releaseId: "example-release", instanceId: "example-season", rulesVersion: "example-v1", merchantId: "EXAMPLE-MERCHANT",
                          storeId: "EXAMPLE-STORE", rewardTitle: "DEMO · 实物奖励 / Physical reward", quantity: 1,
                          validFrom: Date(timeIntervalSince1970: 1_790_812_800),
                          validUntil: Date(timeIntervalSince1970: state == .expired ? 1_790_899_200 : 1_791_158_400),
                          redemptionConditions: "演示门店：每日 10:00–16:00；到店向本店员工出示。 / Example store: 10:00–16:00 daily; present to this store’s staff.",
                          state: state, awardedAt: Date(timeIntervalSince1970: 1_790_812_800), asOf: now)
        }
        #else
        return []
        #endif
    }
}

#if DEBUG
@MainActor private final class NonCashRewardFixtureReader: NonCashRewardReading {
    let identity: any AccountCollectionReading
    let scenario: String
    private var failed = false
    init(identity: any AccountCollectionReading, scenario: String) { self.identity = identity; self.scenario = scenario }
    var scope: UUID { identity.scope }
    var isAuthenticated: Bool { identity.isAuthenticated }
    var isConfigured: Bool { true }
    var isOfflineExample: Bool { true }
    func rewards(cursor: String?) async throws -> NonCashRewardPage {
        guard isAuthenticated else { throw APIError.unauthorized }
        if scenario == "failure", !failed { failed = true; throw APIError.httpStatus(503) }
        return NonCashRewardPage(items: scenario == "empty" ? [] : NonCashRewardDemo.rows, nextCursor: nil, asOf: NonCashRewardDemo.now)
    }
    func reward(_ reference: NonCashRewardReference) async throws -> NonCashReward {
        guard isAuthenticated else { throw APIError.unauthorized }
        guard let reward = NonCashRewardDemo.rows.first(where: { NonCashRewardReference($0) == reference }) else {
            throw AccountCollectionReadFailure.unavailable
        }
        return reward
    }
}
#endif
