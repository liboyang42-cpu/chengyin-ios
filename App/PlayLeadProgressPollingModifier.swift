import SwiftUI

/// Hosts the mini team-progress poll for the lead section. SwiftUI cancels the
/// task when the section leaves, the scene is not active or the authority changes.
@MainActor struct PlayLeadProgressPollingModifier: ViewModifier {
    let model: PlayExperienceCoordinator
    let context: PlayInteractionContext?
    @Environment(\.scenePhase) private var scenePhase
    func body(content: Content) -> some View {
        let key = PlayLeadProgressPolling.Key(context: context, lead: model.lead, sceneActive: scenePhase == .active)
        content.task(id: key) {
            guard key.active else { return }
            await model.pollLead(context: context)
        }
    }
}
