import SwiftUI

/// Adapts the existing session reader; it never constructs another endpoint or transport.
@MainActor private final class CoopSettlementJourneyAdapter: CoopSettlementJourneyReading {
    private let reader: any CoopFlowReading
    private var observed: CoopFlowSession?
    private var stamp = UUID()
    private var active = true
    init(_ reader: any CoopFlowReading) { self.reader = reader; observed = reader.session }
    var scope: UUID? {
        guard active else { return nil }
        let session = reader.session
        if session != observed { observed = session; stamp = UUID() }
        return session == nil ? nil : stamp
    }
    func matches(_ reader: any CoopFlowReading) -> Bool { active && ObjectIdentifier(self.reader) == ObjectIdentifier(reader) }
    func invalidate() { active = false; observed = nil; stamp = UUID() }
    func data(source: CoopFlowSettlement.Source) async throws -> CoopFlowJSON {
        guard let captured = scope else { throw APIError.unauthorized }
        let payload = try await reader.read(source == .finance ? .finance : .myBusiness, isCurrent: { self.scope == captured })
        guard scope == captured, !Task.isCancelled else { throw CoopFlowFailure.stale }
        return payload
    }
}

@MainActor private final class CoopSettlementJourneyViewModel: ObservableObject {
    @Published private(set) var revision = 0
    let journey = CoopSettlementReadJourney()
    private var adapter: CoopSettlementJourneyAdapter?
    func detail(reader: any CoopFlowReading, source: CoopFlowSettlement.Source, id: Int) -> CoopSettlementDetailModel? {
        guard let adapter, adapter.matches(reader) else { return nil }
        return journey.detail(reader: adapter, source: source, id: id)
    }
    func issue(reader: any CoopFlowReading, source: CoopFlowSettlement.Source, id: Int) -> CoopSettlementReadJourney.Issue? {
        guard let adapter, adapter.matches(reader) else { return nil }
        return journey.issue(reader: adapter, source: source, id: id)
    }
    func invalidate() { adapter?.invalidate(); adapter = nil; journey.invalidate(); revision += 1 }
    func load(reader: any CoopFlowReading, source: CoopFlowSettlement.Source, id: Int) async {
        if adapter?.matches(reader) != true { invalidate(); adapter = .init(reader) }
        guard let adapter else { return }
        revision += 1
        await journey.load(reader: adapter, source: source, id: id)
        revision += 1
    }
}

/// Source `pages/coop/settlement-detail` for `source=finance` (organizer) and `source=ledger` (merchant `mybiz`).
/// One read per load; the row is found client-side after the whole payload validates. A failed refresh keeps
/// the last detail visible with an inline notice, as the source `stale-error` state does.
@MainActor struct CoopSettlementDetailView: View {
    let reader: any CoopFlowReading
    let source: CoopFlowSettlement.Source
    let id: Int
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    private typealias Issue = CoopSettlementReadJourney.Issue
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = CoopSettlementJourneyViewModel()
    @State private var refresh = UUID()
    private struct ReadTask: Equatable {
        let reader: ObjectIdentifier
        let account: Int?
        let epoch: UInt64?
        let source: String
        let recordID: Int
        let refresh: UUID
    }
    private var detail: CoopSettlementDetailModel? { model.detail(reader: reader, source: source, id: id) }
    private var issue: Issue? { model.issue(reader: reader, source: source, id: id) }
    private var loading: Bool { model.journey.isLoading }

    var body: some View {
        List {
            if id <= 0 { missingParameter }
            else if reader.session == nil { Text("cooperation.login").accessibilityIdentifier("cooperation.settlement.login") }
            else if let detail {
                if loading { notice("cooperation.settlement.refreshing", "cooperation.settlement.refreshing.detail", id: "refreshing") }
                if case .failed(let message)? = issue {
                    Section {
                        notice("cooperation.settlement.staleError", nil, verbatim: message, id: "stale")
                        Button("cooperation.refresh") { refresh = UUID() }.accessibilityIdentifier("cooperation.settlement.retry")
                    }
                }
                content(detail)
            } else if let issue, !loading { failure(issue) }
            else { ProgressView("cooperation.loading").accessibilityIdentifier("cooperation.settlement.loading") }
        }
        .appNavigationTitle("cooperation.settlement.title")
        .task(id: ReadTask(reader: ObjectIdentifier(reader), account: reader.session?.accountID, epoch: reader.session?.epoch, source: source.rawValue, recordID: id, refresh: refresh)) { await load() }
        .refreshable { await load() }
        .onDisappear { model.invalidate() }
        .onChange(of: reader.session) { _, _ in model.invalidate(); refresh = UUID() }
        .onChange(of: scenePhase) { _, phase in
            model.invalidate()
            if phase == .active { refresh = UUID() }
        }
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
        guard scenePhase == .active else { return }
        await model.load(reader: reader, source: source, id: id)
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
