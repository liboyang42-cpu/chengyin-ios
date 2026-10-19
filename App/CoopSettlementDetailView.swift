import SwiftUI

/// Source `pages/coop/settlement-detail` for `source=finance` (organizer) and `source=ledger` (merchant `mybiz`).
/// One read per load; the row is found client-side after the whole payload validates. A failed refresh keeps
/// the last detail visible with an inline notice, as the source `stale-error` state does.
@MainActor struct CoopSettlementDetailView: View {
    let reader: any CoopFlowReading
    let source: CoopFlowSettlement.Source
    let id: Int
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    private enum Issue: Equatable { case failed(String?), missingRecord, permission(String?) }
    @State private var detail: CoopSettlementDetailModel?
    @State private var issue: Issue?
    @State private var loading = false
    @State private var loadedSession: CoopFlowSession?
    @State private var generation = UUID()
    @State private var refresh = UUID()

    var body: some View {
        List {
            if id <= 0 { missingParameter }
            else if reader.session == nil { Text("cooperation.login").accessibilityIdentifier("cooperation.settlement.login") }
            else if let detail, loadedSession == reader.session {
                if loading { notice("cooperation.settlement.refreshing", "cooperation.settlement.refreshing.detail", id: "refreshing") }
                if case .failed(let message)? = issue {
                    Section {
                        notice("cooperation.settlement.staleError", nil, verbatim: message, id: "stale")
                        Button("cooperation.refresh") { refresh = UUID() }.accessibilityIdentifier("cooperation.settlement.retry")
                    }
                }
                content(detail)
            } else if let issue, loadedSession == reader.session, !loading { failure(issue) }
            else { ProgressView("cooperation.loading").accessibilityIdentifier("cooperation.settlement.loading") }
        }
        .appNavigationTitle("cooperation.settlement.title")
        .task(id: "\(reader.session?.accountID ?? 0):\(reader.session?.epoch ?? 0):\(refresh)") { await load() }
        .refreshable { await load() }
        .onDisappear { generation = UUID(); loading = false }
        .accessibilityIdentifier("cooperation.settlement.\(source.rawValue).\(id)")
    }

    @ViewBuilder private func content(_ detail: CoopSettlementDetailModel) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(LocalizedStringKey("cooperation.settlement.perspective." + detail.perspective.rawValue)).font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    CoopSettlementToneBadge(status: detail.status, tone: detail.tone)
                }
                Text(verbatim: title(detail)).font(.title3.bold())
                Text("cooperation.settlement.line.income").font(.footnote).foregroundStyle(.secondary)
                Text(verbatim: detail.amount.map { "¥" + CoopFinanceProfit.plainText($0) } ?? "—").font(.largeTitle.bold()).monospacedDigit()
                    .accessibilityLabel(detail.amount.map { Text(verbatim: "¥" + CoopFinanceProfit.plainText($0)) } ?? Text("coopflow.amount.unknown"))
                    .accessibilityIdentifier("cooperation.settlement.amount")
            }.padding(.vertical, 4)
        }
        Section("cooperation.settlement.breakdown") {
            ForEach(Array(detail.lines.enumerated()), id: \.offset) { _, line in
                LabeledContent { Text(verbatim: valueText(line.value)).monospacedDigit().fontWeight(line.strong ? .bold : .regular) } label: {
                    Text(LocalizedStringKey("cooperation.settlement.line." + line.key)).fontWeight(line.strong ? .bold : .regular)
                }.accessibilityIdentifier("cooperation.settlement.line.\(line.key)")
            }
        }
        Section("cooperation.settlement.progress") {
            ForEach(Array(detail.timeline.enumerated()), id: \.offset) { _, step in
                LabeledContent { Text(verbatim: valueText(step.value)) } label: {
                    Label { Text(LocalizedStringKey("cooperation.settlement.step." + step.key)) } icon: { Image(systemName: "circle.fill").font(.system(size: 7)) }
                }.accessibilityIdentifier("cooperation.settlement.step.\(step.key)")
            }
        }
        Section { CoopFlowSafetyNotice() }
    }

    private var missingParameter: some View {
        Section {
            notice("cooperation.settlement.missingParam", "cooperation.settlement.missingParam.detail", id: "missingParam")
            Button("cooperation.settlement.back") { dismiss() }
        }
    }
    @ViewBuilder private func failure(_ issue: Issue) -> some View {
        Section {
            switch issue {
            case .missingRecord:
                notice("cooperation.settlement.missingRecord", "cooperation.settlement.missingRecord.detail", id: "missingRecord")
                Button("cooperation.settlement.backToList") { dismiss() }.accessibilityIdentifier("cooperation.settlement.backToList")
            case .permission(let message):
                notice("cooperation.settlement.failed", message == nil ? "cooperation.settlement.reload" : nil, verbatim: message, id: "permission")
            case .failed(let message):
                notice("cooperation.settlement.failed", message == nil ? "cooperation.settlement.failed.detail" : nil, verbatim: message, id: "failed")
                Button("cooperation.refresh") { refresh = UUID() }.accessibilityIdentifier("cooperation.settlement.retry")
            }
        }
    }
    private func notice(_ title: String, _ detail: String?, verbatim: String? = nil, id: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(title)).font(.headline)
            if let verbatim { Text(verbatim: verbatim).font(.footnote).foregroundStyle(.secondary) }
            else if let detail { Text(LocalizedStringKey(detail)).font(.footnote).foregroundStyle(.secondary) }
        }.accessibilityElement(children: .combine).accessibilityIdentifier("cooperation.settlement.state.\(id)")
    }
    private func title(_ detail: CoopSettlementDetailModel) -> String {
        if let name = detail.topicName { return name }
        if let topic = detail.topicID, topic != 0 { return appLocalized("cooperation.finance.topicFallback \(topic)", locale: locale) }
        return appLocalized("cooperation.unnamedTopic", locale: locale)
    }
    private func valueText(_ value: CoopSettlementDetailModel.Value) -> String {
        switch value {
        case .money(let amount): return "¥" + CoopFinanceProfit.plainText(amount)
        case .heads(let count): return appLocalized("cooperation.settlement.value.heads \(count)", locale: locale)
        case .key(let key): return appLocalized(String.LocalizationValue(stringLiteral: "cooperation.settlement.value." + key), locale: locale)
        case .shareRate(let rate): return appLocalized("cooperation.settlement.value.shareRate \(NSDecimalNumber(decimal: rate).stringValue)", locale: locale)
        case .fixedFee(let fee): return appLocalized("cooperation.settlement.value.fixedFee \(CoopFinanceProfit.plainText(fee))", locale: locale)
        case .date(let text): return text
        case .unavailable: return "—"
        }
    }
    private func load() async {
        let stamp = UUID(); generation = stamp
        guard id > 0, let session = reader.session else { detail = nil; issue = nil; loadedSession = nil; return }
        if loadedSession != session { detail = nil; issue = nil; loadedSession = nil }
        loading = true
        defer { if generation == stamp { loading = false } }
        do {
            let value = try await reader.read(source == .finance ? .finance : .myBusiness)
            let resolved = try CoopSettlementDetailModel.resolve(source: source, data: value, id: id)
            guard !Task.isCancelled, generation == stamp, reader.session == session else { return }
            detail = resolved; issue = nil; loadedSession = session
        } catch {
            guard !Task.isCancelled, generation == stamp, reader.session == session else { return }
            let message: String? = { if case CoopFlowFailure.server(_, let text)? = error as? CoopFlowFailure, let text, !text.isEmpty { return text }; return nil }()
            if CoopSettlementDetailModel.isPermission(error) { detail = nil; issue = .permission(message) }
            else if error as? CoopFlowFailure == .unavailable { detail = nil; issue = .missingRecord }
            else { issue = .failed(message) }
            loadedSession = session
        }
    }
}

struct CoopSettlementToneBadge: View {
    let status: CoopSettlementDetailModel.Status
    let tone: CoopSettlementDetailModel.Tone
    var body: some View {
        let color: Color = tone == .success ? .green : tone == .warning ? .orange : tone == .danger ? .red : .secondary
        Text(LocalizedStringKey("cooperation.settlement.status." + status.rawValue))
            .font(.caption.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(color).background(Capsule().fill(color.opacity(0.14)))
            .accessibilityIdentifier("cooperation.settlement.status")
    }
}
