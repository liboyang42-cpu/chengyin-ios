import SwiftUI

@MainActor struct InvoiceLaunchTitlesView: View {
    @ObservedObject var model: InvoiceLaunchPresentation
    @State private var deleteID: Int64?
    var body: some View {
        List {
            InvoiceLaunchStateSection(model: model)
            if let overview = model.overview {
                if overview.titles.isEmpty {
                    ContentUnavailableView { Label { invoiceText("noTitles") } icon: { Image(systemName: "person.text.rectangle") } }
                }
                ForEach(overview.titles, id: \.id) { title in
                    Section {
                        LabeledContent { invoiceText(title.titleType) } label: { Text(verbatim: title.titleName) }
                        if let tax = title.taxNoMasked, !tax.isEmpty { Text(verbatim: tax) }
                        if title.isDefault { invoiceText("defaultTitle") }
                        if model.allows(.saveTitle) {
                            NavigationLink { InvoiceLaunchTitleEditor(model: model, title: title) } label: { invoiceText("edit") }
                                .accessibilityIdentifier("invoice.title.edit.\(title.id)")
                        }
                        if model.allows(.deleteTitle) {
                            Button(role: .destructive) { deleteID = title.id } label: { invoiceText("delete") }
                                .accessibilityIdentifier("invoice.title.delete.\(title.id)")
                        }
                    }
                }
                if model.allows(.saveTitle) {
                    NavigationLink { InvoiceLaunchTitleEditor(model: model, title: nil) } label: { invoiceText("addTitle") }
                        .accessibilityIdentifier("invoice.title.add")
                }
            }
        }
        .listStyle(.insetGrouped).navigationTitle(invoiceText("titles"))
        .task { await model.refresh() }.refreshable { await model.refresh() }
        .confirmationDialog(invoiceText("deleteConfirm"), isPresented: Binding(
            get: { deleteID != nil }, set: { if !$0 { deleteID = nil } }), titleVisibility: .visible) {
            Button(role: .destructive) {
                if let id = deleteID { Task { _ = await model.delete(id) } }
                deleteID = nil
            } label: { invoiceText("delete") }
            Button(role: .cancel) { deleteID = nil } label: { invoiceText("keep") }
        }
    }
}
