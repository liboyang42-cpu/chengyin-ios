import SwiftUI

/// Environment observation resets the form when the authenticated identity/epoch changes.
@MainActor struct SessionRegistrationSheet:View {
    let activity:ActivityDetail
    @EnvironmentObject private var session:AppSession
    var body:some View {
        RegistrationSheetView(activity:activity,coordinator:session.registrationCoordinator,
                              participantReader:session.profileReader,
                              participantCoordinator:session.participantCoordinator,
                              currentIdentity:{ session.profileReader.identity },
                              quoteEnabled:session.isConfigured,creationPolicy:.disabled)
    }
}
