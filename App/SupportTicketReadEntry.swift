import SwiftUI

/// Original ordinary Mine destination, without registration/merchant/club creation context.
@MainActor struct SupportTicketReadEntry: View {
    @ObservedObject var session: AppSession
    var body: some View {
        Section {
            NavigationLink { SupportTicketReadView(session: session) } label: {
                Label { supportTicketReadText("title") } icon: { Image(systemName: "questionmark.bubble") }
            }.accessibilityIdentifier("account.supportTickets")
        }
    }
}
