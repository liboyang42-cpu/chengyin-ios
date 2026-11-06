import SwiftUI

/// Source pages/merchant/ledger/index.wxml rows: title, "who · HH:mm", state chip and right-aligned amount.
struct MerchantLedgerRowLabel: View {
    let line: MerchantLedgerParity.Line
    let identifier: String
    private var chipColor: Color {
        switch line.variant { case .warning: return .orange; case .success: return .green; case .danger: return .red; case .neutral: return .secondary }
    }
    private var amountColor: Color {
        switch line.tone { case .positive: return .green; case .negative: return .red; case .muted: return .secondary }
    }
    private func copy(_ text: String?, _ key: String?) -> String? { text ?? key.map { MerchantOpsCopy.text($0) } }
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                if let title = copy(line.title, line.titleKey) { Text(verbatim: title).font(.headline) }
                let detail = [copy(line.subtitle, line.subtitleKey), line.timeText].compactMap { $0 }.joined(separator: " · ")
                if !detail.isEmpty { Text(verbatim: detail).font(.subheadline).foregroundStyle(.secondary) }
                HStack(spacing: 6) {
                    switch line.state {
                    case .key(let key): Text(verbatim: MerchantOpsCopy.text(key))
                    case .server(let text): Text(verbatim: text)
                    }
                    if let extra = line.extraKey { Text(verbatim: MerchantOpsCopy.text(extra)).foregroundStyle(.secondary) }
                }.font(.footnote).foregroundStyle(chipColor)
            }
            Spacer(minLength: 8)
            if let amount = copy(line.amount, line.amountKey) { Text(verbatim: amount).monospacedDigit().foregroundStyle(amountColor) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

/// Source ledger summary strip: this month's redemptions, pending and arrived, only from server totals.
struct MerchantLedgerSummaryStrip: View {
    let summary: MerchantLedgerParity.Summary
    var body: some View {
        HStack {
            cell("merchantOps.ledger.summary.count", MerchantOpsCopy.text("merchantOps.ledger.summary.countValue %lld", summary.count))
            if let pending = summary.pending { cell("merchantOps.ledger.summary.pending", pending) }
            if let arrived = summary.arrived { cell("merchantOps.ledger.summary.arrived", arrived) }
        }.accessibilityElement(children: .combine).accessibilityIdentifier("merchantOps.ledger.summary")
    }
    private func cell(_ key: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: MerchantOpsCopy.text(key)).font(.caption).foregroundStyle(.secondary)
            Text(verbatim: value).font(.headline).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Source ledger/order-detail hero card.
struct MerchantLedgerRedemptionHero: View {
    let hero: MerchantLedgerParity.RedemptionHero
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let title = hero.title ?? hero.titleKey.map { MerchantOpsCopy.text($0) } ?? ""
            Text(verbatim: hero.showsIncome ? MerchantOpsCopy.text("merchantOps.ledger.detail.income %@", title) : title).font(.subheadline)
            if hero.showsIncome, let amount = hero.amount ?? hero.amountKey.map({ MerchantOpsCopy.text($0) }) {
                Text(verbatim: amount).font(.largeTitle.bold()).monospacedDigit().foregroundStyle(hero.amount == nil ? .secondary : .primary)
            }
            switch hero.state {
            case .key(let key): Text(verbatim: MerchantOpsCopy.text(key)).font(.footnote.bold())
            case .server(let text): Text(verbatim: text).font(.footnote.bold())
            }
            LabeledContent(MerchantOpsCopy.text("merchantOps.ledger.detail.store"), value: hero.store ?? MerchantOpsCopy.text("merchantOps.ledger.detail.storeMissing"))
            if let accrual = hero.accrual { LabeledContent(MerchantOpsCopy.text("merchantOps.ledger.detail.accrual"), value: accrual) }
            if let refund = hero.refundKey { LabeledContent(MerchantOpsCopy.text("merchantOps.ledger.detail.refund"), value: MerchantOpsCopy.text(refund)) }
        }.accessibilityElement(children: .combine).accessibilityIdentifier("merchantOps.ledger.redemptionHero")
    }
}

/// Source ledger/batch-detail hero card.
struct MerchantLedgerBatchHero: View {
    let hero: MerchantLedgerParity.BatchHero
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: MerchantOpsCopy.text("merchantOps.ledger.batch.net %@", hero.period ?? "")).font(.subheadline)
            Text(verbatim: hero.amount ?? MerchantOpsCopy.text("merchantOps.ledger.amount.pending")).font(.largeTitle.bold()).monospacedDigit()
                .foregroundStyle(hero.amount == nil ? .secondary : .primary)
            HStack {
                Text(verbatim: MerchantOpsCopy.text(hero.stateKey)).font(.footnote.bold())
                Text(verbatim: MerchantOpsCopy.text(hero.invoiceKey)).font(.footnote).foregroundStyle(.secondary)
            }
        }.accessibilityElement(children: .combine).accessibilityIdentifier("merchantOps.ledger.batchHero")
    }
}

struct MerchantLedgerBatchStatementCard: View {
    let statement: MerchantLedgerParity.BatchStatementSummary
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("merchant.settlementOverview.statement", tableName: "MerchantSettlementOverview").font(.headline)
            if let total = statement.totalText {
                LabeledContent {
                    Text(verbatim: total).monospacedDigit()
                } label: {
                    Text("merchant.settlementOverview.serverTotal", tableName: "MerchantSettlementOverview")
                }
            } else if statement.emptyText != nil {
                Text("merchant.settlementOverview.statementEmpty", tableName: "MerchantSettlementOverview")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(Array(statement.stepTimestamps.enumerated()), id: \.offset) { _, stamp in
                Text(verbatim: stamp).font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("merchantOps.ledger.batchStatement")
    }
}

/// 对账单 card for one batch-detail response. It reports only the server
/// batch total and how many detail lines this response actually returned;
/// the detail contract has no complete-line total, and that gap is shown.
struct MerchantSettlementStatementCard: View {
    let statement: MerchantSettlementStatement
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("merchant.settlementOverview.statement", tableName: "MerchantSettlementOverview").font(.headline)
            LabeledContent {
                if let total = statement.serverTotalDisplay {
                    Text(verbatim: total).monospacedDigit()
                } else {
                    Text("merchant.settlementOverview.totalUnknown", tableName: "MerchantSettlementOverview")
                        .foregroundStyle(.secondary)
                }
            } label: {
                Text("merchant.settlementOverview.serverTotal", tableName: "MerchantSettlementOverview")
            }
            if statement.returnedDetailCount == 0 {
                Text("merchant.settlementOverview.statementEmpty", tableName: "MerchantSettlementOverview")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("merchant.settlementOverview.batchStatement")
    }
}

/// Owned batch detail reached from the settlement overview's batches section.
/// Reuses the existing `.batch` finance read and settlement progress view;
/// it performs no settlement, payment, refund or payout action.
@MainActor struct MerchantSettlementBatchDetailView: View {
    let reader: any MerchantBusinessReading
    let batchID: Int
    var onReturn: () -> Void = {}
    @State private var snapshot: MerchantBusinessSnapshot?
    @State private var failureKey: String?
    @State private var loading = false
    @State private var generation = 0
    @State private var visible = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        List {
            if loading { ProgressView("merchant.loading") }
            if let failureKey {
                Section {
                    Text(LocalizedStringKey(failureKey))
                    Button("action.retry") { Task { await load() } }.disabled(loading)
                        .accessibilityIdentifier("merchant.settlementOverview.batchDetail.retry")
                }
            }
            if let snapshot {
                let document = snapshot.document
                if let batch = document.sections.first(where: { $0.id == "batch" })?.rows.first {
                    Section("merchant.business.section.batch") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(batch.title).font(.headline)
                            MerchantBusinessRecordFields(row: batch, access: snapshot.access, compact: false,
                                                         settlementReader: reader, settlementSnapshot: { self.snapshot })
                        }
                    }
                }
                if let statement = MerchantSettlementStatement(document: document) {
                    Section {
                        MerchantSettlementStatementCard(statement: statement)
                    }
                }
                detailSection(document, id: "earnings", title: "merchant.settlementOverview.earnings", access: snapshot.access)
                detailSection(document, id: "adjustments", title: "merchant.settlementOverview.adjustments", access: snapshot.access)
            }
        }
        .appNavigationTitle("merchant.business.batch")
        .task { visible = true; await load() }
        .onAppear { visible = true }
        .onDisappear {
            visible = false; generation += 1; loading = false; snapshot = nil; failureKey = nil
            onReturn()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { generation += 1; loading = false; snapshot = nil; failureKey = nil }
            else if visible, snapshot == nil { Task { await load() } }
        }
        .onChange(of: reader.scope) { _, _ in generation += 1; snapshot = nil; Task { await load() } }
        .onChange(of: reader.authorizationGeneration) { _, _ in generation += 1; snapshot = nil; Task { await load() } }
    }

    @ViewBuilder private func detailSection(_ document: MerchantBusinessDocument, id: String,
                                            title: String, access: MerchantBusinessAccess) -> some View {
        if let rows = document.sections.first(where: { $0.id == id })?.rows, !rows.isEmpty {
            Section {
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(row.title).font(.headline)
                        MerchantBusinessRecordFields(row: row, access: access, compact: false, settlementEntries: true)
                    }
                }
            } header: {
                Text(LocalizedStringKey(title), tableName: "MerchantSettlementOverview")
            }
        }
    }

    private func load() async {
        guard visible, scenePhase == .active, !loading, reader.isConfigured,
              let scope = reader.scope, let id = try? MerchantBatchID(batchID) else { return }
        loading = true; failureKey = nil
        generation += 1
        let ticket = generation, authorization = reader.authorizationGeneration
        defer { if generation == ticket { loading = false } }
        do {
            let result = try await reader.snapshot(.batch(id))
            guard visible, scenePhase == .active, generation == ticket, !Task.isCancelled,
                  reader.scope == scope, reader.authorizationGeneration == authorization,
                  result.access.allows("merchant:finance:read"),
                  MerchantSettlementStatement(document: result.document) != nil else { return }
            snapshot = result
        } catch {
            guard visible, scenePhase == .active, generation == ticket, !Task.isCancelled,
                  reader.scope == scope, reader.authorizationGeneration == authorization else { return }
            failureKey = MerchantSettlementOverviewModel.failureKey(error)
        }
    }
}
