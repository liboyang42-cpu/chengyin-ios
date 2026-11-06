import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Only memory fixtures and a deterministic transport. No real request, journal file, or business write.
@MainActor final class RoamPrivatePageLifetimeTests: XCTestCase {
    func testLateCapsuleListAndDetailCannotReviveRetiredPage() async throws {
        let tools = PrivateLifetimeTools(), model = RoamCapsuleCoordinator(tools: tools)
        tools.hold = "capsules"
        let loading = Task { await model.load() }
        await held(tools); model.suspend(); tools.release(); await loading.value
        XCTAssertTrue(model.items.isEmpty); XCTAssertEqual(model.phase, .idle)
        model.resume(); await model.load()
        let item = try XCTUnwrap(model.items.first { $0.state == .open })
        tools.hold = "capsule"
        let opening = Task { await model.open(item) }
        await held(tools); model.suspend(); tools.release(); await opening.value
        XCTAssertNil(model.opened); XCTAssertTrue(model.items.isEmpty)
        model.resume(); await model.load()
        XCTAssertEqual(model.items.count, 2); XCTAssertNil(model.opened)
        XCTAssertTrue(tools.fixture.dispatchedWrites.isEmpty)
    }
    func testLateGoalDetailIsRetiredAndForegroundOnlyReloadsMetadata() async throws {
        let tools = PrivateLifetimeTools(), model = RoamGoalsCoordinator(tools: tools)
        await model.load(); tools.hold = "goal"
        let opening = Task { await model.open("22") }
        await held(tools); model.suspend(); tools.release(); await opening.value
        XCTAssertNil(model.detail); XCTAssertTrue(model.rows.isEmpty)
        model.resume(); await model.load()
        XCTAssertEqual(model.rows.count, 2); XCTAssertNil(model.detail)
        XCTAssertTrue(tools.fixture.dispatchedWrites.isEmpty)
    }
    func testSuspendRetiresUnsubmittedReviewButNeverTouchesExistingPendingPayload() async throws {
        let tools = PrivateLifetimeTools(), capsule = RoamCapsuleCoordinator(tools: tools), goal = RoamGoalsCoordinator(tools: tools)
        capsule.prepareCreate(body: "private", unlockDate: "2030-01-01")
        goal.prepareCreate(metric: .distinctRoutes, target: 5, startDate: "2026-10-19", endDateExclusive: "2026-11-01")
        XCTAssertNotNil(capsule.review); XCTAssertNotNil(goal.review)
        let a = RoamCapsuleDraft(body: "original", unlockDate: "2030-01-01")
        let b = RoamGoalDraft(metric: .distinctRoutes, target: 5, startDate: "2026-10-19", endDateExclusive: "2026-11-01")
        tools.pendingCapsule = a; tools.pendingGoal = b
        capsule.suspend(); goal.suspend()
        XCTAssertNil(capsule.review); XCTAssertNil(goal.review)
        XCTAssertEqual(tools.pendingCapsule, a); XCTAssertEqual(tools.pendingGoal, b)
        let created = await capsule.confirmCreate(), retried = await goal.retryPending()
        XCTAssertFalse(created); XCTAssertFalse(retried); XCTAssertTrue(tools.fixture.dispatchedWrites.isEmpty)
    }
    func testIssuedUnknownCapsuleCreateSettlesWhileHiddenWithoutResending() async throws {
        let tools = PrivateLifetimeTools(scenario: .unknownCreate), model = RoamCapsuleCoordinator(tools: tools)
        model.prepareCreate(body: "original", unlockDate: "2030-01-01")
        let draft = try XCTUnwrap(model.review); tools.hold = "createCapsule"
        let send = Task { await model.confirmCreate() }
        await held(tools); model.suspend(); model.resume()
        await model.load(); await model.verifyPending()
        let duplicate = await model.retryPending(); XCTAssertFalse(duplicate)
        XCTAssertTrue(model.isBusy); XCTAssertEqual(tools.calls, ["createCapsule"])
        tools.release(); let result = await send.value
        XCTAssertFalse(result); XCTAssertEqual(model.pending, draft); XCTAssertEqual(model.issue, .outcomeUnknown)
        XCTAssertEqual(tools.calls, ["createCapsule"]); XCTAssertNil(model.opened)
        await model.load(); await model.verifyPending()
        XCTAssertNil(model.pending); XCTAssertEqual(tools.fixture.dispatchedWrites, [RoamPrivateToolsRoute.capsuleCreate])
    }
    func testIssuedGoalSuccessAfterReturnCannotRestoreOldDetailOrReadAhead() async throws {
        let tools = PrivateLifetimeTools(), model = RoamGoalsCoordinator(tools: tools)
        model.prepareCreate(metric: .distinctRoutes, target: 5, startDate: "2026-10-19", endDateExclusive: "2026-11-01")
        tools.hold = "createGoal"; let send = Task { await model.confirmCreate() }
        await held(tools); model.suspend(); model.resume(); await model.load()
        XCTAssertTrue(model.isBusy); tools.release(); let result = await send.value
        XCTAssertTrue(result); XCTAssertNil(model.pending); XCTAssertNil(model.detail); XCTAssertTrue(model.rows.isEmpty)
        XCTAssertEqual(tools.calls, ["createGoal"])
        await model.load(); XCTAssertEqual(model.rows.count, 3)
    }
    func testIssuedReceiptKeepsOriginalPendingCompletionAfterBackground() async throws {
        let tools = PrivateLifetimeTools(scenario: .unknownCreate), model = RoamGoalsCoordinator(tools: tools)
        model.prepareCreate(metric: .distinctRoutes, target: 5, startDate: "2026-10-19", endDateExclusive: "2026-11-01")
        _ = await model.confirmCreate(); let pending = try XCTUnwrap(model.pending)
        tools.hold = "goalReceipt"; let checking = Task { await model.verifyPending() }
        await held(tools); model.suspend(); model.resume(); await model.verifyPending()
        XCTAssertEqual(model.pending, pending); XCTAssertTrue(model.isBusy)
        tools.release(); await checking.value
        XCTAssertNil(model.pending); XCTAssertNil(model.detail)
        XCTAssertEqual(tools.calls.filter { $0 == "goalReceipt" }.count, 1)
        XCTAssertFalse(tools.calls.contains("goals")); XCTAssertEqual(tools.fixture.dispatchedWrites.count, 1)
    }
    func testIssuedDeleteAndCancellationPreserveOriginalTerminalSemanticsWithoutRevealingDetail() async throws {
        let tools = PrivateLifetimeTools(), capsule = RoamCapsuleCoordinator(tools: tools), goal = RoamGoalsCoordinator(tools: tools)
        await capsule.load(); await capsule.open(try XCTUnwrap(capsule.items.first { $0.state == .open })); capsule.prepareDelete()
        tools.hold = "deleteCapsule"; let deleting = Task { await capsule.confirmDelete() }
        await held(tools); capsule.suspend(); tools.release(); await deleting.value
        XCTAssertNil(capsule.opened); XCTAssertFalse(capsule.deleted)
        capsule.resume(); await capsule.load(); XCTAssertEqual(capsule.items.count, 1)
        await goal.open("22"); goal.prepareCancel(); tools.hold = "cancelGoal"
        let cancelling = Task { await goal.confirmCancel() }
        await held(tools); goal.suspend(); tools.release(); await cancelling.value
        XCTAssertNil(goal.detail); XCTAssertTrue(goal.rows.isEmpty)
        goal.resume(); await goal.load(); XCTAssertEqual(goal.rows.first { $0.id == "22" }?.state, .cancelled)
        XCTAssertEqual(tools.fixture.dispatchedWrites, [RoamPrivateToolsRoute.capsuleDelete, RoamPrivateToolsRoute.goalCancel])
    }
    func testRevocationRetainsPendingAndRestoringReadAccessNeverRetriesWriter() async throws {
        let tools = PrivateLifetimeTools(), model = RoamCapsuleCoordinator(tools: tools)
        let pending = RoamCapsuleDraft(body: "held", unlockDate: "2030-01-01"); tools.pendingCapsule = pending
        model.suspend(); tools.isConfigured = false; model.resume(); await model.load()
        XCTAssertEqual(model.issue, .notConfigured); XCTAssertEqual(model.pending, pending); XCTAssertTrue(tools.calls.isEmpty)
        tools.isConfigured = true; tools.allowsWrites = false; model.resume(); await model.load()
        XCTAssertEqual(model.items.count, 2); XCTAssertEqual(model.pending, pending)
        let retried = await model.retryPending(); XCTAssertFalse(retried); XCTAssertTrue(tools.fixture.dispatchedWrites.isEmpty)
    }
    func testRealJournalUnknownSurvivesBackgroundAndOnlyIssuedOriginalReceiptClearsLock() async throws {
        let wire = PrivateLifetimeWire(), storage = RoamPrivatePendingInMemoryJournalStorage()
        let (reader, scope) = try realReader(wire, storage)
        let model = RoamCapsuleCoordinator(tools: reader)
        model.prepareCreate(body: "not persisted", unlockDate: RoamCapsuleUnlockOption.minimumDate(now: reader.now))
        let draft = try XCTUnwrap(model.review), journal = RoamPrivatePendingJournal(storage: storage)
        let creating = Task { await model.confirmCreate() }
        await wireHeld(wire); XCTAssertEqual(try journal.entry(kind: .capsuleCreate, scope: scope)?.requestID, draft.requestID)
        let originalBytes = storage.values; model.suspend(); XCTAssertEqual(storage.values, originalBytes)
        await wire.fail(); let created = await creating.value; XCTAssertFalse(created)
        XCTAssertEqual(model.pending, draft); XCTAssertEqual(try journal.entry(kind: .capsuleCreate, scope: scope)?.receiptRequired, true)
        model.resume(); let verifying = Task { await model.verifyPending() }
        await wireHeld(wire); model.suspend(); let lockBeforeReply = storage.values
        model.resume(); await model.verifyPending(); XCTAssertEqual(storage.values, lockBeforeReply)
        await wire.reply(#"{"code":200,"data":{"id":"40","state":"LOCKED"}}"#)
        await verifying.value
        XCTAssertNil(model.pending); XCTAssertNil(try journal.entry(kind: .capsuleCreate, scope: scope))
        XCTAssertNil(model.opened); XCTAssertTrue(model.items.isEmpty)
        let paths = await wire.paths
        XCTAssertEqual(paths.map { $0.components(separatedBy: "/api/").last! }, ["capsules/create", "capsules/receipt"])
    }
    func testRealJournalSuccessfulIssuedCreateClearsOnlyItsLockAfterSuspension() async throws {
        let wire = PrivateLifetimeWire(), storage = RoamPrivatePendingInMemoryJournalStorage()
        let (reader, scope) = try realReader(wire, storage), model = RoamCapsuleCoordinator(tools: reader)
        model.prepareCreate(body: "not persisted", unlockDate: RoamCapsuleUnlockOption.minimumDate(now: reader.now))
        let task = Task { await model.confirmCreate() }; await wireHeld(wire); model.suspend()
        XCTAssertNotNil(try RoamPrivatePendingJournal(storage: storage).entry(kind: .capsuleCreate, scope: scope))
        await wire.reply(#"{"code":200,"data":{"id":"40","state":"LOCKED"}}"#)
        let result = await task.value; XCTAssertTrue(result); XCTAssertNil(model.pending)
        XCTAssertNil(try RoamPrivatePendingJournal(storage: storage).entry(kind: .capsuleCreate, scope: scope))
        let paths = await wire.paths; XCTAssertEqual(paths.count, 1)
    }
    private func held(_ tools: PrivateLifetimeTools) async { for _ in 0..<100 { if tools.continuation != nil { return }; await Task.yield() }; XCTFail("Expected original operation to enter test gate") }
    private func wireHeld(_ wire: PrivateLifetimeWire) async { for _ in 0..<100 { if await wire.held { return }; await Task.yield() }; XCTFail("Expected original HTTP request to enter test gate") }
    private func realReader(_ wire: PrivateLifetimeWire, _ storage: RoamPrivatePendingInMemoryJournalStorage) throws -> (RoamPrivateToolsSessionReader, RoamHistoryScope) {
        let base = URL(string: "https://example.test/private-lifetime")!
        let context = RuntimeDependencyContext(market: .china, baseURL: base, role: "player", session: try PlayExperienceSession(accountID: 7, epoch: 1, namespace: "test", token: "synthetic"))
        let access = try RoamPrivateToolsAccess(context: context, approval: .init(baseURL: base, namespace: "test", accountID: 7, paths: RoamPrivateToolsRoute.reads.union(RoamPrivateToolsRoute.writes)))
        let service = try RoamPrivateToolsService(configuration: APIConfiguration(baseURL: base), transport: wire)
        let reader = RoamPrivateToolsSessionReader(service: service, current: { context }, access: { _ in access }, journal: RoamPrivatePendingJournal(storage: storage))
        return (reader, try RoamHistoryScope(market: "cn", deployment: base, accountID: 7, namespace: "test"))
    }
}

private actor PrivateLifetimeWire: HTTPTransport {
    private var continuation: CheckedContinuation<(Data, Int), Error>?
    private(set) var paths: [String] = []
    var held: Bool { continuation != nil }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        paths.append(request.url!.path)
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func reply(_ body: String) { let held = continuation; continuation = nil; held?.resume(returning: (Data(body.utf8), 200)) }
    func fail() { let held = continuation; continuation = nil; held?.resume(throwing: URLError(.timedOut)) }
}

@MainActor private final class PrivateLifetimeTools: RoamPrivateToolsServing {
    let fixture: RoamPrivateToolsFixture
    var identity: RoamExperienceIdentity?
    var isConfigured = true, allowsWrites = true
    let isOfflineExample = true
    var now: Date { fixture.now }
    var pendingCapsule: RoamCapsuleDraft?
    var pendingGoal: RoamGoalDraft?
    var confirmedCancelledGoals: Set<String> = []
    var calls: [String] = [], hold: String?
    var continuation: CheckedContinuation<Void, Never>?
    init(scenario: RoamPrivateToolsFixture.Scenario = .content) { fixture = .init(scenario: scenario); identity = fixture.identity }
    func enter(_ name: String) async { calls.append(name); if hold == name { await withCheckedContinuation { continuation = $0 } } }
    func release() { hold = nil; let held = continuation; continuation = nil; held?.resume() }
    func capsules(beforeID: String?) async throws -> RoamCapsulePage { await enter("capsules"); return try await fixture.capsules(beforeID: beforeID) }
    func capsule(id: String) async throws -> RoamCapsule { await enter("capsule"); return try await fixture.capsule(id: id) }
    func capsuleReceipt(requestID: String) async throws -> RoamCapsule { await enter("capsuleReceipt"); return try await fixture.capsuleReceipt(requestID: requestID) }
    func createCapsule(_ draft: RoamCapsuleDraft) async throws -> RoamCapsule { await enter("createCapsule"); return try await fixture.createCapsule(draft) }
    func deleteCapsule(id: String) async throws -> RoamCapsule { await enter("deleteCapsule"); return try await fixture.deleteCapsule(id: id) }
    func goals(beforeID: String?) async throws -> RoamGoalPage { await enter("goals"); return try await fixture.goals(beforeID: beforeID) }
    func goal(id: String) async throws -> RoamExplorationGoal { await enter("goal"); return try await fixture.goal(id: id) }
    func goalReceipt(requestID: String) async throws -> RoamExplorationGoal { await enter("goalReceipt"); return try await fixture.goalReceipt(requestID: requestID) }
    func createGoal(_ draft: RoamGoalDraft) async throws -> RoamExplorationGoal { await enter("createGoal"); return try await fixture.createGoal(draft) }
    func cancelGoal(id: String) async throws -> RoamExplorationGoal { await enter("cancelGoal"); return try await fixture.cancelGoal(id: id) }
    func prepareExport(_ request: RoamExportRequest) async throws -> RoamExportCheckpoint { throw APIError.notConfigured }
    func exportPage(_ checkpoint: RoamExportCheckpoint) async throws -> RoamExportChunk { throw APIError.notConfigured }
}
