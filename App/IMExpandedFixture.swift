import SwiftUI

/// Explicit fixture root only; never instantiated by ordinary app navigation.
@MainActor private final class IMExpandedFixtureWriter: IMExpandedWriting {
    var identity: MessagingReadIdentity? = .init(accountID: 7, epoch: 1)
    let isConfigured: Bool
    init(configured: Bool) { isConfigured = configured }
    func perform(_ mutation: IMMutation, expectedIdentity: MessagingReadIdentity) async throws -> IMMutationReceipt {
        guard isConfigured, identity == expectedIdentity else { throw APIError.notConfigured }
        switch mutation {
        case .read: return .read
        case .mute(_, let muted): return .muted(muted)
        case .start: return .started(conversationID: 9)
        case .send: throw IMCapabilityGap.unknownOutcome
        }
    }
    func upload(_ selection: IMMediaSelection, consent: IMMediaConsent, expectedIdentity: MessagingReadIdentity) async throws -> URL { throw APIError.notConfigured }
}
@MainActor struct IMExpandedFixtureRoot: View {
    let owner: IMExpandedCoordinator
    init(scenario: String) {
        let identity = MessagingReadIdentity(accountID: 7, epoch: 1)
        let scope = try! IMScope(identity: identity, conversationID: 9)
        let writer = IMExpandedFixtureWriter(configured: scenario != "dormant")
        owner = IMExpandedCoordinator(scope: scope, writer: writer)
        if scenario == "route-review", let intent = try? IMOutgoingIntent(scope: scope, payload: .route(topicID: 11)) { _ = owner.review(.send(intent)) }
    }
    var body: some View {
        NavigationStack { IMConversationControlsView(coordinator: owner, identity: owner.scope.identity, onReceipt: { _ in }) }
    }
}
