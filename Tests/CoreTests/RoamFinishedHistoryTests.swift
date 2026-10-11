import XCTest
@testable import QuestifyCore

@MainActor final class RoamFinishedHistoryTests: XCTestCase {
    private final class Storage: RoamHistoryDataStoring {
        var data: [String: Data] = [:]
        var reads = 0, writes = 0
        var failHistory = false, failClear = false
        var onRead: (() -> Void)?
        func read(key: String) throws -> Data? { reads += 1; onRead?(); return data[key] }
        func write(_ value: Data, key: String) throws {
            writes += 1
            if failHistory && key.hasPrefix("roam-history-v1-") { throw APIError.invalidRequest }
            if failClear && key.hasPrefix("roam-live-v1-"),
               let object = try JSONSerialization.jsonObject(with: value) as? [String: Any], object["record"] == nil { throw APIError.invalidRequest }
            data[key] = value
        }
    }
    private final class Location: RoamDeviceLocationProviding {
        var calls = 0
        let date: Date
        init(date: Date) { self.date = date }
        func currentFix() async throws -> RoamDeviceFix {
            calls += 1
            return try .init(coordinate: RoamCoordinate(latitude: 1, longitude: 1)!, accuracyMeters: 10, measuredAt: date, datum: .gcj02)
        }
        func stop() {}
    }
    private final class Service: RoamLiveServing {
        var identity: RoamExperienceIdentity?
        var isAvailable = true, presenceAvailable = false
        var calls = 0, finishes = 0
        var finished = false, incomplete = false, failFinish = false
        init(identity: RoamExperienceIdentity) { self.identity = identity }
        private func decode<T: Decodable>(_ type: T.Type, _ text: String) throws -> T { try JSONDecoder().decode(type, from: Data(text.utf8)) }
        func reveal(sessionID: Int?, clientSessionKey: String, tiles: [String]) async throws -> RoamLiveRevealReceipt {
            calls += 1; return try decode(RoamLiveRevealReceipt.self, #"{"sessionId":12,"newlyRevealed":0}"#)
        }
        func fact(key: String) async throws -> RoamSessionFact {
            calls += 1
            let fields: [String: Any] = ["state": finished ? "FINISHED" : "ACTIVE", "sessionId": 12, "clientSessionKey": key,
                "resultComplete": !incomplete, "result": ["tileXp": 1, "poiXp": 0, "totalXp": 1, "newTiles": 1, "newPois": 0, "tilesEver": 1, "sessionShops": 0]]
            return try JSONDecoder().decode(RoamSessionFact.self, from: JSONSerialization.data(withJSONObject: fields))
        }
        func places(fix: RoamDeviceFix) async throws -> [RoamPlace] { calls += 1; return [] }
        func registeredShops(fix: RoamDeviceFix) async throws -> [RoamRouteNode] { calls += 1; return [] }
        func discover(sessionID: Int, poiID: Int, fix: RoamDeviceFix) async throws -> RoamLiveDiscoveryReceipt { calls += 1; throw APIError.invalidRequest }
        func shopVisit(sessionID: Int, sourceType: Int, sourceID: Int, fix: RoamDeviceFix) async throws -> RoamLiveShopReceipt { calls += 1; throw APIError.invalidRequest }
        func presence(sessionID: Int, fix: RoamDeviceFix, explorationPercent: Int) async throws { calls += 1 }
        func finish(sessionID: Int, poiIDs: [Int], distanceMeters: Int) async throws {
            calls += 1; finishes += 1; if failFinish { throw APIError.httpStatus(503) }; finished = true
        }
    }
    private final class ScopeBox { var scope: RoamHistoryScope?; init(_ scope: RoamHistoryScope) { self.scope = scope } }
    private struct Fixture {
        let owner: RoamLiveSessionController
        let reader: RoamFinishedHistoryReader
        let service: Service
        let location: Location
        let storage: Storage
        let scope: RoamHistoryScope
        let box: ScopeBox
    }
    private func scope(account: Int = 7, namespace: String = "finished-tests", market: String = "cn", realm: String = "https://example.com/") throws -> RoamHistoryScope {
        try .init(market: market, deployment: URL(string: realm)!, accountID: account, namespace: namespace)
    }
    private func fixture(namespace: String = "finished-tests", withHistory: Bool = true) throws -> Fixture {
        let scope = try scope(namespace: namespace), box = ScopeBox(scope)
        let service = Service(identity: .init(scope: scope, epoch: 1)), storage = Storage()
        let date = Date(timeIntervalSince1970: 1700000000), location = Location(date: date)
        let history = withHistory ? RoamHistoryStore(storage: storage, currentScope: { box.scope }) : nil
        let owner = RoamLiveSessionController(service: service, location: location, journal: RoamLiveJournal(storage: storage), history: history,
                                              now: { date }, key: { String(repeating: "a", count: 32) })
        let reader = owner.makeFinishedHistoryReader(offlineExample: true)
        return .init(owner: owner, reader: reader, service: service, location: location, storage: storage, scope: scope, box: box)
    }
    private func finish(_ fixture: Fixture) async {
        fixture.owner.prepare(); await fixture.owner.start(purposeAccepted: true); await fixture.owner.finish()
    }
    func testConstructingReaderDoesNoWorkAndCannotReadUnfinishedHistory() throws {
        let f = try fixture()
        XCTAssertNil(f.reader.identity); XCTAssertNil(f.owner.completedHistory); XCTAssertThrowsError(try f.reader.history())
        XCTAssertEqual(f.storage.reads, 0); XCTAssertEqual(f.storage.writes, 0); XCTAssertEqual(f.location.calls, 0); XCTAssertEqual(f.service.calls, 0)
    }
    func testReadyActiveAndPausedCannotExposeCompletion() async throws {
        let f = try fixture(); f.owner.prepare(); XCTAssertNil(f.reader.identity)
        await f.owner.start(purposeAccepted: true); XCTAssertEqual(f.owner.phase, .active); XCTAssertNil(f.owner.completedHistory)
        f.owner.pause(); XCTAssertNil(f.reader.identity); XCTAssertThrowsError(try f.reader.history())
    }
    func testSuccessfulArchiveProvidesExactRecordWithoutNetworkLocationOrWrites() async throws {
        let f = try fixture(); await finish(f)
        XCTAssertEqual(f.owner.phase, .finished)
        XCTAssertEqual(f.owner.completedHistory?.timestamp, 1700000000000); XCTAssertEqual(f.owner.completedHistory?.serverSessionID, 12)
        let calls = f.service.calls, fixes = f.location.calls, writes = f.storage.writes
        let rows = try f.reader.history()
        XCTAssertEqual(rows.count, 1); XCTAssertEqual(rows.first?.ts, f.owner.completedHistory?.timestamp); XCTAssertEqual(rows.first?.serverSessionID, 12)
        XCTAssertEqual(f.service.calls, calls); XCTAssertEqual(f.location.calls, fixes); XCTAssertEqual(f.storage.writes, writes)
    }
    func testAllHistoryRetainsOlderOwnedRecordsAlongsideTheFinishedWalk() async throws {
        let f = try fixture()
        let older = try JSONDecoder().decode(RoamHistoryRecord.self, from: Data(#"{"ts":1690000000000,"serverSessionID":99,"shops":0}"#.utf8))
        let fact = try JSONDecoder().decode(RoamSessionFact.self, from: Data(#"{"state":"FINISHED","sessionId":99,"resultComplete":true,"result":{"tileXp":0,"poiXp":0,"totalXp":0,"newTiles":0,"newPois":0,"tilesEver":0,"sessionShops":0}}"#.utf8))
        try RoamHistoryStore(storage: f.storage, currentScope: { f.scope }).prependSettled(older, fact: fact)
        await finish(f)
        XCTAssertEqual(try f.reader.history().map(\.serverSessionID), [12, 99])
        XCTAssertEqual(f.owner.completedHistory?.serverSessionID, 12)
    }
    func testHistoryWriteFailureDoesNotPublishAReference() async throws {
        let f = try fixture(); f.storage.failHistory = true; await finish(f)
        XCTAssertNotEqual(f.owner.phase, .finished); XCTAssertTrue(f.owner.settlement?.hasCompleteSettlement == true)
        XCTAssertNil(f.owner.completedHistory); XCTAssertNil(f.reader.identity)
    }
    func testJournalClearFailureDoesNotPublishPrematureCompletion() async throws {
        let f = try fixture(); f.storage.failClear = true; await finish(f)
        XCTAssertNotNil(f.storage.data[f.scope.storageKey]); XCTAssertNotEqual(f.owner.phase, .finished)
        XCTAssertNil(f.owner.completedHistory); XCTAssertThrowsError(try f.reader.history())
    }
    func testIncompleteSettlementDoesNotPublishAReference() async throws {
        let f = try fixture(); f.service.incomplete = true; await finish(f)
        XCTAssertNil(f.owner.completedHistory); XCTAssertNil(f.reader.identity); XCTAssertNotEqual(f.owner.phase, .finished)
    }
    func testUnknownFinishDoesNotExposeSavedHistory() async throws {
        let f = try fixture(); f.service.failFinish = true; await finish(f)
        XCTAssertEqual(f.owner.phase, .recoveryRequired); XCTAssertNil(f.owner.completedHistory); XCTAssertNil(f.reader.identity)
    }
    func testReadOnlyRecoveryOfFinishedSessionAlsoPublishesArchivedReference() async throws {
        let f = try fixture(); f.owner.prepare(); await f.owner.start(purposeAccepted: true); f.owner.pause()
        f.service.finished = true; await f.owner.recover()
        XCTAssertEqual(f.owner.phase, .finished); XCTAssertEqual(f.service.finishes, 0)
        XCTAssertEqual(try f.reader.history().first?.serverSessionID, 12)
    }
    func testPauseAndReturningToFinishedViewPreserveReadbackWithoutStartingAgain() async throws {
        let f = try fixture(); await finish(f); let reference = f.owner.completedHistory
        let calls = f.service.calls, fixes = f.location.calls
        f.owner.pause(); f.owner.prepare(); XCTAssertEqual(f.owner.completedHistory, reference)
        XCTAssertEqual(try f.reader.history().count, 1); XCTAssertEqual(f.service.calls, calls); XCTAssertEqual(f.location.calls, fixes)
    }
    func testInvalidateRetiresExistingReaderAndCompletion() async throws {
        let f = try fixture(); await finish(f); let reads = f.storage.reads
        f.owner.invalidate(); XCTAssertNil(f.owner.completedHistory); XCTAssertNil(f.reader.identity)
        XCTAssertThrowsError(try f.reader.history()); XCTAssertEqual(f.storage.reads, reads)
    }
    func testReaderCannotOutliveItsOwningControllerAuthority() async throws {
        var f: Fixture? = try fixture(); await finish(f!)
        let reader = f!.reader
        weak var controller = f!.owner
        f = nil
        XCTAssertNil(controller); XCTAssertNil(reader.identity); XCTAssertThrowsError(try reader.history())
    }
    func testAccountEpochMarketNamespaceAndRealmChangesBlockBeforeStorageRead() async throws {
        let f = try fixture(); await finish(f); let reads = f.storage.reads
        let identities = [RoamExperienceIdentity(scope: try scope(account: 8), epoch: 1), .init(scope: f.scope, epoch: 2),
                          .init(scope: try scope(market: "us"), epoch: 1), .init(scope: try scope(namespace: "other"), epoch: 1),
                          .init(scope: try scope(realm: "https://other.example.com/"), epoch: 1)]
        for identity in identities { f.service.identity = identity; XCTAssertThrowsError(try f.reader.history()) }
        f.service.identity = nil; XCTAssertThrowsError(try f.reader.history()); XCTAssertEqual(f.storage.reads, reads)
    }
    func testCanonicallyEquivalentNamespaceDoesNotShareCompletionReader() async throws {
        let f = try fixture(namespace: "e\u{301}"); await finish(f); let reads = f.storage.reads
        f.service.identity = .init(scope: try scope(namespace: "\u{e9}"), epoch: 1)
        XCTAssertThrowsError(try f.reader.history()); XCTAssertEqual(f.storage.reads, reads)
    }
    func testStoreScopeMismatchNeverReadsAnotherAccount() async throws {
        let f = try fixture(); await finish(f); let reads = f.storage.reads
        f.box.scope = try scope(account: 8)
        XCTAssertThrowsError(try f.reader.history()); XCTAssertEqual(f.storage.reads, reads)
    }
    func testIdentityChangedDuringStorageReadIsRejected() async throws {
        let f = try fixture(); await finish(f)
        f.storage.onRead = { f.service.identity = nil }
        XCTAssertThrowsError(try f.reader.history()) { XCTAssertTrue($0 is CancellationError) }
    }
    func testDeletedHistoryStaysMissingWithoutRecreatingIt() async throws {
        let f = try fixture(); await finish(f); f.storage.data[f.scope.storageKey] = nil
        let writes = f.storage.writes
        XCTAssertTrue(try f.reader.history().isEmpty); XCTAssertEqual(f.storage.writes, writes)
    }
    func testCorruptOrReplacedTimestampIsErrorNotAnotherSession() async throws {
        let f = try fixture(); await finish(f)
        let data = try XCTUnwrap(f.storage.data[f.scope.storageKey])
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var rows = try XCTUnwrap(envelope["records"] as? [[String: Any]])
        rows[0]["serverSessionID"] = 13; envelope["records"] = rows
        f.storage.data[f.scope.storageKey] = try JSONSerialization.data(withJSONObject: envelope)
        XCTAssertThrowsError(try f.reader.history())
        f.storage.data[f.scope.storageKey] = Data("corrupt".utf8); XCTAssertThrowsError(try f.reader.history())
    }
    func testDisabledServiceOrAbsentHistoryCannotProvideCompletion() async throws {
        let f = try fixture(); await finish(f); f.service.isAvailable = false
        XCTAssertNil(f.reader.identity); XCTAssertThrowsError(try f.reader.history())
        let missing = try fixture(withHistory: false); await finish(missing)
        XCTAssertFalse(missing.reader.isConfigured); XCTAssertNil(missing.owner.completedHistory)
    }
    func testLocalReaderRejectsAllRemoteContractsAndPreservesOfflineNotice() async throws {
        let f = try fixture(); await finish(f); let calls = f.service.calls
        XCTAssertTrue(f.reader.isOfflineExample); XCTAssertFalse(f.owner.makeFinishedHistoryReader().isOfflineExample)
        do { _ = try await f.reader.album(page: 1, pageSize: 20); XCTFail() } catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        do { _ = try await f.reader.tilePage(afterID: 0, limit: 20); XCTFail() } catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        do { _ = try await f.reader.sessionFact(.sessionID(12)); XCTFail() } catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        do { _ = try await f.reader.shopBadge(); XCTFail() } catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        XCTAssertEqual(f.service.calls, calls)
    }
}
