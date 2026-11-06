import XCTest
import Observation
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Synthetic original reader + memory journal. Scope observation never mutates pending storage.
@MainActor final class RoamPrivateReadGrantScopeTests: XCTestCase {
    func testSameContextReplacementRetiresReadScopeWithoutChangingBusinessIdentity() throws {
        let r = try PrivateReadGrantRig(), before = r.reader.readScope, identity = r.reader.identity
        XCTAssertEqual(before, r.reader.readScope); r.access = try r.grantAll()
        XCTAssertEqual(identity, r.reader.identity); XCTAssertNotEqual(before, r.reader.readScope)
        XCTAssertEqual(r.reader.readScope, r.reader.readScope)
    }
    func testRevocationIsObservableAndFreshGrantDoesNotRestoreOldScope() throws {
        let r = try PrivateReadGrantRig(), initial = r.reader.readScope
        let changed = expectation(description: "Original read access revoked")
        withObservationTracking { _ = r.reader.readScope } onChange: { changed.fulfill() }
        r.access?.revoke(); let revoked = r.reader.readScope
        XCTAssertFalse(r.reader.isConfigured); XCTAssertNotEqual(initial, revoked)
        r.access = try r.grantAll()
        XCTAssertNotEqual(initial, r.reader.readScope); XCTAssertNotEqual(revoked, r.reader.readScope)
        XCTAssertTrue(r.reader.isConfigured)
        wait(for: [changed], timeout: 0.1)
    }
    func testSameEpochTokenChangeRetiresScopeEvenBeforeReplacementGrantExists() throws {
        let r = try PrivateReadGrantRig(), initial = r.reader.readScope, identity = r.reader.identity
        r.context = .init(market: .china, baseURL: PrivateReadGrantRig.base, role: "player",
            session: try .init(accountID: 7, epoch: 1, namespace: "grant-scope", token: "replacement-synthetic"))
        XCTAssertEqual(identity, r.reader.identity); XCTAssertNotEqual(initial, r.reader.readScope)
        XCTAssertFalse(r.reader.isConfigured)
    }
    func testScopeChangesNeverDeleteOrUpgradeUnknownJournalOrInMemoryDrafts() throws {
        let r = try PrivateReadGrantRig(); try r.seed(receiptRequired: true)
        r.reader.pendingCapsule = r.capsule; r.reader.pendingGoal = r.goal
        let before = r.storage.values, stores = r.storage.stores
        _ = r.reader.readScope; r.access = try r.grantAll(); _ = r.reader.readScope
        r.access?.revoke(); _ = r.reader.readScope; r.access = nil; _ = r.reader.readScope
        r.access = try r.grant(RoamPrivateToolsRoute.reads); _ = r.reader.readScope
        XCTAssertEqual(r.reader.pendingCapsule, r.capsule); XCTAssertEqual(r.reader.pendingGoal, r.goal)
        XCTAssertEqual(r.reader.unresolvedCapsuleRequestID, r.capsule.requestID)
        XCTAssertEqual(r.reader.unresolvedGoalRequestID, r.goal.requestID)
        XCTAssertEqual(r.storage.values, before); XCTAssertEqual(r.storage.stores, stores); XCTAssertEqual(r.storage.removes, 0)
        XCTAssertTrue(r.wire.requests.isEmpty)
    }
    func testReadScopeDoesNotWidenOriginalAllReadsAndAllWritesSets() throws {
        let r = try PrivateReadGrantRig()
        r.access = try r.grant([RoamPrivateToolsRoute.capsuleDetail]); _ = r.reader.readScope
        XCTAssertFalse(r.reader.isConfigured); XCTAssertFalse(r.reader.allowsWrites)
        r.access = try r.grant(RoamPrivateToolsRoute.reads); _ = r.reader.readScope
        XCTAssertTrue(r.reader.isConfigured); XCTAssertFalse(r.reader.allowsWrites)
        XCTAssertTrue(r.wire.requests.isEmpty); XCTAssertEqual(r.storage.stores, 0)
    }
    func testIssuedOriginalWriterStillConfirmsAfterScopeObservationOnly() async throws {
        let r = try PrivateReadGrantRig(); r.access = try r.grantAll(); r.wire.hold = true
        let task = Task { try await r.reader.createCapsule(r.capsule) }
        try await waitFor { r.wire.pending != nil }; let held = try XCTUnwrap(r.wire.pending); r.wire.pending = nil
        let scope = r.reader.readScope
        XCTAssertEqual(scope, r.reader.readScope)
        held.resume(returning: (try r.wire.reply(capsule: true), 200))
        let value = try await task.value
        XCTAssertEqual(value.id, "40"); XCTAssertNil(r.reader.unresolvedCapsuleRequestID)
        XCTAssertEqual(r.storage.removes, 1); XCTAssertEqual(r.wire.requests.count, 1)
    }
    func testIssuedWriterGrantReplacementKeepsOriginalChangedContextAndPendingLock() async throws {
        let r = try PrivateReadGrantRig(); r.access = try r.grantAll(); r.wire.hold = true
        let task = Task { try await r.reader.createCapsule(r.capsule) }
        try await waitFor { r.wire.pending != nil }; let held = try XCTUnwrap(r.wire.pending); r.wire.pending = nil
        let before = r.storage.values, scope = r.reader.readScope
        r.access = try r.grantAll(); XCTAssertNotEqual(scope, r.reader.readScope)
        held.resume(returning: (try r.wire.reply(capsule: true), 200))
        do { _ = try await task.value; XCTFail() } catch { XCTAssertEqual(error as? RoamPrivateWriteError, .changedContext) }
        XCTAssertEqual(r.storage.values, before); XCTAssertEqual(r.storage.removes, 0)
        XCTAssertEqual(r.reader.unresolvedCapsuleRequestID, r.capsule.requestID); XCTAssertEqual(r.wire.requests.count, 1)
    }
    func testNewReadGrantMayReadOriginalReceiptWithoutReissuingWrite() async throws {
        let r = try PrivateReadGrantRig(); try r.seed(receiptRequired: true); r.reopen()
        _ = r.reader.readScope; r.access = try r.grant(RoamPrivateToolsRoute.reads); _ = r.reader.readScope
        let result = try await r.reader.capsuleReceipt(requestID: r.capsule.requestID)
        XCTAssertEqual(result.id, "40"); XCTAssertNil(r.reader.unresolvedCapsuleRequestID)
        XCTAssertEqual(r.reader.unresolvedGoalRequestID, r.goal.requestID)
        XCTAssertEqual(r.wire.requests.map(\.httpMethod), ["GET"]); XCTAssertEqual(r.storage.removes, 1)
    }
    private func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<200 { if condition() { return }; await Task.yield() }
        XCTFail("Memory request did not enter"); throw APIError.notConfigured
    }
}

@MainActor private final class PrivateReadGrantStorage: RoamPrivatePendingJournalStoring {
    var values: [String: Data] = [:]
    var stores = 0, removes = 0, failStores = false
    func read(key: String) throws -> Data? { values[key] }
    func store(_ data: Data, key: String) throws {
        stores += 1
        if failStores { throw RoamPrivatePendingJournalError.saveFailed }
        values[key] = data
    }
    func remove(key: String) throws { removes += 1; values[key] = nil }
}
@MainActor private final class PrivateReadGrantWire: HTTPTransport {
    var requests: [URLRequest] = []
    var beforeSend: ((URLRequest) throws -> Void)?
    var goal: RoamGoalDraft!
    var hold = false
    var pending: CheckedContinuation<(Data, Int), Error>?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); try beforeSend?(request)
        if hold { return try await withCheckedThrowingContinuation { pending = $0 } }
        return (try reply(capsule: request.url!.path.contains("capsules")), 200)
    }
    func reply(capsule: Bool) throws -> Data {
        let row: [String: Any]
        if capsule { row = ["id": "40", "state": "LOCKED"] }
        else { row = ["id": "41", "requestId": goal.requestID, "metric": goal.metric.rawValue, "target": goal.target,
                      "startDate": goal.startDate, "endDateExclusive": goal.endDateExclusive, "progress": 0, "state": "SCHEDULED",
                      "privateCommemoration": false, "timeZone": "Asia/Shanghai", "countingVersion": "COMPLETED_SESSION_AGGREGATE_V1",
                      "asOfMs": 1_792_382_400_000, "createdAtMs": 1_792_382_400_000] }
        return try JSONSerialization.data(withJSONObject: ["code": 200, "data": row])
    }
}
@MainActor private final class PrivateReadGrantRig {
    static let base = URL(string: "https://example.test/native")!
    let storage = PrivateReadGrantStorage(), wire = PrivateReadGrantWire()
    let scope: RoamHistoryScope
    var context: RuntimeDependencyContext
    let capsule: RoamCapsuleDraft, goal: RoamGoalDraft
    var access: RoamPrivateToolsAccess?
    var reader: RoamPrivateToolsSessionReader!
    let withJournal: Bool
    lazy var journal = RoamPrivatePendingJournal(storage: storage)
    init(withJournal: Bool = true) throws {
        self.withJournal = withJournal
        scope = try .init(market: "cn", deployment: Self.base, accountID: 7, namespace: "grant-scope")
        context = .init(market: .china, baseURL: Self.base, role: "player", session: try .init(accountID: 7, epoch: 1, namespace: "grant-scope", token: "synthetic"))
        let period = try XCTUnwrap(RoamGoalPeriod.periods(now: Date()).last)
        capsule = .init(requestID: "ios_0123456789abcdef", body: "Synthetic capsule", unlockDate: period.endDateExclusive)
        goal = .init(requestID: "ios_abcdef0123456789", metric: .distinctRoutes, target: 3, startDate: period.startDate, endDateExclusive: period.endDateExclusive)
        wire.goal = goal
        access = try grant(RoamPrivateToolsRoute.reads); reopen()
    }
    func grant(_ paths: Set<String>) throws -> RoamPrivateToolsAccess {
        try .init(context: context, approval: .init(baseURL: Self.base, namespace: "grant-scope", accountID: 7, paths: paths))
    }
    func grantAll() throws -> RoamPrivateToolsAccess { try grant(RoamPrivateToolsRoute.reads.union(RoamPrivateToolsRoute.writes)) }
    func reopen() {
        let service = RoamPrivateToolsService(configuration: try! .init(baseURL: Self.base), transport: wire)
        reader = .init(service: service, current: { [weak self] in self?.context }, access: { [weak self] _ in self?.access }, journal: withJournal ? journal : nil)
    }
    func seed(receiptRequired: Bool) throws {
        for (kind, id) in [(RoamPrivatePendingKind.capsuleCreate, capsule.requestID), (.goalCreate, goal.requestID)] {
            try journal.record(kind: kind, requestID: id, scope: scope, now: Date())
            if receiptRequired { try journal.requireReceipt(kind: kind, requestID: id, scope: scope) }
        }
    }
}
