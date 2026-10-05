#if DEBUG
import SwiftUI
import Observation

@MainActor @Observable private final class SquareWorkspaceRecoveryTransport: HTTPTransport {
    private(set) var pending = false
    private(set) var requests = 0
    private var continuation: CheckedContinuation<(Data, Int), Error>?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        guard request.httpMethod == "POST", request.url?.path == "/api/creativesquare/info" else { throw SquareWorkspaceFailure.invalid }
        requests += 1
        return try await withCheckedThrowingContinuation { continuation = $0; pending = true }
    }
    func release() {
        let value = continuation; continuation = nil; pending = false
        let body = String(data: SquareWorkspaceFixtures.legacyPost, encoding: .utf8)!
        value?.resume(returning: (Data("{\"code\":200,\"data\":\(body)}".utf8), 200))
    }
}

@MainActor struct SquareWorkspaceFixtureHost: View {
    @State private var coordinator: SquareWorkspaceCoordinator
    @State private var recovery: SquareWorkspaceRecoveryTransport?
    init() {
        let session = try! SquareWorkspaceSession(accountID: 81, namespace: "synthetic-square", epoch: 1)
        let store = SquareWorkspaceStore(storage: SquareWorkspaceMemoryStorage())
        let delayed = ProcessInfo.processInfo.arguments.contains("--uitesting-workspace-delayed-recovery")
        let recovery = delayed ? SquareWorkspaceRecoveryTransport() : nil
        let service = recovery.map { SquareWorkspaceService(configuration: try! .init(baseURL: URL(string: "https://example.com")!), transport: $0) }
        var grants = SquareWorkspaceGrants(); grants.live = delayed
        let coordinator = SquareWorkspaceCoordinator(session: session, store: store, service: service, grants: grants, currentSession: { session }, token: { "synthetic-only-token" })
        var first = SquareWorkspaceFixtures.draft()
        if delayed { first.postID = 701; first.body = "Saved first recovery draft" }
        try? coordinator.saveLocal(first, lane: .legacy)
        if delayed {
            var second = SquareWorkspaceDraft(workflowID: "synthetic-square-002", body: "Saved second recovery draft")
            second.postID = 701
            try? coordinator.saveLocal(second, lane: .legacy)
        }
        _coordinator = State(initialValue: coordinator)
        _recovery = State(initialValue: recovery)
    }
    var body: some View {
        VStack {
            if let recovery {
                Text(verbatim: recovery.pending ? "Synthetic recovery suspended" : "Synthetic recovery ready")
                    .accessibilityIdentifier("fixture.workspaceRecovery.state")
                Text(verbatim: String(recovery.requests)).accessibilityIdentifier("fixture.workspaceRecovery.requests")
                Button { recovery.release() } label: { Text(verbatim: "Release synthetic recovery") }
                    .disabled(!recovery.pending).accessibilityIdentifier("fixture.workspaceRecovery.release")
            }
            NavigationStack { SquareWorkspaceView(coordinator: coordinator) }
        }
    }
}
#endif
