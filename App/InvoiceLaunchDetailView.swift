import SwiftUI

@MainActor struct InvoiceLaunchDetailView: View {
    @ObservedObject var model: InvoiceLaunchPresentation
    let applicationID: Int64
    @Environment(\.locale) private var locale
    @State private var confirmsCancel = false
    var body: some View {
        List {
            InvoiceLaunchStateSection(model: model, retry: { await model.loadDetail(applicationID) })
            if let row = model.detail, row.id == applicationID {
                Section {
                    invoiceText(row.status.rawValue).font(.title2).bold()
                    if let reason = row.rejectReason, !reason.isEmpty { Text(verbatim: reason) }
                }
                Section {
                    LabeledContent { Text(verbatim: row.titleName) } label: { invoiceText("titleName") }
                    LabeledContent { invoiceText(row.titleType) } label: { invoiceText("titleType") }
                    if let tax = row.taxNoMasked, !tax.isEmpty {
                        LabeledContent { Text(verbatim: tax) } label: { invoiceText("taxNo") }
                    }
                    if row.status == .issued {
                        if let number = row.invoiceNo, !number.isEmpty {
                            LabeledContent { Text(verbatim: number).textSelection(.enabled) } label: { invoiceText("invoiceNo") }
                        }
                        LabeledContent { Text(verbatim: invoiceTime(row.issuedAt, locale: locale)) } label: { invoiceText("issuedAt") }
                    }
                } header: { invoiceText("information") }
                Section {
                    ForEach(row.orders, id: \.orderId) { order in
                        LabeledContent {
                            Text(verbatim: invoiceAmount(order.amount, locale: locale))
                        } label: { Text(verbatim: order.orderTitle ?? "—") }
                    }
                    LabeledContent { Text(verbatim: invoiceAmount(row.totalAmount, locale: locale)).bold() } label: { invoiceText("amount") }
                } header: { invoiceText("orders") }
                if row.status == .submitted && model.allows(.cancel) {
                    Section {
                        Button(role: .destructive) { confirmsCancel = true } label: { invoiceText("withdraw") }
                            .accessibilityIdentifier("invoice.cancel")
                    }
                }
            }
        }
        .listStyle(.insetGrouped).navigationTitle(invoiceText("detail"))
        .task(id: applicationID) { await model.loadDetail(applicationID) }
        .refreshable { await model.loadDetail(applicationID) }
        .confirmationDialog(invoiceText("withdrawConfirm"), isPresented: $confirmsCancel, titleVisibility: .visible) {
            Button(role: .destructive) {
                Task { if await model.cancel(applicationID) { await model.loadDetail(applicationID) } }
            } label: { invoiceText("withdraw") }
            Button(role: .cancel) {} label: { invoiceText("keep") }
        }
    }
}
