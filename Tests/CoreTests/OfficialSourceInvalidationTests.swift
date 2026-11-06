import XCTest
import Foundation
@testable import QuestifyCore

@MainActor private final class InvalidationRoamReader: RoamExperienceReading {
    var identity: RoamExperienceIdentity?
    var isConfigured = true
    var isOfflineExample = true
    init() throws { identity = .init(scope: try RoamHistoryScope(market: "cn", deployment: URL(string: "https://example.test")!, accountID: 7, namespace: "synthetic"), epoch: 1) }
    func history() throws -> [RoamHistoryRecord] { XCTFail(); return [] }
    func sessionFact(_ query: RoamRecoveryQuery) async throws -> RoamSessionFact { throw APIError.notConfigured }
    func album(page: Int, pageSize: Int) async throws -> RoamAlbumPage { throw APIError.notConfigured }
    func tilePage(afterID: Int, limit: Int) async throws -> RoamTileMemoryPage { throw APIError.notConfigured }
    func shopBadge() async throws -> RoamShopBadge? { throw APIError.notConfigured }
}
@MainActor private final class InvalidationOfficialReader: OfficialEventReading {
    let invalidationSignal: OfficialReadInvalidationSignal? = OfficialReadInvalidationSignal()
    var scope = UUID()
    var isConfigured = true
    var isAuthenticated = true
    var isOfflineExample = true
    var calls: [String] = []
    var afterAll: (() -> Void)?
    func invalidateSource() { scope = UUID(); invalidationSignal?.invalidate() }
    func rows() throws -> [OfficialEvent] { try JSONDecoder().decode([OfficialEvent].self, from: Data(#"[{"id":71,"title":"Synthetic","status":3}]"#.utf8)) }
    func events(city: String?) async throws -> [OfficialEvent] { calls.append("all"); afterAll?(); return try rows() }
    func myEvents() async throws -> [OfficialEvent] { calls.append("mine"); return try rows() }
    func detail(id: Int) async throws -> OfficialEvent { throw APIError.notConfigured }
    func partyInbox() async throws -> [OfficialPartyInvite] { throw APIError.notConfigured }
    func canPublish() async throws -> Bool { false }
    func myPublished() async throws -> OfficialPublished { throw APIError.notConfigured }
    func broadcastStats(id: Int) async throws -> OfficialBroadcastStats { throw APIError.notConfigured }
}

@MainActor final class OfficialSourceInvalidationTests: XCTestCase {
    private let base = URL(string: "https://example.test/native")!
    private func source() throws -> OfficialPublicEventReadSource { try .init(baseURL: base, namespace: "synthetic") }

    func testDefaultEmptySelectionDoesNotPublishOrIssueSource() {
        let selection = OfficialPublicEventReadSelection()
        var calls = 0
        let token = selection.invalidations.observe { calls += 1 }
        selection.select(nil)
        XCTAssertEqual(calls, 0); XCTAssertNil(selection.source)
        XCTAssertNil(selection.activeRevision(baseURL: base, namespace: "synthetic"))
        withExtendedLifetime(token) {}
    }
    func testRevokeNotifiesSynchronouslyAfterAuthorityIsRetiredAndOnlyOnce() throws {
        let selection = OfficialPublicEventReadSelection(), source = try self.source()
        selection.select(source); let original = selection.revision
        var calls = 0
        let token = selection.invalidations.observe {
            calls += 1; XCTAssertTrue(source.isRevoked)
            XCTAssertNil(selection.activeRevision(baseURL: self.base, namespace: "synthetic"))
            XCTAssertNotEqual(selection.revision, original)
        }
        source.revoke(); XCTAssertEqual(calls, 1)
        source.revoke(); XCTAssertEqual(calls, 1)
        withExtendedLifetime(token) {}
    }
    func testReplacementDetachesOldSourceAndNotifiesOnlyCurrentSource() throws {
        let selection = OfficialPublicEventReadSelection(), old = try source(), next = try source()
        selection.select(old)
        var calls = 0
        let token = selection.invalidations.observe { calls += 1 }
        selection.select(next); XCTAssertEqual(calls, 1)
        old.revoke(); XCTAssertEqual(calls, 1); XCTAssertFalse(next.isRevoked)
        next.revoke(); XCTAssertEqual(calls, 2)
        withExtendedLifetime(token) {}
    }
    func testRemovalReselectionAndTerminalRevocationNeverReuseRevision() throws {
        let selection = OfficialPublicEventReadSelection(), source = try self.source()
        selection.select(source); let first = selection.revision
        var revisions: [UUID] = []
        let token = selection.invalidations.observe { revisions.append(selection.revision) }
        selection.select(nil); selection.select(source); source.revoke()
        XCTAssertEqual(revisions.count, 3); XCTAssertEqual(Set(revisions).count, 3)
        XCTAssertFalse(revisions.contains(first))
        XCTAssertNil(selection.activeRevision(baseURL: base, namespace: "synthetic"))
        withExtendedLifetime(token) {}
    }
    func testCancelledAndDroppedSubscriptionsCannotReceiveFurtherEvents() {
        let signal = OfficialReadInvalidationSignal()
        var calls = 0
        var token: OfficialReadInvalidationSubscription? = signal.observe { calls += 1 }
        signal.invalidate(); XCTAssertEqual(calls, 1)
        token?.cancel(); signal.invalidate(); XCTAssertEqual(calls, 1)
        token = signal.observe { calls += 1 }
        weak var released = token; token = nil
        XCTAssertNil(released)
        signal.invalidate(); XCTAssertEqual(calls, 1)
    }
    func testSubscriptionAddedDuringDeliveryStartsAtNextEvent() {
        let signal = OfficialReadInvalidationSignal()
        var nested: OfficialReadInvalidationSubscription?, nextCalls = 0
        let first = signal.observe { if nested == nil { nested = signal.observe { nextCalls += 1 } } }
        signal.invalidate(); XCTAssertEqual(nextCalls, 0)
        signal.invalidate(); XCTAssertEqual(nextCalls, 1)
        withExtendedLifetime((first, nested)) {}
    }
    func testCancelledOwnerDoesNotReenterWhenCallbackInvalidatesAgain() {
        let signal = OfficialReadInvalidationSignal()
        var token: OfficialReadInvalidationSubscription?, calls = 0
        token = signal.observe { calls += 1; token?.cancel(); signal.invalidate() }
        signal.invalidate(); XCTAssertEqual(calls, 1)
    }
    func testSelectionIsNotRetainedByAnUnrevokedSourceSubscription() throws {
        let source = try self.source()
        var selection: OfficialPublicEventReadSelection? = .init()
        selection?.select(source); weak var released = selection
        selection = nil; XCTAssertNil(released)
        source.revoke(); XCTAssertTrue(source.isRevoked)
    }
    func testReaderSignalIsOptionalAndDoesNotChangeAuthenticationByItself() {
        let old = OfficialSessionReader(service: nil, currentContext: { .init(guestEpoch: 1) })
        XCTAssertNil(old.invalidationSignal)
        let signal = OfficialReadInvalidationSignal()
        let reader = OfficialSessionReader(service: nil, currentContext: { .init(guestEpoch: 1) }, invalidationSignal: signal)
        XCTAssertTrue(reader.invalidationSignal === signal)
        signal.invalidate(); XCTAssertFalse(reader.isAuthenticated); XCTAssertFalse(reader.isConfigured)
    }
    func testRoamSnapshotAndNavigationRetireImmediatelyWithoutNewReads() async throws {
        let official = InvalidationOfficialReader(), roam = try InvalidationRoamReader()
        let model = RoamOfficialTasksModel(roam: roam, official: official)
        model.appear(); await model.load()
        let snapshot = try XCTUnwrap(model.snapshot)
        let query = OfficialEventBrowseQuery(bucket: .live, keyword: "")
        let target = try XCTUnwrap(model.select(eventID: 71, query: query, renderedSnapshotID: snapshot.id))
        var invalidations = 0; model.onChange = { invalidations += 1 }
        official.invalidateSource()
        XCTAssertNil(model.snapshot); XCTAssertFalse(model.mayRemainOpen(target)); XCTAssertFalse(model.isLoading)
        XCTAssertTrue(model.error is OfficialReadInvalidationFailure)
        XCTAssertEqual(invalidations, 1); XCTAssertEqual(official.calls, ["all", "mine"])
        await model.load()
        let recovered = try XCTUnwrap(model.snapshot)
        XCTAssertNotNil(model.select(eventID: 71, query: query, renderedSnapshotID: recovered.id))
        XCTAssertFalse(model.mayRemainOpen(target))
    }
    func testRoamRevocationDuringFirstReadStopsSecondReadAndLateSnapshot() async throws {
        let official = InvalidationOfficialReader(), roam = try InvalidationRoamReader()
        let model = RoamOfficialTasksModel(roam: roam, official: official)
        official.afterAll = { [weak official] in official?.invalidateSource() }
        await model.load()
        XCTAssertEqual(official.calls, ["all"]); XCTAssertNil(model.snapshot); XCTAssertFalse(model.isLoading)
        XCTAssertTrue(model.error is OfficialReadInvalidationFailure)
    }
    func testRoamModelIsNotRetainedByItsSourceObservation() throws {
        let official = InvalidationOfficialReader(), roam = try InvalidationRoamReader()
        var model: RoamOfficialTasksModel? = .init(roam: roam, official: official)
        weak var released = model; model = nil
        XCTAssertNil(released); official.invalidateSource()
    }
}
