import SwiftUI

@MainActor private final class WalletScreen<Value>: ObservableObject {
    @Published var value: Value?
    @Published var failed = false
    @Published var loading = false
    @Published var requiresLogin = false
    @Published var loadedScope: WalletCommerceScope?
    private var generation = UUID()
    func cancel() { generation = UUID(); loading = false }
    func clear() { generation = UUID(); value = nil; failed = false; requiresLogin = false; loading = false; loadedScope = nil }
    func load(_ reader: WalletCommerceReader, operation: (WalletCommerceService, String) async throws -> Value) async {
        let stamp = UUID(); generation = stamp; value = nil; failed = false; requiresLogin = false; loading = true
        let scope = reader.scope
        do {
            let result = try await reader.read(operation)
            guard stamp == generation, scope == reader.scope else { return }
            value = result; loadedScope = scope
        } catch {
            guard stamp == generation, scope == reader.scope else { return }
            failed = true; requiresLogin = (error as? APIError) == .unauthorized
        }
        loading = false
    }
}
@MainActor private struct WalletIssueView: View {
    @Environment(\.locale) private var locale
    private var format: WalletFormatting { .init(locale: locale) }
    let reader: WalletCommerceReader
    var requiresLogin = false
    var retry: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedStringKey((reader.scope == nil || requiresLogin) ? "wallet.login" : reader.isConfigured ? "wallet.failed" : "wallet.unavailable")).accessibilityIdentifier("wallet.issue")
            if reader.isConfigured && reader.scope != nil && !requiresLogin {
                Button("wallet.retry", action: retry).frame(minHeight: 44)
            }
        }
    }
}
private struct WalletFormatting {
    let locale: Locale
    func amount(_ value: WalletAmount?, currency: String? = nil) -> String {
        guard let value else { return appLocalized("wallet.unknown", locale: locale) }
        return value.text + " " + (currency ?? appLocalized("wallet.currencyUnknown", locale: locale))
    }
    func points(_ value: WalletAmount?) -> String {
        guard let value else { return appLocalized("wallet.unknownPoints", locale: locale) }
        return value.text + " " + appLocalized("wallet.pointsUnit", locale: locale)
    }
}
/// Additive destination only. Host must keep existing entry gates and reset .id(reader.scope)
/// whenever deployment/account/epoch changes; no new root navigation entry is installed here.
@MainActor struct WalletCommerceHomeView: View {
    @Environment(\.locale) private var locale
    private var format: WalletFormatting { .init(locale: locale) }
    let reader: WalletCommerceReader
    let visibility: WalletCommerceVisibility
    let onCooperationFinance: () -> Void
    var body: some View {
        List {
            if visibility.assets { NavigationLink("wallet.assets") { WalletAssetsView(reader: reader) } }
            if visibility.income { NavigationLink("wallet.income") { WalletIncomeView(reader: reader, onCooperationFinance: onCooperationFinance) } }
            if visibility.points { NavigationLink("wallet.points") { WalletLedgerView(reader: reader, kind: .points) } }
            if visibility.mall { NavigationLink("wallet.mall") { WalletProductsView(reader: reader) } }
            if visibility.withdrawalRecords {
                NavigationLink("withdrawal.support.title") { WithdrawalSupportLandingView(reader: reader) }
                NavigationLink("wallet.withdrawals") { WalletWithdrawalsView(reader: reader) }
            }
        }.appNavigationTitle("wallet.title")
    }
}
@MainActor struct WalletAssetsView: View {
    @Environment(\.locale) private var locale
    private var format: WalletFormatting { .init(locale: locale) }
    let reader: WalletCommerceReader
    @StateObject private var funds = WalletScreen<WalletFundsStages>()
    var body: some View {
        List {
            Section("wallet.fundStages") {
                if funds.loading { ProgressView("wallet.loading") }
                else if let value = funds.value, funds.loadedScope == reader.scope {
                    if !value.amountsKnown { Text("wallet.amountsUnknown") }
                    if value.pendingSettlement.value > 0 { LabeledContent("wallet.pendingSettlement", value: format.amount(value.pendingSettlement, currency: value.currency)) }
                    ForEach(Array(value.complaintPeriod.enumerated()), id: \.offset) { _, item in
                        LabeledContent { Text(format.amount(item.amount, currency: value.currency)) } label: {
                            Text("wallet.complaintPeriod"); Text(verbatim: item.availableDate)
                        }
                    }
                    if value.disputed.value > 0 { LabeledContent("wallet.disputed", value: format.amount(value.disputed, currency: value.currency)) }
                    LabeledContent("wallet.available", value: format.amount(value.withdrawable, currency: value.currency))
                    Text("wallet.notPayout")
                } else { WalletIssueView(reader: reader, requiresLogin: funds.requiresLogin) { Task { await load() } } }
            }
            Section {
                NavigationLink("withdrawal.support.title") { WithdrawalSupportLandingView(reader: reader) }
                NavigationLink("wallet.balanceLedger") { WalletLedgerView(reader: reader, kind: .balance) }
                NavigationLink("wallet.pointsLedger") { WalletLedgerView(reader: reader, kind: .assetPoints) }
            }
        }.appNavigationTitle("wallet.assets").task(id: reader.scope) { funds.clear(); await load() }
            .onDisappear { funds.cancel() }.refreshable { await load() }
    }
    private func load() async { await funds.load(reader) { try await $0.stages(token: $1) } }
}
@MainActor private final class WalletPagerScreen: ObservableObject {
    @Published var revision = 0
    let pager = WalletLedgerPager()
    func reset() { pager.reset(); revision += 1 }
    func cancel() { pager.cancel(); revision += 1 }
    func load(_ reader: WalletCommerceReader, kind: WalletLedgerKind) async {
        revision += 1; await pager.load(reader: reader, kind: kind); revision += 1
    }
}
@MainActor struct WalletLedgerView: View {
    @Environment(\.locale) private var locale
    private var format: WalletFormatting { .init(locale: locale) }
    let reader: WalletCommerceReader
    let kind: WalletLedgerKind
    @StateObject private var model = WalletPagerScreen()
    @State private var direction = "all"
    private var points: Bool { kind == .points || kind == .assetPoints }
    private var income: Bool { if case .income = kind { return true }; return false }
    private var filtered: [WalletLedgerRow] {
        model.pager.rows.filter { row in
            direction == "all" || (income ? row.incomeDirection : row.assetDirection).rawValue == direction
        }
    }
    var body: some View {
        List {
            Picker("wallet.direction", selection: $direction) {
                Text("wallet.all").tag("all"); Text("wallet.inflow").tag("income"); Text("wallet.outflow").tag("expense")
            }.pickerStyle(.menu)
            if points { Text("wallet.loadedFilter"); NavigationLink("wallet.tasks") { WalletPointsTasksView(reader: reader) } }
            if model.pager.loadedScope == reader.scope {
                if points { LabeledContent("wallet.pointsBalance", value: format.points(model.pager.rows.first?.afterPoints)) }
                if filtered.isEmpty && !model.pager.isLoading && !model.pager.failed { Text("wallet.empty") }
                ForEach(filtered) { row in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: row.changeReason ?? appLocalized("wallet.entry", locale: locale))
                        if income { Text(LocalizedStringKey(row.incomeEventKey)) }
                        Text(LocalizedStringKey("wallet.direction." + (income ? row.incomeDirection : row.assetDirection).rawValue))
                        HStack {
                            Text(verbatim: row.signedText(points: points, income: income) ?? appLocalized("wallet.unknown", locale: locale))
                            if points { Text("wallet.pointsUnit") }
                            else { Text(verbatim: row.currency ?? appLocalized("wallet.currencyUnknown", locale: locale)) }
                        }
                        if !points, let balance = row.afterBalance { LabeledContent("wallet.balanceAfter", value: format.amount(balance, currency: row.currency)) }
                        if let date = row.createTime { Text(verbatim: date).font(.caption) }
                    }.accessibilityElement(children: .combine).accessibilityIdentifier("wallet.ledger.\(row.id)")
                }
            }
            if model.pager.failed || !reader.isConfigured || reader.scope == nil {
                WalletIssueView(reader: reader) { Task { await model.load(reader, kind: kind) } }
            }
            if model.pager.isLoading { ProgressView("wallet.loading") }
            else if model.pager.hasMore && reader.isConfigured && reader.scope != nil {
                Button("wallet.loadMore") { Task { await model.load(reader, kind: kind) } }.frame(minHeight: 44)
            }
        }.appNavigationTitle(key: points ? "wallet.pointsLedger" : "wallet.balanceLedger")
            .task(id: reader.scope) { model.reset(); await model.load(reader, kind: kind) }
            .onDisappear { model.cancel() }
            .refreshable { model.reset(); await model.load(reader, kind: kind) }
    }
}
@MainActor struct WalletIncomeView: View {
    @Environment(\.locale) private var locale
    private var format: WalletFormatting { .init(locale: locale) }
    let reader: WalletCommerceReader
    let onCooperationFinance: () -> Void
    @State private var filter = WalletIncomeFilter.all
    var body: some View {
        VStack {
            Picker("wallet.income", selection: $filter) {
                Text("wallet.all").tag(WalletIncomeFilter.all)
                Text("wallet.creationIncome").tag(WalletIncomeFilter.create)
                Text("wallet.brandIncome").tag(WalletIncomeFilter.brand)
            }.pickerStyle(.segmented).padding()
            Button("wallet.clubFinance", action: onCooperationFinance).frame(minHeight: 44)
            WalletLedgerView(reader: reader, kind: .income(filter)).id(filter.rawValue)
        }.appNavigationTitle("wallet.income")
    }
}
@MainActor struct WalletProductsView: View {
    @Environment(\.locale) private var locale
    private var format: WalletFormatting { .init(locale: locale) }
    let reader: WalletCommerceReader
    @StateObject private var model = WalletScreen<WalletPage<WalletProduct>>()
    @State private var keyword = ""
    @State private var sort = 0
    var body: some View {
        List {
            NavigationLink("wallet.cart") { WalletCartView(reader: reader) }
            Picker("wallet.sort", selection: $sort) {
                ForEach(0..<5) { value in Text(LocalizedStringKey("wallet.sort." + String(value))).tag(value) }
            }.onChange(of: sort) { _, _ in Task { await load() } }
            if model.loading { ProgressView("wallet.loading") }
            else if let page = model.value, model.loadedScope == reader.scope {
                if page.rows.isEmpty { Text("wallet.empty") }
                ForEach(page.rows) { item in
                    NavigationLink { WalletProductView(reader: reader, productID: item.id) } label: {
                        VStack(alignment: .leading) {
                            Text(verbatim: item.productName ?? appLocalized("wallet.product", locale: locale))
                            Text(format.points(item.price))
                        }.accessibilityElement(children: .combine)
                    }
                }
                if let total = page.total, total > page.rows.count { Text("wallet.sourceLimited") }
            } else { WalletIssueView(reader: reader, requiresLogin: model.requiresLogin) { Task { await load() } } }
        }.appNavigationTitle("wallet.mall").searchable(text: $keyword)
            .onSubmit(of: .search) { Task { await load() } }
            .task(id: reader.scope) { model.clear(); await load() }
            .onDisappear { model.cancel() }.refreshable { await load() }
    }
    private func load() async {
        let search = keyword; let order = sort
        await model.load(reader) { try await $0.products(sortType: order, keyword: search, token: $1) }
    }
}
@MainActor struct WalletProductView: View {
    @Environment(\.locale) private var locale
    private var format: WalletFormatting { .init(locale: locale) }
    let reader: WalletCommerceReader
    let productID: Int
    @StateObject private var model = WalletScreen<WalletProduct>()
    var body: some View {
        List {
            if model.loading { ProgressView("wallet.loading") }
            else if let item = model.value, model.loadedScope == reader.scope {
                Text(verbatim: item.productName ?? appLocalized("wallet.product", locale: locale)).font(.title2)
                LabeledContent("wallet.price", value: format.points(item.price))
                LabeledContent("wallet.stock", value: item.stock.map(String.init) ?? appLocalized("wallet.unknown", locale: locale))
                ForEach(item.skuList ?? []) { sku in
                    VStack(alignment: .leading) {
                        Text(verbatim: sku.skuName ?? appLocalized("wallet.sku", locale: locale))
                        Text(format.points(sku.price))
                        LabeledContent("wallet.stock", value: sku.stock.map(String.init) ?? appLocalized("wallet.unknown", locale: locale))
                    }.accessibilityElement(children: .combine)
                }
                if let html = item.detailHtml {
                    // Plain accessible text only: never execute HTML or load remote resources.
                    Text(verbatim: html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression))
                }
                Text("wallet.dormant").accessibilityIdentifier("wallet.dormant")
            } else { WalletIssueView(reader: reader, requiresLogin: model.requiresLogin) { Task { await load() } } }
        }.appNavigationTitle("wallet.product").task(id: reader.scope) { model.clear(); await load() }.onDisappear { model.cancel() }
    }
    private func load() async { await model.load(reader) { try await $0.product(id: productID, token: $1) } }
}
@MainActor struct WalletCartView: View {
    @Environment(\.locale) private var locale
    private var format: WalletFormatting { .init(locale: locale) }
    let reader: WalletCommerceReader
    @StateObject private var model = WalletScreen<WalletPage<WalletCartItem>>()
    @State private var selected = Set<Int>()
    var body: some View {
        List {
            if model.loading { ProgressView("wallet.loading") }
            else if let page = model.value, model.loadedScope == reader.scope {
                if page.rows.isEmpty { Text("wallet.empty") }
                ForEach(page.rows) { item in
                    Toggle(isOn: Binding(get: { selected.contains(item.id) }, set: { yes in
                        if yes { selected.insert(item.id) } else { selected.remove(item.id) }
                    })) {
                        VStack(alignment: .leading) {
                            Text(verbatim: item.productName ?? appLocalized("wallet.product", locale: locale))
                            Text(format.points(item.price))
                            LabeledContent("wallet.quantity", value: String(item.quantity))
                            LabeledContent("wallet.subtotal", value: format.points(item.subtotalPoints.map(WalletAmount.init)))
                        }
                    }.accessibilityIdentifier("wallet.cart.\(item.id)")
                }
                if !selected.isEmpty {
                    NavigationLink("wallet.preview") { WalletCheckoutView(reader: reader, cartIDs: selected.sorted()) }
                }
                if let total = page.total, total > page.rows.count { Text("wallet.sourceLimited") }
                Text("wallet.dormant")
            } else { WalletIssueView(reader: reader, requiresLogin: model.requiresLogin) { Task { await load() } } }
        }.appNavigationTitle("wallet.cart").task(id: reader.scope) { selected = []; model.clear(); await load() }
            .onDisappear { model.cancel() }.refreshable { selected = []; await load() }
    }
    private func load() async { await model.load(reader) { try await $0.cart(token: $1) } }
}
@MainActor struct WalletCheckoutView: View {
    @Environment(\.locale) private var locale
    private var format: WalletFormatting { .init(locale: locale) }
    let reader: WalletCommerceReader
    let cartIDs: [Int]
    @StateObject private var model = WalletScreen<WalletCheckoutPreview>()
    var body: some View {
        List {
            if model.loading { ProgressView("wallet.loading") }
            else if let preview = model.value, model.loadedScope == reader.scope {
                LabeledContent("wallet.productAmount", value: format.points(preview.productAmount))
                LabeledContent("wallet.deliveryFee", value: format.points(preview.deliveryFee))
                LabeledContent("wallet.taxFee", value: format.points(preview.taxFee))
                LabeledContent("wallet.total", value: format.points(preview.totalAmount))
                LabeledContent("wallet.requiredPoints", value: format.points(preview.requiredPoints.map(WalletAmount.init)))
                LabeledContent("wallet.pointsBalance", value: format.points(preview.pointBalance))
                if let enough = preview.hasEnoughPoints { Text(LocalizedStringKey(enough ? "wallet.sufficient" : "wallet.insufficient")) }
                else { Text("wallet.balanceUnknown") }
                if let address = preview.address {
                    LabeledContent("wallet.addressReference", value: String(address.id))
                    if let phone = address.maskedPhone { Text(verbatim: phone) }
                } else { Text("wallet.addressMissing") }
                Text("wallet.previewOnly").accessibilityIdentifier("wallet.previewOnly")
                Text("wallet.dormant")
            } else { WalletIssueView(reader: reader, requiresLogin: model.requiresLogin) { Task { await load() } } }
        }.appNavigationTitle("wallet.preview").task(id: reader.scope) { model.clear(); await load() }.onDisappear { model.cancel() }
    }
    private func load() async { await model.load(reader) { try await $0.checkout(cartIDs: cartIDs, token: $1) } }
}
@MainActor struct WalletWithdrawalsView: View {
    @Environment(\.locale) private var locale
    private var format: WalletFormatting { .init(locale: locale) }
    let reader: WalletCommerceReader
    @StateObject private var model = WalletScreen<WalletPage<WalletWithdrawalRecord>>()
    var body: some View {
        List {
            Text("bank.withdrawal.historyNotice")
            if model.loading { ProgressView("wallet.loading") }
            else if let page = model.value, model.loadedScope == reader.scope {
                if page.rows.isEmpty { Text("wallet.empty") }
                ForEach(page.rows) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(format.amount(item.amount, currency: item.currency))
                        Text(LocalizedStringKey(item.statusKey))
                        if let date = item.createTime { Text(verbatim: date) }
                        if let account = item.maskedAccount { Text(verbatim: account) }
                    }.accessibilityElement(children: .combine).accessibilityIdentifier("wallet.withdrawal.\(item.id)")
                }
                if let total = page.total, total > page.rows.count { Text("wallet.sourceLimited") }
            } else { WalletIssueView(reader: reader, requiresLogin: model.requiresLogin) { Task { await load() } } }
        }.appNavigationTitle("wallet.withdrawals").task(id: reader.scope) { model.clear(); await load() }
            .onDisappear { model.cancel() }.refreshable { await load() }
    }
    private func load() async { await model.load(reader) { try await $0.withdrawals(token: $1) } }
}

@MainActor struct WalletPointsTasksView: View {
    @Environment(\.locale) private var locale
    private var format: WalletFormatting { .init(locale: locale) }
    let reader: WalletCommerceReader
    @StateObject private var model = WalletScreen<[WalletPointsTask]>()
    var body: some View {
        List {
            if model.loading { ProgressView("wallet.loading") }
            else if let rows = model.value, model.loadedScope == reader.scope {
                if rows.isEmpty { Text("wallet.empty") }
                ForEach(rows) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: item.title ?? appLocalized("wallet.entry", locale: locale))
                        if let description = item.description { Text(verbatim: description) }
                        Text(format.points(item.value))
                        LabeledContent("wallet.doneCount", value: item.pointsNum.map(String.init) ?? appLocalized("wallet.unknown", locale: locale))
                    }.accessibilityElement(children: .combine)
                }
            } else { WalletIssueView(reader: reader, requiresLogin: model.requiresLogin) { Task { await load() } } }
        }.appNavigationTitle("wallet.tasks").task(id: reader.scope) { model.clear(); await load() }.onDisappear { model.cancel() }
    }
    private func load() async { await model.load(reader) { try await $0.pointsTasks(token: $1) } }
}
