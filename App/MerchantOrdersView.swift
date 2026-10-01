import SwiftUI

@MainActor
struct MerchantOrdersView<Reader: MerchantReading>: View {
    @ObservedObject var reader: Reader
    @StateObject private var model = MerchantLoadModel<[MerchantOrder]>()
    @State private var filter = MerchantOrderFilter()
    @State private var draftFilter = MerchantOrderFilter()
    @State private var showFilters = false
    @State private var selection: OrderSelection?

    private struct OrderSelection: Identifiable {
        let id = UUID()
        let order: MerchantOrder
        let revision: UInt64
    }

    var body: some View {
        ZStack {
            if !reader.isConfigured {
                ContentUnavailableView("merchant.orders", systemImage: "network.slash", description: Text("auth.notConfigured"))
            } else if !reader.isSignedIn {
                ContentUnavailableView("merchant.orders", systemImage: "lock", description: Text("merchant.signIn"))
            } else if model.loadedRevision == reader.sessionRevision, let rows = model.value {
                List {
                    Section {
                        Text("merchant.readOnly").font(.footnote).foregroundStyle(.secondary)
                        if filter.status != nil || filter.aftersaleStatus != nil { filterSummary }
                        if model.isLoading { ProgressView("merchant.refreshing") }
                        if let error = model.errorKey {
                            Text("merchant.stale").font(.footnote).foregroundStyle(.secondary)
                            MerchantInlineFailure(errorKey: error, retry: { Task { await reload() } })
                        }
                    }
                    if rows.isEmpty {
                        Section { Text("merchant.orders.empty").accessibilityIdentifier("merchant.orders.empty") }
                    } else {
                        ForEach(Array(rows.enumerated()), id: \.offset) { index, order in
                            Button {
                                selection = OrderSelection(order: order, revision: reader.sessionRevision)
                            } label: { MerchantOrderRow(order: order) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("merchant.order.row.\(order.id.map(String.init) ?? String(index))")
                        }
                    }
                }.refreshable { await reload() }
            } else if let error = model.errorKey {
                MerchantFailureView(errorKey: error, identifier: "merchant.orders", retry: { Task { await reload() } })
            } else { ProgressView("merchant.loading") }
        }
        .navigationTitle("merchant.orders")
        .toolbar {
            if reader.isSignedIn && reader.isConfigured && model.errorKey != "merchant.access.denied" {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { draftFilter = filter; showFilters = true } label: { Label("merchant.filters", systemImage: "line.3.horizontal.decrease.circle") }
                        .accessibilityIdentifier("merchant.orders.filters")
                }
            }
        }
        .sheet(isPresented: $showFilters) {
            NavigationStack {
                Form {
                    Picker("merchant.order.status", selection: $draftFilter.status) {
                        Text("merchant.filter.all").tag(nil as MerchantOrderStatus?)
                        ForEach(MerchantOrderStatus.allCases, id: \.rawValue) { status in
                            Text(LocalizedStringKey(status.titleKey)).tag(Optional(status))
                        }
                    }
                    Picker("merchant.order.aftersale", selection: $draftFilter.aftersaleStatus) {
                        Text("merchant.filter.all").tag(nil as MerchantAftersaleStatus?)
                        ForEach(MerchantAftersaleStatus.allCases, id: \.rawValue) { status in
                            Text(LocalizedStringKey(status.titleKey)).tag(Optional(status))
                        }
                    }
                    Button("merchant.filters.reset") { draftFilter = .init() }
                }
                .navigationTitle("merchant.filters")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("merchant.cancel") { showFilters = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("merchant.filters.apply") {
                            filter = draftFilter; showFilters = false
                            Task { await reload(discardOldValue: true) }
                        }.accessibilityIdentifier("merchant.orders.filters.apply")
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $selection) { selected in
            NavigationStack {
                if reader.isSignedIn && selected.revision == reader.sessionRevision {
                    MerchantOrderSummary(order: selected.order)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("merchant.done") { selection = nil } } }
                } else { ContentUnavailableView("merchant.signIn", systemImage: "lock") }
            }
        }
        .task(id: reader.sessionRevision) { await reload(discardOldValue: true) }
        .onChange(of: reader.sessionRevision) { _, _ in selection = nil; showFilters = false }
    }
    @ViewBuilder private var filterSummary: some View {
        if let status = filter.status { Text(LocalizedStringKey(status.titleKey)) }
        if let aftersale = filter.aftersaleStatus { Text(LocalizedStringKey(aftersale.titleKey)) }
    }
    private func reload(discardOldValue: Bool = false) async {
        let requestedFilter = filter
        let revision = reader.sessionRevision
        await model.load(reader: reader, discardOldValue: discardOldValue) {
            let access = try await reader.merchantAccess()
            guard revision == reader.sessionRevision, reader.isSignedIn else { throw CancellationError() }
            guard access.allows(.orders) else { throw MerchantReadError.accessDenied }
            try Task.checkCancellation()
            return try await reader.merchantOrders(access: access, filter: requestedFilter)
        }
    }
}

private struct MerchantOrderRow: View {
    @Environment(\.locale) private var locale
    let order: MerchantOrder
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(order.orderSn.flatMap { $0.isEmpty ? nil : $0 } ?? appLocalized("merchant.orders",locale:locale))
                .font(.headline)
            MerchantOrderStatusLabel(value: order.status)
            if let time = order.createTime, !time.isEmpty { Text(time).font(.caption).foregroundStyle(.secondary) }
            Text(MerchantMoney.display(order.payAmount)).monospacedDigit()
            if let raw = order.aftersaleStatus, raw >= 2 {
                MerchantAftersaleLabel(value: raw).font(.subheadline).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 4)
    }
}

private struct MerchantOrderSummary: View {
    let order: MerchantOrder
    var body: some View {
        Form {
            Section {
                Text("merchant.summarySnapshot").font(.footnote).foregroundStyle(.secondary)
                if let value = order.orderSn, !value.isEmpty { LabeledContent("merchant.order.number", value: value).textSelection(.enabled) }
                if let value = order.id { MerchantCountRow("merchant.recordID", value: value) }
                LabeledContent { MerchantOrderStatusLabel(value: order.status) } label: { Text("merchant.order.status") }
                if let value = order.aftersaleStatus {
                    LabeledContent { MerchantAftersaleLabel(value: value) } label: { Text("merchant.order.aftersale") }
                }
                LabeledContent("merchant.order.amount", value: MerchantMoney.display(order.payAmount))
                if let value = order.createTime, !value.isEmpty { LabeledContent("merchant.order.created", value: value) }
            }
        }.navigationTitle("merchant.order.summary")
    }
}

private struct MerchantOrderStatusLabel: View {
    let value: Int?
    var body: some View {
        if let value, let known = MerchantOrderStatus(rawValue: value) { Text(LocalizedStringKey(known.titleKey)) }
        else if let value { HStack { Text("merchant.status.unknown"); Text(String(value)) } }
        else { Text("merchant.status.missing").foregroundStyle(.secondary) }
    }
}
private struct MerchantAftersaleLabel: View {
    let value: Int
    var body: some View {
        if let known = MerchantAftersaleStatus(rawValue: value) { Text(LocalizedStringKey(known.titleKey)) }
        else { HStack { Text("merchant.status.unknown"); Text(String(value)) } }
    }
}
