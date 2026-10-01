import SwiftUI

/// Insert into AccountView's existing Form/NavigationStack. Session owns the reader.
@MainActor
struct ProfileAccountLinks: View {
    let reader: any ProfileReading
    var participantCoordinator: ParticipantMutationCoordinator? = nil
    var body: some View {
        Section("profile.library") {
            NavigationLink { ProfileOrdersView(reader: reader) } label: {
                Label("profile.orders.title", systemImage: "list.bullet.rectangle")
            }.accessibilityIdentifier("profile.open.orders")
            NavigationLink { ProfileParticipantsView(reader:reader,coordinator:participantCoordinator) } label: {
                Label("profile.participants.title", systemImage: "person.2")
            }.accessibilityIdentifier("profile.open.participants")
            NavigationLink { ProfileBadgesView(reader: reader) } label: {
                Label("profile.badges.title", systemImage: "medal")
            }.accessibilityIdentifier("profile.open.badges")
        }
    }
}
