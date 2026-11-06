import XCTest
@testable import QuestifyCore

@MainActor final class CooperationConfirmRecheckTests: XCTestCase {
    private final class Evidence: CoopFlowEvidenceReading {
        var calls = 0
        var onConfirm: () -> Void = {}
        func freshEvidence(for operation: CoopFlowMutation, session: CoopFlowSession) async throws -> CoopFlowEvidence {
            calls += 1
            if calls == 2 { await Task.yield(); onConfirm() }
            return CoopFlowEvidence(baseline: .object(["topicId": .id(9)]), permitted: true)
        }
    }
    private final class Executor: CoopFlowExecuting {
        var permits = true
        var calls = 0
        var fails = false
        var dispatchScope: String? { "synthetic-scope" }
        func permitsDispatch(_ operation: CoopFlowMutation) -> Bool { permits }
        func execute(_ operation: CoopFlowMutation, session: CoopFlowSession) async throws -> CoopFlowJSON {
            calls += 1
            if fails { throw CoopFlowFailure.ambiguous }
            return .object([:])
        }
    }
    private final class Locks: CoopFlowLockStore {
        var keys: Set<String> = []
        var acquisitions = 0
        func contains(_ key: String) throws -> Bool { keys.contains(key) }
        func acquire(_ key: String) throws { acquisitions += 1; keys.insert(key) }
        func complete(_ key: String) throws { keys.remove(key) }
    }
    private func checkAge(_ elapsed: TimeInterval, allowed: Bool) async throws {
        let session = try CoopFlowSession(accountID: 7, epoch: 1, token: "synthetic")
        var now = Date(timeIntervalSince1970: 1000)
        let evidence = Evidence(), executor = Executor(), locks = Locks()
        let coordinator = CoopFlowCoordinator(current: { session }, evidence: evidence, executor: executor,
            locks: locks, enabled: true, now: { now })
        let review = try await coordinator.prepare(.apply(topicID: 9))
        evidence.onConfirm = { now = Date(timeIntervalSince1970: 1000 + elapsed) }
        do { _ = try await coordinator.confirm(review); XCTAssertTrue(allowed) }
        catch { XCTAssertFalse(allowed); XCTAssertEqual(error as? CoopFlowFailure, .stale) }
        XCTAssertEqual(executor.calls, allowed ? 1 : 0)
        XCTAssertEqual(locks.acquisitions, allowed ? 1 : 0)
        XCTAssertTrue(locks.keys.isEmpty)
    }
    func testEvidenceReadCrossesDeadlineWithoutDispatchOrUnknownLock() async throws { try await checkAge(121, allowed: false) }
    func testExactOriginalDeadlineIsStillAccepted() async throws { try await checkAge(120, allowed: true) }
    func testBackwardClockDuringEvidenceRemainsStale() async throws { try await checkAge(-1, allowed: false) }
    func testHostRevocationDuringEvidencePreventsDispatch() async throws {
        let session = try CoopFlowSession(accountID: 7, epoch: 1, token: "synthetic")
        var enabled = true
        let evidence = Evidence(), executor = Executor(), locks = Locks()
        let coordinator = CoopFlowCoordinator(current: { session }, evidence: evidence, executor: executor, locks: locks, enabled: { enabled })
        let review = try await coordinator.prepare(.apply(topicID: 9))
        evidence.onConfirm = { enabled = false }
        do { _ = try await coordinator.confirm(review); XCTFail("Revoked host gate") }
        catch { XCTAssertEqual(error as? CoopFlowFailure, .disabled) }
        XCTAssertEqual(executor.calls, 0); XCTAssertEqual(locks.acquisitions, 0)
    }
    func testExecutorRevocationDuringEvidenceDoesNotCreateUnknownLock() async throws {
        let session = try CoopFlowSession(accountID: 7, epoch: 1, token: "synthetic")
        let evidence = Evidence(), executor = Executor(), locks = Locks()
        let coordinator = CoopFlowCoordinator(current: { session }, evidence: evidence, executor: executor, locks: locks, enabled: true)
        let review = try await coordinator.prepare(.apply(topicID: 9))
        evidence.onConfirm = { executor.permits = false }
        do { _ = try await coordinator.confirm(review); XCTFail("Revoked executor gate") }
        catch { XCTAssertEqual(error as? CoopFlowFailure, .disabled) }
        XCTAssertEqual(executor.calls, 0); XCTAssertEqual(locks.acquisitions, 0)
    }
    func testDispatchedUnknownStillRetainsLockAndCannotResend() async throws {
        let session = try CoopFlowSession(accountID: 7, epoch: 1, token: "synthetic")
        let evidence = Evidence(), executor = Executor(), locks = Locks()
        executor.fails = true
        let coordinator = CoopFlowCoordinator(current: { session }, evidence: evidence, executor: executor, locks: locks, enabled: true)
        let review = try await coordinator.prepare(.apply(topicID: 9))
        do { _ = try await coordinator.confirm(review); XCTFail("Unknown outcome") }
        catch { XCTAssertEqual(error as? CoopFlowFailure, .ambiguous) }
        XCTAssertEqual(executor.calls, 1); XCTAssertEqual(locks.keys.count, 1)
        do { _ = try await coordinator.prepare(.apply(topicID: 9)); XCTFail("Unknown cannot resend") }
        catch { XCTAssertEqual(error as? CoopFlowFailure, .ambiguous) }
        XCTAssertEqual(executor.calls, 1)
    }
}
