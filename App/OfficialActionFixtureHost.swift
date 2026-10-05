#if DEBUG
import SwiftUI

@MainActor private final class OfficialActionFixtureAccess: OfficialActionAccess {
    let identity: OfficialActionIdentity? = .init(accountID: 77, epoch: UUID(), namespace: "official-action-synthetic")
    let enabled = false
    func snapshot(for command: OfficialActionCommand) async throws -> OfficialActionSnapshot {
        guard let identity else { throw OfficialActionFailure.forbidden }
        return OfficialActionSnapshot(identity: identity, publisher: true)
    }
    func send(_ command: OfficialActionCommand) async throws -> OfficialActionReceipt { throw OfficialActionFailure.disabled }
}
@MainActor private final class OfficialActionFixtureLocks: OfficialActionLockStore {
    private var keys: Set<String> = []
    func contains(_ key: String) throws -> Bool { keys.contains(key) }
    func insert(_ key: String) throws { keys.insert(key) }
    func remove(_ key: String) throws { keys.remove(key) }
}
@MainActor struct OfficialActionFixtureHost: View {
    private let coordinator = OfficialActionCoordinator(access: OfficialActionFixtureAccess(), locks: OfficialActionFixtureLocks())
    var body: some View {
        NavigationStack {
            List {
                NavigationLink("officialAction.publish") { OfficialPublishEditor(coordinator: coordinator) }
                    .accessibilityIdentifier("officialAction.openPublish")
                NavigationLink("officialAction.broadcast") { OfficialBroadcastEditor(coordinator: coordinator) }
                    .accessibilityIdentifier("officialAction.openBroadcast")
            }.navigationTitle("officialAction.fixture")
        }
    }
}
#endif
