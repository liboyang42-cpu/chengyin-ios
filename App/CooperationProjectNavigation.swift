import SwiftUI

private struct CooperationProjectDestinationKey: EnvironmentKey {
    static let defaultValue: ((Int) -> AnyView)? = nil
}
extension EnvironmentValues {
    /// Existing public topic screen, supplied by the list. Nil does not navigate.
    var cooperationProjectDestination: ((Int) -> AnyView)? {
        get { self[CooperationProjectDestinationKey.self] }
        set { self[CooperationProjectDestinationKey.self] = newValue }
    }
}

/// Invite → bound topic. A missing or non-positive topic does not open.
/// The invite id stays on the route so Back re-reads that invite instead of sending another.
struct CooperationProjectNavigation: Equatable {
    let topicID: Int
    let invite: CooperationInviteKey
    var opens: Bool { topicID > 0 }
}

/// Account, authentication, or reader identity. Applied to the list stack so the old push closes.
struct CooperationProjectNavigationHost: Hashable {
    let scope: UUID
    let authenticated: Bool
    let reader: ObjectIdentifier
}

/// Public topic entry. The closure is the existing destination; this view grants no edit and sends no invite.
struct CooperationProjectNavigationLink: View {
    let topicID: Int?
    let invite: CooperationInviteKey
    let destination: ((Int) -> AnyView)?
    @Binding var openedTopic: Int?
    var body: some View {
        let route = topicID.map { CooperationProjectNavigation(topicID: $0, invite: invite) }
        if let route, route.opens, destination != nil {
            Button("cooperation.detail.project") { openedTopic = route.topicID }
                .accessibilityIdentifier("cooperation.project.open.\(route.topicID)")
        }
    }
}

/// Shown only for a positive topic with a destination. Topic load failures stay inside that destination.
struct CooperationProjectNavigationDestination: View {
    let topicID: Int
    let invite: CooperationInviteKey
    let destination: ((Int) -> AnyView)?
    var body: some View {
        if CooperationProjectNavigation(topicID: topicID, invite: invite).opens, let destination {
            destination(topicID)
        }
    }
}
