import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Real service/session-reader/coordinator, with deterministic in-memory HTTP and journal storage only.
@MainActor final class RoamPrivateReadDenialTests: XCTestCase {
    func testCapsuleContinuationDenialClearsMetadataAndCursorWithoutSuccessfulEmpty() async throws {
        for denial in [(401, 200), (200, 401), (403, 200), (200, 403)] {
            let r = try PrivateReadDenialRig(); await r.capsule.load()
            XCTAssertEqual(r.capsule.items.map(\.id), ["12"]); XCTAssertTrue(r.capsule.hasMore)
            r.wire.status = denial.0; r.wire.code = denial.1; await r.capsule.load(more: true)
            XCTAssertTrue(r.capsule.items.isEmpty); XCTAssertNil(r.capsule.opened); XCTAssertFalse(r.capsule.hasMore)
            XCTAssertEqual(r.capsule.phase, .failed); XCTAssertNotNil(r.capsule.issue)
            XCTAssertEqual(r.unauthorized, denial.0 == 401 || denial.1 == 401 ? 1 : 0)
            r.wire.status = 200; r.wire.code = 200; r.wire.offset = 100; await r.capsule.load()
            XCTAssertEqual(r.capsule.items.map(\.id), ["112"])
            XCTAssertEqual(r.wire.cursors, [nil, "12", nil]); XCTAssertNil(r.capsule.issue)
        }
    }
    func testGoalContinuationDenialClearsOldOpenDetailAndRestartsAtFirstPage() async throws {
        for denial in [(401, 200), (200, 401), (403, 200), (200, 403)] {
            let r = try PrivateReadDenialRig(); await r.goal.load(); await r.goal.open("22")
            XCTAssertNotNil(r.goal.detail)
            r.wire.status = denial.0; r.wire.code = denial.1; await r.goal.load(more: true)
            XCTAssertTrue(r.goal.rows.isEmpty); XCTAssertNil(r.goal.detail); XCTAssertFalse(r.goal.hasMore)
            XCTAssertEqual(r.goal.phase, .failed)
            r.wire.status = 200; r.wire.code = 200; r.wire.offset = 100; await r.goal.load()
            XCTAssertEqual(r.goal.rows.map(\.id), ["122"]); XCTAssertNil(r.goal.detail)
            XCTAssertEqual(r.wire.cursors, [nil, "22", nil])
        }
    }
    func testCurrentDetailRefusalClearsPriorPrivateDetailsAndNeverTurnsIntoEmptySuccess() async throws {
        for status in [401, 403] {
            let r = try PrivateReadDenialRig(); await r.capsule.load()
            let first = try XCTUnwrap(r.capsule.items.first); await r.capsule.open(first)
            XCTAssertEqual(r.capsule.opened?.body, "Synthetic private body")
            r.wire.status = status; await r.capsule.open(first)
            XCTAssertNil(r.capsule.opened); XCTAssertTrue(r.capsule.items.isEmpty); XCTAssertEqual(r.capsule.phase, .failed)
            r.wire.status = 200; await r.goal.load(); await r.goal.open("22")
            r.wire.status = status; await r.goal.open("22")
            XCTAssertNil(r.goal.detail); XCTAssertTrue(r.goal.rows.isEmpty); XCTAssertEqual(r.goal.phase, .failed)
        }
    }
    func testTransientHTTPWithMisleadingDeniedBodyRetainsContinuationAndDetail() async throws {
        for status in [408, 429, 500, 503] {
            let r = try PrivateReadDenialRig(); await r.capsule.load(); await r.goal.load(); await r.goal.open("22")
            r.wire.status = status; r.wire.code = 403
            await r.capsule.load(more: true); await r.goal.load(more: true)
            XCTAssertEqual(r.capsule.items.map(\.id), ["12"]); XCTAssertTrue(r.capsule.hasMore)
            XCTAssertEqual(r.goal.rows.map(\.id), ["22"]); XCTAssertTrue(r.goal.hasMore); XCTAssertEqual(r.goal.detail?.id, "22")
            XCTAssertEqual(r.capsule.issue, .readFailed(.httpStatus(status)))
            XCTAssertEqual(r.goal.issue, .readFailed(.httpStatus(status)))
            r.wire.status = 200; r.wire.code = 200
            await r.capsule.load(more: true); await r.goal.load(more: true)
            XCTAssertEqual(r.capsule.items.map(\.id), ["11"], "Original capsule replaces pages")
            XCTAssertEqual(r.goal.rows.map(\.id), ["22", "21"], "Original goals append pages")
            XCTAssertEqual(r.wire.cursors, [nil, nil, "12", "22", "12", "22"])
        }
    }
    func testOfflineAndMalformedFailuresKeepOriginalDetailRetryPolicy() async throws {
        for malformed in [false, true] {
            let r = try PrivateReadDenialRig(); await r.capsule.load()
            let row = try XCTUnwrap(r.capsule.items.first); await r.capsule.open(row)
            await r.goal.load(); await r.goal.open("22")
            if malformed { r.wire.malformed = true } else { r.wire.failure = URLError(.notConnectedToInternet) }
            await r.capsule.open(row); await r.goal.open("22")
            XCTAssertEqual(r.capsule.opened?.body, "Synthetic private body"); XCTAssertEqual(r.goal.detail?.id, "22")
            XCTAssertTrue(r.capsule.hasMore); XCTAssertTrue(r.goal.hasMore)
            r.wire.failure = nil; r.wire.malformed = false; await r.goal.open("22")
            XCTAssertNil(r.goal.issue)
        }
    }
    func testDeniedReceiptDoesNotClearOriginalInMemoryPendingOrDurableLock() async throws {
        let r = try PrivateReadDenialRig()
        let a = RoamCapsuleDraft(requestID: "capsule_request_0001", body: "original body", unlockDate: "2030-01-01")
        let b = RoamGoalDraft(requestID: "goals_request_000001", metric: .distinctRoutes, target: 5, startDate: "2026-10-19", endDateExclusive: "2026-11-01")
        try r.journal.record(kind: .capsuleCreate, requestID: a.requestID, scope: r.scope, now: r.reader.now)
        try r.journal.record(kind: .goalCreate, requestID: b.requestID, scope: r.scope, now: r.reader.now)
        r.reader.pendingCapsule = a; r.reader.pendingGoal = b
        await r.capsule.load(); await r.goal.load(); await r.goal.open("22")
        let bytes = r.storage.values
        r.wire.status = 403; await r.capsule.verifyPending(); await r.goal.verifyPending()
        XCTAssertEqual(r.capsule.pending, a); XCTAssertEqual(r.goal.pending, b); XCTAssertEqual(r.storage.values, bytes)
        XCTAssertTrue(r.capsule.items.isEmpty); XCTAssertTrue(r.goal.rows.isEmpty); XCTAssertNil(r.goal.detail)
        XCTAssertEqual(r.capsule.issue, .outcomeUnknown); XCTAssertEqual(r.goal.issue, .outcomeUnknown)
        XCTAssertEqual(r.capsule.phase, .failed); XCTAssertEqual(r.goal.phase, .failed)
        XCTAssertTrue(r.wire.methods.allSatisfy { $0 == "GET" })
    }
    func testRestoredReceiptOnlyLocksSurviveDenialAndClearOnlyOnOriginalReceipt() async throws {
        let r = try PrivateReadDenialRig(seedLocks: true)
        XCTAssertNil(r.capsule.pending); XCTAssertNil(r.goal.pending)
        let before = r.storage.values
        r.wire.status = 403; await r.capsule.verifyPending(); await r.goal.verifyPending()
        XCTAssertEqual(r.storage.values, before); XCTAssertNotNil(r.capsule.pendingRequestID); XCTAssertNotNil(r.goal.pendingRequestID)
        r.wire.status = 200; await r.capsule.verifyPending(); await r.goal.verifyPending()
        XCTAssertNil(r.capsule.pendingRequestID); XCTAssertNil(r.goal.pendingRequestID); XCTAssertTrue(r.storage.values.isEmpty)
        XCTAssertEqual(r.wire.paths.filter { $0.hasSuffix("/receipt") }.count, 4)
        XCTAssertTrue(r.wire.methods.allSatisfy { $0 == "GET" })
    }
    func testOldDeniedResponseAfterRetirementCannotEraseNewSuccessfulMetadata() async throws {
        let r = try PrivateReadDenialRig(); await r.goal.load()
        r.wire.hold = true
        let old = Task { await r.goal.load(more: true) }
        for _ in 0..<100 { if r.wire.held != nil { break }; await Task.yield() }
        XCTAssertNotNil(r.wire.held)
        r.goal.suspend(); r.goal.resume(); r.wire.hold = false; r.wire.offset = 100; await r.goal.load()
        XCTAssertEqual(r.goal.rows.map(\.id), ["122"])
        r.wire.release(status: 403, code: 403); await old.value
        XCTAssertEqual(r.goal.rows.map(\.id), ["122"]); XCTAssertTrue(r.goal.hasMore); XCTAssertNil(r.goal.issue)
    }
    func testFirstPageDenialDiffersFromRealSuccessfulEmpty() async throws {
        let r = try PrivateReadDenialRig(); r.wire.code = 403
        await r.capsule.load(); await r.goal.load()
        XCTAssertEqual(r.capsule.phase, .failed); XCTAssertEqual(r.goal.phase, .failed)
        r.wire.code = 200; r.wire.empty = true
        await r.capsule.load(); await r.goal.load()
        XCTAssertEqual(r.capsule.phase, .ready); XCTAssertEqual(r.goal.phase, .ready)
        XCTAssertNil(r.capsule.issue); XCTAssertNil(r.goal.issue)
    }
}

@MainActor private final class PrivateReadDenialRig {
    static let base = URL(string: "https://example.test/private-denial")!
    let wire = PrivateReadDenialWire()
    let storage = RoamPrivatePendingInMemoryJournalStorage()
    let scope: RoamHistoryScope
    let context: RuntimeDependencyContext
    let access: RoamPrivateToolsAccess
    var unauthorized = 0
    lazy var journal = RoamPrivatePendingJournal(storage: storage)
    private(set) var reader: RoamPrivateToolsSessionReader!
    private(set) var capsule: RoamCapsuleCoordinator!
    private(set) var goal: RoamGoalsCoordinator!
    init(seedLocks: Bool = false) throws {
        scope = try .init(market: "cn", deployment: Self.base, accountID: 7, namespace: "denial")
        context = .init(market: .china, baseURL: Self.base, role: "player", session: try .init(accountID: 7, epoch: 1, namespace: "denial", token: "synthetic"))
        access = try .init(context: context, approval: .init(baseURL: Self.base, namespace: "denial", accountID: 7, paths: RoamPrivateToolsRoute.reads))
        if seedLocks {
            let journal = RoamPrivatePendingJournal(storage: storage)
            try journal.record(kind: .capsuleCreate, requestID: "capsule_request_0001", scope: scope, now: Date())
            try journal.record(kind: .goalCreate, requestID: "goals_request_000001", scope: scope, now: Date())
        }
        let service = try RoamPrivateToolsService(configuration: .init(baseURL: Self.base), transport: wire)
        reader = .init(service: service, current: { [weak self] in self?.context }, access: { [weak self] _ in self?.access }, onUnauthorized: { [weak self] _ in self?.unauthorized += 1 }, journal: journal)
        capsule = .init(tools: reader); goal = .init(tools: reader)
    }
}
@MainActor private final class PrivateReadDenialWire: HTTPTransport {
    var status = 200, code = 200, offset = 0
    var malformed = false, empty = false, hold = false
    var failure: Error?
    var held: CheckedContinuation<(Data, Int), Error>?
    var cursors: [String?] = [], paths: [String] = [], methods: [String] = []
    func release(status: Int, code: Int) { let pending = held; held = nil; pending?.resume(returning: (Data("{\"code\":\(code)}".utf8), status)) }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let url = try XCTUnwrap(request.url), path = url.path
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func field(_ key: String) -> String? { query.first { $0.name == key }?.value }
        paths.append(path); methods.append(request.httpMethod ?? "")
        XCTAssertEqual(request.httpMethod, "GET", "Only original read routes are used")
        if path.hasSuffix("/list") { cursors.append(field("beforeId")) }
        if hold { return try await withCheckedThrowingContinuation { held = $0 } }
        if let failure { throw failure }
        if status != 200 || code != 200 { return (Data("{\"code\":\(code)}".utf8), status) }
        if malformed { return (Data(#"{"code":200,"data":{}}"#.utf8), 200) }
        let capsule = path.contains("/capsules/"), list = path.hasSuffix("/list")
        let more = field("beforeId") != nil
        let id = field("id") ?? String((capsule ? 12 : 22) + offset - (more ? 1 : 0))
        var row: [String: Any]
        if capsule {
            row = ["id": id, "state": "OPEN", "unlockAtMs": 1_792_209_600_000, "createdAtMs": 1_775_102_400_000]
            if !list { row["body"] = "Synthetic private body" }
        } else {
            row = ["id": id, "requestId": field("requestId") ?? "goals_request_000001", "metric": "DISTINCT_ROUTES", "target": 5, "startDate": "2026-10-19", "endDateExclusive": "2026-11-01", "progress": 2, "state": "ACTIVE", "privateCommemoration": false, "timeZone": "Asia/Shanghai", "countingVersion": "COMPLETED_SESSION_AGGREGATE_V1", "asOfMs": 1_792_382_400_000, "createdAtMs": 1_792_382_400_000]
        }
        let data: [String: Any] = list ? ["items": empty ? [] : [row], "hasMore": !empty && !more, "nextBeforeId": !empty && !more ? id as Any : NSNull()] : row
        return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": data]), 200)
    }
}
