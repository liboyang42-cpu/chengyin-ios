import XCTest
@testable import QuestifyCore

@MainActor final class NativeChannelProgressFakeAccess: NativeChannelProgressAccess {
    var authority: NativeChannelProgressAuthoritySnapshot?
    var calls: [String] = []
    var saved: [NativeChannelProgressPrivacyCommand] = []
    var foundReceipt: NativeChannelProgressPrivacy?
    var failSave = true
    var saveConflict = false
    var currentPrivacyRevision: Int64 = 0
    var staleNext = false
    var historyRevision = "history-r"
    var recentHasMore = false
    var staleRecentCursor = false
    var failBest = false
    var failRecent = false
    var beforeBest: (() -> Void)?
    var recentRequests: [(query: NativeChannelProgressQuery, cursor: String?)] = []
    var latePage: (() async -> Void)?
    init() throws { authority = try NativeChannelProgressFixtures.authority() }
    func retireOperations() { calls.append("retire") }
    func definitions() async throws -> NativeChannelProgressDefinitions { calls.append("definitions"); return try NativeChannelProgressFixtures.decode("{\"visible\":true,\"list\":[\(NativeChannelProgressFixtures.boardJSON)]}") }
    func overview() async throws -> NativeChannelProgressOverview { try NativeChannelProgressFixtures.decode(#"{"visible":false}"#) }
    func page(_ query: NativeChannelProgressQuery, detail: Bool, cursor: String?) async throws -> NativeChannelProgressPage {
        calls.append(detail ? "detail" : "top")
        if let latePage { await latePage() }
        if cursor != nil && staleNext { staleNext = false; throw NativeChannelProgressError.server(status: 409, code: "BOARD_CURSOR_STALE") }
        return try NativeChannelProgressFixtures.decode(#"{"visible":true,"revision":"r","list":[],"next_cursor":"cursor-r-1","has_more":true}"#)
    }
    func best(_ query: NativeChannelProgressQuery) async throws -> NativeChannelProgressRow {
        calls.append("best"); beforeBest?()
        if failBest { throw NativeChannelProgressError.server(status: 500, code: "OUTCOME_UNKNOWN") }
        return try NativeChannelProgressFixtures.decode("""
        {"visible":true,"rank":null,"rank_known":false,"state":"NO_COMPLETED_EFFORT","revision":"best-\(historyRevision)"}
        """)
    }
    func recent(_ query: NativeChannelProgressQuery, cursor: String?) async throws -> NativeChannelProgressPage {
        calls.append("recent"); recentRequests.append((query, cursor))
        if failRecent { throw NativeChannelProgressError.server(status: 500, code: "OUTCOME_UNKNOWN") }
        if cursor != nil && staleRecentCursor { staleRecentCursor = false; throw NativeChannelProgressError.server(status: 409, code: "BOARD_CURSOR_STALE") }
        let revision = "\(historyRevision)-limit\(query.limit)"
        let next = recentHasMore ? "\"cursor-\(revision)\"" : "null"
        return try NativeChannelProgressFixtures.decode("""
        {"visible":true,"revision":"\(revision)","list":[{"subject_type":"MEMBER","subject_id":101,"required":10,"done":5,"completed":false,"percent":50,"metric":"PERCENT","metric_value":5000,"revision":"fact-v1","as_of":"2026-10-23T16:00:00Z","rank":null,"rank_known":false}],"next_cursor":\(next),"has_more":\(recentHasMore)}
        """)
    }
    func version(_ boardKey: String) async throws -> NativeChannelProgressVersion { try NativeChannelProgressFixtures.decode(#"{"visible":true,"revision":"r"}"#) }
    func meter(_ board: NativeChannelProgressBoard) async throws -> NativeChannelProgressMeter { calls.append("meter"); return try NativeChannelProgressFixtures.decode(#"{"visible":false}"#) }
    func privacy() async throws -> NativeChannelProgressPrivacy { calls.append("privacy"); return try NativeChannelProgressFixtures.privacy(revision: currentPrivacyRevision) }
    func save(_ command: NativeChannelProgressPrivacyCommand) async throws -> NativeChannelProgressPrivacy {
        calls.append("save"); saved.append(command)
        if saveConflict { currentPrivacyRevision = 1; throw NativeChannelProgressError.server(status: 409, code: "PRIVACY_CONFLICT") }
        if failSave { throw URLError(.timedOut) }; currentPrivacyRevision = 9; return try NativeChannelProgressFixtures.receipt(command)
    }
    func receipt(_ command: NativeChannelProgressPrivacyCommand) async throws -> NativeChannelProgressPrivacy? { calls.append("receipt"); return foundReceipt }
}
final class NativeChannelProgressCoordinatorTests: XCTestCase {
    @MainActor private func setup() throws -> (NativeChannelProgressCoordinator, NativeChannelProgressFakeAccess, NativeChannelProgressMemoryStorage) {
        let access = try NativeChannelProgressFakeAccess(), storage = NativeChannelProgressMemoryStorage()
        let journal = try NativeChannelProgressPrivacyJournal(identity: XCTUnwrap(access.authority).identity, storage: storage)
        return (try NativeChannelProgressCoordinator(access: access, journal: journal), access, storage)
    }
    @MainActor func testSelectPerformsAllFourReadsAndStaleCursorRereads() async throws {
        let (flow,access,_) = try setup(); await flow.activate()
        let board = try XCTUnwrap(flow.definitions.first), query = try NativeChannelProgressQuery(board: board, period: "ALL")
        await flow.select(board, query: query)
        XCTAssertTrue(["top","detail","best","recent"].allSatisfy(access.calls.contains))
        access.staleNext = true; let previous = access.calls.filter { $0 == "best" }.count
        await flow.loadMore()
        XCTAssertEqual(access.calls.filter { $0 == "best" }.count, previous + 1)
        XCTAssertEqual(flow.top.rows, [])
    }
    @MainActor func testUnknownWriteUsesOriginalReceiptBeforeSameKeyRetry() async throws {
        let (flow,access,storage) = try setup(); await flow.activatePrivacy()
        await flow.savePrivacy(try NativeChannelProgressFixtures.values())
        let original = try XCTUnwrap(access.saved.first)
        XCTAssertEqual(flow.privacyPhase, .unresolved); XCTAssertNotNil(flow.pendingCommand)
        XCTAssertEqual(access.calls.suffix(2), ["save","receipt"])
        XCTAssertFalse(storage.rows.isEmpty)
        access.failSave = false
        await flow.recoverOriginal(retryOriginal: true)
        XCTAssertEqual(access.saved, [original,original])
        XCTAssertEqual(Array(access.calls.suffix(3)), ["receipt","save","privacy"])
        XCTAssertNil(flow.pendingCommand); XCTAssertEqual(flow.receipt?.requestId, original.requestId)
        XCTAssertEqual(flow.privacy?.revision, 9) // Current settings are separate from original receipt revision 1.
    }
    @MainActor func testReceiptRecoveryAfterReloginDoesNotSendAgain() async throws {
        let (flow,access,storage) = try setup(); await flow.activatePrivacy(); await flow.savePrivacy(try NativeChannelProgressFixtures.values())
        let original = try XCTUnwrap(access.saved.first); access.foundReceipt = try NativeChannelProgressFixtures.receipt(original); access.currentPrivacyRevision = 9
        flow.invalidate()
        let journal = try NativeChannelProgressPrivacyJournal(identity: XCTUnwrap(access.authority).identity, storage: storage)
        let restored = try NativeChannelProgressCoordinator(access: access, journal: journal); await restored.activatePrivacy()
        XCTAssertEqual(access.saved.count, 1); XCTAssertEqual(restored.receipt?.requestId, original.requestId); XCTAssertNil(restored.pendingCommand)
    }
    @MainActor func testAuthorityLossImmediatelyWithholdsRowsAndPendingUI() async throws {
        let (flow,access,_) = try setup(); await flow.activatePrivacy(); await flow.savePrivacy(try NativeChannelProgressFixtures.values())
        access.authority = nil
        XCTAssertFalse(flow.isCurrent); XCTAssertNil(flow.privacy); XCTAssertNil(flow.pendingCommand); XCTAssertEqual(flow.privacyPhase, .accessClosed)
        flow.invalidate(); XCTAssertTrue(access.calls.contains("retire"))
    }
    @MainActor func testCASConflictRereadsBeforeNewUserIntent() async throws {
        let (flow,access,storage) = try setup(); await flow.activatePrivacy(); access.saveConflict = true
        await flow.savePrivacy(try NativeChannelProgressFixtures.values())
        XCTAssertEqual(flow.privacyPhase, .conflict); XCTAssertNil(flow.pendingCommand); XCTAssertNil(flow.receipt)
        XCTAssertEqual(flow.privacy?.revision, 1); XCTAssertTrue(storage.rows.isEmpty); XCTAssertEqual(access.saved.count, 1)
        XCTAssertEqual(Array(access.calls.suffix(3)), ["save","receipt","privacy"])
    }
    @MainActor func testAppliedReceiptSurvivesJournalClearFailureWithoutResend() async throws {
        let (flow,access,storage) = try setup(); await flow.activatePrivacy(); access.failSave = false; storage.failRemoves = true
        await flow.savePrivacy(try NativeChannelProgressFixtures.values())
        XCTAssertEqual(flow.privacyPhase, .persistenceFailed); XCTAssertNotNil(flow.receipt); XCTAssertNotNil(flow.pendingCommand)
        XCTAssertEqual(access.saved.count, 1); XCTAssertFalse(flow.canSavePrivacy)
        access.foundReceipt = flow.receipt; storage.failRemoves = false
        await flow.recoverOriginal()
        XCTAssertEqual(access.saved.count, 1); XCTAssertNil(flow.pendingCommand); XCTAssertEqual(flow.privacyPhase, .applied)
    }
    @MainActor func testLateReadAfterRetirementCannotRepopulateState() async throws {
        let (flow,access,_) = try setup(); await flow.activate()
        let board = try XCTUnwrap(flow.definitions.first), query = try NativeChannelProgressQuery(board: board, period: "ALL")
        access.latePage = { flow.invalidate() }
        await flow.select(board, query: query)
        XCTAssertFalse(flow.isCurrent); XCTAssertNil(flow.top.page); XCTAssertNil(flow.best); XCTAssertEqual(flow.definitions, [])
    }
    @MainActor func testUnchangedTopProbeStillRereadsOpaqueHistoryRevisions() async throws {
        let (flow,access,_) = try setup(); await flow.activate()
        let board = try XCTUnwrap(flow.definitions.first), query = try NativeChannelProgressQuery(board: board, period: "ALL")
        await flow.select(board, query: query)
        let oldRows = flow.recent.rows, oldRevision = flow.recent.page?.revision
        let topReads = access.calls.filter { $0 == "top" }.count
        access.historyRevision = "same-values-new-privacy-revision"
        access.beforeBest = { XCTAssertNil(flow.best); XCTAssertNil(flow.recent.page); XCTAssertEqual(flow.recent.rows, []) }
        await flow.checkVersion(); access.beforeBest = nil
        XCTAssertEqual(access.calls.filter { $0 == "top" }.count, topReads)
        XCTAssertEqual(flow.recent.rows, oldRows) // Numeric/fact rows did not change.
        XCTAssertNotEqual(flow.recent.page?.revision, oldRevision)
        XCTAssertEqual(flow.best?.revision, "best-same-values-new-privacy-revision")
        XCTAssertEqual(access.recentRequests.last?.query, query); XCTAssertNil(access.recentRequests.last?.cursor)
    }
    @MainActor func testStaleHistoryCursorRestartsOriginalQueryWithoutAppending() async throws {
        let (flow,access,_) = try setup(); access.recentHasMore = true; await flow.activate()
        let board = try XCTUnwrap(flow.definitions.first), query = try NativeChannelProgressQuery(board: board, period: "TOPIC", limit: 1)
        await flow.select(board, query: query)
        let originalCursor = try XCTUnwrap(flow.recent.page?.nextCursor)
        access.historyRevision = "new-permission-revision"; access.staleRecentCursor = true
        await flow.loadMore(history: true)
        let requests = Array(access.recentRequests.suffix(2))
        XCTAssertEqual(requests.count, 2); XCTAssertEqual(requests[0].cursor, originalCursor); XCTAssertNil(requests[1].cursor)
        XCTAssertTrue(requests.allSatisfy { $0.query == query }); XCTAssertEqual(flow.recent.rows.count, 1)
        XCTAssertEqual(flow.recent.page?.revision, "new-permission-revision-limit1")
        XCTAssertEqual(flow.best?.revision, "best-new-permission-revision")
    }
    @MainActor func testHistoryUnknownClearsOldPagesAndRetriesSameReadQuery() async throws {
        let (flow,access,_) = try setup(); await flow.activate()
        let board = try XCTUnwrap(flow.definitions.first), query = try NativeChannelProgressQuery(board: board, period: "TOPIC", limit: 20)
        await flow.select(board, query: query); XCTAssertEqual(flow.recent.rows.count, 1)
        access.failBest = true; access.failRecent = true; await flow.refreshOwnHistory()
        XCTAssertNil(flow.best); XCTAssertNil(flow.recent.page); XCTAssertEqual(flow.recent.rows, [])
        XCTAssertNotNil(flow.issue("best")); XCTAssertNotNil(flow.issue("recent"))
        access.failBest = false; access.failRecent = false; await flow.refreshOwnHistory()
        XCTAssertEqual(access.recentRequests.last?.query, query); XCTAssertNil(access.recentRequests.last?.cursor)
        XCTAssertEqual(flow.recent.rows.count, 1); XCTAssertTrue(access.saved.isEmpty); XCTAssertFalse(access.calls.contains("receipt"))
    }
    @MainActor func testChangingLimitStartsFreshHistoryEvenWhenFactsMatch() async throws {
        let (flow,access,_) = try setup(); await flow.activate()
        let board = try XCTUnwrap(flow.definitions.first)
        let firstQuery = try NativeChannelProgressQuery(board: board, period: "ALL", limit: 10)
        let secondQuery = try NativeChannelProgressQuery(board: board, period: "ALL", limit: 20)
        await flow.select(board, query: firstQuery)
        let first = flow.recent.page?.revision
        await flow.select(board, query: secondQuery)
        XCTAssertNotEqual(flow.recent.page?.revision, first); XCTAssertNil(access.recentRequests.last?.cursor)
        XCTAssertEqual(flow.recent.rows.count, 1); XCTAssertEqual(access.recentRequests.last?.query.limit, 20)
    }
}
