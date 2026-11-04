import SwiftUI

private struct CoopWalletReaderKey: EnvironmentKey {
    static let defaultValue: WalletCommerceReader? = nil
}
extension EnvironmentValues {
    /// Wallet session used for owner-only funds stages and withdrawal records on coop pages.
    var coopWalletReader: WalletCommerceReader? {
        get { self[CoopWalletReaderKey.self] }
        set { self[CoopWalletReaderKey.self] = newValue }
    }
}

/// Source `pages/coop/finance` deep-link shell around `components/cy/scene-merchant-profit`.
/// Read-only: the only action opens platform withdrawal support; nothing here moves money.
@MainActor struct CoopFinanceProfitView: View {
    let reader: any CoopFlowReading
    @Environment(\.coopWalletReader) private var walletReader
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var profit: CoopFinanceProfit?
    @State private var issue: CoopFinanceProfit.ReadIssue?
    @State private var loadedSession: CoopFlowSession?
    @State private var generation = UUID()
    @State private var refresh = UUID()
    @State private var showsSupport = false

    var body: some View {
        List {
            if reader.session == nil { failure(.authRequired) }
            else if loadedSession != reader.session { ProgressView("cooperation.loading").padding(.vertical, Theme.Space.s3).accessibilityIdentifier("cooperation.finance.loading") }
            else if let issue { failure(issue) }
            else if let profit { content(profit) }
            else { ProgressView("cooperation.loading") }
        }
        .appNavigationTitle("cooperation.finance.title")
        .modifier(CoopOperationListPresentation())
        .labeledContentStyle(CoopFinancialRowStyle())
        .themeDomain(.merchant)
        .task(id: "\(reader.session?.accountID ?? 0):\(reader.session?.epoch ?? 0):\(refresh)") { await load() }
        .refreshable { await load() }
        .onDisappear { generation = UUID() }
        .onChange(of: reader.session) { _, _ in showsSupport = false }
        .sheet(isPresented: $showsSupport) { WithdrawalSupportContactView() }
        .accessibilityIdentifier("cooperation.finance")
    }

    @ViewBuilder private func content(_ profit: CoopFinanceProfit) -> some View {
        Section {
            ForEach(profit.stats, id: \.key) { stat in
                Group {
                    if stat.key == .income {
                        VStack(alignment: .leading, spacing: Theme.Space.s2) {
                            Text(LocalizedStringKey("cooperation.finance.stat." + stat.key.rawValue))
                                .font(.subheadline).foregroundStyle(.secondary)
                            Text(verbatim: statText(stat)).font(.largeTitle.weight(.semibold)).monospacedDigit()
                                .fixedSize(horizontal: false, vertical: true)
                        }.padding(.vertical, Theme.Space.s2).accessibilityElement(children: .combine)
                    } else {
                        LabeledContent { Text(verbatim: statText(stat)).monospacedDigit().fontWeight(.semibold) } label: {
                            Text(LocalizedStringKey("cooperation.finance.stat." + stat.key.rawValue)).foregroundStyle(.secondary)
                        }
                    }
                }
                    .accessibilityIdentifier("cooperation.finance.stat.\(stat.key.rawValue)")
            }
            if let reason = profit.adjustReason { Text(verbatim: reason).font(.footnote).foregroundStyle(.secondary) }
        }
        if profit.isOwner, let walletReader { CoopFinanceFundsStagesSection(reader: walletReader) }
        Section {
            Button { if profit.canWithdraw, loadedSession == reader.session { showsSupport = true } } label: {
                Text("cooperation.finance.withdraw").frame(maxWidth: .infinity)
            }
            .buttonStyle(.questifyPrimary).controlSize(.large).disabled(!profit.canWithdraw)
            .accessibilityLabel(Text(LocalizedStringKey(withdrawAccessibilityKey(profit.withdrawState))))
            .accessibilityIdentifier("cooperation.finance.withdraw")
            if profit.withdrawState == .unknown { Text("cooperation.finance.withdraw.unknown").font(.footnote).foregroundStyle(.secondary) }
            else if profit.withdrawState == .zero { Text("cooperation.finance.withdraw.zero").font(.footnote).foregroundStyle(.secondary) }
        }
        if profit.topics.isEmpty {
            Section {
                ContentUnavailableView("cooperation.finance.empty", systemImage: "tray")
                    .accessibilityIdentifier("cooperation.finance.empty")
            }
        } else {
            Section {
                ForEach(Array(profit.topics.enumerated()), id: \.offset) { index, topic in
                    if let id = topic.topicID, topic.canOpenDetail {
                        NavigationLink { CoopSettlementDetailView(reader: reader, source: .finance, id: id) } label: { row(topic) }
                            .accessibilityIdentifier("coopflow.settlement.finance.\(id)")
                    } else { row(topic).accessibilityIdentifier("cooperation.finance.topic.unavailable.\(index)") }
                }
            } header: { Text("cooperation.finance.topics") } footer: { Text("cooperation.finance.explainer") }
        }
        Section { CoopFlowSafetyNotice() }
    }

    private func row(_ topic: CoopFinanceProfit.Topic) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Theme.Space.s2) {
                    Text(verbatim: topicName(topic)).font(.headline).fixedSize(horizontal: false, vertical: true)
                    topicAmount(topic)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s3) {
                    Text(verbatim: topicName(topic)).font(.headline).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Theme.Space.s2)
                    topicAmount(topic)
                }
            }
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Theme.Space.s2) {
                    topicStatus(topic)
                    CoopFinanceBadge(settled: topic.status != .unsettled && topic.status != .settlementUnknown, status: topic.status)
                }
            } else { ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s3) {
                    topicStatus(topic)
                    Spacer(minLength: Theme.Space.s2)
                    CoopFinanceBadge(settled: topic.status != .unsettled && topic.status != .settlementUnknown, status: topic.status)
                }
                VStack(alignment: .leading, spacing: Theme.Space.s2) {
                    topicStatus(topic)
                    CoopFinanceBadge(settled: topic.status != .unsettled && topic.status != .settlementUnknown, status: topic.status)
                }
            }}
        }.padding(.vertical, Theme.Space.s2)
    }
    private func topicAmount(_ topic: CoopFinanceProfit.Topic) -> some View {
        Text(verbatim: topic.status != .unsettled && topic.status != .settlementUnknown ? topic.income.map { "¥" + CoopFinanceProfit.plainText($0) } ?? "—" : "—")
            .font(.headline).monospacedDigit().fixedSize(horizontal: false, vertical: true)
    }
    private func topicStatus(_ topic: CoopFinanceProfit.Topic) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s1) {
            Text(LocalizedStringKey("cooperation.finance.status." + topic.status.rawValue)).font(.subheadline)
            Text(LocalizedStringKey("cooperation.finance.merchant." + topic.merchantStatus.rawValue))
                .font(.footnote).foregroundStyle(.secondary)
        }.fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func failure(_ issue: CoopFinanceProfit.ReadIssue) -> some View {
        let key: String = issue == .authRequired ? "auth" : issue == .accessDenied ? "denied" : "failed"
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Label(LocalizedStringKey("cooperation.finance.issue." + key + ".title"), systemImage: issue == .accessDenied ? "lock" : "exclamationmark.circle").font(.headline)
                Text(LocalizedStringKey("cooperation.finance.issue." + key + ".detail")).font(.footnote).foregroundStyle(.secondary)
            }.padding(.vertical, Theme.Space.s2).accessibilityElement(children: .combine).accessibilityIdentifier("cooperation.finance.issue.\(key)")
            // Sign-in is owned by the account entry; this page never presents credentials itself.
            if issue != .authRequired || reader.session != nil {
                Button("cooperation.refresh") { refresh = UUID() }.accessibilityIdentifier("cooperation.finance.retry")
            }
        }
    }

    private func topicName(_ topic: CoopFinanceProfit.Topic) -> String {
        if let name = topic.topicName { return name }
        if let id = topic.topicID, id != 0 { return appLocalized("cooperation.finance.topicFallback \(id)", locale: locale) }
        return appLocalized("cooperation.unnamedTopic", locale: locale)
    }
    private func statText(_ stat: CoopFinanceProfit.Stat) -> String {
        guard let amount = stat.amount else { return "—" }
        return (stat.key == .adjustExecuted ? "−¥" : "¥") + CoopFinanceProfit.plainText(amount)
    }
    private func withdrawAccessibilityKey(_ state: CoopFinanceProfit.WithdrawState) -> String {
        switch state { case .positive: return "cooperation.finance.withdraw"; case .unknown: return "cooperation.finance.withdraw.a11y.unknown"; case .zero: return "cooperation.finance.withdraw.a11y.zero" }
    }
    private func load() async {
        let stamp = UUID(); generation = stamp; profit = nil; issue = nil; loadedSession = nil
        guard let session = reader.session else { return }
        do {
            let value = try await reader.read(.finance)
            let parsed = try CoopFinanceProfit(value)
            guard !Task.isCancelled, generation == stamp, reader.session == session else { return }
            profit = parsed; loadedSession = session
        } catch {
            guard !Task.isCancelled, generation == stamp, reader.session == session else { return }
            issue = CoopFinanceProfit.issue(for: error); loadedSession = session
        }
    }
}

struct CoopFinanceBadge: View {
    let settled: Bool
    let status: CoopFinanceProfit.TopicStatus
    var body: some View {
        let badge: CoopFinanceProfit.Badge = settled ? .success : status.badge
        Text(LocalizedStringKey(settled ? "cooperation.finance.settled" : "cooperation.finance.status." + status.rawValue))
            .font(.caption.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(badge == .success ? Color.green : badge == .warning ? Color.orange : Color.secondary)
            .background(Capsule().fill((badge == .success ? Color.green : badge == .warning ? Color.orange : Color.secondary).opacity(0.14)))
    }
}

/// Owner-only "not yet received" breakdown, read with the wallet session; unknown amounts are labelled, not zeroed.
@MainActor struct CoopFinanceFundsStagesSection: View {
    let reader: WalletCommerceReader
    @Environment(\.locale) private var locale
    @State private var stages: WalletFundsStages?
    @State private var failed = false
    @State private var loadedScope: WalletCommerceScope?
    @State private var generation = 0
    var body: some View {
        Section {
            if let stages, loadedScope == reader.scope {
                if stages.pendingSettlement.value > 0 { LabeledContent("cooperation.finance.stages.pending", value: amount(stages.pendingSettlement, stages.currency)) }
                ForEach(Array(stages.complaintPeriod.enumerated()), id: \.offset) { _, item in
                    LabeledContent { Text(verbatim: amount(item.amount, stages.currency)) } label: { Text("wallet.complaintPeriod"); Text(verbatim: item.availableDate) }
                }
                if stages.disputed.value > 0 { LabeledContent("cooperation.finance.stages.disputed", value: amount(stages.disputed, stages.currency)) }
                if !stages.amountsKnown { Text("cooperation.finance.stages.unknown").font(.footnote).foregroundStyle(.secondary) }
            } else if failed {
                Text("cooperation.finance.stages.failed")
                Button("cooperation.refresh") { Task { await load() } }.accessibilityIdentifier("cooperation.finance.stages.retry")
            } else if reader.scope != nil {
                ProgressView("cooperation.loading").font(.subheadline).padding(.vertical, Theme.Space.s2)
            }
        }
        .task(id: reader.scope) { await load() }
        .accessibilityIdentifier("cooperation.finance.stages")
    }
    private func amount(_ value: WalletAmount, _ currency: String?) -> String {
        value.text + " " + (currency ?? appLocalized("wallet.currencyUnknown", locale: locale))
    }
    private func load() async {
        generation += 1; let ticket = generation; let scope = reader.scope
        stages = nil; failed = false; loadedScope = nil
        guard scope != nil else { return }
        do {
            let result = try await reader.read { try await $0.stages(token: $1) }
            guard ticket == generation, reader.scope == scope, !Task.isCancelled else { return }
            stages = result; loadedScope = scope
        } catch { guard ticket == generation, reader.scope == scope, !Task.isCancelled else { return }; failed = true }
    }
}
