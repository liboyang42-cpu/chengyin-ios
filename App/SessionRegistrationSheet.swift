import SwiftUI

/// Environment observation resets the form when the authenticated identity/epoch changes.
@MainActor struct SessionRegistrationSheet:View {
    let activity:ActivityDetail
    @EnvironmentObject private var session:AppSession
    var body:some View {
        RegistrationSheetView(activity:activity,coordinator:session.registrationCoordinator,
                              participantReader:session.profileReader,
                              orderReader:session.ownedOrderReader,
                              participantCoordinator:session.participantCoordinator,
                              currentIdentity:{ session.profileReader.identity },
                              quoteEnabled:session.isConfigured,
                              creationPolicy:session.registrationCreationPolicy(activityID:activity.summary.id),
                              waitlistService:session.registrationWaitlistService(activityID:activity.summary.id))
    }
}
