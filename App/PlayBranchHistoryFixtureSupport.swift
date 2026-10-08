#if DEBUG
import SwiftUI
import Observation

/// Exercises the normal play summary and sheet with the existing offline recorder.
/// Only the already existing reads capability is granted; every request is recorded.
@MainActor struct PlayBranchHistoryFixtureHost: View {
    private final class Owner {
        var session = try! PlayExperienceSession(accountID: 9001, epoch: 1, namespace: "synthetic-history", token: "synthetic")
    }
    private let owner: Owner
    private let recorder: PlayRecoveryRecordingTransport
    @State private var model: PlayExperienceCoordinator
    @State private var handshake: PlayBranchHistoryFixtureHandshake
    init() {
        let owner = Owner(), recorder = PlayRecoveryRecordingTransport()
        let args = ProcessInfo.processInfo.arguments
        let index = args.firstIndex(of: "--branch-history-scenario")
        let scenario = index.flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } ?? "recorded"
        let log: String? = scenario == "missing" ? nil : scenario == "empty" ? "[]" : scenario == "malformed" ? "[{},null]" : PlayBranchHistorySyntheticFixtures.recorded
        Self.configure(recorder, log: log, linear: scenario == "linear")
        let service = PlayExperienceService(configuration: try! APIConfiguration(baseURL: URL(string: "https://example.com/fixture/")!), transport: recorder, enabled: [.reads])
        self.owner = owner; self.recorder = recorder
        let model = PlayExperienceCoordinator(scope: .activity(41), service: service, recovery: PlayMemoryCompletionRecovery(), pausedStorage: PlayMemoryPausedStorage(), currentSession: { owner.session })
        _model = State(initialValue: model)
        _handshake = State(initialValue: PlayBranchHistoryFixtureHandshake { action in
            if action == .switchOwner {
                owner.session = try! .init(accountID: 9002, epoch: 2, namespace: "synthetic-history", token: "synthetic-other")
                model.invalidate()
            }
            Self.configure(recorder, log: "[]", sessionID: 502, version: 0)
            await model.load()
        })
    }
    var body: some View {
        NavigationStack {
            PlayExperienceView(model: model)
                .environment(\.branchHistoryFixtureHandshake, handshake)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu("Fixture changes") {
                            Button("Refresh with empty history") { Task { await replaceHistory() } }
                                .accessibilityIdentifier("branchHistory.fixture.empty")
                            Button("Arm refresh after presentation") { handshake.arm(.refresh) }
                                .accessibilityIdentifier("branchHistory.fixture.delayedRefresh")
                            Button("Arm account switch after presentation") { handshake.arm(.switchOwner) }
                                .accessibilityIdentifier("branchHistory.fixture.delayedSwitch")
                        }.accessibilityIdentifier("branchHistory.fixture.menu")
                    }
                }
        }
        .onDisappear { handshake.cancel() }
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
/// The normal sheet consumes an armed action only after XCTest has observed its old rows.
/// No elapsed-time trigger or production capability is involved.
@MainActor @Observable final class PlayBranchHistoryFixtureHandshake {
    enum Action: Equatable { case refresh, switchOwner }
    private(set) var armed: Action?
    private(set) var consumedCount = 0
    private(set) var applying = false
    private let perform: @MainActor (Action) async -> Void
    private var task: Task<Void, Never>?
    private var generation = UUID()
    init(perform: @escaping @MainActor (Action) async -> Void) { self.perform = perform }
    func arm(_ action: Action) { guard !applying else { return }; armed = action }
    func canApply(_ history: PlayBranchHistoryPresentation?) -> Bool {
        armed != nil && !applying && history?.state == .recorded && history?.rows.isEmpty == false
    }
    @discardableResult func apply(_ history: PlayBranchHistoryPresentation?) -> Bool {
        guard canApply(history), let action = armed else { return false }
        armed = nil; applying = true; consumedCount += 1
        let current = generation
        task = Task {
            guard !Task.isCancelled, generation == current else { return }
            await perform(action)
            guard generation == current else { return }
            applying = false; task = nil
        }
        return true
    }
    // Sheet dismissal clears only unconsumed intent. The in-flight normal refresh must finish.
    func disarm() { armed = nil }
    func cancel() { generation = UUID(); armed = nil; task?.cancel(); task = nil; applying = false }
    func waitForChange() async { await task?.value }
}
private struct PlayBranchHistoryFixtureHandshakeKey: EnvironmentKey {
    static let defaultValue: PlayBranchHistoryFixtureHandshake? = nil
}
extension EnvironmentValues {
    var branchHistoryFixtureHandshake: PlayBranchHistoryFixtureHandshake? {
        get { self[PlayBranchHistoryFixtureHandshakeKey.self] }
        set { self[PlayBranchHistoryFixtureHandshakeKey.self] = newValue }
    }
}
#endif
