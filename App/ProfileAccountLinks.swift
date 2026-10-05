import SwiftUI

/// Insert into AccountView's existing Form/NavigationStack. Session owns the reader.
@MainActor
struct ProfileAccountLinks: View {
    let reader: any ProfileReading
    var ordersDestination: (@MainActor () -> AnyView)? = nil
    var participantCoordinator: ParticipantMutationCoordinator? = nil
    var orderLifecycleCoordinator: OrderLifecycleCoordinator? = nil
    var mediaScope: UUID = UUID()
    var makeExternalMaps: (@MainActor () -> PlatformExternalMaps)? = nil
    var body: some View {
        Section("profile.library") {
            NavigationLink {
                if let ordersDestination { ordersDestination() }
                else { ProfileOrdersView(reader: reader, lifecycleCoordinator: orderLifecycleCoordinator, mediaScope: mediaScope, makeExternalMaps: makeExternalMaps) }
            } label: {
                Label("profile.orders.title", systemImage: "list.bullet.rectangle")
            }.accessibilityIdentifier("profile.open.orders")
            NavigationLink { ProfileParticipantsView(reader:reader,coordinator:participantCoordinator) } label: {
                Label("profile.participants.title", systemImage: "person.2")
            }.accessibilityIdentifier("profile.open.participants")
            NavigationLink { ObjectBadgeWallView(reader: reader) } label: {
                Label("profile.badges.title", systemImage: "medal")
            }.accessibilityIdentifier("profile.open.badges")
        }
    }
}
