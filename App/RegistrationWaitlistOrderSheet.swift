import SwiftUI

/// A separate read-only sheet keeps the registration form and its replay locks intact.
/// Dismissal returns to that form; it never claims, cancels, pays or replaces an order.
@MainActor struct RegistrationWaitlistOrderSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let reader: RegistrationWaitlistOrderReader
    init(presentation: RegistrationWaitlistOrderPresentation, reader: any ProfileReading, isCurrent: @escaping () -> Bool) {
        self.reader = .init(presentation: presentation, base: reader, isCurrent: isCurrent)
    }
    var body: some View {
        NavigationStack {
            ProfileOrderDetailView(id: reader.destination.registrationID, reader: reader)
                .id(reader.identity)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("action.close") { dismiss() }
                            .accessibilityIdentifier("registration.waitlist.order.close")
                    }
                }
        }
        .accessibilityIdentifier("registration.waitlist.order.sheet")
    }
}
