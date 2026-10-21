import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private actor C6PendingWire: HTTPTransport {
    enum Reply { case body(String, Int), failure }
    var replies: [Reply]
    private(set) var requests: [URLRequest] = []
    init(_ replies: [Reply]) { self.replies = replies }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        switch replies.removeFirst() {
        case .body(let text, let status): return (Data(text.utf8), status)
        case .failure: throw URLError(.timedOut)
        }
    }
}

@MainActor final class RoamPrivatePendingJournalTests: XCTestCase {
    private let base = URL(string: "https://tools.example/native")!
    private let requestID = "ios_0123456789abcdef"

    private func scope(account: Int = 7, namespace: String = "roam-tools") throws -> RoamHistoryScope {
        try RoamHistoryScope(market: "cn", deployment: base, accountID: account, namespace: namespace)
    }
    private func context(account: Int = 7) throws -> RuntimeDependencyContext {
        RuntimeDependencyContext(market: .china, baseURL: base, role: "player",
                                 session: try PlayExperienceSession(accountID: account, epoch: 1, namespace: "roam-tools", token: "synthetic-\(account)"))
    }
    private func reader(wire: C6PendingWire, storage: RoamPrivatePendingInMemoryJournalStorage,
                        context: RuntimeDependencyContext) throws -> RoamPrivateToolsSessionReader {
        let access = try RoamPrivateToolsAccess(context: context, approval: .init(
            baseURL: base, namespace: "roam-tools", accountID: context.session.accountID,
            paths: RoamPrivateToolsRoute.reads.union(RoamPrivateToolsRoute.writes)))
        let service = try RoamPrivateToolsService(configuration: APIConfiguration(baseURL: base), transport: wire)
        return RoamPrivateToolsSessionReader(service: service, current: { context }, access: { _ in access },
                                             journal: RoamPrivatePendingJournal(storage: storage))
    }

    func testJournalRecordSurvivesNewInstanceAndStoresOnlyMinimalIdentity() throws {
        let storage = RoamPrivatePendingInMemoryJournalStorage()
        let owner = try scope()
        try RoamPrivatePendingJournal(storage: storage).record(kind: .capsuleCreate, requestID: requestID, scope: owner, now: Date(timeIntervalSince1970: 1_792_382_400))
        // A fresh journal over the same storage is the restart.
        let restored = try RoamPrivatePendingJournal(storage: storage).entry(kind: .capsuleCreate, scope: owner)
        XCTAssertEqual(restored?.requestID, requestID)
        XCTAssertEqual(restored?.accountID, 7)
        let raw = String(decoding: try XCTUnwrap(storage.values.values.first), as: UTF8.self)
        let keys = Set(((try JSONSerialization.jsonObject(with: XCTUnwrap(storage.values.values.first)) as? [String: Any]) ?? [:]).keys)
        XCTAssertEqual(keys, ["version", "kind", "requestId", "market", "deployment", "namespace", "accountId", "recordedAtMs"])
        for forbidden in ["token", "body", "photo", "secret"] { XCTAssertFalse(raw.contains(forbidden), forbidden) }
        XCTAssertNil(try RoamPrivatePendingJournal(storage: storage).entry(kind: .goalCreate, scope: owner), "Kinds hold separate slots")
    }

    func testJournalIsIsolatedByAccountDeploymentAndNamespace() throws {
        let storage = RoamPrivatePendingInMemoryJournalStorage()
        let journal = RoamPrivatePendingJournal(storage: storage)
        try journal.record(kind: .goalCreate, requestID: requestID, scope: try scope(), now: Date())
        XCTAssertNil(try journal.entry(kind: .goalCreate, scope: try scope(account: 8)))
        XCTAssertNil(try journal.entry(kind: .goalCreate, scope: try scope(namespace: "other")))
        XCTAssertNil(try journal.entry(kind: .goalCreate, scope: try RoamHistoryScope(
            market: "cn", deployment: URL(string: "https://elsewhere.example/native")!, accountID: 7, namespace: "roam-tools")))
        XCTAssertThrowsError(try journal.record(kind: .goalCreate, requestID: "ios_fedcba9876543210", scope: try scope())) {
            XCTAssertEqual($0 as? RoamPrivatePendingJournalError, .locked, "A held slot is never overwritten by another request")
        }
        XCTAssertThrowsError(try journal.clear(kind: .goalCreate, requestID: "ios_fedcba9876543210", scope: try scope())) {
            XCTAssertEqual($0 as? RoamPrivatePendingJournalError, .locked, "Another request cannot clear the lock")
        }
        XCTAssertEqual(try journal.entry(kind: .goalCreate, scope: try scope())?.requestID, requestID)
    }

    func testCorruptJournalBytesFailClosed() throws {
        let storage = RoamPrivatePendingInMemoryJournalStorage()
        let journal = RoamPrivatePendingJournal(storage: storage)
        try journal.record(kind: .capsuleCreate, requestID: requestID, scope: try scope(), now: Date())
        for key in Array(storage.values.keys) { storage.values[key] = Data(#"{"version":1,"kind":"capsuleCreate","requestId":"ios_0123456789abcdef","body":"smuggled"}"#.utf8) }
        XCTAssertThrowsError(try journal.entry(kind: .capsuleCreate, scope: try scope())) {
            XCTAssertEqual($0 as? RoamPrivatePendingJournalError, .corrupted)
        }
        for key in Array(storage.values.keys) { storage.values[key] = Data("not json".utf8) }
        XCTAssertThrowsError(try journal.entry(kind: .capsuleCreate, scope: try scope())) {
            XCTAssertEqual($0 as? RoamPrivatePendingJournalError, .corrupted, "Non-JSON bytes are never trusted either")
        }
    }

    func testFileJournalRoundTripsAcrossInstancesAndCorruptionFailsClosed() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("c6-journal-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let owner = try scope()
        try RoamPrivatePendingJournal(storage: RoamPrivatePendingFileJournalStorage(directory: directory))
            .record(kind: .capsuleCreate, requestID: requestID, scope: owner, now: Date())
        let reopened = RoamPrivatePendingJournal(storage: RoamPrivatePendingFileJournalStorage(directory: directory))
        XCTAssertEqual(try reopened.entry(kind: .capsuleCreate, scope: owner)?.requestID, requestID)
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        try Data("garbage".utf8).write(to: file)
        XCTAssertThrowsError(try reopened.entry(kind: .capsuleCreate, scope: owner)) {
            XCTAssertEqual($0 as? RoamPrivatePendingJournalError, .corrupted)
        }
    }

    func testUnknownCreateSurvivesRestartLocksNewRequestsAndClearsOnlyOnReceipt() async throws {
        let storage = RoamPrivatePendingInMemoryJournalStorage()
        let owner = try context()
        let draft = RoamCapsuleDraft(requestID: requestID, body: "给明年的自己", unlockDate: "2030-01-01")
        let firstWire = C6PendingWire([.failure])
        let first = try reader(wire: firstWire, storage: storage, context: owner)
        do { _ = try await first.createCapsule(draft); XCTFail() }
        catch { XCTAssertEqual(error as? RoamPrivateWriteError, .outcomeUnknown) }

        // Restart: a brand-new reader over the same durable storage.
        let secondWire = C6PendingWire([.body(#"{"code":200,"data":{"id":"40","state":"LOCKED"}}"#, 200)])
        let second = try reader(wire: secondWire, storage: storage, context: owner)
        XCTAssertNil(second.pendingCapsule, "The draft body is never restored from the journal")
        XCTAssertEqual(second.unresolvedCapsuleRequestID, requestID)
        let other = RoamCapsuleDraft(requestID: "ios_fedcba9876543210", body: "另一枚", unlockDate: "2030-01-01")
        do { _ = try await second.createCapsule(other); XCTFail() }
        catch { XCTAssertEqual(error as? RoamPrivateWriteError, .pendingMismatch) }
        let blocked = await secondWire.requests.count
        XCTAssertEqual(blocked, 0, "A different request is refused before dispatch while the lock is held")

        _ = try await second.capsuleReceipt(requestID: requestID)
        XCTAssertNil(second.unresolvedCapsuleRequestID, "A returned receipt is the confirmation that clears the lock")
        XCTAssertNil(try RoamPrivatePendingJournal(storage: storage).entry(kind: .capsuleCreate, scope: try scope()))
    }

    func testSaveFailureSendsNothingAndCorruptionBlocksReader() async throws {
        let owner = try context()
        let draft = RoamCapsuleDraft(requestID: requestID, body: "ok", unlockDate: "2030-01-01")
        let failingStorage = RoamPrivatePendingInMemoryJournalStorage()
        failingStorage.storeError = NSError(domain: "c6", code: 1)
        let wire = C6PendingWire([.body(#"{"code":200,"data":{"id":"40","state":"LOCKED"}}"#, 200)])
        let reader = try reader(wire: wire, storage: failingStorage, context: owner)
        do { _ = try await reader.createCapsule(draft); XCTFail() }
        catch { XCTAssertEqual(error as? RoamPrivatePendingJournalError, .saveFailed) }
        let sent = await wire.requests.count
        XCTAssertEqual(sent, 0, "When the minimal identity cannot be saved, the request is not sent")

        let corruptStorage = RoamPrivatePendingInMemoryJournalStorage()
        let journal = RoamPrivatePendingJournal(storage: corruptStorage)
        try journal.record(kind: .capsuleCreate, requestID: requestID, scope: try scope(), now: Date())
        for key in Array(corruptStorage.values.keys) { corruptStorage.values[key] = Data("broken".utf8) }
        let corruptWire = C6PendingWire([])
        let corruptReader = try reader(wire: corruptWire, storage: corruptStorage, context: owner)
        _ = corruptReader.unresolvedCapsuleRequestID
        XCTAssertTrue(corruptReader.pendingJournalBlocked)
        XCTAssertNil(corruptReader.unresolvedCapsuleRequestID, "Corrupt bytes never yield a trusted request ID")
        do { _ = try await corruptReader.createCapsule(draft); XCTFail() }
        catch { XCTAssertEqual(error as? RoamPrivatePendingJournalError, .corrupted) }
        let corruptSent = await corruptWire.requests.count
        XCTAssertEqual(corruptSent, 0)
    }

    func testRestoredLockBlocksCoordinatorCreatesAndReceiptOnlyVerification() async {
        let tools = C6RestoredTools()
        tools.unresolvedCapsuleRequestID = requestID
        let model = RoamCapsuleCoordinator(tools: tools)
        XCTAssertNil(model.pending)
        XCTAssertEqual(model.pendingRequestID, requestID)
        model.prepareCreate(body: "新内容", unlockDate: "2030-01-01")
        XCTAssertEqual(model.issue, .pendingFirst)
        XCTAssertNil(model.review)
        let retried = await model.retryPending()
        XCTAssertFalse(retried)
        XCTAssertEqual(tools.createCalls, 0, "A request ID alone never rebuilds or resends a body")
        await model.verifyPending()
        XCTAssertEqual(tools.receiptIDs, [requestID])
        XCTAssertNil(model.pendingRequestID)
    }

    func testFirstRefusalClearsButRejectionAfterUnknownSurvivesRestart() async throws {
        let storage = RoamPrivatePendingInMemoryJournalStorage()
        let owner = try context()
        let draft = RoamCapsuleDraft(requestID: requestID, body: "给明年的自己", unlockDate: "2030-01-01")
        let refused = C6PendingWire([.body(#"{"code":400,"msg":"no"}"#, 200)])
        let first = try reader(wire: refused, storage: storage, context: owner)
        do { _ = try await first.createCapsule(draft); XCTFail() }
        catch { XCTAssertEqual(error as? RoamPrivateWriteError, .rejected("no")) }
        XCTAssertNil(first.unresolvedCapsuleRequestID, "A refusal of a never-uncertain attempt still clears the lock")
        XCTAssertNil(try RoamPrivatePendingJournal(storage: storage).entry(kind: .capsuleCreate, scope: try scope()))

        let unknown = C6PendingWire([.failure])
        let second = try reader(wire: unknown, storage: storage, context: owner)
        do { _ = try await second.createCapsule(draft); XCTFail() }
        catch { XCTAssertEqual(error as? RoamPrivateWriteError, .outcomeUnknown) }
        let marked = try RoamPrivatePendingJournal(storage: storage).entry(kind: .capsuleCreate, scope: try scope())
        XCTAssertEqual(marked?.requestID, requestID)
        XCTAssertEqual(marked?.receiptRequired, true)

        let retry = C6PendingWire([.body(#"{"code":400,"msg":"again"}"#, 200)])
        let third = try reader(wire: retry, storage: storage, context: owner)
        do { _ = try await third.createCapsule(draft); XCTFail() }
        catch { XCTAssertEqual(error as? RoamPrivateWriteError, .rejected("again")) }
        XCTAssertEqual(third.unresolvedCapsuleRequestID, requestID, "A later refusal does not prove the unknown attempt failed")

        let restarted = try reader(wire: C6PendingWire([]), storage: storage, context: owner)
        XCTAssertEqual(restarted.unresolvedCapsuleRequestID, requestID)
        let other = RoamCapsuleDraft(requestID: "ios_fedcba9876543210", body: "另一枚", unlockDate: "2030-01-01")
        do { _ = try await restarted.createCapsule(other); XCTFail() }
        catch { XCTAssertEqual(error as? RoamPrivateWriteError, .pendingMismatch) }
    }
}

/// Serving fake whose only pending state is a restored request ID, as after a restart.
@MainActor private final class C6RestoredTools: RoamPrivateToolsServing {
    private let ownerScope = try! RoamHistoryScope(market: "cn", deployment: URL(string: "https://example.com/synthetic-roam")!, accountID: 900)
    var identity: RoamExperienceIdentity? { RoamExperienceIdentity(scope: ownerScope, epoch: 1) }
    var isConfigured: Bool { true }
    var allowsWrites: Bool { true }
    var isOfflineExample: Bool { false }
    var now: Date { Date(timeIntervalSince1970: 1_792_382_400) }
    var pendingCapsule: RoamCapsuleDraft?
    var pendingGoal: RoamGoalDraft?
    var confirmedCancelledGoals: Set<String> = []
    var unresolvedCapsuleRequestID: String?
    var createCalls = 0
    var receiptIDs: [String] = []

    func capsules(beforeID: String?) async throws -> RoamCapsulePage { RoamCapsulePage(items: [], hasMore: false, nextBeforeID: nil) }
    func capsule(id: String) async throws -> RoamCapsule { throw APIError.notConfigured }
    func capsuleReceipt(requestID: String) async throws -> RoamCapsule {
        receiptIDs.append(requestID)
        if unresolvedCapsuleRequestID == requestID { unresolvedCapsuleRequestID = nil }
        return RoamCapsule(id: "40", state: .locked, unlockAtMs: nil, createdAtMs: nil, body: nil, photoURL: nil)
    }
    func createCapsule(_ draft: RoamCapsuleDraft) async throws -> RoamCapsule { createCalls += 1; throw APIError.notConfigured }
    func deleteCapsule(id: String) async throws -> RoamCapsule { throw APIError.notConfigured }
    func goals(beforeID: String?) async throws -> RoamGoalPage { throw APIError.notConfigured }
    func goal(id: String) async throws -> RoamExplorationGoal { throw APIError.notConfigured }
    func goalReceipt(requestID: String) async throws -> RoamExplorationGoal { throw APIError.notConfigured }
    func createGoal(_ draft: RoamGoalDraft) async throws -> RoamExplorationGoal { createCalls += 1; throw APIError.notConfigured }
    func cancelGoal(id: String) async throws -> RoamExplorationGoal { throw APIError.notConfigured }
    func prepareExport(_ request: RoamExportRequest) async throws -> RoamExportCheckpoint { throw APIError.notConfigured }
    func exportPage(_ checkpoint: RoamExportCheckpoint) async throws -> RoamExportChunk { throw APIError.notConfigured }
}
