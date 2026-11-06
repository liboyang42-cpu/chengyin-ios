import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Original reader/service/journal contracts with memory-only storage/transport. No device files or network.
@MainActor final class RoamPrivateCreateAdmissionTests: XCTestCase {
    func testMissingApprovalKeepsNotConfiguredWithoutStorageMutation() async throws {
        let r = try PrivateCreateAdmissionRig(); r.access = nil
        await expectBoth(r, api: .notConfigured)
        XCTAssertEqual(r.storage.stores, 0); XCTAssertEqual(r.storage.removes, 0); XCTAssertTrue(r.wire.requests.isEmpty)
    }
    func testReadOnlyGrantRejectsBothCreatesBeforeMissingJournal() async throws {
        let r = try PrivateCreateAdmissionRig(withJournal: false)
        XCTAssertTrue(r.reader.isConfigured); XCTAssertFalse(r.reader.allowsWrites)
        await expectBoth(r, write: .writesDisabled)
        XCTAssertTrue(r.wire.requests.isEmpty)
    }
    func testReadOnlyEmptyJournalIsNeverWrittenOrCleared() async throws {
        let r = try PrivateCreateAdmissionRig()
        await expectBoth(r, write: .writesDisabled)
        XCTAssertTrue(r.storage.values.isEmpty); XCTAssertEqual(r.storage.stores, 0); XCTAssertEqual(r.storage.removes, 0)
        XCTAssertNil(r.reader.journalCapsuleRequestID); XCTAssertNil(r.reader.journalGoalRequestID)
        XCTAssertTrue(r.wire.requests.isEmpty)
    }
    func testReadOnlySamePendingIDsDoNotBecomeReceiptRequired() async throws {
        let r = try PrivateCreateAdmissionRig(); try r.seed(receiptRequired: false)
        let before = r.storage.values, stores = r.storage.stores
        r.reader.pendingCapsule = r.capsule; r.reader.pendingGoal = r.goal
        await expectBoth(r, write: .writesDisabled)
        XCTAssertEqual(r.storage.values, before); XCTAssertEqual(r.storage.stores, stores); XCTAssertEqual(r.storage.removes, 0)
        XCTAssertEqual(try r.journal.entry(kind: .capsuleCreate, scope: r.scope)?.receiptRequired, false)
        XCTAssertEqual(try r.journal.entry(kind: .goalCreate, scope: r.scope)?.receiptRequired, false)
        XCTAssertEqual(r.reader.pendingCapsule, r.capsule); XCTAssertEqual(r.reader.pendingGoal, r.goal)
        XCTAssertTrue(r.wire.requests.isEmpty)
    }
    func testReadOnlyUnknownLocksSurviveFreshReaderAndDeniedRetry() async throws {
        let r = try PrivateCreateAdmissionRig(); try r.seed(receiptRequired: true)
        r.reopen()
        let before = r.storage.values, stores = r.storage.stores
        XCTAssertNil(r.reader.pendingCapsule); XCTAssertNil(r.reader.pendingGoal)
        XCTAssertEqual(r.reader.unresolvedCapsuleRequestID, r.capsule.requestID)
        XCTAssertEqual(r.reader.unresolvedGoalRequestID, r.goal.requestID)
        await expectBoth(r, write: .writesDisabled)
        XCTAssertEqual(r.storage.values, before); XCTAssertEqual(r.storage.stores, stores); XCTAssertEqual(r.storage.removes, 0)
        XCTAssertTrue(r.wire.requests.isEmpty)
    }
    func testReadOnlyDifferentDraftDoesNotReplaceOrClearExistingLocks() async throws {
        let r = try PrivateCreateAdmissionRig(); try r.seed(receiptRequired: false)
        let before = r.storage.values, stores = r.storage.stores
        let capsule = RoamCapsuleDraft(requestID: "ios_fedcba9876543210", body: "Another draft", unlockDate: r.capsule.unlockDate)
        let goal = RoamGoalDraft(requestID: "ios_1111111111111111", metric: .distinctRoutes, target: 3,
                                 startDate: r.goal.startDate, endDateExclusive: r.goal.endDateExclusive)
        do { _ = try await r.reader.createCapsule(capsule); XCTFail() }
        catch { XCTAssertEqual(error as? RoamPrivateWriteError, .writesDisabled) }
        do { _ = try await r.reader.createGoal(goal); XCTFail() }
        catch { XCTAssertEqual(error as? RoamPrivateWriteError, .writesDisabled) }
        XCTAssertEqual(r.storage.values, before); XCTAssertEqual(r.storage.stores, stores); XCTAssertEqual(r.storage.removes, 0)
        XCTAssertEqual(r.reader.unresolvedCapsuleRequestID, r.capsule.requestID)
        XCTAssertEqual(r.reader.unresolvedGoalRequestID, r.goal.requestID)
    }
    func testPartialWritePathsDoNotWidenOriginalAllWritesContract() async throws {
        let r = try PrivateCreateAdmissionRig()
        r.access = try r.grant(RoamPrivateToolsRoute.reads.union([RoamPrivateToolsRoute.capsuleCreate, RoamPrivateToolsRoute.goalCreate]))
        XCTAssertFalse(r.reader.allowsWrites)
        await expectBoth(r, write: .writesDisabled)
        XCTAssertEqual(r.storage.stores, 0); XCTAssertTrue(r.wire.requests.isEmpty)
    }
    func testWriteApprovedMissingOrFailingJournalStillBlocksOriginalDispatch() async throws {
        let missing = try PrivateCreateAdmissionRig(withJournal: false); missing.access = try missing.grantAll()
        await expectBoth(missing, journal: .unavailable)
        XCTAssertTrue(missing.wire.requests.isEmpty)
        let failing = try PrivateCreateAdmissionRig(); failing.access = try failing.grantAll()
        failing.storage.failStores = true
        await expectBoth(failing, journal: .saveFailed)
        XCTAssertTrue(failing.wire.requests.isEmpty)
    }
    func testCorruptPendingBytesAreUntouchedAndStillBlockApprovedWrites() async throws {
        let r = try PrivateCreateAdmissionRig(); try r.seed(receiptRequired: false)
        for key in Array(r.storage.values.keys) { r.storage.values[key] = Data("corrupt".utf8) }
        r.reopen(); let before = r.storage.values, stores = r.storage.stores
        await expectBoth(r, write: .writesDisabled)
        XCTAssertEqual(r.storage.values, before); XCTAssertEqual(r.storage.stores, stores)
        r.access = try r.grantAll()
        await expectBoth(r, journal: .corrupted)
        XCTAssertEqual(r.storage.values, before); XCTAssertEqual(r.storage.removes, 0); XCTAssertTrue(r.wire.requests.isEmpty)
    }
    func testReadOnlyMatchingReceiptStillClearsOnlyItsOriginalLock() async throws {
        let r = try PrivateCreateAdmissionRig(); try r.seed(receiptRequired: true); r.reopen()
        let capsule = try await r.reader.capsuleReceipt(requestID: r.capsule.requestID)
        XCTAssertEqual(capsule.id, "40"); XCTAssertNil(r.reader.unresolvedCapsuleRequestID)
        XCTAssertEqual(r.reader.unresolvedGoalRequestID, r.goal.requestID)
        let goal = try await r.reader.goalReceipt(requestID: r.goal.requestID)
        XCTAssertEqual(goal.requestID, r.goal.requestID); XCTAssertNil(r.reader.unresolvedGoalRequestID)
        XCTAssertEqual(r.wire.requests.map(\.httpMethod), ["GET", "GET"])
        XCTAssertEqual(r.wire.requests.compactMap { $0.url?.path }, ["/native/api/capsules/receipt", "/native/api/exploration-goals/receipt"])
        XCTAssertTrue(r.storage.values.isEmpty); XCTAssertEqual(r.storage.removes, 2)
    }
    func testRestoredWriteGrantDoesNotReplayUntilExplicitSameDraftRequest() async throws {
        let r = try PrivateCreateAdmissionRig(); try r.seed(receiptRequired: true)
        let before = r.storage.values
        await expectBoth(r, write: .writesDisabled)
        r.access = try r.grantAll()
        XCTAssertTrue(r.reader.allowsWrites); XCTAssertEqual(r.storage.values, before); XCTAssertTrue(r.wire.requests.isEmpty)
        r.wire.beforeSend = { request in
            let kind: RoamPrivatePendingKind = request.url!.path.contains("capsules") ? .capsuleCreate : .goalCreate
            XCTAssertNotNil(try r.journal.entry(kind: kind, scope: r.scope), "Original journal must remain durable before either original writer")
        }
        _ = try await r.reader.createCapsule(r.capsule)
        _ = try await r.reader.createGoal(r.goal)
        XCTAssertEqual(r.wire.requests.map(\.httpMethod), ["POST", "POST"])
        XCTAssertEqual(r.wire.requests.compactMap { $0.httpBody }, [r.capsule.json, r.goal.json])
        XCTAssertTrue(r.storage.values.isEmpty); XCTAssertEqual(r.storage.removes, 2)
    }
    func testRevokedGrantRejectsWithoutClearingUnknownLocks() async throws {
        let r = try PrivateCreateAdmissionRig(); try r.seed(receiptRequired: true)
        r.access = try r.grantAll(); r.access?.revoke()
        let before = r.storage.values, stores = r.storage.stores
        await expectBoth(r, api: .notConfigured)
        XCTAssertEqual(r.storage.values, before); XCTAssertEqual(r.storage.stores, stores); XCTAssertEqual(r.storage.removes, 0)
        XCTAssertTrue(r.wire.requests.isEmpty)
    }
    func testAlreadyDispatchedCreateStillRetainsLockWhenGrantIsRevoked() async throws {
        let r = try PrivateCreateAdmissionRig(); r.access = try r.grantAll(); r.wire.hold = true
        let task = Task { try await r.reader.createCapsule(r.capsule) }
        for _ in 0..<200 { if r.wire.pending != nil { break }; await Task.yield() }
        let held = try XCTUnwrap(r.wire.pending); r.wire.pending = nil
        XCTAssertNotNil(try r.journal.entry(kind: .capsuleCreate, scope: r.scope))
        r.access?.revoke(); held.resume(returning: (try r.wire.reply(capsule: true), 200))
        do { _ = try await task.value; XCTFail() }
        catch { XCTAssertEqual(error as? RoamPrivateWriteError, .changedContext) }
        XCTAssertEqual(r.reader.unresolvedCapsuleRequestID, r.capsule.requestID)
        XCTAssertEqual(r.wire.requests.count, 1); XCTAssertEqual(r.storage.removes, 0)
    }
    private func expectBoth(_ r: PrivateCreateAdmissionRig, api: APIError? = nil,
                            write: RoamPrivateWriteError? = nil, journal: RoamPrivatePendingJournalError? = nil) async {
        for capsule in [true, false] {
            do {
                if capsule { _ = try await r.reader.createCapsule(r.capsule) }
                else { _ = try await r.reader.createGoal(r.goal) }
                XCTFail("The original create must be refused")
            } catch {
                if let api { XCTAssertEqual(error as? APIError, api) }
                if let write { XCTAssertEqual(error as? RoamPrivateWriteError, write) }
                if let journal { XCTAssertEqual(error as? RoamPrivatePendingJournalError, journal) }
            }
        }
    }
}

@MainActor private final class PrivateCreateAdmissionStorage: RoamPrivatePendingJournalStoring {
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
@MainActor private final class PrivateCreateAdmissionWire: HTTPTransport {
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
@MainActor private final class PrivateCreateAdmissionRig {
    static let base = URL(string: "https://example.test/native")!
    let storage = PrivateCreateAdmissionStorage(), wire = PrivateCreateAdmissionWire()
    let scope: RoamHistoryScope, context: RuntimeDependencyContext
    let capsule: RoamCapsuleDraft, goal: RoamGoalDraft
    var access: RoamPrivateToolsAccess?
    var reader: RoamPrivateToolsSessionReader!
    let withJournal: Bool
    lazy var journal = RoamPrivatePendingJournal(storage: storage)
    init(withJournal: Bool = true) throws {
        self.withJournal = withJournal
        scope = try .init(market: "cn", deployment: Self.base, accountID: 7, namespace: "create-admission")
        context = .init(market: .china, baseURL: Self.base, role: "player", session: try .init(accountID: 7, epoch: 1, namespace: "create-admission", token: "synthetic"))
        let period = try XCTUnwrap(RoamGoalPeriod.periods(now: Date()).last)
        capsule = .init(requestID: "ios_0123456789abcdef", body: "Synthetic capsule", unlockDate: period.endDateExclusive)
        goal = .init(requestID: "ios_abcdef0123456789", metric: .distinctRoutes, target: 3, startDate: period.startDate, endDateExclusive: period.endDateExclusive)
        wire.goal = goal
        access = try grant(RoamPrivateToolsRoute.reads); reopen()
    }
    func grant(_ paths: Set<String>) throws -> RoamPrivateToolsAccess {
        try .init(context: context, approval: .init(baseURL: Self.base, namespace: "create-admission", accountID: 7, paths: paths))
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
