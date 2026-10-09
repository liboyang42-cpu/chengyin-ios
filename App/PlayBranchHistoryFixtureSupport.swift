#if DEBUG
import SwiftUI
import Observation
import UIKit

/// Exercises the normal play summary and sheet with the existing offline recorder.
/// Only the already existing reads capability is granted; every request is recorded.
@MainActor struct PlayBranchHistoryFixtureHost: View {
    // The transport, session owner, model and handshake have one mounted lifetime.
    // A new SwiftUI value must not pair a new recorder with the retained model.
    @State private var fixture: PlayBranchHistoryFixtureState
    private let fixtureObserver: ((PlayBranchHistoryFixtureState, PlayBranchHistoryFixtureEvent) -> Void)?
    private let probeRevision: Int
    init(scenario: String? = nil,
         fixtureObserver: ((PlayBranchHistoryFixtureState, PlayBranchHistoryFixtureEvent) -> Void)? = nil,
         probeRevision: Int = 0) {
        let args = ProcessInfo.processInfo.arguments
        let index = args.firstIndex(of: "--branch-history-scenario")
        let selected = scenario ?? index.flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } ?? "recorded"
        _fixture = State(initialValue: PlayBranchHistoryFixtureState(scenario: selected))
        self.fixtureObserver = fixtureObserver; self.probeRevision = probeRevision
    }
    var body: some View {
        let model = fixture.model
        NavigationStack {
            PlayExperienceView(model: model)
                .environment(\.branchHistoryFixtureHandshake, fixture.handshake)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu("Fixture changes") {
                            Button("Refresh with empty history") { Task { await fixture.replaceHistory() } }
                                .accessibilityIdentifier("branchHistory.fixture.empty")
                            Button("Arm refresh after presentation") { fixture.handshake.arm(.refresh) }
                                .accessibilityIdentifier("branchHistory.fixture.delayedRefresh")
                            Button("Arm account switch after presentation") { fixture.handshake.arm(.switchOwner) }
                                .accessibilityIdentifier("branchHistory.fixture.delayedSwitch")
                        }.accessibilityIdentifier("branchHistory.fixture.menu")
                    }
                }
        }
        .onDisappear {
            fixture.handshake.cancel()
            fixtureObserver?(fixture, .disappeared)
        }
        .background {
            if let fixtureObserver {
                PlayBranchHistoryFixtureProbe(fixture: fixture, revision: probeRevision,
                    phase: fixture.model.phase, observe: fixtureObserver)
                    .frame(width: 0, height: 0).allowsHitTesting(false).accessibilityHidden(true)
            }
        }
    }
}
/// One retained dependency graph for one mounted synthetic host. New mounts start afresh.
@MainActor final class PlayBranchHistoryFixtureState {
    private final class Owner {
        var session = try! PlayExperienceSession(accountID: 9001, epoch: 1, namespace: "synthetic-history", token: "synthetic")
    }
    private let owner: Owner
    let recorder: PlayRecoveryRecordingTransport
    let model: PlayExperienceCoordinator
    let handshake: PlayBranchHistoryFixtureHandshake
    var session: PlayExperienceSession { owner.session }
    init(scenario: String) {
        let owner = Owner(), recorder = PlayRecoveryRecordingTransport()
        let log: String? = scenario == "missing" ? nil : scenario == "empty" ? "[]" : scenario == "malformed" ? "[{},null]" : PlayBranchHistorySyntheticFixtures.recorded
        Self.configure(recorder, log: log, linear: scenario == "linear")
        let service = PlayExperienceService(configuration: try! APIConfiguration(baseURL: URL(string: "https://example.com/fixture/")!), transport: recorder, enabled: [.reads])
        let model = PlayExperienceCoordinator(scope: .activity(41), service: service, recovery: PlayMemoryCompletionRecovery(), pausedStorage: PlayMemoryPausedStorage(), currentSession: { owner.session })
        self.owner = owner; self.recorder = recorder; self.model = model
        handshake = PlayBranchHistoryFixtureHandshake { action in
            if action == .switchOwner {
                owner.session = try! .init(accountID: 9002, epoch: 2, namespace: "synthetic-history", token: "synthetic-other")
                model.invalidate()
            }
            Self.configure(recorder, log: "[]", sessionID: 502, version: 0)
            await model.load()
        }
    }
    func replaceHistory() async {
        Self.configure(recorder, log: "[]", sessionID: 502, version: 0)
        await model.load()
    }
    private static func configure(_ recorder: PlayRecoveryRecordingTransport, log: String?, sessionID: Int = 501, version: Int = 2, linear: Bool = false) {
        let route = PlayBranchHistorySyntheticFixtures.route(log: log, sessionID: sessionID, version: version, mode: linear ? "LINEAR" : "BRANCH_GRAPH")
        recorder.responses["/fixture/api/play/nodes"] = .reply(PlayExperienceSyntheticFixtures.envelope(PlayBranchHistorySyntheticFixtures.nodes(route: route)), 200)
        recorder.responses["/fixture/api/play/route-state"] = .reply(PlayExperienceSyntheticFixtures.envelope(route), 200)
    }
}
/// Opt-in AppUnit observation, following the other hosted fixture ownership tests.
/// No new visible control, network capability, elapsed-time action or release symbol.
enum PlayBranchHistoryFixtureEvent: Equatable { case rendered(Int), disappeared }
@MainActor private struct PlayBranchHistoryFixtureProbe: UIViewRepresentable {
    let fixture: PlayBranchHistoryFixtureState
    let revision: Int
    let phase: PlayExperienceCoordinator.Phase
    let observe: (PlayBranchHistoryFixtureState, PlayBranchHistoryFixtureEvent) -> Void
    func makeUIView(context: Context) -> UIView { UIView(frame: .zero) }
    func updateUIView(_ uiView: UIView, context: Context) { observe(fixture, .rendered(revision)) }
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
