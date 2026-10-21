import SwiftUI

/// 对账单 card for one batch-detail response. It reports only the server
/// batch total and how many detail lines this response actually returned;
/// the detail contract has no complete-line total, and that gap is shown.
struct MerchantLedgerBatchStatementCard: View {
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
            if statement.returnedDetailCount > 0 {
                Text("merchant.settlementOverview.returnedDetails \(statement.returnedDetailCount)",
                     tableName: "MerchantSettlementOverview")
                    .font(.footnote)
            } else {
                Text("merchant.settlementOverview.statementEmpty", tableName: "MerchantSettlementOverview")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Text("merchant.settlementOverview.detailIncomplete", tableName: "MerchantSettlementOverview")
                .font(.footnote).foregroundStyle(.secondary)
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
                        MerchantLedgerBatchStatementCard(statement: statement)
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
            guard visible, scenePhase == .active, generation == ticket, !Task.isCancelled else { return }
            failureKey = MerchantSettlementOverviewModel.failureKey(error)
        }
    }
}
