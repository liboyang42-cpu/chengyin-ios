#if DEBUG
import SwiftUI

/// Exercises the normal play summary and sheet with the existing offline recorder.
/// Only the already existing reads capability is granted; every request is recorded.
@MainActor struct PlayBranchHistoryFixtureHost: View {
    private final class Owner {
        var session = try! PlayExperienceSession(accountID: 9001, epoch: 1, namespace: "synthetic-history", token: "synthetic")
    }
    private let owner: Owner
    private let recorder: PlayRecoveryRecordingTransport
    @State private var model: PlayExperienceCoordinator
    @State private var delayedChange: Task<Void, Never>?
    init() {
        let owner = Owner(), recorder = PlayRecoveryRecordingTransport()
        let args = ProcessInfo.processInfo.arguments
        let index = args.firstIndex(of: "--branch-history-scenario")
        let scenario = index.flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } ?? "recorded"
        let log: String? = scenario == "missing" ? nil : scenario == "empty" ? "[]" : scenario == "malformed" ? "[{},null]" : PlayBranchHistorySyntheticFixtures.recorded
        Self.configure(recorder, log: log, linear: scenario == "linear")
        let service = PlayExperienceService(configuration: try! APIConfiguration(baseURL: URL(string: "https://example.com/fixture/")!), transport: recorder, enabled: [.reads])
        self.owner = owner; self.recorder = recorder
        _model = State(initialValue: .init(scope: .activity(41), service: service, recovery: PlayMemoryCompletionRecovery(), pausedStorage: PlayMemoryPausedStorage(), currentSession: { owner.session }))
    }
    var body: some View {
        NavigationStack {
            PlayExperienceView(model: model)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu("Fixture changes") {
                            Button("Refresh with empty history") { Task { await replaceHistory() } }
                                .accessibilityIdentifier("branchHistory.fixture.empty")
                            Button("Refresh shortly") { scheduleChange(switchOwner: false) }
                                .accessibilityIdentifier("branchHistory.fixture.delayedRefresh")
                            Button("Switch account shortly") { scheduleChange(switchOwner: true) }
                                .accessibilityIdentifier("branchHistory.fixture.delayedSwitch")
                        }.accessibilityIdentifier("branchHistory.fixture.menu")
                    }
                }
        }
        .onDisappear { delayedChange?.cancel(); delayedChange = nil }
    }
    private func scheduleChange(switchOwner: Bool) {
        delayedChange?.cancel()
        delayedChange = Task {
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            if switchOwner {
                owner.session = try! .init(accountID: 9002, epoch: 2, namespace: "synthetic-history", token: "synthetic-other")
                model.invalidate()
            }
            await replaceHistory()
        }
    }
    private func replaceHistory() async {
        Self.configure(recorder, log: "[]", sessionID: 502, version: 0)
        await model.load()
    }
    private static func configure(_ recorder: PlayRecoveryRecordingTransport, log: String?, sessionID: Int = 501, version: Int = 2, linear: Bool = false) {
        let route = PlayBranchHistorySyntheticFixtures.route(log: log, sessionID: sessionID, version: version, mode: linear ? "LINEAR" : "BRANCH_GRAPH")
        recorder.responses["/fixture/api/play/nodes"] = .reply(PlayExperienceSyntheticFixtures.envelope(PlayBranchHistorySyntheticFixtures.nodes(route: route)), 200)
        recorder.responses["/fixture/api/play/route-state"] = .reply(PlayExperienceSyntheticFixtures.envelope(route), 200)
    }
}
#endif
