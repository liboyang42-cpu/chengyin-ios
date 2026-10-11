import XCTest
@testable import QuestifyCore

@MainActor final class RoamOfficialTasksTests: XCTestCase {
    private func events(_ json: String = #"[{"id":71,"title":"City walk","city":"Example","status":3},{"id":72,"title":"Next","status":1},{"id":73,"title":"Past","status":5},{"id":74,"title":"Unknown"}]"#) throws -> [OfficialEvent] { try JSONDecoder().decode([OfficialEvent].self, from: Data(json.utf8)) }
    private func identity(account: Int = 1, epoch: UInt64 = 1, namespace: String = "roam", market: String = "cn", host: String = "https://example.com") throws -> RoamExperienceIdentity {
        .init(scope: try RoamHistoryScope(market: market, deployment: URL(string: host)!, accountID: account, namespace: namespace), epoch: epoch)
    }
    private func setup() throws -> (Roam, Official, RoamOfficialTasksModel) {
        let roam = Roam(identity: try identity()), official = Official(); official.all = try events(); official.mine = try events(#"[{"id":81,"title":"Joined","status":3,"signed":true}]"#)
        return (roam, official, .init(roam: roam, official: official))
    }
    private let live = OfficialEventBrowseQuery(bucket: .live, keyword: "")
    func testConstructionDoesNotReadAnything() throws {
        let (roam, official, model) = try setup()
        XCTAssertNil(model.snapshot); XCTAssertNil(model.error); XCTAssertEqual(official.calls, []); XCTAssertEqual(roam.reads, 0)
    }
    func testCompleteSceneReadsOnlyTwoExistingListContracts() async throws {
        let (roam, official, model) = try setup(); await model.load()
        XCTAssertEqual(official.calls, ["all", "mine"]); XCTAssertEqual(roam.reads, 0)
        XCTAssertEqual(model.snapshot?.all.count, 4); XCTAssertEqual(model.snapshot?.mine.map(\.id), [81]); XCTAssertFalse(model.isLoading)
    }
    func testFourBucketsReuseExistingOfficialStatusContract() async throws {
        let (_, _, model) = try setup(); await model.load(); let snapshot = try XCTUnwrap(model.snapshot)
        XCTAssertEqual(snapshot.visible(live).map(\.id), [71, 74])
        XCTAssertEqual(snapshot.visible(.init(bucket: .upcoming, keyword: "")).map(\.id), [72])
        XCTAssertEqual(snapshot.visible(.init(bucket: .ended, keyword: "")).map(\.id), [73])
        XCTAssertEqual(snapshot.visible(.init(bucket: .mine, keyword: "")).map(\.id), [81])
    }
    func testSourceKeywordFiltersLoadedRowsWithoutMoreReads() async throws {
        let (_, official, model) = try setup(); await model.load(); let snapshot = try XCTUnwrap(model.snapshot)
        XCTAssertEqual(snapshot.visible(.init(bucket: .live, keyword: "  EXAMPLE ")).map(\.id), [71])
        XCTAssertTrue(snapshot.visible(.init(bucket: .mine, keyword: "missing")).isEmpty)
        XCTAssertEqual(official.calls, ["all", "mine"])
    }
    func testSuccessfulEmptySnapshotIsDifferentFromError() async throws {
        let (_, official, model) = try setup(); official.all = []; official.mine = []; await model.load()
        XCTAssertNotNil(model.snapshot); XCTAssertNil(model.error); XCTAssertTrue(model.snapshot!.visible(live).isEmpty)
    }
    func testFirstListFailureDoesNotIssuePrivateReadOrCreateEmptySuccess() async throws {
        let (_, official, model) = try setup(); official.allFailure = APIError.httpStatus(503); await model.load()
        XCTAssertEqual(official.calls, ["all"]); XCTAssertNil(model.snapshot); XCTAssertNotNil(model.error)
    }
    func testSecondListFailureDoesNotPublishHalfSnapshot() async throws {
        let (_, official, model) = try setup(); official.mineFailure = APIError.httpStatus(503); await model.load()
        XCTAssertEqual(official.calls, ["all", "mine"]); XCTAssertNil(model.snapshot); XCTAssertNotNil(model.error)
    }
    func testRefreshFailureRetainsExactSameOwnerSnapshot() async throws {
        let (_, official, model) = try setup(); await model.load(); let original = try XCTUnwrap(model.snapshot)
        official.all = try events(#"[{"id":99,"title":"New","status":3}]"#); official.mineFailure = APIError.httpStatus(503); await model.load()
        XCTAssertEqual(model.snapshot?.id, original.id); XCTAssertEqual(model.snapshot?.all.map(\.id), [71,72,73,74]); XCTAssertNotNil(model.error)
    }
    func testRetryReplacesSnapshotOnlyAfterBothListsSucceed() async throws {
        let (_, official, model) = try setup(); official.mineFailure = APIError.httpStatus(503); await model.load()
        official.mineFailure = nil; await model.load(); XCTAssertNotNil(model.snapshot); XCTAssertNil(model.error)
    }
    func testUnauthorizedRefreshClearsOldPrivateSnapshot() async throws {
        let (_, official, model) = try setup(); await model.load(); official.mineFailure = APIError.unauthorized; await model.load()
        XCTAssertNil(model.snapshot); XCTAssertEqual(model.error as? APIError, .unauthorized)
    }
    func testUnavailableOrUnsignedSceneNeverReads() async throws {
        let (roam, official, model) = try setup(); official.isConfigured = false; await model.load(); XCTAssertTrue(official.calls.isEmpty)
        official.isConfigured = true; official.isAuthenticated = false; await model.load(); XCTAssertTrue(official.calls.isEmpty)
        official.isAuthenticated = true; roam.identity = nil; await model.load(); XCTAssertTrue(official.calls.isEmpty); XCTAssertNil(model.snapshot)
    }
    func testRoamRemoteConfigurationDoesNotInventExtraGrant() async throws {
        let (roam, official, model) = try setup(); roam.isConfigured = false; await model.load()
        XCTAssertEqual(official.calls, ["all","mine"]); XCTAssertNotNil(model.snapshot)
    }
    func testOfficialScopeChangeHidesOldSnapshotBeforeReload() async throws {
        let (_, official, model) = try setup(); await model.load(); official.scope = UUID()
        XCTAssertNil(model.snapshot); XCTAssertNil(model.error)
    }
    func testAllRoamOwnerDimensionsHideOldSnapshot() async throws {
        let alternatives = try [identity(account: 2), identity(epoch: 2), identity(namespace: "other"), identity(market: "us"), identity(host: "https://example.org")]
        for identity in alternatives {
            let (roam, _, model) = try setup(); await model.load(); roam.identity = identity; XCTAssertNil(model.snapshot)
        }
    }
    func testExactUnicodeNamespaceBytesMatter() async throws {
        let (roam, _, model) = try setup(); roam.identity = try identity(namespace: "\u{00E9}"); await model.load()
        roam.identity = try identity(namespace: "e\u{0301}"); XCTAssertNil(model.snapshot)
    }
    func testOwnerChangedBetweenReadsPreventsMineRequest() async throws {
        let (roam, official, model) = try setup(); official.afterAll = { roam.identity = nil }; await model.load()
        XCTAssertEqual(official.calls, ["all"]); XCTAssertNil(model.snapshot)
    }
    func testLateSecondReadCannotPopulateNewOwner() async throws {
        let (_, official, model) = try setup(); official.afterMine = { official.scope = UUID() }; await model.load()
        XCTAssertNil(model.snapshot); XCTAssertNil(model.error)
    }
    func testCancellationBetweenReadsPreventsMineAndIgnoresResult() async throws {
        let (_, official, model) = try setup(); official.afterAll = { model.cancelPending() }; await model.load()
        XCTAssertEqual(official.calls, ["all"]); XCTAssertNil(model.snapshot); XCTAssertFalse(model.isLoading)
    }
    func testOlderRefreshCannotOverwriteNewSnapshot() async throws {
        let (_, official, model) = try setup()
        official.suspendNextAll = true
        let old = Task { await model.load() }
        while official.pendingAll == nil { await Task.yield() }
        official.all = try events(#"[{"id":99,"title":"Newest","status":3}]"#); await model.load()
        let latest = try XCTUnwrap(model.snapshot)
        official.pendingAll?.resume(returning: try events()); official.pendingAll = nil; await old.value
        XCTAssertEqual(model.snapshot?.id, latest.id); XCTAssertEqual(model.snapshot?.all.map(\.id), [99])
    }
    func testDuplicateOrInvalidOfficialIDsFailClosed() async throws {
        for raw in [#"[{"id":0,"title":"Invalid"}]"#, #"[{"id":71},{"id":71}]"#] {
            let (_, official, model) = try setup(); official.all = try events(raw); await model.load()
            XCTAssertNil(model.snapshot); XCTAssertEqual(model.error as? APIError, .malformedResponse)
        }
    }
    func testSelectionRequiresVisibleCurrentActualRow() async throws {
        let (_, _, model) = try setup(); await model.load(); let snapshot = try XCTUnwrap(model.snapshot)
        XCTAssertNil(model.select(eventID: 71, query: live, renderedSnapshotID: snapshot.id)); model.appear()
        XCTAssertNil(model.select(eventID: 71, query: live, renderedSnapshotID: UUID()))
        XCTAssertNil(model.select(eventID: 72, query: live, renderedSnapshotID: snapshot.id))
        XCTAssertNil(model.select(eventID: 999, query: live, renderedSnapshotID: snapshot.id))
        XCTAssertEqual(model.select(eventID: 71, query: live, renderedSnapshotID: snapshot.id)?.eventID, 71)
    }
    func testPushingDetailKeepsExactSelectionWhileCancellingListLoad() async throws {
        let (_, _, model) = try setup(); model.appear(); await model.load(); let snapshot = try XCTUnwrap(model.snapshot)
        let target = try XCTUnwrap(model.select(eventID: 71, query: live, renderedSnapshotID: snapshot.id))
        model.cancelPending(); XCTAssertTrue(model.mayRemainOpen(target))
        XCTAssertNil(model.select(eventID: 71, query: live, renderedSnapshotID: snapshot.id))
    }
    func testSelectedDetailRetiresOnOwnerOrSnapshotChange() async throws {
        let (_, official, model) = try setup(); model.appear(); await model.load(); let snapshot = try XCTUnwrap(model.snapshot)
        let target = try XCTUnwrap(model.select(eventID: 71, query: live, renderedSnapshotID: snapshot.id))
        await model.load(); XCTAssertFalse(model.mayRemainOpen(target))
        official.scope = UUID(); XCTAssertFalse(model.mayRemainOpen(target))
    }
    func testSelectionCannotCrossIndependentReaderPair() async throws {
        let (_, _, first) = try setup(), (_, _, second) = try setup(); first.appear(); await first.load(); await second.load()
        let target = try XCTUnwrap(first.select(eventID: 71, query: live, renderedSnapshotID: try XCTUnwrap(first.snapshot).id))
        XCTAssertFalse(second.mayRemainOpen(target))
    }
    func testInvalidateErasesBothListsAndPendingNavigation() async throws {
        let (_, _, model) = try setup(); model.appear(); await model.load(); let snapshot = try XCTUnwrap(model.snapshot)
        let target = try XCTUnwrap(model.select(eventID: 71, query: live, renderedSnapshotID: snapshot.id))
        model.invalidate(); XCTAssertNil(model.snapshot); XCTAssertNil(model.error); XCTAssertFalse(model.mayRemainOpen(target))
    }
    @MainActor private final class Roam: RoamExperienceReading {
        var identity: RoamExperienceIdentity?
        var isConfigured = true
        var isOfflineExample = true
        var reads = 0
        init(identity: RoamExperienceIdentity?) { self.identity = identity }
        func history() throws -> [RoamHistoryRecord] { reads += 1; return [] }
        func sessionFact(_ query: RoamRecoveryQuery) async throws -> RoamSessionFact { reads += 1; throw APIError.notConfigured }
        func album(page: Int, pageSize: Int) async throws -> RoamAlbumPage { reads += 1; throw APIError.notConfigured }
        func tilePage(afterID: Int, limit: Int) async throws -> RoamTileMemoryPage { reads += 1; throw APIError.notConfigured }
        func shopBadge() async throws -> RoamShopBadge? { reads += 1; throw APIError.notConfigured }
    }
    @MainActor private final class Official: OfficialEventReading {
        var isConfigured = true
        var isAuthenticated = true
        var isOfflineExample = true
        var scope = UUID()
        var all: [OfficialEvent] = [], mine: [OfficialEvent] = []
        var calls: [String] = []
        var allFailure: Error?, mineFailure: Error?
        var afterAll: (() -> Void)?, afterMine: (() -> Void)?
        var suspendNextAll = false
        var pendingAll: CheckedContinuation<[OfficialEvent], Error>?
        func events(city: String?) async throws -> [OfficialEvent] {
            calls.append("all"); afterAll?(); if let allFailure { throw allFailure }
            if suspendNextAll { suspendNextAll = false; return try await withCheckedThrowingContinuation { pendingAll = $0 } }
            return all
        }
        func myEvents() async throws -> [OfficialEvent] { calls.append("mine"); afterMine?(); if let mineFailure { throw mineFailure }; return mine }
        func detail(id: Int) async throws -> OfficialEvent { calls.append("detail"); throw APIError.notConfigured }
        func partyInbox() async throws -> [OfficialPartyInvite] { calls.append("inbox"); throw APIError.notConfigured }
        func canPublish() async throws -> Bool { calls.append("publisher"); throw APIError.notConfigured }
        func myPublished() async throws -> OfficialPublished { calls.append("published"); throw APIError.notConfigured }
        func broadcastStats(id: Int) async throws -> OfficialBroadcastStats { calls.append("broadcast"); throw APIError.notConfigured }
    }
}
