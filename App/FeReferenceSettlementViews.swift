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
    private func t(_ en: String, _ cn: String) -> String { zh ? cn : en }
    var body: some View {
        List {
            Section {
                Text(t("Reference amounts only. The platform transfers nothing; organizer and merchant settle offline.",
                       "以下均为参考金额，平台不划款，由主办方与店铺线下结款。"))
                    .font(.footnote).foregroundStyle(.secondary)
                LabeledContent(t("Open (reference)", "待线下结款（参考）"), value: (list ?? .init()).totalOpenText)
                    .accessibilityIdentifier("feReference.totalOpen")
                LabeledContent(t("Settled offline (reference)", "已线下结清（参考）"), value: (list ?? .init()).totalSettledText)
                    .accessibilityIdentifier("feReference.totalSettled")
                if role == .merchant {
                    Picker(t("Status", "状态"), selection: $filter) {
                        Text(t("All", "全部")).tag(FeReferenceSettlementStatus?.none)
                        ForEach(FeReferenceSettlementStatus.allCases, id: \.self) { status in
                            Text(status.title(zh: zh)).tag(Optional(status))
                        }
                    }.pickerStyle(.menu)
                }
            }
            if client?.canRead != true {
                Section { Text(t("Live reads are disabled until independently approved.", "真实读取需独立批准后启用。")) }
            }
            if let list {
                if list.isEmpty { Section { Text(t("No reference settlement rows.", "暂无参考结算记录。")) } }
                ForEach(list.groups) { group in
                    Section {
                        LabeledContent(t("Open (reference)", "待结（参考）"), value: group.openAmountText)
                        LabeledContent(t("Settled (reference)", "已结（参考）"), value: group.settledAmountText)
                        ForEach(group.rows) { row in rowView(row) }
                    } header: {
                        Text(verbatim: [group.activityTitle ?? "#\(group.activityID)", group.payerName].compactMap { $0 }.joined(separator: " · "))
                    }
                }
                if role == .payer { settleSection(list) }
            }
            if !message.isEmpty { Section { Text(message).accessibilityIdentifier("feReference.message") } }
        }
        .navigationTitle(t("Free exploration settlement (reference)", "自由探索结算（参考）"))
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
                    .accessibilityLabel(Text(verbatim: t("Select", "选择")))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: [row.chapterName, row.merchantName].compactMap { $0 }.joined(separator: " · "))
                if row.isAuthorSelfSupply { Text(t("Author self-supply, no settlement needed", "作者自营，无需结算")).font(.caption) }
                Text(verbatim: "\(row.basis?.title(zh: zh) ?? "—") × \(row.quantity) · \(row.unitAmountText)").font(.caption).foregroundStyle(.secondary)
                Text(verbatim: t("Reference ", "参考 ") + row.amountText).font(.headline)
                Text(verbatim: row.statusTitle(zh: zh)).font(.caption)
                if let voucher = row.voucherNo { Text(verbatim: t("Voucher ", "凭证号 ") + voucher).font(.caption2) }
                if let at = row.settledAt { Text(verbatim: at).font(.caption2).foregroundStyle(.secondary) }
                if role == .merchant, row.status == .open, !row.isAuthorSelfSupply {
                    Button(t("Dispute", "提出异议")) { disputeNote = ""; disputeRow = row }
                        .disabled(client?.canDispute != true || busy)
                        .accessibilityIdentifier("feReference.dispute.\(row.id)")
                }
            }
        }.accessibilityIdentifier("feReference.row.\(row.id)")
    }
    @ViewBuilder private func settleSection(_ list: FeReferenceSettlementList) -> some View {
        let rows = FeReferencePayerActions.settleable(list).filter { selected.contains($0.id) }
        Section {
            TextField(t("Voucher number (optional)", "凭证号（选填）"), text: $voucher)
            Button(t("Mark as settled offline", "标记已线下结清")) { Task { await settle(rows) } }
                .disabled(busy || rows.isEmpty || client?.canSettle != true)
                .accessibilityIdentifier("feReference.settle")
            if client?.canSettle != true {
                Text(t("Marking is disabled until independently approved.", "标记结清需独立批准后启用。")).font(.caption).foregroundStyle(.secondary)
            }
        } footer: {
            Text(t("Only records that payment happened offline; the merchant may dispute.", "仅记录已在线下付款；店铺可提出异议。"))
        }
    }
    private func disputeSheet(_ row: FeReferenceSettlementRow) -> some View {
        NavigationStack {
            Form {
                Text(verbatim: t("Reference ", "参考 ") + row.amountText)
                TextField(t("Reason", "异议说明"), text: $disputeNote, axis: .vertical).lineLimit(3...6)
                Button(t("Submit dispute", "提交异议")) { Task { await dispute(row) } }
                    .disabled(busy || (try? FeReferenceDisputeRequest(row: row, note: disputeNote)) == nil || client?.canDispute != true)
            }
            .navigationTitle(t("Dispute", "提出异议"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(t("Cancel", "取消")) { disputeRow = nil } } }
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
        case .acknowledged: message = t("Server acknowledged; refreshing.", "服务器已接收，正在刷新。"); selected = []; reloadKey = UUID()
        case .rejected(let text): message = text
        case .notSent: message = t("Not sent. Authorization is disabled or the session changed.", "未发送。授权关闭或账号已变化。")
        case .unknown: message = t("Outcome unknown. Check server state; do not resubmit.", "结果未知。请核对服务器状态，勿重复提交。")
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
