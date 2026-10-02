#if DEBUG
import SwiftUI

@MainActor struct SquareWorkspaceFixtureHost: View {
    @State private var coordinator: SquareWorkspaceCoordinator
    init() {
        let session = try! SquareWorkspaceSession(accountID: 81, namespace: "synthetic-square", epoch: 1)
        let store = SquareWorkspaceStore(storage: SquareWorkspaceMemoryStorage())
        let coordinator = SquareWorkspaceCoordinator(session: session, store: store, currentSession: { session })
        try? coordinator.saveLocal(SquareWorkspaceFixtures.draft(), lane: .legacy)
        _coordinator = State(initialValue: coordinator)
    }
    var body: some View { NavigationStack { SquareWorkspaceView(coordinator: coordinator) } }
}
#endif
