import SwiftUI

@MainActor struct InvoiceLaunchApplyView: View {
    @ObservedObject var model: InvoiceLaunchPresentation
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @State private var titleID: Int64?
    @State private var selected = Set<Int64>()
    @State private var choosingTitle = false
    private var title: InvoiceLaunchTitle? { model.overview?.titles.first { $0.id == titleID } }
    private var canSubmit: Bool {
        model.allows(.apply) && title != nil && !selected.isEmpty && selected.count <= 50
            && selected.isSubset(of: Set(model.overview?.eligibleOrders.map(\.orderId) ?? []))
    }
    var body: some View {
        List {
            InvoiceLaunchStateSection(model: model)
            if let overview = model.overview {
                Section {
                    Button { choosingTitle = true } label: {
                        LabeledContent { Text(verbatim: title?.titleName ?? "—") } label: { invoiceText("chooseTitle") }
                    }.disabled(!model.allows(.apply))
                } header: { invoiceText("titles") }
                Section {
                    if overview.eligibleOrders.isEmpty { invoiceText("noOrders") }
                    ForEach(overview.eligibleOrders, id: \.orderId) { order in
                        Toggle(isOn: Binding(get: { selected.contains(order.orderId) }, set: { on in
                            if on { selected.insert(order.orderId) } else { selected.remove(order.orderId) }
                        })) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(verbatim: order.orderTitle ?? "—")
                                Text(verbatim: invoiceAmount(order.amount, locale: locale))
                            }
                        }.disabled(!model.allows(.apply) || (!selected.contains(order.orderId) && selected.count >= 50))
                        .accessibilityIdentifier("invoice.select.\(order.orderId)")
                    }
                } header: { invoiceText("orders") }
                LabeledContent { Text(selected.count, format: .number) } label: { invoiceText("selectedCount") }
                if model.allows(.apply) {
                    Button {
                        guard let titleID, canSubmit else { return }
                        Task { if await model.apply(titleID: titleID, orderIDs: selected.sorted()) { dismiss() } }
                    } label: { invoiceText("submit") }.disabled(!canSubmit)
                        .accessibilityIdentifier("invoice.submit")
                }
            }
        }
        .navigationTitle(invoiceText("apply")).listStyle(.insetGrouped)
        .onChange(of: model.identityRevision) { _, _ in titleID = nil; selected = []; choosingTitle = false; dismiss() }
        .sheet(isPresented: $choosingTitle) { titlePicker }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { titleID = nil; selected = []; choosingTitle = false }
        }
    }
    private var titlePicker: some View {
        NavigationStack {
            List(model.overview?.titles ?? [], id: \.id) { candidate in
                Button {
                    titleID = candidate.id; choosingTitle = false
                } label: {
                    HStack {
                        Text(verbatim: candidate.titleName)
                        Spacer()
                        if candidate.id == titleID { Image(systemName: "checkmark") }
                    }
                }.disabled(!model.allows(.apply))
            }.navigationTitle(invoiceText("chooseTitle"))
        }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }
}
