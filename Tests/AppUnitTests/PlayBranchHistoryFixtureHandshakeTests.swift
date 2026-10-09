import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class PlayBranchHistoryFixtureHandshakeTests: XCTestCase {
    private func recorded() throws -> PlayBranchHistoryPresentation {
        .init(snapshot: try PlayBranchHistorySyntheticFixtures.snapshot())
    }
    func testDefaultEnvironmentHasNoFixtureControl() {
        XCTAssertNil(EnvironmentValues().branchHistoryFixtureHandshake)
    }
    func testArmAloneNeverStartsRefreshOrChangesRecordedRows() async throws {
        var calls = 0
        let handshake = PlayBranchHistoryFixtureHandshake { _ in calls += 1 }
        let history = try recorded()
        handshake.arm(.refresh)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(calls, 0); XCTAssertEqual(handshake.consumedCount, 0)
        XCTAssertEqual(handshake.armed, .refresh); XCTAssertTrue(handshake.canApply(history))
        XCTAssertTrue(history.rows.first?.fromName?.contains("Synthetic courtyard") == true)
    }
    func testUnarmedNilUnavailableAndEmptyCannotConsume() async throws {
        var calls = 0
        let handshake = PlayBranchHistoryFixtureHandshake { _ in calls += 1 }
        XCTAssertFalse(handshake.apply(try recorded()))
        handshake.arm(.refresh)
        let empty = PlayBranchHistoryPresentation(snapshot: try PlayBranchHistorySyntheticFixtures.snapshot(log: "[]"))
        let unavailable = PlayBranchHistoryPresentation(snapshot: try PlayBranchHistorySyntheticFixtures.snapshot(log: nil))
        for history in [nil, empty, unavailable] {
            XCTAssertFalse(handshake.canApply(history)); XCTAssertFalse(handshake.apply(history))
        }
        await handshake.waitForChange()
        XCTAssertEqual(calls, 0); XCTAssertEqual(handshake.armed, .refresh)
    }
    func testPresentedCommitConsumesExactlyOnceAndRetainsTheChosenAction() async throws {
        var actions: [PlayBranchHistoryFixtureHandshake.Action] = []
        let handshake = PlayBranchHistoryFixtureHandshake { actions.append($0) }
        let history = try recorded()
        handshake.arm(.switchOwner)
        XCTAssertTrue(handshake.apply(history)); XCTAssertFalse(handshake.apply(history))
        await handshake.waitForChange()
        XCTAssertFalse(handshake.apply(history)); XCTAssertNil(handshake.armed)
        XCTAssertEqual(actions, [.switchOwner]); XCTAssertEqual(handshake.consumedCount, 1)
    }
    func testClosingUnconsumedSheetClearsIntentAndReopenNeedsNewArm() async throws {
        var calls = 0
        let handshake = PlayBranchHistoryFixtureHandshake { _ in calls += 1 }
        let history = try recorded()
        handshake.arm(.refresh); handshake.disarm()
        XCTAssertFalse(handshake.apply(history)); XCTAssertFalse(handshake.canApply(history))
        handshake.arm(.switchOwner); XCTAssertTrue(handshake.apply(history))
        await handshake.waitForChange(); XCTAssertEqual(calls, 1)
    }
    func testDismissalDuringRefreshDoesNotCancelTheNormalReadOrAllowSecondAction() async throws {
        let pause = SuspendedRead()
        var actions: [PlayBranchHistoryFixtureHandshake.Action] = []
        let handshake = PlayBranchHistoryFixtureHandshake { action in
            actions.append(action)
            await pause.wait()
        }
        defer { pause.release(); handshake.cancel() }
        let history = try recorded()
        handshake.arm(.refresh); XCTAssertTrue(handshake.apply(history))
        let ready = await pause.waitUntilReady(timeout: 2)
        let continuation = pause.continuation
        XCTAssertNotNil(continuation); XCTAssertTrue(handshake.applying)
        guard ready, continuation != nil else {
            XCTFail("Synthetic history read did not suspend before the readiness deadline")
            return
        }
        handshake.disarm(); handshake.arm(.switchOwner)
        XCTAssertNil(handshake.armed); XCTAssertFalse(handshake.apply(history))
        pause.release(); await handshake.waitForChange()
        XCTAssertFalse(handshake.applying); XCTAssertEqual(actions, [.refresh])
    }
    func testLeavingFixtureCancelsQueuedChangeBeforeAnyRead() async throws {
        var calls = 0
        let handshake = PlayBranchHistoryFixtureHandshake { _ in calls += 1 }
        handshake.arm(.refresh); XCTAssertTrue(handshake.apply(try recorded()))
        handshake.cancel()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(calls, 0); XCTAssertNil(handshake.armed); XCTAssertFalse(handshake.applying)
        await assertReadinessTimeoutReleasesLateContinuation()
        try await assertCancellationReleasesRegisteredContinuation()
        try await assertLeavingAndReenteringFixtureResetsItsDependencyGraph()
    }
    // Match the existing expectation-based transport tests, with a latched release
    // so cleanup also covers a read that registers after the readiness deadline.
    @MainActor private final class SuspendedRead {
        private let started = XCTestExpectation(description: "Synthetic history read suspended")
        private(set) var continuation: CheckedContinuation<Void, Never>?
        private var released = false
        func wait() async {
            await withCheckedContinuation { continuation in
                guard !released else { continuation.resume(); return }
                self.continuation = continuation
                started.fulfill()
            }
        }
        func waitUntilReady(timeout: TimeInterval) async -> Bool {
            let result = await XCTWaiter.fulfillment(of: [started], timeout: timeout)
            return result == .completed && continuation != nil
        }
        func release() {
            released = true
            let pending = continuation; continuation = nil
            pending?.resume()
        }
    }
    private func assertReadinessTimeoutReleasesLateContinuation() async {
        let pause = SuspendedRead()
        defer { pause.release() }
        let ready = await pause.waitUntilReady(timeout: 0.01)
        XCTAssertFalse(ready); XCTAssertNil(pause.continuation)
        pause.release(); pause.release()
        let finished = XCTestExpectation(description: "Late read exits after readiness cleanup")
        let task = Task { await pause.wait(); finished.fulfill() }
        defer { pause.release(); task.cancel() }
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertNil(pause.continuation)
    }
    private func assertCancellationReleasesRegisteredContinuation() async throws {
        let pause = SuspendedRead()
        let finished = XCTestExpectation(description: "Cancelled read exits after explicit release")
        let handshake = PlayBranchHistoryFixtureHandshake { _ in
            await pause.wait(); finished.fulfill()
        }
        defer { pause.release(); handshake.cancel() }
        handshake.arm(.refresh); XCTAssertTrue(handshake.apply(try recorded()))
        let ready = await pause.waitUntilReady(timeout: 2)
        guard ready else { XCTFail("Synthetic cancellation read did not start"); return }
        handshake.cancel()
        // Task cancellation alone must not be mistaken for continuation release.
        XCTAssertNotNil(pause.continuation)
        pause.release(); pause.release()
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertNil(pause.continuation); XCTAssertNil(handshake.armed); XCTAssertFalse(handshake.applying)
    }
    private final class Owner {
        var session = try! PlayExperienceSession(accountID: 9001, epoch: 1, namespace: "synthetic-history", token: "synthetic")
    }
    private func configure(_ wire: PlayRecoveryRecordingTransport, log: String, sessionID: Int, version: Int) {
        let route = PlayBranchHistorySyntheticFixtures.route(log: log, sessionID: sessionID, version: version)
        wire.responses["/fixture/api/play/nodes"] = .reply(PlayExperienceSyntheticFixtures.envelope(PlayBranchHistorySyntheticFixtures.nodes(route: route)), 200)
        wire.responses["/fixture/api/play/route-state"] = .reply(PlayExperienceSyntheticFixtures.envelope(route), 200)
    }
    func testBothConsumedActionsUseNormalReadsAndInvalidateAnAlreadyPresentedSelection() async throws {
        for action in [PlayBranchHistoryFixtureHandshake.Action.refresh, .switchOwner] {
            let owner = Owner(), wire = PlayRecoveryRecordingTransport()
            configure(wire, log: PlayBranchHistorySyntheticFixtures.recorded, sessionID: 501, version: 2)
            let service = PlayExperienceService(configuration: try APIConfiguration(baseURL: URL(string: "https://example.com/fixture/")!), transport: wire, enabled: [.reads])
            let model = PlayExperienceCoordinator(scope: .activity(41), service: service, recovery: PlayMemoryCompletionRecovery(), pausedStorage: PlayMemoryPausedStorage(), currentSession: { owner.session })
            await model.load()
            let selection = try XCTUnwrap(PlayBranchHistorySelection(snapshot: XCTUnwrap(model.snapshot)))
            let history = try XCTUnwrap(selection.presentation(snapshot: model.snapshot))
            let oldCount = wire.requests.count
            let handshake = PlayBranchHistoryFixtureHandshake { chosen in
                if chosen == .switchOwner {
                    owner.session = try! .init(accountID: 9002, epoch: 2, namespace: "synthetic-history", token: "synthetic-other")
                    model.invalidate()
                }
                self.configure(wire, log: "[]", sessionID: 502, version: 0)
                await model.load()
            }
            handshake.arm(action)
            XCTAssertEqual(wire.requests.count, oldCount)
            XCTAssertEqual(selection.presentation(snapshot: model.snapshot), history)
            XCTAssertTrue(handshake.apply(history)); await handshake.waitForChange()
            XCTAssertNil(selection.presentation(snapshot: model.snapshot))
            XCTAssertEqual(PlayBranchHistoryPresentation(snapshot: try XCTUnwrap(model.snapshot)).state, .empty)
            XCTAssertEqual(wire.requests.count, oldCount + 2)
            XCTAssertTrue(wire.requests.allSatisfy { $0.httpMethod == "GET" })
            XCTAssertFalse(model.canWrite); XCTAssertNil(model.reward); XCTAssertNil(model.ending)
        }
        try await assertHostReconstructionRefreshesTheRetainedRecorder()
    }

    @MainActor private final class RebuildSignal: ObservableObject {
        @Published var revision = 0
        @Published var mounted = true
    }
    @MainActor private struct RebuildingHost: View {
        @ObservedObject var signal: RebuildSignal
        let observe: (PlayBranchHistoryFixtureState, PlayBranchHistoryFixtureEvent) -> Void
        var body: some View {
            if signal.mounted {
                PlayBranchHistoryFixtureHost(scenario: "recorded", fixtureObserver: observe,
                    probeRevision: signal.revision)
            } else { Color.clear }
        }
    }
    @MainActor private final class FixtureMount {
        let signal = RebuildSignal()
        let window = UIWindow(frame: UIScreen.main.bounds)
        var observe: ((PlayBranchHistoryFixtureState, PlayBranchHistoryFixtureEvent) -> Void)?
        private var host: UIHostingController<RebuildingHost>?
        func show() {
            let host = UIHostingController(rootView: RebuildingHost(signal: signal, observe: { [weak self] fixture, event in
                self?.observe?(fixture, event)
            }))
            self.host = host; window.rootViewController = host; window.makeKeyAndVisible()
        }
        func close() { observe = nil; window.isHidden = true; window.rootViewController = nil; host = nil }
    }
    private func awaitMountedFixture(_ mount: FixtureMount, revision: Int,
                                     trigger: () -> Void) async throws -> PlayBranchHistoryFixtureState {
        let ready = expectation(description: "Actual branch-history host ready at revision \(revision)")
        var result: PlayBranchHistoryFixtureState?
        mount.observe = { fixture, event in
            guard event == .rendered(revision), fixture.model.phase == .ready, result == nil else { return }
            result = fixture; ready.fulfill()
        }
        defer { mount.observe = nil }
        trigger()
        await fulfillment(of: [ready], timeout: 2)
        return try XCTUnwrap(result, "The actual SwiftUI host must mount or reconstruct before the action")
    }
    private func assertHostReconstructionRefreshesTheRetainedRecorder() async throws {
        let mount = FixtureMount()
        defer { mount.close() }
        let original = try await awaitMountedFixture(mount, revision: 0) { mount.show() }
        let before = try XCTUnwrap(original.model.snapshot)
        XCTAssertEqual(PlayBranchHistoryPresentation(snapshot: before).state, .recorded)
        let selection = try XCTUnwrap(PlayBranchHistorySelection(snapshot: before))
        for revision in [1, 2] {
            let current = try await awaitMountedFixture(mount, revision: revision) { mount.signal.revision = revision }
            XCTAssertTrue(current === original)
            XCTAssertTrue(current.recorder === original.recorder)
            XCTAssertTrue(current.model === original.model)
            XCTAssertTrue(current.handshake === original.handshake)
            XCTAssertEqual(current.session, original.session)
            let oldCount = original.recorder.requests.count
            // Same method invoked by the immediate toolbar action, after actual Host reconstruction.
            await current.replaceHistory()
            let snapshot = try XCTUnwrap(original.model.snapshot)
            XCTAssertEqual(PlayBranchHistoryPresentation(snapshot: snapshot).state, .empty)
            XCTAssertEqual(snapshot.route?.sessionID, 502); XCTAssertEqual(snapshot.route?.version, 0)
            XCTAssertNil(selection.presentation(snapshot: original.model.snapshot))
            XCTAssertEqual(original.recorder.requests.count, oldCount + 2)
            XCTAssertEqual(Array(original.recorder.requests.suffix(2)).compactMap { $0.url?.path },
                           ["/fixture/api/play/nodes", "/fixture/api/play/route-state"])
            XCTAssertTrue(original.recorder.requests.allSatisfy { $0.httpMethod == "GET" })
            XCTAssertFalse(original.model.canWrite); XCTAssertNil(original.model.reward); XCTAssertNil(original.model.ending)
        }
    }
    private func assertLeavingAndReenteringFixtureResetsItsDependencyGraph() async throws {
        let mount = FixtureMount()
        defer { mount.close() }
        let original = try await awaitMountedFixture(mount, revision: 0) { mount.show() }
        let history = PlayBranchHistoryPresentation(snapshot: try XCTUnwrap(original.model.snapshot))
        let oldCount = original.recorder.requests.count
        original.handshake.arm(.switchOwner); XCTAssertTrue(original.handshake.apply(history))
        original.handshake.cancel(); await original.handshake.waitForChange()
        XCTAssertEqual(original.recorder.requests.count, oldCount)
        XCTAssertEqual(original.session.accountID, 9001)
        await original.replaceHistory()
        original.handshake.arm(.switchOwner)
        let disappeared = expectation(description: "Leaving the actual fixture cancels unconsumed intent")
        var observedExit = false
        mount.observe = { fixture, event in
            guard event == .disappeared, !observedExit else { return }
            observedExit = true
            XCTAssertTrue(fixture === original)
            XCTAssertNil(fixture.handshake.armed); XCTAssertFalse(fixture.handshake.applying)
            disappeared.fulfill()
        }
        mount.signal.mounted = false
        await fulfillment(of: [disappeared], timeout: 2)
        XCTAssertTrue(observedExit)
        let current = try await awaitMountedFixture(mount, revision: 1) {
            mount.signal.revision = 1; mount.signal.mounted = true
        }
        XCTAssertFalse(current === original)
        XCTAssertFalse(current.recorder === original.recorder)
        XCTAssertFalse(current.model === original.model)
        XCTAssertFalse(current.handshake === original.handshake)
        XCTAssertEqual(current.session.accountID, 9001); XCTAssertEqual(current.session.epoch, 1)
        XCTAssertNil(current.handshake.armed); XCTAssertEqual(current.handshake.consumedCount, 0)
        let freshSnapshot = try XCTUnwrap(current.model.snapshot)
        XCTAssertEqual(PlayBranchHistoryPresentation(snapshot: freshSnapshot).state, .recorded)
        XCTAssertEqual(freshSnapshot.route?.sessionID, 501); XCTAssertEqual(freshSnapshot.route?.version, 2)
        let retiredCount = original.recorder.requests.count
        await current.replaceHistory()
        XCTAssertEqual(PlayBranchHistoryPresentation(snapshot: try XCTUnwrap(current.model.snapshot)).state, .empty)
        XCTAssertEqual(original.recorder.requests.count, retiredCount)
        XCTAssertFalse(current.model.canWrite); XCTAssertNil(current.model.reward); XCTAssertNil(current.model.ending)
    }
}
