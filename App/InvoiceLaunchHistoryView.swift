import SwiftUI

/// Mount only from a reviewed normal account entry, retaining the same model across child pages.
@MainActor struct InvoiceLaunchHistoryView: View {
    @ObservedObject var model: InvoiceLaunchPresentation
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @State private var filter = "all"
    private var rows: [InvoiceLaunchApplication] {
        (model.overview?.applications ?? []).filter { filter == "all" || $0.status.rawValue == filter }
    }
    var body: some View {
        List {
            InvoiceLaunchStateSection(model: model)
            if let overview = model.overview {
                if !overview.applications.isEmpty {
                    Picker(selection: $filter) {
                        invoiceText("all").tag("all")
                        invoiceText("SUBMITTED").tag("SUBMITTED")
                        invoiceText("ISSUED").tag("ISSUED")
                        invoiceText("REJECTED").tag("REJECTED")
                        invoiceText("CANCELLED").tag("CANCELLED")
                    } label: { invoiceText("status") }
                    .pickerStyle(.menu).accessibilityIdentifier("invoice.history.filter")
                }
                if rows.isEmpty {
                    ContentUnavailableView { Label { invoiceText("empty") } icon: { Image(systemName: "doc.text") } }
                }
                ForEach(rows, id: \.id) { row in
                    NavigationLink {
                        InvoiceLaunchDetailView(model: model, applicationID: row.id)
                    } label: { historyRow(row) }
                    .accessibilityIdentifier("invoice.history.row.\(row.id)")
                }
                Section {
                    NavigationLink { InvoiceLaunchTitlesView(model: model) } label: { invoiceText("titles") }
                        .accessibilityIdentifier("invoice.titles.entry")
                    if model.allows(.apply) {
                        NavigationLink { InvoiceLaunchApplyView(model: model) } label: { invoiceText("apply") }
                            .accessibilityIdentifier("invoice.apply.entry")
                    }
                }
            }
        }
        .listStyle(.insetGrouped).navigationTitle(invoiceText("history"))
        .task { await model.refresh() }.refreshable { await model.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.invalidate() }
            else { Task { await model.refresh() } }
        }
    }
    private func historyRow(_ row: InvoiceLaunchApplication) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: row.titleName).font(.headline)
                Spacer()
                invoiceText(row.status.rawValue)
            }
            LabeledContent { invoiceText(row.titleType) } label: { invoiceText("titleType") }
            if let tax = row.taxNoMasked, !tax.isEmpty {
                LabeledContent { Text(verbatim: tax) } label: { invoiceText("taxNo") }
            }
            LabeledContent { Text(verbatim: invoiceTime(row.createTime, locale: locale)) } label: { invoiceText("created") }
            LabeledContent { Text(row.orderCount, format: .number) } label: { invoiceText("orderCount") }
            LabeledContent { Text(verbatim: invoiceAmount(row.totalAmount, locale: locale)) } label: { invoiceText("amount") }
        }.fixedSize(horizontal: false, vertical: true)
    }
}
