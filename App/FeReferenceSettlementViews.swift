import SwiftUI

enum FeReferenceSettlementRole: String { case merchant, payer }

/// F11 「自由探索结算（参考）」: read-only reference amounts. Money never moves through the
/// platform; the payer may mark rows as settled offline and the merchant may dispute, each only
/// behind an independent grant (off by default). No data shows ¥0.00.
@MainActor struct FeReferenceSettlementView: View {
    let client: FeReferenceSettlementHTTP?
    let role: FeReferenceSettlementRole
    @State private var list: FeReferenceSettlementList?
    @State private var filter: FeReferenceSettlementStatus?
    @State private var selected = Set<Int>()
    @State private var voucher = ""
    @State private var disputeRow: FeReferenceSettlementRow?
    @State private var disputeNote = ""
    @State private var message = ""
    @State private var busy = false
    @State private var reloadKey = UUID()
    @Environment(\.locale) private var locale
    private var zh: Bool { locale.language.languageCode?.identifier == "zh" }
    var body: some View {
        List {
            Section {
                Text(appLocalized("feReference.referenceAmountsOnlyThe", locale: locale))
                    .font(.footnote).foregroundStyle(.secondary)
                LabeledContent(appLocalized("feReference.openReference", locale: locale), value: (list ?? .init()).totalOpenText)
                    .accessibilityIdentifier("feReference.totalOpen")
                LabeledContent(appLocalized("feReference.settledOfflineReference", locale: locale), value: (list ?? .init()).totalSettledText)
                    .accessibilityIdentifier("feReference.totalSettled")
                if role == .merchant {
                    Picker(appLocalized("feReference.status", locale: locale), selection: $filter) {
                        Text(appLocalized("feReference.all", locale: locale)).tag(FeReferenceSettlementStatus?.none)
                        ForEach(FeReferenceSettlementStatus.allCases, id: \.self) { status in
                            Text(LocalizedStringKey(status.localizationKey)).tag(Optional(status))
                        }
                    }.pickerStyle(.menu)
                }
            }
            if client?.canRead != true {
                Section { Text(appLocalized("feReference.liveReadsAreDisabled", locale: locale)) }
            }
            if let list {
                if list.isEmpty { Section { Text(appLocalized("feReference.noReferenceSettlementRows", locale: locale)) } }
                ForEach(list.groups) { group in
                    Section {
                        LabeledContent(appLocalized("feReference.openReference2", locale: locale), value: group.openAmountText)
                        LabeledContent(appLocalized("feReference.settledReference", locale: locale), value: group.settledAmountText)
                        ForEach(group.rows) { row in rowView(row) }
                    } header: {
                        Text(verbatim: [group.activityTitle ?? "#\(group.activityID)", group.payerName].compactMap { $0 }.joined(separator: " · "))
                    }
                }
                if role == .payer { settleSection(list) }
            }
            if !message.isEmpty { Section { Text(message).accessibilityIdentifier("feReference.message") } }
        }
        .navigationTitle(appLocalized("feReference.freeExplorationSettlementReference", locale: locale))
        .task(id: "\(reloadKey)-\(filter?.rawValue ?? "all")") { await load() }
        .refreshable { await load() }
        .sheet(item: $disputeRow) { row in disputeSheet(row) }
    }
    @ViewBuilder private func rowView(_ row: FeReferenceSettlementRow) -> some View {
        HStack(alignment: .top) {
            if role == .payer, row.status == .open, !row.isAuthorSelfSupply {
                Button { toggle(row.id) } label: {
                    Image(systemName: selected.contains(row.id) ? "checkmark.circle.fill" : "circle")
                }.buttonStyle(.borderless).frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel(Text(verbatim: appLocalized("feReference.select", locale: locale)))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: [row.chapterName, row.merchantName].compactMap { $0 }.joined(separator: " · "))
                if row.isAuthorSelfSupply { Text(appLocalized("feReference.authorSelfSupplyNo", locale: locale)).font(.caption) }
                Text(verbatim: "\(row.basis.map { appLocalized(String.LocalizationValue($0.localizationKey), locale: locale) } ?? "—") × \(row.quantity) · \(row.unitAmountText)").font(.caption).foregroundStyle(.secondary)
                Text(verbatim: String(format: appLocalized("feReference.referenceAmount", locale: locale), row.amountText)).font(.headline)
                Text(verbatim: row.statusText ?? appLocalized(String.LocalizationValue(row.statusLocalizationKey), locale: locale)).font(.caption)
                if let voucher = row.voucherNo { Text(verbatim: String(format: appLocalized("feReference.voucherNumber", locale: locale), voucher)).font(.caption2) }
                if let at = row.settledAt { Text(verbatim: at).font(.caption2).foregroundStyle(.secondary) }
                if role == .merchant, row.status == .open, !row.isAuthorSelfSupply {
                    Button(appLocalized("feReference.dispute", locale: locale)) { disputeNote = ""; disputeRow = row }
                        .disabled(client?.canDispute != true || busy)
                        .accessibilityIdentifier("feReference.dispute.\(row.id)")
                }
            }
        }.accessibilityIdentifier("feReference.row.\(row.id)")
    }
    @ViewBuilder private func settleSection(_ list: FeReferenceSettlementList) -> some View {
        let rows = FeReferencePayerActions.settleable(list).filter { selected.contains($0.id) }
        Section {
            TextField(appLocalized("feReference.voucherNumberOptional", locale: locale), text: $voucher)
            Button(appLocalized("feReference.markAsSettledOffline", locale: locale)) { Task { await settle(rows) } }
                .disabled(busy || rows.isEmpty || client?.canSettle != true)
                .accessibilityIdentifier("feReference.settle")
            if client?.canSettle != true {
                Text(appLocalized("feReference.markingIsDisabledUntil", locale: locale)).font(.caption).foregroundStyle(.secondary)
            }
        } footer: {
            Text(appLocalized("feReference.onlyRecordsThatPayment", locale: locale))
        }
    }
    private func disputeSheet(_ row: FeReferenceSettlementRow) -> some View {
        NavigationStack {
            Form {
                Text(verbatim: String(format: appLocalized("feReference.referenceAmount", locale: locale), row.amountText))
                TextField(appLocalized("feReference.reason", locale: locale), text: $disputeNote, axis: .vertical).lineLimit(3...6)
                Button(appLocalized("feReference.submitDispute", locale: locale)) { Task { await dispute(row) } }
                    .disabled(busy || (try? FeReferenceDisputeRequest(row: row, note: disputeNote)) == nil || client?.canDispute != true)
            }
            .navigationTitle(appLocalized("feReference.dispute", locale: locale))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(appLocalized("feReference.cancel", locale: locale)) { disputeRow = nil } } }
        }
    }
    private func toggle(_ id: Int) { if selected.contains(id) { selected.remove(id) } else { selected.insert(id) } }
    private func load() async {
        guard let client, client.canRead else { list = nil; return }
        do {
            switch role {
            case .merchant: list = try await client.merchantList(.init(status: filter))
            case .payer: list = try await client.payerList(try .init())
            }
            selected = selected.intersection(Set((list.map(FeReferencePayerActions.settleable) ?? []).map(\.id)))
        } catch { message = PublisherLifecycleCopy.error(error, zh: zh) }
    }
    private func settle(_ rows: [FeReferenceSettlementRow]) async {
        guard !busy, let client, let request = try? FeReferenceSettleRequest(rows: rows, voucherNo: voucher) else { return }
        busy = true; defer { busy = false }
        report(await client.settle(request))
    }
    private func dispute(_ row: FeReferenceSettlementRow) async {
        guard !busy, let client, let request = try? FeReferenceDisputeRequest(row: row, note: disputeNote) else { return }
        busy = true; defer { busy = false }
        report(await client.dispute(request)); disputeRow = nil
    }
    private func report(_ outcome: FeReferenceSettlementOutcome) {
        switch outcome {
        case .acknowledged: message = appLocalized("feReference.serverAcknowledgedRefreshing", locale: locale); selected = []; reloadKey = UUID()
        case .rejected(let text): message = text
        case .notSent: message = appLocalized("feReference.notSentAuthorizationIs", locale: locale)
        case .unknown: message = appLocalized("feReference.outcomeUnknownCheckServer", locale: locale)
        }
    }
}

@MainActor struct SessionFeReferenceSettlementView: View {
    @ObservedObject var session: AppSession
    let role: FeReferenceSettlementRole
    var body: some View {
        // Grants stay dormant: reads and both writes require independent approval.
        FeReferenceSettlementView(client: session.publisherLifecycleContext.map { FeReferenceSettlementHTTP(sharing: $0.client) }, role: role)
            .id(session.sessionRevision)
    }
}
/// Single account entry for F11; the store and organizer views are separate rows here so the
/// account list gains only one row.
@MainActor struct SessionFeReferenceSettlementHubView: View {
    @ObservedObject var session: AppSession
    var body: some View {
        List {
            Section {
                NavigationLink { SessionFeReferenceSettlementView(session: session, role: .merchant) } label: {
                    Label("feReference.hub.merchant", systemImage: "storefront")
                }.accessibilityIdentifier("feReference.hub.merchant")
                NavigationLink { SessionFeReferenceSettlementView(session: session, role: .payer) } label: {
                    Label("feReference.hub.payer", systemImage: "checklist")
                }.accessibilityIdentifier("feReference.hub.payer")
            } footer: { Text("feReference.hub.note") }
        }
        .navigationTitle(Text("feReference.entry"))
    }
}
