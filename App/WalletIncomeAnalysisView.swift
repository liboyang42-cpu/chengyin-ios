import SwiftUI

/// Original income-table analysis: at most ten approved 20-row reads, not an atomic snapshot.
@MainActor struct WalletIncomeAnalysisView: View {
    let reader: WalletCommerceReader
    @StateObject private var model = WalletIncomeAnalysisReader()
    @Environment(\.scenePhase) private var phase
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.themeDomain) private var domain
    @State private var visible = false
    @State private var mode = WalletIncomeAnalysisPresentation.Mode.income
    @State private var selectedCurrency: String?
    @State private var measuredAt = Date()
    private func text(_ key: String) -> Text { Text(LocalizedStringKey("wallet.analysis." + key), tableName: "WalletIncomeAnalysis") }
    private func readText(_ key: String) -> Text { Text(LocalizedStringKey("wallet.analysis.read." + key), tableName: "WalletIncomeAnalysisRead") }
    var body: some View {
        List {
            if !reader.isConfigured { text("unavailable") }
            else if reader.scope == nil || model.requiresLogin { text("login") }
            else if model.loading {
                Section {
                    ProgressView { text("loading") }.frame(maxWidth: .infinity)
                }.accessibilityIdentifier("wallet.analysis.loading")
            }
            else if model.unavailable { text("unavailable") }
            else if model.failed {
                Label { text("failed") } icon: { Image(systemName: "exclamationmark.circle").accessibilityHidden(true) }
                    .font(Theme.Font.sectionTitle).fixedSize(horizontal: false, vertical: true)
                Button { Task { await load() } } label: { text("retry") }
                    .buttonStyle(.bordered).controlSize(.large).frame(minHeight: 44)
            } else if let slice = model.displayedResult(for: reader) {
                content(slice)
            } else { ProgressView { text("loading") } }
        }
        .listStyle(.insetGrouped)
        .font(Theme.Font.body)
        .scrollContentBackground(.hidden)
        .background(Theme.Color.bgPage(in: domain))
        .labeledContentStyle(WalletIncomeAnalysisDetailStyle())
        .navigationTitle(text("title"))
        .themeDomain(domain)
        .tint(Theme.Color.accent(in: domain))
        .privacySensitive()
        .task(id: WalletIncomeAnalysisReadIdentity(reader)) { visible = true; await load() }
        .refreshable { await load() }
        .onDisappear { visible = false; model.cancel() }
        .disabled(phase != .active)
        .onChange(of: phase) { _, value in
            if value != .active { model.cancel() }
            else if visible { Task { await load() } }
        }
        .accessibilityIdentifier("wallet.analysis")
    }
    @ViewBuilder private func content(_ slice: WalletIncomeAnalysisSlice) -> some View {
        let currencies = WalletIncomeAnalysisPresentation.currencies(slice.rows)
        let currency = selectedCurrency.flatMap { currencies.contains($0) ? $0 : nil } ?? currencies.first
        let summary = WalletIncomeAnalysisPresentation(rows: slice.rows, mode: mode, currency: currency, now: measuredAt)
        Section {
            // Mini-program `an-seg` 收入 / 提现 first; read-mechanics notes are not user copy.
            if slice.isPartial {
                Label { readText("partial") } icon: { Image(systemName: "exclamationmark.circle").accessibilityHidden(true) }
                Button { Task { await load() } } label: { text("retry") }
                    .accessibilityIdentifier("wallet.analysis.partial.retry")
            } else if slice.stop == .budget {
                readText("budget").font(Theme.Font.label).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if dynamicTypeSize.isAccessibilitySize { modePicker.pickerStyle(.menu) }
            else { modePicker.pickerStyle(.segmented) }
            if currencies.count > 1 {
                Picker(selection: Binding(get: { currency ?? "" }, set: { selectedCurrency = $0 })) {
                    ForEach(currencies, id: \.self) { Text(verbatim: $0).tag($0) }
                } label: { text("currency") }
            }
            if summary.unknownCount > 0 {
                LabeledContent { Text(verbatim: String(summary.unknownCount)) } label: { text("unknown") }
            }
        }
        if slice.rows.isEmpty { if slice.isPartial { readText("noVerifiedRecords") } else { text("empty") } }
        else if let currency {
            Section {
                if let current = summary.months.last {
                    VStack(alignment: .leading, spacing: Theme.Space.s2) {
                        Text(verbatim: current.id).font(Theme.Font.label).foregroundStyle(.secondary)
                        monthAmount(current, summary: summary, currency: currency)
                            .font(.system(.largeTitle, weight: .semibold)).monospacedDigit()
                            .fixedSize(horizontal: false, vertical: true)
                        if summary.unknownCount > 0 { text("knownSubtotal").font(Theme.Font.label).foregroundStyle(.secondary) }
                    }.padding(.vertical, Theme.Space.s3)
                }
                if !dynamicTypeSize.isAccessibilitySize {
                    monthChart(summary)
                        .accessibilityHidden(true)
                    DisclosureGroup { monthRows(summary, currency: currency) } label: { text("months") }
                } else { monthRows(summary, currency: currency) }
            } header: { text("months") }
            if mode == .income {
                Section {
                    if summary.sources.isEmpty { text("noSources") }
                    ForEach(summary.sources) { source in
                        VStack(alignment: .leading, spacing: Theme.Space.s2) {
                            LabeledContent { Text(verbatim: WalletIncomeAnalysisPresentation.text(source.amount, currency: currency, locale: locale)).monospacedDigit().font(Theme.Font.cardTitle) } label: { text("source." + source.id) }
                            GeometryReader { geometry in
                                Capsule().fill(Theme.Color.success(in: domain))
                                    .frame(width: geometry.size.width * CGFloat(sourceFraction(source, summary: summary)))
                            }.frame(height: Theme.Space.s1).accessibilityHidden(true)
                        }.padding(.vertical, Theme.Space.s2).accessibilityElement(children: .combine)
                    }
                } header: { text("sources") }
            }
        } else { text("currencyUnknown") }
    }
    @ViewBuilder private func monthAmount(_ month: WalletIncomeAnalysisPresentation.Month,
                                          summary: WalletIncomeAnalysisPresentation, currency: String) -> some View {
        if summary.unknownCount > 0, month.count == 0 { text("unverified") }
        else { Text(verbatim: WalletIncomeAnalysisPresentation.text(month.amount, currency: currency, locale: locale)) }
    }
    private func monthRows(_ summary: WalletIncomeAnalysisPresentation, currency: String) -> some View {
        ForEach(summary.months) { month in
            VStack(alignment: .leading, spacing: Theme.Space.s1) {
                LabeledContent { monthAmount(month, summary: summary, currency: currency).monospacedDigit() }
                    label: { Text(verbatim: month.id) }
                if summary.unknownCount > 0, month.count > 0 { text("knownSubtotal").font(Theme.Font.label).foregroundStyle(.secondary) }
            }.fixedSize(horizontal: false, vertical: true).accessibilityElement(children: .combine)
        }
    }
    private func monthChart(_ summary: WalletIncomeAnalysisPresentation) -> some View {
        HStack(alignment: .bottom, spacing: Theme.Space.s3) {
            ForEach(summary.months) { month in
                VStack(spacing: Theme.Space.s2) {
                    GeometryReader { geometry in
                        VStack {
                            Spacer(minLength: 0)
                            if summary.unknownCount == 0 || month.count > 0 {
                                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                                    .fill(month.id == summary.months.last?.id ? Theme.Color.textPrimary(in: domain) : Theme.Color.bgRaised(in: domain))
                                    .frame(height: geometry.size.height * CGFloat(summary.fraction(month.amount)))
                            }
                        }
                    }.frame(height: 120)
                    Text(verbatim: String(month.id.suffix(2))).font(Theme.Font.label).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity)
            }
        }.padding(.vertical, Theme.Space.s3)
    }
    private func sourceFraction(_ source: WalletIncomeAnalysisPresentation.Source,
                                summary: WalletIncomeAnalysisPresentation) -> Double {
        guard let maximum = summary.sources.map(\.amount).max(), maximum > 0 else { return 0 }
        let fraction = NSDecimalNumber(decimal: source.amount / maximum).doubleValue
        return fraction.isFinite ? min(1, max(0, fraction)) : 0
    }
    private var modePicker: some View {
        Picker(selection: $mode) {
            text("income").tag(WalletIncomeAnalysisPresentation.Mode.income)
            text("withdrawal").tag(WalletIncomeAnalysisPresentation.Mode.withdrawal)
        } label: { text("mode") }
    }
    private func load() async {
        guard visible, phase == .active, !Task.isCancelled else { return }
        measuredAt = Date()
        await model.load(reader)
    }
}


// Feature-local layout; it neither supplies a reader nor alters any value.
private struct WalletIncomeAnalysisDetailStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s2) {
            configuration.label.font(Theme.Font.body).foregroundStyle(.secondary)
            configuration.content.fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
