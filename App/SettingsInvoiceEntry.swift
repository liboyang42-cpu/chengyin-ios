import SwiftUI

/// Reuses the normal account reader and its original-request recovery.
/// A missing real read approval hides this entry; no write capability is issued here.
@MainActor struct SettingsInvoiceEntry: View {
    @ObservedObject var session: AppSession
    var body: some View {
        if let invoice = session.makeInvoiceLaunchPresentation() {
            Section {
                NavigationLink {
                    InvoiceLaunchHistoryView(model: invoice)
                } label: {
                    Label { invoiceText("history") } icon: {
                        Image(systemName: "doc.text").accessibilityHidden(true)
                    }
                }
                .accessibilityIdentifier("settings.invoices")
            }
        }
    }
}
