import Foundation

/// One visible opening of a read-only waitlist order. Reopening the same order is a new visit.
struct RegistrationWaitlistOrderVisit: Identifiable, Equatable {
    let id = UUID()
    let presentation: RegistrationWaitlistOrderPresentation
    static func permits(_ captured: Self, current: Self?, destination: RegistrationWaitlistOrderDestination?, isActive: Bool) -> Bool {
        isActive && current == captured && destination == captured.presentation.destination
    }
}
