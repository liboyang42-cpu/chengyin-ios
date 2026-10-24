import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor private final class LiveStorage: RoamHistoryDataStoring {
    var bytes: [String: Data] = [:]
    var failWrites = false
    func read(key: String) throws -> Data? { bytes[key] }
    func write(_ data: Data, key: String) throws { if failWrites { throw APIError.invalidRequest }; bytes[key] = data }
}
@MainActor private final class LiveLocation: RoamDeviceLocationProviding {
    var calls = 0, stops = 0
    var value: RoamDeviceFix
    var callback: (() -> Void)?
    init(_ date: Date) { value = try! RoamDeviceFix(coordinate: RoamCoordinate(latitude: 31.2, longitude: 121.4)!, accuracyMeters: 10, measuredAt: date, datum: .gcj02) }
    func currentFix() async throws -> RoamDeviceFix { calls += 1; callback?(); return value }
    func stop() { stops += 1 }
}
@MainActor private final class LiveService: RoamLiveServing {
    var identity: RoamExperienceIdentity?
    var isAvailable = true, presenceAvailable = true
    var reveals = 0, finishes = 0, discoveries = 0, visits = 0, heartbeats = 0, reads = 0
    var failReveal = false, failFinish = false, failDiscover = false, omitShopReceipt = false
    var onReveal: (() -> Void)?
    var factState = "ACTIVE"
    var returnedKey = String(repeating: "a", count: 32)
    var placesReads = 0, registeredReads = 0
    var failPlacesRead = false, failRegisteredRead = false
    var onPlacesRead: (() -> Void)?
    var lastPlacesReadFix: RoamDeviceFix?
    var lastRegisteredReadFix: RoamDeviceFix?
    var rows: [RoamPlace] = []
    var shops: [RoamRouteNode] = []
    var lastShopType: Int?
    var lastShopID: Int?
    var lastTiles: [String] = []
    init(_ identity: RoamExperienceIdentity) { self.identity = identity }
    func decode<T: Decodable>(_ type: T.Type, _ value: String) throws -> T { try JSONDecoder().decode(type, from: Data(value.utf8)) }
    func reveal(sessionID: Int?, clientSessionKey: String, tiles: [String]) async throws -> RoamLiveRevealReceipt {
        reveals += 1; lastTiles = tiles; onReveal?(); if failReveal { throw APIError.httpStatus(503) }
        return try decode(RoamLiveRevealReceipt.self, #"{"sessionId":"12","newlyRevealed":0}"#)
    }
    func fact(key: String) async throws -> RoamSessionFact {
        reads += 1
        let result = factState == "FINISHED" ? #", "resultComplete":true,"result":{"tileXp":1,"poiXp":0,"totalXp":1,"newTiles":1,"newPois":0,"tilesEver":1,"sessionShops":0}"# : ""
        return try decode(RoamSessionFact.self, "{\"state\":\"\(factState)\",\"sessionId\":12,\"clientSessionKey\":\"\(returnedKey)\"\(result)}")
    }
    func places(fix: RoamDeviceFix) async throws -> [RoamPlace] {
        placesReads += 1; lastPlacesReadFix = fix; onPlacesRead?()
        if failPlacesRead { throw APIError.httpStatus(503) }; return rows
    }
    func registeredShops(fix: RoamDeviceFix) async throws -> [RoamRouteNode] {
        registeredReads += 1; lastRegisteredReadFix = fix
        if failRegisteredRead { throw APIError.httpStatus(503) }; return shops
    }
    func discover(sessionID: Int, poiID: Int, fix: RoamDeviceFix) async throws -> RoamLiveDiscoveryReceipt {
        discoveries += 1; if failDiscover { throw APIError.httpStatus(503) }
        return try decode(RoamLiveDiscoveryReceipt.self, "{\"discovered\":false,\"poiId\":\(poiID)}")
    }
    func shopVisit(sessionID: Int, sourceType: Int, sourceID: Int, fix: RoamDeviceFix) async throws -> RoamLiveShopReceipt {
        visits += 1; lastShopType = sourceType; lastShopID = sourceID; return try decode(RoamLiveShopReceipt.self, "{\"recorded\":\(!omitShopReceipt)}")
    }
    func presence(sessionID: Int, fix: RoamDeviceFix, explorationPercent: Int) async throws { heartbeats += 1 }
    func finish(sessionID: Int, poiIDs: [Int], distanceMeters: Int) async throws {
        finishes += 1; if failFinish { throw APIError.httpStatus(503) }; factState = "FINISHED"
    }
}
@MainActor final class RoamLiveSessionTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_790_932_200)
    private let key = String(repeating: "a", count: 32)
    private func fixture() throws -> (RoamLiveSessionController, LiveService, LiveLocation, LiveStorage, RoamHistoryScope) {
        let scope = try RoamHistoryScope(market: "cn", deployment: URL(string: "https://example.com/api/")!, accountID: 7)
        let service = LiveService(RoamExperienceIdentity(scope: scope, epoch: 1)), location = LiveLocation(date), storage = LiveStorage()
        let history = RoamHistoryStore(storage: storage, currentScope: { scope })
        let owner = RoamLiveSessionController(service: service, location: location, journal: RoamLiveJournal(storage: storage), history: history, now: { self.date }, key: { self.key })
        owner.prepare(); return (owner, service, location, storage, scope)
    }
    func testPreparationAndDeclinedPurposeDoNotReadLocationOrDispatch() async throws {
        let (owner, service, location, storage, _) = try fixture()
        XCTAssertEqual(owner.phase, .ready); XCTAssertTrue(storage.bytes.isEmpty)
        await owner.start(purposeAccepted: false)
        XCTAssertEqual(location.calls, 0); XCTAssertEqual(service.reveals, 0)
    }
    func testStartUsesDurableKeyBeforeRevealAndDoesNotInventRewards() async throws {
        let (owner, service, location, storage, scope) = try fixture()
        service.onReveal = { XCTAssertEqual(try? RoamLiveJournal(storage: storage).read(scope: scope)?.pendingWrite, .reveal) }
        await owner.start(purposeAccepted: true)
        XCTAssertEqual(owner.phase, .active); XCTAssertEqual(location.calls, 1); XCTAssertEqual(service.reveals, 1)
        XCTAssertEqual(owner.record?.sessionID, 12); XCTAssertEqual(owner.record?.distanceMeters, 0)
        XCTAssertNil(owner.settlement); XCTAssertEqual(service.heartbeats, 0)
        let bytes = String(data: storage.bytes.values.first!, encoding: .utf8)!
        XCTAssertFalse(bytes.contains("31.2")); XCTAssertFalse(bytes.contains("121.4")); XCTAssertFalse(bytes.contains("token")); XCTAssertFalse(bytes.contains("track"))
    }
    func testUnreadableOrUnwritableJournalStopsBeforeMutation() async throws {
        let (owner, service, _, storage, _) = try fixture(); storage.failWrites = true
        await owner.start(purposeAccepted: true)
        XCTAssertEqual(service.reveals, 0); XCTAssertNil(owner.record)
    }
    func testRevealUnknownSurvivesRelaunchAndCannotBlindStartAgain() async throws {
        let (owner, service, location, storage, scope) = try fixture(); service.failReveal = true
        await owner.start(purposeAccepted: true); XCTAssertEqual(owner.phase, .recoveryRequired)
        await owner.start(purposeAccepted: true); XCTAssertEqual(service.reveals, 1)
        let restored = RoamLiveSessionController(service: service, location: location, journal: RoamLiveJournal(storage: storage), now: { self.date })
        restored.prepare(); XCTAssertEqual(restored.record?.clientSessionKey, key); XCTAssertEqual(restored.phase, .recoveryRequired)
        await restored.recover(); XCTAssertEqual(service.reads, 1); XCTAssertEqual(service.reveals, 1)
        XCTAssertEqual(restored.phase, .paused); XCTAssertNil(try RoamLiveJournal(storage: storage).read(scope: scope)?.pendingWrite)
    }
    func testCanceledBootstrapKeepsPendingWriteAndDiscardsLateReceipt() async throws {
        let (owner, service, _, storage, scope) = try fixture(); service.onReveal = { owner.pause() }
        await owner.start(purposeAccepted: true)
        XCTAssertEqual(owner.phase, .recoveryRequired); XCTAssertNil(owner.record?.sessionID)
        XCTAssertEqual(try RoamLiveJournal(storage: storage).read(scope: scope)?.pendingWrite, .reveal)
    }
    func testForegroundPauseClearsPreciseFixAndRequiresExplicitResume() async throws {
        let (owner, service, location, _, _) = try fixture()
        await owner.start(purposeAccepted: true, presenceAccepted: true); owner.setForeground(false); await owner.pulse()
        XCTAssertEqual(owner.phase, .paused); XCTAssertNil(owner.lastFix); XCTAssertFalse(owner.presenceEnabled)
        XCTAssertEqual(location.calls, 1); XCTAssertEqual(service.heartbeats, 0)
        owner.setForeground(true); XCTAssertEqual(owner.phase, .paused)
    }
    func testPoorStaleAndFutureLocationCannotCreateSession() async throws {
        for (accuracy, delta) in [(81.0, 0.0), (10, -31), (10, 3)] {
            let (owner, service, location, _, _) = try fixture()
            location.value = try RoamDeviceFix(coordinate: location.value.coordinate, accuracyMeters: accuracy, measuredAt: date.addingTimeInterval(delta), datum: .gcj02)
            await owner.start(purposeAccepted: true); XCTAssertEqual(service.reveals, 0); XCTAssertEqual(owner.phase, .locationDenied)
        }
    }
    func testGPSJumpAddsNeitherDistanceNorTile() async throws {
        let (owner, service, location, _, _) = try fixture(); await owner.start(purposeAccepted: true)
        location.value = try RoamDeviceFix(coordinate: RoamCoordinate(latitude: 31.3, longitude: 121.5)!, accuracyMeters: 10, measuredAt: date.addingTimeInterval(1), datum: .gcj02)
        await owner.pulse(); XCTAssertEqual(owner.record?.distanceMeters, 0); XCTAssertEqual(service.reveals, 1)
        XCTAssertNil(owner.lastFix)
    }
    func testResumeDoesNotCountGapAcrossPause() async throws {
        let (owner, _, location, _, _) = try fixture(); await owner.start(purposeAccepted: true); owner.pause()
        location.value = try RoamDeviceFix(coordinate: RoamCoordinate(latitude: 31.3, longitude: 121.5)!, accuracyMeters: 10, measuredAt: date.addingTimeInterval(1), datum: .gcj02)
        await owner.resume(purposeAccepted: true); XCTAssertEqual(owner.record?.distanceMeters, 0)
    }
    func testIdentityChangeWhileAcquiringDiscardsFixBeforeAnyWrite() async throws {
        let (owner, service, location, _, _) = try fixture(); location.callback = { service.identity = nil }
        await owner.start(purposeAccepted: true); XCTAssertEqual(service.reveals, 0); XCTAssertNil(owner.record)
    }
    func testDiscoveryRequiresExplicitGestureFreshFixAndMatchingSource() async throws {
        let (owner, service, _, _, _) = try fixture()
        let place = try service.decode(RoamPlace.self, #"{"id":6,"type":1,"lat":31.2,"lng":121.4,"name":"Park"}"#)
        service.rows = [place]; await owner.start(purposeAccepted: true); XCTAssertEqual(service.discoveries, 0)
        await owner.discover(place); XCTAssertEqual(service.discoveries, 1); XCTAssertTrue(owner.actionConfirmed(place, shop: false)); XCTAssertNil(owner.settlement)
        await owner.discover(place); XCTAssertEqual(service.discoveries, 1)
    }
    func testUnknownDiscoveryLocksTargetAcrossRecovery() async throws {
        let (owner, service, _, _, _) = try fixture()
        let place = try service.decode(RoamPlace.self, #"{"id":6,"type":1,"lat":31.2,"lng":121.4}"#)
        service.rows = [place]; service.failDiscover = true; await owner.start(purposeAccepted: true)
        await owner.discover(place); await owner.discover(place)
        XCTAssertEqual(service.discoveries, 1); XCTAssertTrue(owner.actionUnresolved(place, shop: false))
        owner.pause(); await owner.recover(); XCTAssertTrue(owner.actionUnresolved(place, shop: false))
    }
    func testShopRequiresRecordedTrueAndNoNodeIDSubstitution() async throws {
        let (owner, service, _, _, _) = try fixture()
        let place = try service.decode(RoamPlace.self, #"{"id":6,"type":2,"lat":31.2,"lng":121.4}"#)
        service.rows = [place]; service.omitShopReceipt = true; await owner.start(purposeAccepted: true)
        await owner.visitShop(place); XCTAssertEqual(service.visits, 1); XCTAssertFalse(owner.actionConfirmed(place, shop: true)); XCTAssertTrue(owner.actionUnresolved(place, shop: true))
    }
    func testRegistrationShopUsesRegistrationRowIDNotNodeOrTopic() async throws {
        let (owner, service, _, _, _) = try fixture()
        let shop = try service.decode(RoamRouteNode.self, #"{"id":61,"nodeId":999,"topicId":777,"latitude":31.2,"longitude":121.4,"addressName":"Shop"}"#)
        service.shops = [shop]; await owner.start(purposeAccepted: true); await owner.visitRegisteredShop(shop)
        XCTAssertEqual(service.lastShopType, 2); XCTAssertEqual(service.lastShopID, 61); XCTAssertTrue(owner.registeredShopConfirmed(shop))
    }
    func testFinishUsesReadbackAndArchivesOnlyCompleteMatchingFact() async throws {
        let (owner, service, _, storage, scope) = try fixture(); await owner.start(purposeAccepted: true)
        await owner.finish(); XCTAssertEqual(service.finishes, 1); XCTAssertEqual(service.reads, 1); XCTAssertEqual(owner.phase, .finished)
        XCTAssertEqual(owner.settlement?.result?.totalXp, 1); XCTAssertNil(try RoamLiveJournal(storage: storage).read(scope: scope))
        XCTAssertEqual(try RoamHistoryStore(storage: storage, currentScope: { scope }).readAll().first?.serverSessionID, 12)
    }
    func testFinishUnknownAndWrongOwnerReadbackNeverAwardOrRetry() async throws {
        let (owner, service, _, _, _) = try fixture(); await owner.start(purposeAccepted: true); service.failFinish = true
        await owner.finish(); await owner.finish(); XCTAssertEqual(service.finishes, 1); XCTAssertNil(owner.settlement)
        service.factState = "FINISHED"; service.returnedKey = String(repeating: "b", count: 32)
        await owner.recover(); XCTAssertNil(owner.settlement); XCTAssertEqual(owner.phase, .recoveryRequired)
        service.returnedKey = key; await owner.recover(); XCTAssertEqual(owner.phase, .finished); XCTAssertEqual(service.finishes, 1)
    }
    func testFinishedFactWithPendingRevealRemainsUnreconciled() async throws {
        let (owner, service, _, _, _) = try fixture(); service.failReveal = true; await owner.start(purposeAccepted: true)
        service.factState = "FINISHED"; await owner.recover()
        XCTAssertNotEqual(owner.phase, .finished); XCTAssertNil(owner.settlement); XCTAssertFalse(owner.record!.pendingTiles.isEmpty)
    }
    func testDormantControllerDoesNotInvokeProvider() async throws {
        let location = LiveLocation(date)
        let owner = RoamLiveSessionController(location: location, journal: RoamLiveJournal(storage: LiveStorage()))
        owner.prepare(); await owner.start(purposeAccepted: true); XCTAssertEqual(owner.phase, .unavailable); XCTAssertEqual(location.calls, 0)
    }
}

private final class LiveTransport: HTTPTransport {
    var requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return (Data(#"{"code":200,"data":{"sessionId":"12","newlyRevealed":1}}"#.utf8), 200) }
}
@MainActor final class RoamLiveServiceTests: XCTestCase {
    func testDisabledOrMismatchedGrantNeverDispatches() async throws {
        let url = URL(string: "https://example.com/api/")!, transport = LiveTransport(), api = try APIConfiguration(baseURL: url)
        let session = try RoamExperienceSession(scope: RoamHistoryScope(market: "cn", deployment: url, accountID: 7), epoch: 1, token: "test-token")
        for approval in [nil, RoamLiveApproval(endpoints: try OperationEndpointApproval(baseURL: url, namespace: "standalone", accountID: 8, paths: RoamLiveApproval.requiredPaths), foregroundLocation: true)] {
            let service = RoamLiveService(api: api, approval: approval, transport: transport, currentSession: { session })
            do { _ = try await service.reveal(sessionID: nil, clientSessionKey: String(repeating: "a", count: 32), tiles: ["wtw3sjq"]); XCTFail("Must be denied") } catch {}
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testApprovedBootstrapBuildsKeyedSourceRequestAndTokenRotationInvalidates() async throws {
        let url = URL(string: "https://example.com/api/")!, transport = LiveTransport(), api = try APIConfiguration(baseURL: url)
        let scope = try RoamHistoryScope(market: "cn", deployment: url, accountID: 7)
        var session: RoamExperienceSession? = try RoamExperienceSession(scope: scope, epoch: 1, token: "test-token")
        let approval = RoamLiveApproval(endpoints: try OperationEndpointApproval(baseURL: url, namespace: scope.namespace, accountID: 7, paths: RoamLiveApproval.requiredPaths), foregroundLocation: true)
        let service = RoamLiveService(api: api, approval: approval, transport: transport, currentSession: { session })
        let clientKey = String(repeating: "a", count: 32)
        let receipt = try await service.reveal(sessionID: nil, clientSessionKey: clientKey, tiles: ["wtw3sjq"])
        XCTAssertEqual(receipt.sessionId, 12)
        let request = try XCTUnwrap(transport.requests.first)
        let body = try XCTUnwrap(String(data: try XCTUnwrap(request.httpBody), encoding: .utf8))
        let contentType = try XCTUnwrap(request.value(forHTTPHeaderField: "Content-Type"))
        let prefix = "multipart/form-data; boundary="
        XCTAssertTrue(contentType.hasPrefix(prefix))
        let boundary = String(contentType.dropFirst(prefix.count))
        XCTAssertFalse(boundary.isEmpty)
        // The shared source-backed builder emits multipart FormData, not URL-encoded fields.
        // Compare the entire payload so missing, duplicated or substituted recovery fields fail.
        let expectedFields = ["clientSessionKey": clientKey, "sessionId": "0", "tiles": "wtw3sjq"]
        let expectedBody = expectedFields.keys.sorted().map {
            "--\(boundary)\r\nContent-Disposition: form-data; name=\"\($0)\"\r\n\r\n\(expectedFields[$0]!)\r\n"
        }.joined() + "--\(boundary)--\r\n"
        XCTAssertEqual(body, expectedBody)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url, url.appendingPathComponent("api/roam/reveal"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "test-token")
        XCTAssertFalse(service.presenceAvailable)
        session = try RoamExperienceSession(scope: scope, epoch: 1, token: "rotated-token")
        XCTAssertFalse(service.isAvailable)
        do {
            _ = try await service.reveal(sessionID: 12, clientSessionKey: clientKey, tiles: ["wtw3sjq"])
            XCTFail("The captured service must not dispatch after credential rotation")
        } catch {
            XCTAssertEqual(error as? RoamLiveFailure, .unavailable)
        }
        XCTAssertEqual(transport.requests.count, 1)
    }
}

@MainActor private final class UnstartedStorageFixture: RoamHistoryDataStoring {
    var bytes: [String: Data] = [:]
    var writes = 0
    var failWrite = false
    var corruptReadback = false
    func read(key: String) throws -> Data? { bytes[key] }
    func write(_ data: Data, key: String) throws {
        writes += 1
        if failWrite { throw RoamLiveFailure.journalUnavailable }
        bytes[key] = corruptReadback ? Data("corrupt".utf8) : data
    }
}
@MainActor private final class UnstartedFactFixture: RoamLiveServing {
    var identity: RoamExperienceIdentity?
    var isAvailable = true
    let presenceAvailable = false
    var reads = 0, commands = 0
    var factJSON = #"{"state":"NOT_FOUND"}"#
    var onFact: (() -> Void)?
    var holdFact = false
    var pendingFact: CheckedContinuation<Void, Never>?
    init(_ identity: RoamExperienceIdentity) { self.identity = identity }
    func fact(key: String) async throws -> RoamSessionFact {
        reads += 1
        if holdFact { await withCheckedContinuation { pendingFact = $0 } }
        onFact?()
        return try JSONDecoder().decode(RoamSessionFact.self, from: Data(factJSON.utf8))
    }
    func reveal(sessionID: Int?, clientSessionKey: String, tiles: [String]) async throws -> RoamLiveRevealReceipt { commands += 1; throw APIError.notConfigured }
    func places(fix: RoamDeviceFix) async throws -> [RoamPlace] { commands += 1; throw APIError.notConfigured }
    func registeredShops(fix: RoamDeviceFix) async throws -> [RoamRouteNode] { commands += 1; throw APIError.notConfigured }
    func discover(sessionID: Int, poiID: Int, fix: RoamDeviceFix) async throws -> RoamLiveDiscoveryReceipt { commands += 1; throw APIError.notConfigured }
    func shopVisit(sessionID: Int, sourceType: Int, sourceID: Int, fix: RoamDeviceFix) async throws -> RoamLiveShopReceipt { commands += 1; throw APIError.notConfigured }
    func presence(sessionID: Int, fix: RoamDeviceFix, explorationPercent: Int) async throws { commands += 1; throw APIError.notConfigured }
    func finish(sessionID: Int, poiIDs: [Int], distanceMeters: Int) async throws { commands += 1; throw APIError.notConfigured }
}
@MainActor final class RoamUnstartedContinuationTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_790_932_200)
    private func fixture(edit: (inout RoamLiveRecord) -> Void = { _ in }) throws -> (RoamLiveSessionController, UnstartedFactFixture, LiveLocation, UnstartedStorageFixture, RoamLiveJournal, RoamLiveRecord) {
        let scope = try RoamHistoryScope(market: "cn", deployment: XCTUnwrap(URL(string: "https://example.com/api/")), accountID: 7)
        let service = UnstartedFactFixture(.init(scope: scope, epoch: 1)), location = LiveLocation(date)
        let storage = UnstartedStorageFixture(), journal = RoamLiveJournal(storage: storage)
        var record = RoamLiveRecord(scope: scope, clientSessionKey: String(repeating: "a", count: 32), startedAt: date)
        record.finishRequested = true; edit(&record); try journal.write(record)
        let owner = RoamLiveSessionController(service: service, location: location, journal: journal, now: { self.date })
        owner.prepare(); return (owner, service, location, storage, journal, record)
    }
    func testCurrentNotFoundAndExplicitClickOnlyFlipFinishIntentWithoutRequestsOrLocation() async throws {
        let (owner, service, location, storage, journal, original) = try fixture()
        XCTAssertFalse(owner.canContinueUnstartedRoam); let before = storage.bytes, writes = storage.writes
        await owner.recover()
        XCTAssertTrue(owner.canContinueUnstartedRoam); XCTAssertEqual(storage.bytes, before); XCTAssertEqual(storage.writes, writes)
        XCTAssertEqual(service.reads, 1)
        owner.continueUnstartedRoam()
        var expected = original; expected.finishRequested = false
        XCTAssertEqual(try journal.read(scope: original.scope), expected); XCTAssertEqual(owner.record, expected)
        XCTAssertEqual(owner.phase, .paused); XCTAssertFalse(owner.canContinueUnstartedRoam)
        XCTAssertEqual(service.reads, 1); XCTAssertEqual(service.commands, 0); XCTAssertEqual(location.calls, 0)
        let committed = storage.bytes, committedWrites = storage.writes
        owner.continueUnstartedRoam(); XCTAssertEqual(storage.bytes, committed); XCTAssertEqual(storage.writes, committedWrites)
    }
    func testPrepareActiveOrInvalidReplyNeverAuthorizeContinuation() async throws {
        for reply in [#"{"state":"ACTIVE","sessionId":12,"clientSessionKey":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}"#,
                      #"{"state":"NOT_FOUND","sessionId":12}"#,
                      #"{"state":"NOT_FOUND","clientSessionKey":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}"#,
                      #"{"state":"UNKNOWN"}"#] {
            let (owner, service, location, storage, _, _) = try fixture()
            owner.continueUnstartedRoam(); XCTAssertFalse(owner.canContinueUnstartedRoam)
            service.factJSON = reply; await owner.recover(); XCTAssertFalse(owner.canContinueUnstartedRoam)
            let before = storage.bytes; owner.continueUnstartedRoam(); XCTAssertEqual(storage.bytes, before)
            XCTAssertEqual(service.commands, 0); XCTAssertEqual(location.calls, 0)
        }
    }
    func testSessionAndEveryPendingOrRecordedProgressKindRejectContinuation() async throws {
        let edits: [(inout RoamLiveRecord) -> Void] = [
            { $0.sessionID = 12 }, { $0.pendingWrite = .reveal }, { $0.pendingWrite = .finish },
            { $0.allTiles = ["wtw3sjq"]; $0.pendingTiles = ["wtw3sjq"] },
            { $0.unresolvedActions = ["shop:1:7"] }, { $0.allTiles = ["wtw3sjq"] },
            { $0.confirmedPOIIDs = [7] }, { $0.confirmedShops = ["shop:1:7"] }, { $0.distanceMeters = 1 }
        ]
        for edit in edits {
            let (owner, service, location, storage, _, _) = try fixture(edit: edit)
            await owner.recover(); XCTAssertFalse(owner.canContinueUnstartedRoam)
            let before = storage.bytes; owner.continueUnstartedRoam(); XCTAssertEqual(storage.bytes, before)
            XCTAssertEqual(service.commands, 0); XCTAssertEqual(location.calls, 0)
        }
    }
    func testFullJournalChangeDuringFactReadCannotBeOverwrittenOrIssueProof() async throws {
        let (owner, service, _, storage, _, _) = try fixture(); let writes = storage.writes
        service.onFact = {
            for key in Array(storage.bytes.keys) { storage.bytes[key]?.append(32) } // Valid JSON, same decoded record, different full preimage.
        }
        await owner.recover()
        XCTAssertFalse(owner.canContinueUnstartedRoam); XCTAssertEqual(storage.writes, writes)
        let changed = storage.bytes; owner.continueUnstartedRoam(); XCTAssertEqual(storage.bytes, changed)
    }
    func testFullJournalChangeAfterReadFailsCASAndCannotRetryOldProof() async throws {
        let (owner, _, _, storage, _, _) = try fixture(); await owner.recover()
        XCTAssertTrue(owner.canContinueUnstartedRoam)
        for key in Array(storage.bytes.keys) { storage.bytes[key]?.append(32) }
        let changed = storage.bytes, writes = storage.writes
        owner.continueUnstartedRoam()
        XCTAssertEqual(owner.phase, .recoveryRequired); XCTAssertFalse(owner.canContinueUnstartedRoam)
        XCTAssertEqual(storage.bytes, changed); XCTAssertEqual(storage.writes, writes)
        owner.continueUnstartedRoam(); XCTAssertEqual(storage.bytes, changed)
    }
    func testAccountEpochForegroundAndConfigurationChangesRejectOldProof() async throws {
        for change in 0..<4 {
            let (owner, service, location, storage, _, original) = try fixture(); await owner.recover()
            if change == 0 { service.identity = .init(scope: original.scope, epoch: 2) }
            if change == 1 {
                let scope = try RoamHistoryScope(market: "cn", deployment: XCTUnwrap(URL(string: "https://example.com/api/")), accountID: 8)
                service.identity = .init(scope: scope, epoch: 1)
            }
            if change == 2 { owner.setForeground(false) }
            if change == 3 { service.isAvailable = false }
            XCTAssertFalse(owner.canContinueUnstartedRoam)
            let bytes = storage.bytes, writes = storage.writes; owner.continueUnstartedRoam()
            XCTAssertEqual(storage.bytes, bytes); XCTAssertEqual(storage.writes, writes)
            service.isAvailable = true
            XCTAssertFalse(owner.canContinueUnstartedRoam); XCTAssertEqual(location.calls, 0)
        }
    }
    func testStorageFailureConsumesProofAndRequiresFreshRecovery() async throws {
        for corruptReadback in [false, true] {
            let (owner, service, location, storage, _, _) = try fixture(); await owner.recover()
            storage.failWrite = !corruptReadback; storage.corruptReadback = corruptReadback
            owner.continueUnstartedRoam(); XCTAssertFalse(owner.canContinueUnstartedRoam)
            XCTAssertEqual(owner.phase, .recoveryRequired); XCTAssertEqual(owner.record?.finishRequested, true)
            let writes = storage.writes, bytes = storage.bytes
            owner.continueUnstartedRoam(); XCTAssertEqual(storage.writes, writes); XCTAssertEqual(storage.bytes, bytes)
            XCTAssertEqual(service.commands, 0); XCTAssertEqual(location.calls, 0)
        }
    }
    func testLateNotFoundAfterLeavingCannotReviveProofOrWrite() async throws {
        let (owner, service, location, storage, _, _) = try fixture(); service.holdFact = true
        let task = Task { await owner.recover() }
        for _ in 0..<100 where service.pendingFact == nil { await Task.yield() }
        let pending = try XCTUnwrap(service.pendingFact); service.pendingFact = nil
        let bytes = storage.bytes, writes = storage.writes
        owner.pause(); pending.resume(); await task.value
        XCTAssertFalse(owner.canContinueUnstartedRoam); owner.continueUnstartedRoam()
        XCTAssertEqual(storage.bytes, bytes); XCTAssertEqual(storage.writes, writes)
        XCTAssertEqual(service.commands, 0); XCTAssertEqual(location.calls, 0)
    }
    func testNewRecoveryConsumesOldProofEvenWhenNewReadFails() async throws {
        let (owner, service, _, storage, _, _) = try fixture(); await owner.recover()
        XCTAssertTrue(owner.canContinueUnstartedRoam)
        service.factJSON = #"{"state":"UNKNOWN"}"#; await owner.recover()
        XCTAssertFalse(owner.canContinueUnstartedRoam)
        let bytes = storage.bytes; owner.continueUnstartedRoam(); XCTAssertEqual(storage.bytes, bytes)
    }
    func testLocalIntentChangePreservesUnknownEnvelopeAndRecordFields() async throws {
        let (owner, _, _, storage, _, original) = try fixture()
        for key in Array(storage.bytes.keys) {
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(storage.bytes[key])) as? [String: Any])
            json["futureEnvelope"] = "retained"
            var row = try XCTUnwrap(json["record"] as? [String: Any]); row["futureRecord"] = "retained"; json["record"] = row
            storage.bytes[key] = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        }
        await owner.recover(); XCTAssertTrue(owner.canContinueUnstartedRoam); owner.continueUnstartedRoam()
        for bytes in storage.bytes.values {
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            XCTAssertEqual(json["futureEnvelope"] as? String, "retained")
            let row = try XCTUnwrap(json["record"] as? [String: Any])
            XCTAssertEqual(row["futureRecord"] as? String, "retained"); XCTAssertEqual(row["finishRequested"] as? Bool, false)
        }
        XCTAssertEqual(owner.record?.clientSessionKey, original.clientSessionKey)
    }
}

@MainActor final class RoamLiveNearbyReadRetryTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_790_932_200)
    private func fixture(now: (() -> Date)? = nil) throws -> (RoamLiveSessionController, LiveService, LiveLocation, LiveStorage, RoamHistoryScope) {
        let scope = try RoamHistoryScope(market: "cn", deployment: XCTUnwrap(URL(string: "https://example.com/api/")), accountID: 7)
        let service = LiveService(.init(scope: scope, epoch: 1)), location = LiveLocation(date), storage = LiveStorage()
        let owner = RoamLiveSessionController(service: service, location: location, journal: .init(storage: storage),
            now: now ?? { self.date }, key: { String(repeating: "a", count: 32) })
        owner.prepare(); return (owner, service, location, storage, scope)
    }
    func testExplicitRetryUsesAcceptedFixWithoutLocationMutationOrJournalWork() async throws {
        let (owner, service, location, storage, _) = try fixture()
        service.failPlacesRead = true; service.failRegisteredRead = true
        await owner.start(purposeAccepted: true)
        XCTAssertTrue(owner.nearbyReadFailed); XCTAssertTrue(owner.canRetryNearbyRead)
        let fix = try XCTUnwrap(owner.lastFix), bytes = storage.bytes, calls = location.calls, reveals = service.reveals
        service.failPlacesRead = false; service.failRegisteredRead = false
        await owner.retryNearbyRead()
        XCTAssertFalse(owner.nearbyReadFailed); XCTAssertFalse(owner.canRetryNearbyRead)
        XCTAssertEqual(service.placesReads, 2); XCTAssertEqual(service.registeredReads, 2)
        XCTAssertEqual(service.lastPlacesReadFix, fix); XCTAssertEqual(service.lastRegisteredReadFix, fix)
        XCTAssertEqual(location.calls, calls); XCTAssertEqual(service.reveals, reveals)
        XCTAssertEqual(service.finishes, 0); XCTAssertEqual(service.visits, 0); XCTAssertEqual(service.discoveries, 0)
        XCTAssertEqual(service.heartbeats, 0); XCTAssertEqual(storage.bytes, bytes); XCTAssertEqual(owner.phase, .active)
        await owner.retryNearbyRead(); XCTAssertEqual(service.placesReads, 2)
    }
    func testPartialFailureRetainsActualRowsAndIndependentSourceFailureFlags() async throws {
        let (owner, service, _, _, _) = try fixture()
        let row = try service.decode(RoamPlace.self, #"{"id":6,"type":1,"name":"Actual POI","lat":31.2,"lng":121.4}"#)
        service.rows = [row]; service.failRegisteredRead = true; await owner.start(purposeAccepted: true)
        XCTAssertFalse(owner.placesReadFailed); XCTAssertTrue(owner.registeredShopsReadFailed); XCTAssertEqual(owner.places, [row])
        service.failPlacesRead = true; service.rows = []; await owner.retryNearbyRead()
        XCTAssertTrue(owner.placesReadFailed); XCTAssertTrue(owner.registeredShopsReadFailed)
        XCTAssertEqual(owner.places, [row])
        service.failPlacesRead = false; service.failRegisteredRead = false; await owner.retryNearbyRead()
        XCTAssertTrue(owner.places.isEmpty); XCTAssertFalse(owner.nearbyReadFailed)
    }
    func testStaleOrFutureFixDoesNotReadAndDoesNotAcquireAReplacement() async throws {
        for offset in [31.0, -3.0] {
            var now = date
            let (owner, service, location, storage, _) = try fixture(now: { now })
            service.failPlacesRead = true; await owner.start(purposeAccepted: true)
            XCTAssertTrue(owner.canRetryNearbyRead); now = date.addingTimeInterval(offset)
            let reads = service.placesReads, calls = location.calls, bytes = storage.bytes
            XCTAssertFalse(owner.canRetryNearbyRead); await owner.retryNearbyRead()
            XCTAssertEqual(service.placesReads, reads); XCTAssertEqual(location.calls, calls); XCTAssertEqual(storage.bytes, bytes)
        }
    }
    func testPauseEpochAccountAndConfigurationLossRejectRetry() async throws {
        for change in 0..<4 {
            let (owner, service, location, storage, scope) = try fixture()
            service.failPlacesRead = true; await owner.start(purposeAccepted: true)
            if change == 0 { owner.pause() }
            if change == 1 { service.identity = .init(scope: scope, epoch: 2) }
            if change == 2 {
                let other = try RoamHistoryScope(market: "cn", deployment: XCTUnwrap(URL(string: "https://example.com/api/")), accountID: 8)
                service.identity = .init(scope: other, epoch: 1)
            }
            if change == 3 { service.isAvailable = false }
            let reads = service.placesReads, calls = location.calls, bytes = storage.bytes
            XCTAssertFalse(owner.canRetryNearbyRead); await owner.retryNearbyRead()
            XCTAssertEqual(service.placesReads, reads); XCTAssertEqual(location.calls, calls); XCTAssertEqual(storage.bytes, bytes)
        }
    }
    func testLeaveDuringFirstRetryReadDropsRowsAndSkipsSecondSource() async throws {
        let (owner, service, location, storage, _) = try fixture()
        service.failPlacesRead = true; await owner.start(purposeAccepted: true)
        service.failPlacesRead = false; service.rows = [try service.decode(RoamPlace.self, #"{"id":8,"type":1,"lat":31.2,"lng":121.4}"#)]
        service.onPlacesRead = { owner.pause() }
        let reads = service.registeredReads, calls = location.calls, bytes = storage.bytes
        await owner.retryNearbyRead()
        XCTAssertTrue(owner.places.isEmpty); XCTAssertEqual(service.registeredReads, reads)
        XCTAssertFalse(owner.canRetryNearbyRead); XCTAssertEqual(owner.phase, .paused)
        XCTAssertEqual(location.calls, calls); XCTAssertEqual(storage.bytes, bytes)
    }
    func testBusyRetryAndUnconfiguredControllerCannotDispatch() async throws {
        let (owner, service, location, _, _) = try fixture(); service.failPlacesRead = true
        await owner.start(purposeAccepted: true); service.failPlacesRead = false
        service.onPlacesRead = { XCTAssertFalse(owner.canRetryNearbyRead) }
        await owner.retryNearbyRead(); XCTAssertEqual(service.placesReads, 2)
        let disabled = RoamLiveSessionController(location: location, journal: .init(storage: LiveStorage()))
        disabled.prepare(); let calls = location.calls
        XCTAssertFalse(disabled.canRetryNearbyRead); await disabled.retryNearbyRead()
        XCTAssertEqual(location.calls, calls); XCTAssertEqual(service.placesReads, 2)
    }
}

@MainActor extension RoamUnstartedContinuationTests {
    func testUnknownPendingMarkerSurvivesTwoLookupsAndReconstructedController() async throws {
        for pending in [RoamLivePending.reveal, .finish] {
            let (owner, service, location, storage, journal, original) = try fixture(edit: { $0.pendingWrite = pending })
            let bytes = storage.bytes, writes = storage.writes
            for _ in 0..<2 {
                await owner.recover()
                XCTAssertEqual(owner.phase, .recoveryRequired); XCTAssertFalse(owner.canContinueUnstartedRoam)
                XCTAssertEqual(owner.record?.pendingWrite, pending)
                owner.continueUnstartedRoam()
                XCTAssertEqual(storage.bytes, bytes); XCTAssertEqual(storage.writes, writes)
                XCTAssertEqual(try journal.read(scope: original.scope), original)
            }
            let recreated = RoamLiveSessionController(service: service, location: location, journal: journal, now: { self.date })
            recreated.prepare(); await recreated.recover()
            XCTAssertEqual(recreated.phase, .recoveryRequired); XCTAssertFalse(recreated.canContinueUnstartedRoam)
            recreated.continueUnstartedRoam()
            XCTAssertEqual(storage.bytes, bytes); XCTAssertEqual(storage.writes, writes)
            XCTAssertEqual(try journal.read(scope: original.scope)?.pendingWrite, pending)
            XCTAssertEqual(service.reads, 3); XCTAssertEqual(service.commands, 0); XCTAssertEqual(location.calls, 0)
        }
    }
    func testUnknownPendingCannotBeLaunderedThroughFinishAndAnotherRecovery() async throws {
        for pending in [RoamLivePending.reveal, .finish] {
            let (owner, service, location, storage, journal, original) = try fixture(edit: { $0.pendingWrite = pending })
            let bytes = storage.bytes, writes = storage.writes
            await owner.recover(); await owner.finish(); await owner.recover()
            XCTAssertFalse(owner.canContinueUnstartedRoam); XCTAssertEqual(owner.phase, .recoveryRequired)
            owner.continueUnstartedRoam()
            XCTAssertEqual(storage.bytes, bytes); XCTAssertEqual(storage.writes, writes)
            XCTAssertEqual(try journal.read(scope: original.scope), original)
            XCTAssertEqual(service.commands, 0); XCTAssertEqual(location.calls, 0)
        }
    }
}
@MainActor extension RoamLiveNearbyReadRetryTests {
    func testReadErrorsStaySourceOwnedAndEachSuccessClearsOnlyItsOwnFailure() async throws {
        let (owner, service, location, storage, _) = try fixture()
        service.failPlacesRead = true; service.failRegisteredRead = true
        await owner.start(purposeAccepted: true)
        XCTAssertNil(owner.error); XCTAssertNotNil(owner.placesReadError); XCTAssertNotNil(owner.registeredShopsReadError)
        let calls = location.calls, bytes = storage.bytes
        service.failPlacesRead = false; await owner.retryNearbyRead()
        XCTAssertNil(owner.error); XCTAssertNil(owner.placesReadError); XCTAssertNotNil(owner.registeredShopsReadError)
        XCTAssertTrue(owner.nearbyReadFailed)
        service.failRegisteredRead = false; await owner.retryNearbyRead()
        XCTAssertNil(owner.error); XCTAssertNil(owner.placesReadError); XCTAssertNil(owner.registeredShopsReadError)
        XCTAssertFalse(owner.nearbyReadFailed); XCTAssertEqual(location.calls, calls); XCTAssertEqual(storage.bytes, bytes)
    }
    func testSuccessfulReadRetryNeverClearsUnrelatedLocationOperationError() async throws {
        let (owner, service, location, storage, _) = try fixture()
        let row = try service.decode(RoamPlace.self, #"{"id":6,"type":1,"lat":31.2,"lng":121.4}"#)
        service.rows = [row]; service.failRegisteredRead = true; await owner.start(purposeAccepted: true)
        location.value = try .init(coordinate: XCTUnwrap(RoamCoordinate(latitude: 31.2, longitude: 121.4)), accuracyMeters: 100, measuredAt: date, datum: .wgs84)
        await owner.discover(row)
        XCTAssertEqual(owner.error as? RoamLiveFailure, .locationQuality)
        let calls = location.calls, bytes = storage.bytes
        service.failRegisteredRead = false; await owner.retryNearbyRead()
        XCTAssertFalse(owner.nearbyReadFailed); XCTAssertEqual(owner.error as? RoamLiveFailure, .locationQuality)
        XCTAssertEqual(location.calls, calls); XCTAssertEqual(storage.bytes, bytes)
    }
    func testStaleReadCannotOverwritePriorGlobalErrorOrStartSecondRead() async throws {
        let (owner, service, location, storage, scope) = try fixture()
        let row = try service.decode(RoamPlace.self, #"{"id":6,"type":1,"lat":31.2,"lng":121.4}"#)
        service.rows = [row]; service.failRegisteredRead = true; await owner.start(purposeAccepted: true)
        location.value = try .init(coordinate: XCTUnwrap(RoamCoordinate(latitude: 31.2, longitude: 121.4)), accuracyMeters: 100, measuredAt: date, datum: .wgs84)
        await owner.discover(row); XCTAssertEqual(owner.error as? RoamLiveFailure, .locationQuality)
        let calls = location.calls, reads = service.registeredReads, bytes = storage.bytes
        service.onPlacesRead = { service.identity = .init(scope: scope, epoch: 2) }
        await owner.retryNearbyRead()
        XCTAssertEqual(owner.error as? RoamLiveFailure, .locationQuality)
        XCTAssertEqual(service.registeredReads, reads); XCTAssertEqual(location.calls, calls); XCTAssertEqual(storage.bytes, bytes)
        XCTAssertFalse(owner.canRetryNearbyRead)
    }
    func testFinishUnknownErrorIsNeitherClearedNorOverwrittenByReadRetry() async throws {
        let (owner, service, location, storage, _) = try fixture()
        service.failRegisteredRead = true; await owner.start(purposeAccepted: true)
        service.failFinish = true; await owner.finish()
        XCTAssertEqual(owner.phase, .recoveryRequired); XCTAssertEqual(owner.record?.pendingWrite, .finish)
        XCTAssertEqual(owner.error as? APIError, .httpStatus(503))
        let calls = location.calls, reads = service.placesReads, bytes = storage.bytes
        await owner.retryNearbyRead()
        XCTAssertEqual(owner.error as? APIError, .httpStatus(503)); XCTAssertEqual(owner.record?.pendingWrite, .finish)
        XCTAssertEqual(service.placesReads, reads); XCTAssertEqual(location.calls, calls); XCTAssertEqual(storage.bytes, bytes)
    }
}

@MainActor extension RoamUnstartedContinuationTests {
    func testUnknownPendingWithoutFinishIntentCannotBecomeAuthorityViaFinishOrRecreation() async throws {
        for pending in [RoamLivePending.reveal, .finish] {
            let (owner, service, location, storage, journal, original) = try fixture(edit: {
                $0.finishRequested = false; $0.pendingWrite = pending
            })
            let bytes = storage.bytes, writes = storage.writes
            await owner.recover(); await owner.finish(); await owner.recover()
            XCTAssertEqual(owner.phase, .recoveryRequired); XCTAssertFalse(owner.canContinueUnstartedRoam)
            XCTAssertEqual(owner.record?.pendingWrite, pending); XCTAssertEqual(owner.record?.finishRequested, false)
            owner.continueUnstartedRoam()
            XCTAssertEqual(storage.bytes, bytes); XCTAssertEqual(storage.writes, writes)
            XCTAssertEqual(try journal.read(scope: original.scope), original)
            let recreated = RoamLiveSessionController(service: service, location: location, journal: journal, now: { self.date })
            recreated.prepare(); await recreated.recover(); await recreated.finish(); await recreated.recover()
            XCTAssertEqual(recreated.phase, .recoveryRequired); XCTAssertFalse(recreated.canContinueUnstartedRoam)
            recreated.continueUnstartedRoam()
            XCTAssertEqual(storage.bytes, bytes); XCTAssertEqual(storage.writes, writes)
            XCTAssertEqual(try journal.read(scope: original.scope), original)
            XCTAssertEqual(service.reads, 4); XCTAssertEqual(service.commands, 0); XCTAssertEqual(location.calls, 0)
        }
    }
}

@MainActor private final class ForegroundElapsedInput {
    var uptime: TimeInterval = 100
    var date = Date(timeIntervalSince1970: 1_790_932_200)
}
@MainActor final class RoamForegroundElapsedTests: XCTestCase {
    private let key = String(repeating: "a", count: 32)
    private func fixture(_ input: ForegroundElapsedInput) throws -> (RoamLiveSessionController, LiveService, LiveLocation, LiveStorage, RoamHistoryScope) {
        let scope = try RoamHistoryScope(market: "cn", deployment: URL(string: "https://elapsed.example/native")!, accountID: 7)
        let service = LiveService(.init(scope: scope, epoch: 1)), location = LiveLocation(input.date), storage = LiveStorage()
        let owner = RoamLiveSessionController(service: service, location: location, journal: RoamLiveJournal(storage: storage),
            now: { input.date }, monotonicNow: { input.uptime }, key: { self.key })
        owner.prepare(); return (owner, service, location, storage, scope)
    }
    func testNewAcceptedWalkCountsOnlyMonotonicTimeWithoutExtraWork() async throws {
        let input = ForegroundElapsedInput(), (owner, service, location, storage, _) = try fixture(input)
        XCTAssertNil(owner.localForegroundElapsedSeconds)
        await owner.start(purposeAccepted: false); XCTAssertNil(owner.localForegroundElapsedSeconds)
        await owner.start(purposeAccepted: true); XCTAssertEqual(owner.localForegroundElapsedSeconds, 0)
        let bytes = storage.bytes, fixes = location.calls, reads = service.placesReads + service.registeredReads, reveals = service.reveals
        input.uptime = 165.9
        XCTAssertEqual(owner.localForegroundElapsedSeconds, 65)
        input.date = input.date.addingTimeInterval(-86_400)
        XCTAssertEqual(owner.localForegroundElapsedSeconds, 65)
        input.date = input.date.addingTimeInterval(86_400 * 3)
        XCTAssertEqual(owner.localForegroundElapsedSeconds, 65)
        XCTAssertEqual(storage.bytes, bytes); XCTAssertEqual(location.calls, fixes)
        XCTAssertEqual(service.placesReads + service.registeredReads, reads); XCTAssertEqual(service.reveals, reveals)
        let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(storage.bytes.values.first)) as? [String: Any])
        XCTAssertEqual(Set(envelope.keys), Set(["version", "scope", "record"]))
        let savedRecord = try XCTUnwrap(envelope["record"] as? [String: Any])
        // Check serialized fields, not values such as this fixture's elapsed.example deployment.
        XCTAssertEqual(Set(savedRecord.keys), Set([
            "scope", "clientSessionKey", "startedAt", "sessionID", "allTiles", "pendingTiles",
            "distanceMeters", "confirmedPOIIDs", "confirmedShops", "unresolvedActions", "finishRequested"
        ]))
    }
    func testRepeatedPauseAndResumeKeepFractionAndExcludePausedGap() async throws {
        let input = ForegroundElapsedInput(), (owner, _, _, storage, _) = try fixture(input)
        await owner.start(purposeAccepted: true)
        input.uptime = 110.75; let bytes = storage.bytes; owner.pause(); owner.pause()
        XCTAssertEqual(storage.bytes, bytes); XCTAssertEqual(owner.localForegroundElapsedSeconds, 10)
        input.uptime = 200; owner.pause(); XCTAssertEqual(owner.localForegroundElapsedSeconds, 10)
        await owner.resume(purposeAccepted: false); XCTAssertEqual(owner.phase, .paused)
        XCTAssertEqual(owner.localForegroundElapsedSeconds, 10)
        await owner.resume(purposeAccepted: true)
        input.uptime = 205.5; await owner.resume(purposeAccepted: true)
        XCTAssertEqual(owner.localForegroundElapsedSeconds, 16)
        owner.pause(); input.uptime = 900; XCTAssertEqual(owner.localForegroundElapsedSeconds, 16)
    }
    func testBackgroundStopsAndReturnRequiresExplicitResume() async throws {
        let input = ForegroundElapsedInput(), (owner, _, location, storage, _) = try fixture(input)
        await owner.start(purposeAccepted: true)
        input.uptime = 109; let bytes = storage.bytes, fixes = location.calls
        owner.setForeground(false); XCTAssertEqual(owner.phase, .paused)
        XCTAssertNil(owner.localForegroundElapsedSeconds); XCTAssertEqual(storage.bytes, bytes)
        input.uptime = 400; owner.setForeground(true)
        XCTAssertEqual(owner.localForegroundElapsedSeconds, 9); XCTAssertEqual(location.calls, fixes)
        await owner.resume(purposeAccepted: true); input.uptime = 404
        XCTAssertEqual(owner.localForegroundElapsedSeconds, 13)
    }
    func testOwnerEpochAccountAndAvailabilityChangesPermanentlyRetireDisplay() async throws {
        for change in ["epoch", "account", "unavailable", "invalidate"] {
            let input = ForegroundElapsedInput(), (owner, service, _, storage, scope) = try fixture(input)
            await owner.start(purposeAccepted: true); input.uptime = 110
            let original = service.identity, bytes = storage.bytes
            switch change {
            case "epoch": service.identity = .init(scope: scope, epoch: 2)
            case "account": service.identity = .init(scope: try RoamHistoryScope(market: "cn", deployment: URL(string: "https://elapsed.example/native")!, accountID: 8), epoch: 2)
            case "unavailable": service.isAvailable = false
            default: owner.invalidate()
            }
            XCTAssertNil(owner.localForegroundElapsedSeconds, change)
            service.identity = original; service.isAvailable = true; input.uptime = 400
            XCTAssertNil(owner.localForegroundElapsedSeconds, change)
            XCTAssertEqual(storage.bytes, bytes)
        }
    }
    func testReconstructedRecordAndExplicitRecoveryNeverInferElapsedFromStartDate() async throws {
        let input = ForegroundElapsedInput(), (owner, service, location, storage, scope) = try fixture(input)
        await owner.start(purposeAccepted: true); input.uptime = 110; owner.pause()
        XCTAssertEqual(owner.localForegroundElapsedSeconds, 10)
        let restored = RoamLiveSessionController(service: service, location: location, journal: .init(storage: storage),
            now: { input.date.addingTimeInterval(86_400) }, monotonicNow: { input.uptime })
        restored.prepare(); XCTAssertEqual(restored.record?.startedAt, input.date)
        XCTAssertNil(restored.localForegroundElapsedSeconds)
        await restored.recover(); XCTAssertEqual(restored.phase, .paused); XCTAssertNil(restored.localForegroundElapsedSeconds)
        input.uptime = 999; XCTAssertNil(restored.localForegroundElapsedSeconds)
        // Recovering even within the original controller discards local provenance.
        await owner.recover(); XCTAssertNil(owner.localForegroundElapsedSeconds)
        XCTAssertEqual(try RoamLiveJournal(storage: storage).read(scope: scope)?.startedAt, input.date)
    }
    func testLegacyRecordRemainsUnknownAfterApprovedResume() async throws {
        let input = ForegroundElapsedInput(), (owner, service, location, storage, scope) = try fixture(input)
        var legacy = RoamLiveRecord(scope: scope, clientSessionKey: key, startedAt: input.date.addingTimeInterval(-86_400))
        legacy.sessionID = 12; try RoamLiveJournal(storage: storage).write(legacy)
        owner.prepare(); XCTAssertNil(owner.localForegroundElapsedSeconds)
        await owner.recover(); await owner.resume(purposeAccepted: true)
        XCTAssertEqual(owner.phase, .active); XCTAssertEqual(location.calls, 1); XCTAssertGreaterThan(service.reads, 0)
        input.uptime = 180; XCTAssertNil(owner.localForegroundElapsedSeconds)
    }
    func testCancellationDuringRevealKeepsUnknownWriteAndJournalBytes() async throws {
        let input = ForegroundElapsedInput(), (owner, service, _, storage, scope) = try fixture(input)
        var pendingBytes: [String: Data] = [:]
        service.onReveal = { input.uptime = 108; pendingBytes = storage.bytes; owner.pause() }
        await owner.start(purposeAccepted: true)
        XCTAssertEqual(owner.phase, .recoveryRequired); XCTAssertNil(owner.localForegroundElapsedSeconds)
        XCTAssertEqual(storage.bytes, pendingBytes)
        XCTAssertEqual(try RoamLiveJournal(storage: storage).read(scope: scope)?.pendingWrite, .reveal)
        input.uptime = 200; XCTAssertNil(owner.localForegroundElapsedSeconds)
    }
    func testCancelledStartTaskStopsClockWithoutClearingUncertainReveal() async throws {
        let input = ForegroundElapsedInput(), (owner, service, _, storage, scope) = try fixture(input)
        service.onReveal = {
            input.uptime = 108
            withUnsafeCurrentTask { $0?.cancel() }
        }
        let task = Task { await owner.start(purposeAccepted: true) }
        await task.value
        XCTAssertEqual(owner.phase, .recoveryRequired)
        XCTAssertNil(owner.localForegroundElapsedSeconds)
        let bytes = storage.bytes; input.uptime = 900
        XCTAssertNil(owner.localForegroundElapsedSeconds); XCTAssertEqual(storage.bytes, bytes)
        XCTAssertEqual(try RoamLiveJournal(storage: storage).read(scope: scope)?.pendingWrite, .reveal)
        XCTAssertEqual(service.reveals, 1)
    }
    func testBothUnknownPendingMarkersAndFinishIntentsRemainByteExact() throws {
        for pending in [RoamLivePending.reveal, .finish] {
            for finish in [false, true] {
                let input = ForegroundElapsedInput(), (owner, _, _, storage, scope) = try fixture(input)
                var draft = RoamLiveRecord(scope: scope, clientSessionKey: key, startedAt: input.date)
                draft.pendingWrite = pending; draft.finishRequested = finish
                try RoamLiveJournal(storage: storage).write(draft); owner.prepare()
                let bytes = storage.bytes
                XCTAssertNil(owner.localForegroundElapsedSeconds); owner.pause(); input.uptime = 800
                XCTAssertNil(owner.localForegroundElapsedSeconds)
                XCTAssertEqual(storage.bytes, bytes)
                XCTAssertEqual(try RoamLiveJournal(storage: storage).read(scope: scope), draft)
                XCTAssertFalse(owner.canContinueUnstartedRoam)
            }
        }
    }
    func testNegativeNonfiniteAndRegressingSamplesCannotBecomeDurationAgain() async throws {
        for sample in [-1.0, .nan, .infinity, -.infinity, 99.0, Double.greatestFiniteMagnitude] {
            let input = ForegroundElapsedInput(), (owner, _, _, storage, _) = try fixture(input)
            await owner.start(purposeAccepted: true); let bytes = storage.bytes
            input.uptime = sample; XCTAssertNil(owner.localForegroundElapsedSeconds)
            input.uptime = 500; XCTAssertNil(owner.localForegroundElapsedSeconds)
            XCTAssertEqual(storage.bytes, bytes)
        }
        for initial in [-1.0, .nan, .infinity, -.infinity] {
            let input = ForegroundElapsedInput(); input.uptime = initial
            let (owner, service, _, _, _) = try fixture(input)
            await owner.start(purposeAccepted: true)
            XCTAssertEqual(service.reveals, 1); XCTAssertEqual(owner.phase, .active)
            XCTAssertNil(owner.localForegroundElapsedSeconds)
            input.uptime = 200; XCTAssertNil(owner.localForegroundElapsedSeconds)
        }
    }
    func testClockDuplicateTransitionsAndBackwardWhilePausedFailClosed() throws {
        var clock = try XCTUnwrap(RoamForegroundElapsedClock(now: 20))
        clock.resume(at: 21); XCTAssertEqual(clock.seconds(at: 23.75), 3)
        clock.pause(at: 23.75); clock.pause(at: 24)
        XCTAssertEqual(clock.seconds(at: 30), 3)
        clock.resume(at: 30); clock.resume(at: 31)
        XCTAssertEqual(clock.seconds(at: 32.25), 6)
        clock.pause(at: 33); XCTAssertNil(clock.seconds(at: 32))
        clock.resume(at: 200); XCTAssertNil(clock.seconds(at: 201))
    }
}

@MainActor private final class PlaceMemoryService: RoamLiveServing {
    let base: LiveService
    var identity: RoamExperienceIdentity? { base.identity }
    var isAvailable: Bool { base.isAvailable }
    var presenceAvailable: Bool { base.presenceAvailable }
    var text: String? = "Returned place description"
    var returnedPOIID: Int?
    var onDiscover: (() -> Void)?
    init(_ base: LiveService) { self.base = base }
    func reveal(sessionID: Int?, clientSessionKey: String, tiles: [String]) async throws -> RoamLiveRevealReceipt {
        try await base.reveal(sessionID: sessionID, clientSessionKey: clientSessionKey, tiles: tiles)
    }
    func fact(key: String) async throws -> RoamSessionFact { try await base.fact(key: key) }
    func places(fix: RoamDeviceFix) async throws -> [RoamPlace] { try await base.places(fix: fix) }
    func registeredShops(fix: RoamDeviceFix) async throws -> [RoamRouteNode] { try await base.registeredShops(fix: fix) }
    func discover(sessionID: Int, poiID: Int, fix: RoamDeviceFix) async throws -> RoamLiveDiscoveryReceipt {
        _ = try await base.discover(sessionID: sessionID, poiID: poiID, fix: fix)
        onDiscover?()
        var payload: [String: Any] = ["discovered": false, "poiId": returnedPOIID ?? poiID]
        if let text { payload["meaning"] = text }
        return try JSONDecoder().decode(RoamLiveDiscoveryReceipt.self, from: JSONSerialization.data(withJSONObject: payload))
    }
    func shopVisit(sessionID: Int, sourceType: Int, sourceID: Int, fix: RoamDeviceFix) async throws -> RoamLiveShopReceipt {
        try await base.shopVisit(sessionID: sessionID, sourceType: sourceType, sourceID: sourceID, fix: fix)
    }
    func presence(sessionID: Int, fix: RoamDeviceFix, explorationPercent: Int) async throws {
        try await base.presence(sessionID: sessionID, fix: fix, explorationPercent: explorationPercent)
    }
    func finish(sessionID: Int, poiIDs: [Int], distanceMeters: Int) async throws {
        try await base.finish(sessionID: sessionID, poiIDs: poiIDs, distanceMeters: distanceMeters)
    }
}

@MainActor final class RoamPlaceMemoryTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_790_932_200)
    private let key = String(repeating: "a", count: 32)
    private func fixture() throws -> (RoamLiveSessionController, PlaceMemoryService, LiveLocation, LiveStorage, RoamHistoryScope) {
        let scope = try RoamHistoryScope(market: "cn", deployment: XCTUnwrap(URL(string: "https://memory.example/native/")), accountID: 7)
        let base = LiveService(.init(scope: scope, epoch: 1)), service = PlaceMemoryService(base)
        base.rows = try [6, 7, 8].map { id in
            try base.decode(RoamPlace.self, "{\"id\":\(id),\"type\":1,\"lat\":31.2,\"lng\":121.4,\"name\":\"Place \(id)\"}")
        }
        let location = LiveLocation(date), storage = LiveStorage()
        let history = RoamHistoryStore(storage: storage, currentScope: { base.identity?.scope })
        let owner = RoamLiveSessionController(service: service, location: location, journal: .init(storage: storage), history: history,
            now: { self.date }, key: { self.key })
        owner.prepare(); return (owner, service, location, storage, scope)
    }
    func testConfirmedReceiptPublishesVerbatimOnlyAfterJournalConfirmation() async throws {
        let (owner, service, location, storage, scope) = try fixture(); await owner.start(purposeAccepted: true)
        let place = service.base.rows[0]; service.text = "  Cafe\u{301} memory\n"
        service.onDiscover = {
            XCTAssertNil(owner.placeMemory)
            XCTAssertTrue((try? RoamLiveJournal(storage: storage).read(scope: scope)?.unresolvedActions.contains("poi:6")) == true)
        }
        await owner.discover(place)
        let memory = try XCTUnwrap(owner.placeMemory)
        XCTAssertEqual(memory.poiID, place.id); XCTAssertEqual(memory.placeName, place.name)
        XCTAssertEqual(Array(memory.text.utf8), Array(try XCTUnwrap(service.text).utf8))
        XCTAssertTrue(owner.actionConfirmed(place, shop: false)); XCTAssertFalse(owner.actionUnresolved(place, shop: false))
        let record = try XCTUnwrap(RoamLiveJournal(storage: storage).read(scope: scope))
        XCTAssertTrue(record.confirmedPOIIDs.contains(place.id)); XCTAssertTrue(record.unresolvedActions.isEmpty)
        let bytes = storage.bytes, calls = service.base.discoveries, fixes = location.calls
        for _ in 0..<3 { XCTAssertEqual(owner.placeMemory, memory) }
        XCTAssertEqual(storage.bytes, bytes); XCTAssertEqual(service.base.discoveries, calls); XCTAssertEqual(location.calls, fixes)
        XCTAssertFalse(storage.bytes.values.contains { String(decoding: $0, as: UTF8.self).contains("\"meaning\"") })
    }
    func testUnknownWrongPOIAndFailedConfirmationNeverPublishOrUnlock() async throws {
        for mode in 0..<3 {
            let (owner, service, _, storage, scope) = try fixture(); await owner.start(purposeAccepted: true)
            if mode == 0 { service.base.failDiscover = true }
            if mode == 1 { service.returnedPOIID = 99 }
            if mode == 2 { service.onDiscover = { storage.failWrites = true } }
            await owner.discover(service.base.rows[0])
            XCTAssertNil(owner.placeMemory); XCTAssertTrue(owner.actionUnresolved(service.base.rows[0], shop: false))
            storage.failWrites = false
            XCTAssertTrue(try XCTUnwrap(RoamLiveJournal(storage: storage).read(scope: scope)).unresolvedActions.contains("poi:6"))
            await owner.discover(service.base.rows[0]); XCTAssertEqual(service.base.discoveries, 1)
        }
    }
    func testLateReceiptAfterPauseBackgroundInvalidationOrOwnerChangeCannotPublish() async throws {
        for mode in 0..<4 {
            let (owner, service, _, storage, scope) = try fixture(); await owner.start(purposeAccepted: true)
            service.onDiscover = {
                if mode == 0 { owner.pause() }
                if mode == 1 { owner.setForeground(false) }
                if mode == 2 { owner.invalidate() }
                if mode == 3 { service.base.identity = .init(scope: scope, epoch: 2) }
            }
            await owner.discover(service.base.rows[0]); XCTAssertNil(owner.placeMemory)
            XCTAssertTrue(try XCTUnwrap(RoamLiveJournal(storage: storage).read(scope: scope)).unresolvedActions.contains("poi:6"))
        }
    }
    func testDismissConsumesOnlyCurrentUUIDAndCannotCloseReplacement() async throws {
        let (owner, service, location, storage, _) = try fixture(); await owner.start(purposeAccepted: true)
        await owner.discover(service.base.rows[0]); let old = try XCTUnwrap(owner.placeMemory)
        await owner.discover(service.base.rows[1]); let current = try XCTUnwrap(owner.placeMemory)
        XCTAssertNotEqual(old.id, current.id)
        let bytes = storage.bytes, calls = service.base.discoveries, fixes = location.calls
        owner.dismissPlaceMemory(id: old.id); XCTAssertEqual(owner.placeMemory, current)
        owner.dismissPlaceMemory(id: current.id); XCTAssertNil(owner.placeMemory)
        owner.dismissPlaceMemory(id: current.id); XCTAssertNil(owner.placeMemory)
        XCTAssertEqual(storage.bytes, bytes); XCTAssertEqual(service.base.discoveries, calls); XCTAssertEqual(location.calls, fixes)
    }
    func testMissingAndBlankNewMeaningRetireEarlierTextWithoutInventingFallback() async throws {
        for text in [nil, "", " \n\t"] as [String?] {
            let (owner, service, _, _, _) = try fixture(); await owner.start(purposeAccepted: true)
            await owner.discover(service.base.rows[0]); XCTAssertNotNil(owner.placeMemory)
            service.text = text; await owner.discover(service.base.rows[1])
            XCTAssertNil(owner.placeMemory); XCTAssertTrue(owner.actionConfirmed(service.base.rows[1], shop: false))
        }
    }
    func testPauseRecoveryAndReconstructionDoNotRestoreEphemeralMeaning() async throws {
        let (owner, service, location, storage, _) = try fixture(); await owner.start(purposeAccepted: true)
        await owner.discover(service.base.rows[0]); XCTAssertNotNil(owner.placeMemory)
        owner.pause(); XCTAssertNil(owner.placeMemory); await owner.recover(); XCTAssertNil(owner.placeMemory)
        await owner.resume(purposeAccepted: true); XCTAssertNil(owner.placeMemory)
        let restored = RoamLiveSessionController(service: service, location: location, journal: .init(storage: storage), now: { self.date })
        restored.prepare(); XCTAssertNil(restored.placeMemory)
    }
    func testEpochAccountAndRevocationPreventViewingOrClosingOwnedText() async throws {
        let (owner, service, _, storage, scope) = try fixture(); await owner.start(purposeAccepted: true)
        await owner.discover(service.base.rows[0]); let memory = try XCTUnwrap(owner.placeMemory); let bytes = storage.bytes
        service.base.identity = .init(scope: scope, epoch: 2)
        XCTAssertNil(owner.placeMemory); owner.dismissPlaceMemory(id: memory.id)
        let other = try RoamHistoryScope(market: "cn", deployment: XCTUnwrap(URL(string: "https://memory.example/native/")), accountID: 8)
        service.base.identity = .init(scope: other, epoch: 1); XCTAssertNil(owner.placeMemory)
        service.base.identity = .init(scope: scope, epoch: 1); service.base.isAvailable = false
        XCTAssertNil(owner.placeMemory); XCTAssertEqual(storage.bytes, bytes)
    }
    func testFinishRetiresPlaceTextWithoutTreatingItAsSettlementOrReward() async throws {
        let (owner, service, _, _, _) = try fixture(); await owner.start(purposeAccepted: true)
        await owner.discover(service.base.rows[0]); XCTAssertNotNil(owner.placeMemory); XCTAssertNil(owner.settlement)
        await owner.finish(); XCTAssertNil(owner.placeMemory); XCTAssertEqual(owner.phase, .finished)
        XCTAssertEqual(service.base.finishes, 1); XCTAssertEqual(service.base.discoveries, 1)
    }
}

@MainActor private final class PlaceMemoryPostWriteStorage: RoamHistoryDataStoring {
    let base = LiveStorage()
    var afterWrite: (() -> Void)?
    func read(key: String) throws -> Data? { try base.read(key: key) }
    func write(_ data: Data, key: String) throws { try base.write(data, key: key); afterWrite?() }
}
@MainActor extension RoamPlaceMemoryTests {
    func testOwnerRetiredInsideConfirmationStorageCallbackCannotPublishMeaning() async throws {
        let scope = try RoamHistoryScope(market: "cn", deployment: XCTUnwrap(URL(string: "https://memory.example/native/")), accountID: 7)
        let base = LiveService(.init(scope: scope, epoch: 1)), service = PlaceMemoryService(base)
        let row = try base.decode(RoamPlace.self, #"{"id":6,"type":1,"lat":31.2,"lng":121.4,"name":"Place"}"#)
        base.rows = [row]
        let storage = PlaceMemoryPostWriteStorage(), location = LiveLocation(date)
        let owner = RoamLiveSessionController(service: service, location: location, journal: .init(storage: storage), now: { self.date }, key: { self.key })
        owner.prepare(); await owner.start(purposeAccepted: true)
        service.onDiscover = {
            storage.afterWrite = { storage.afterWrite = nil; owner.pause() }
        }
        await owner.discover(row)
        XCTAssertNil(owner.placeMemory); XCTAssertEqual(owner.phase, .paused)
        XCTAssertEqual(base.discoveries, 1)
        XCTAssertTrue(try XCTUnwrap(RoamLiveJournal(storage: storage).read(scope: scope)).confirmedPOIIDs.contains(row.id))
    }
}

@MainActor extension RoamPlaceMemoryTests {
    func testFailedPulsePauseThenResumeCannotReviveEarlierMeaningWithoutDiscovery() async throws {
        let (owner, service, location, _, _) = try fixture(); await owner.start(purposeAccepted: true)
        await owner.discover(service.base.rows[0]); XCTAssertNotNil(owner.placeMemory)
        let originalFix = location.value, discoveries = service.base.discoveries
        location.value = try RoamDeviceFix(coordinate: originalFix.coordinate, accuracyMeters: 81,
            measuredAt: originalFix.measuredAt, datum: originalFix.datum)
        await owner.pulse()
        XCTAssertEqual(owner.phase, .paused); XCTAssertNil(owner.placeMemory)
        XCTAssertEqual(owner.error as? RoamLiveFailure, .locationQuality)
        location.value = originalFix
        await owner.resume(purposeAccepted: true)
        XCTAssertEqual(owner.phase, .active); XCTAssertNil(owner.placeMemory)
        XCTAssertEqual(service.base.discoveries, discoveries)
        XCTAssertTrue(owner.actionConfirmed(service.base.rows[0], shop: false))
    }
}

@MainActor final class RoamLiveMerchantDescriptionTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_790_932_200)
    private func place(_ text: Any? = "Provided merchant information", type: Int = 2, id: Int = 6) throws -> RoamPlace {
        var object: [String: Any] = ["id": id, "type": type, "lat": 31.2, "lng": 121.4, "name": "Returned merchant"]
        if let text { object["description"] = text }
        return try JSONDecoder().decode(RoamPlace.self, from: JSONSerialization.data(withJSONObject: object))
    }
    private func fixture(_ row: RoamPlace? = nil) throws -> (RoamLiveSessionController, LiveService, LiveLocation, LiveStorage) {
        let scope = try RoamHistoryScope(market: "cn", deployment: XCTUnwrap(URL(string: "https://merchant-description.example/native/")), accountID: 7)
        let service = LiveService(.init(scope: scope, epoch: 1)), location = LiveLocation(date), storage = LiveStorage()
        service.rows = [try row ?? place()]
        let owner = RoamLiveSessionController(service: service, location: location, journal: .init(storage: storage),
            now: { self.date }, key: { String(repeating: "a", count: 32) })
        owner.prepare(); return (owner, service, location, storage)
    }
    func testCurrentMerchantTextIsReadOnlyAndPreservesReturnedString() async throws {
        let text = "  Provided e\u{301} description\n", row = try place(text)
        let (owner, service, location, storage) = try fixture(row)
        XCTAssertNil(owner.merchantDescription(for: row))
        service.onPlacesRead = { XCTAssertNil(owner.merchantDescription(for: row)) }
        await owner.start(purposeAccepted: true)
        let bytes = storage.bytes, fixes = location.calls, reads = service.placesReads
        let shown = try XCTUnwrap(owner.merchantDescription(for: row))
        XCTAssertEqual(Array(shown.utf8), Array(text.utf8))
        XCTAssertEqual(row.description, "Provided e\u{301} description")
        XCTAssertEqual(storage.bytes, bytes); XCTAssertEqual(location.calls, fixes); XCTAssertEqual(service.placesReads, reads)
        XCTAssertEqual(service.discoveries, 0); XCTAssertEqual(service.visits, 0); XCTAssertEqual(service.finishes, 0)
    }
    func testOnlyExactCurrentSupportedTypeTwoRowCanProvideMerchantText() async throws {
        let (owner, service, _, storage) = try fixture(); await owner.start(purposeAccepted: true)
        let bytes = storage.bytes
        XCTAssertNotNil(owner.merchantDescription(for: service.rows[0]))
        for row in [try place(type: 1), try place(type: 3), try place(id: 0), try place(id: 99), try place("Stale text")] {
            XCTAssertNil(owner.merchantDescription(for: row))
        }
        let (cityOwner, _, _, _) = try fixture(place("Unreviewed city description", type: 1))
        await cityOwner.start(purposeAccepted: true)
        XCTAssertNil(cityOwner.merchantDescription(for: try place("Unreviewed city description", type: 1)))
        XCTAssertNil(cityOwner.placeMemory)
        XCTAssertEqual(storage.bytes, bytes); XCTAssertEqual(service.discoveries, 0); XCTAssertEqual(service.visits, 0)
    }
    func testMissingBlankAndNumericSourceDoNotInventAnIntroduction() async throws {
        for text in [nil, NSNull(), "", " \n", 123] as [Any?] {
            let row = try place(text), (owner, service, _, storage) = try fixture(row)
            await owner.start(purposeAccepted: true)
            let bytes = storage.bytes
            XCTAssertNil(owner.merchantDescription(for: row)); XCTAssertEqual(storage.bytes, bytes)
            if text is Int { XCTAssertEqual(row.description, "123"); XCTAssertNil(row.merchantDescriptionText) }
            XCTAssertEqual(service.discoveries, 0); XCTAssertEqual(service.visits, 0)
        }
        // Existing malformed-row contract stays intact; no new success/fallback is introduced.
        for value in [true, ["text": "No coercion"], ["No coercion"]] as [Any] {
            XCTAssertThrowsError(try place(value))
        }
    }
    func testPauseBackgroundOwnerEpochRevocationAndInvalidationHideMetadata() async throws {
        let (owner, service, location, storage) = try fixture(); await owner.start(purposeAccepted: true)
        let row = service.rows[0], identity = try XCTUnwrap(service.identity)
        let reads = service.placesReads, fixes = location.calls, bytes = storage.bytes
        service.identity = .init(scope: identity.scope, epoch: identity.epoch + 1)
        XCTAssertTrue(service.isAvailable); XCTAssertNil(owner.merchantDescription(for: row))
        let other = try RoamHistoryScope(market: "cn", deployment: XCTUnwrap(URL(string: identity.scope.deployment)), accountID: 8)
        service.identity = .init(scope: other, epoch: identity.epoch)
        XCTAssertNil(owner.merchantDescription(for: row))
        service.identity = identity; service.isAvailable = false
        XCTAssertNil(owner.merchantDescription(for: row)); service.isAvailable = true
        owner.setForeground(false); XCTAssertNil(owner.merchantDescription(for: row))
        owner.setForeground(true); XCTAssertEqual(owner.phase, .paused); XCTAssertNil(owner.merchantDescription(for: row))
        owner.invalidate(); XCTAssertNil(owner.merchantDescription(for: row))
        XCTAssertEqual(storage.bytes, bytes); XCTAssertEqual(service.placesReads, reads); XCTAssertEqual(location.calls, fixes)
        XCTAssertEqual(service.discoveries, 0); XCTAssertEqual(service.visits, 0)
    }
    func testFailedNearbyReadCannotExposeRetainedText() async throws {
        let (owner, service, _, storage) = try fixture(); service.failPlacesRead = true
        await owner.start(purposeAccepted: true)
        XCTAssertTrue(owner.placesReadFailed); XCTAssertNil(owner.merchantDescription(for: service.rows[0]))
        service.failPlacesRead = false; await owner.retryNearbyRead()
        XCTAssertNotNil(owner.merchantDescription(for: service.rows[0]))
        let bytes = storage.bytes
        owner.pause(); XCTAssertNil(owner.merchantDescription(for: service.rows[0]))
        XCTAssertEqual(storage.bytes, bytes); XCTAssertEqual(service.discoveries, 0); XCTAssertEqual(service.visits, 0)
    }
}

@MainActor final class RoamPauseRouteOverviewTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_790_932_200)
    private let key = String(repeating: "a", count: 32)
    private func fixture() throws -> (RoamLiveSessionController, LiveService, LiveLocation, LiveStorage, RoamHistoryScope) {
        let scope = try RoamHistoryScope(market: "cn", deployment: XCTUnwrap(URL(string: "https://route-overview.example/native/")), accountID: 7)
        let service = LiveService(.init(scope: scope, epoch: 1)), location = LiveLocation(date), storage = LiveStorage()
        let owner = RoamLiveSessionController(service: service, location: location, journal: .init(storage: storage),
            now: { self.date }, key: { self.key })
        owner.prepare(); return (owner, service, location, storage, scope)
    }
    private func secondPoint(_ owner: RoamLiveSessionController, _ location: LiveLocation) async throws {
        location.value = try RoamDeviceFix(coordinate: XCTUnwrap(RoamCoordinate(latitude: 31.2001, longitude: 121.4001)),
            accuracyMeters: 10, measuredAt: date.addingTimeInterval(1), datum: .gcj02)
        await owner.pulse()
    }
    func testPauseKeepsExactCurrentSamplesAndViewingDoesNoWork() async throws {
        let (owner, service, location, storage, _) = try fixture()
        XCTAssertNil(owner.currentRouteTrack)
        await owner.start(purposeAccepted: true); XCTAssertEqual(owner.currentRouteTrack?.count, 1)
        try await secondPoint(owner, location)
        let track = try XCTUnwrap(owner.currentRouteTrack); XCTAssertEqual(track.count, 2)
        owner.pause(); XCTAssertEqual(owner.phase, .paused); XCTAssertNil(owner.lastFix)
        let bytes = storage.bytes, fixes = location.calls, reads = service.reads, reveals = service.reveals
        let places = service.placesReads, shops = service.registeredReads, stops = location.stops
        for _ in 0..<3 { XCTAssertEqual(owner.currentRouteTrack, track) }
        XCTAssertEqual(storage.bytes, bytes); XCTAssertEqual(location.calls, fixes); XCTAssertEqual(location.stops, stops)
        XCTAssertEqual(service.reads, reads); XCTAssertEqual(service.reveals, reveals)
        XCTAssertEqual(service.placesReads, places); XCTAssertEqual(service.registeredReads, shops)
        XCTAssertEqual(service.finishes, 0); XCTAssertEqual(service.visits, 0); XCTAssertEqual(service.discoveries, 0)
    }
    func testForegroundReturnOnlyReviewsPausedTrackAndExplicitResumeKeepsExistingContract() async throws {
        let (owner, service, location, storage, _) = try fixture()
        await owner.start(purposeAccepted: true); try await secondPoint(owner, location)
        let track = try XCTUnwrap(owner.currentRouteTrack)
        owner.setForeground(false); XCTAssertNil(owner.currentRouteTrack)
        let bytes = storage.bytes, fixes = location.calls, reveals = service.reveals
        owner.setForeground(true)
        XCTAssertEqual(owner.phase, .paused); XCTAssertEqual(owner.currentRouteTrack, track)
        XCTAssertEqual(location.calls, fixes); XCTAssertEqual(service.reveals, reveals); XCTAssertEqual(storage.bytes, bytes)
        await owner.resume(purposeAccepted: false)
        XCTAssertEqual(owner.phase, .paused); XCTAssertEqual(location.calls, fixes)
        XCTAssertEqual(owner.currentRouteTrack, track); XCTAssertNotNil(owner.error)
        location.value = try RoamDeviceFix(coordinate: XCTUnwrap(RoamCoordinate(latitude: 31.2002, longitude: 121.4002)),
            accuracyMeters: 10, measuredAt: date.addingTimeInterval(2), datum: .gcj02)
        let previousDistance = owner.record?.distanceMeters
        await owner.resume(purposeAccepted: true)
        XCTAssertEqual(owner.phase, .active); XCTAssertEqual(location.calls, fixes + 1)
        XCTAssertEqual(owner.record?.distanceMeters, previousDistance)
        XCTAssertEqual(Array(try XCTUnwrap(owner.currentRouteTrack).prefix(track.count)), track)
    }
    func testRestoredRecordDoesNotInventEarlierRouteFromDistanceOrTiles() async throws {
        let (owner, service, location, storage, _) = try fixture()
        await owner.start(purposeAccepted: true); try await secondPoint(owner, location); owner.pause()
        XCTAssertGreaterThan(try XCTUnwrap(owner.record).distanceMeters, 0)
        let restored = RoamLiveSessionController(service: service, location: location, journal: .init(storage: storage), now: { self.date })
        restored.prepare(); XCTAssertNil(restored.currentRouteTrack)
        await restored.recover(); XCTAssertEqual(restored.phase, .paused)
        XCTAssertEqual(restored.currentRouteTrack, []); XCTAssertTrue(restored.track.isEmpty)
        XCTAssertNil(restored.localForegroundElapsedSeconds)
        let bytes = storage.bytes, fixes = location.calls, reads = service.reads
        for _ in 0..<3 { XCTAssertEqual(restored.currentRouteTrack, []) }
        XCTAssertEqual(storage.bytes, bytes); XCTAssertEqual(location.calls, fixes); XCTAssertEqual(service.reads, reads)
    }
    func testAccountEpochMissingIdentityRevocationAndInvalidateHideOldTrack() async throws {
        let (owner, service, location, storage, scope) = try fixture()
        await owner.start(purposeAccepted: true); try await secondPoint(owner, location); owner.pause()
        let current = try XCTUnwrap(service.identity), bytes = storage.bytes, fixes = location.calls
        service.identity = .init(scope: scope, epoch: 2)
        XCTAssertTrue(service.isAvailable); XCTAssertNil(owner.currentRouteTrack)
        let other = try RoamHistoryScope(market: "cn", deployment: XCTUnwrap(URL(string: scope.deployment)), accountID: 8)
        service.identity = .init(scope: other, epoch: 1); XCTAssertNil(owner.currentRouteTrack)
        service.identity = nil; XCTAssertNil(owner.currentRouteTrack)
        service.identity = current; service.isAvailable = false; XCTAssertNil(owner.currentRouteTrack)
        service.isAvailable = true; owner.invalidate(); XCTAssertNil(owner.currentRouteTrack); XCTAssertTrue(owner.track.isEmpty)
        XCTAssertEqual(storage.bytes, bytes); XCTAssertEqual(location.calls, fixes)
    }
    func testFailedPauseKeepsRiskAndViewingNeverRetriesLocation() async throws {
        let (owner, service, location, storage, _) = try fixture()
        await owner.start(purposeAccepted: true); try await secondPoint(owner, location)
        let track = try XCTUnwrap(owner.currentRouteTrack)
        location.value = try RoamDeviceFix(coordinate: location.value.coordinate, accuracyMeters: 81,
            measuredAt: date.addingTimeInterval(2), datum: .gcj02)
        await owner.pulse(); XCTAssertEqual(owner.phase, .paused); XCTAssertNotNil(owner.error)
        let bytes = storage.bytes, fixes = location.calls, reveals = service.reveals
        XCTAssertEqual(owner.currentRouteTrack, track); XCTAssertNotNil(owner.error)
        XCTAssertEqual(storage.bytes, bytes); XCTAssertEqual(location.calls, fixes); XCTAssertEqual(service.reveals, reveals)
    }
    func testBusyPendingBootstrapAndFinishIntentDoNotExposeAnOverview() async throws {
        let (owner, service, _, _, _) = try fixture()
        service.onPlacesRead = { XCTAssertTrue(owner.busy); XCTAssertNil(owner.currentRouteTrack) }
        await owner.start(purposeAccepted: true); XCTAssertNotNil(owner.currentRouteTrack)
        service.failFinish = true; await owner.finish()
        XCTAssertEqual(owner.record?.finishRequested, true); XCTAssertNil(owner.currentRouteTrack)
        let (pending, other, _, storage, _) = try fixture()
        other.failReveal = true; await pending.start(purposeAccepted: true)
        XCTAssertEqual(pending.record?.pendingWrite, .reveal); XCTAssertNil(pending.currentRouteTrack)
        let bytes = storage.bytes; pending.pause(); XCTAssertNil(pending.currentRouteTrack); XCTAssertEqual(storage.bytes, bytes)
    }
}

@MainActor extension RoamPauseRouteOverviewTests {
    func testOwnerRetiredInsideExistingReadCannotPublishOldRoute() async throws {
        let (owner, service, location, storage, scope) = try fixture()
        service.onPlacesRead = {
            service.identity = .init(scope: scope, epoch: 2)
            XCTAssertNil(owner.currentRouteTrack)
        }
        await owner.start(purposeAccepted: true)
        XCTAssertEqual(owner.phase, .unavailable); XCTAssertNil(owner.currentRouteTrack); XCTAssertTrue(owner.track.isEmpty)
        let bytes = storage.bytes, calls = location.calls, reads = service.reads, reveals = service.reveals
        XCTAssertNil(owner.currentRouteTrack)
        XCTAssertEqual(storage.bytes, bytes); XCTAssertEqual(location.calls, calls)
        XCTAssertEqual(service.reads, reads); XCTAssertEqual(service.reveals, reveals)
    }
}

@MainActor final class RoamLocalBrowseIdentityTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_790_932_200)
    private func fixture() throws -> (RoamLiveSessionController, LiveService, LiveLocation, LiveStorage) {
        let scope = try RoamHistoryScope(market: "cn", deployment: XCTUnwrap(URL(string: "https://local-browse.example/native")), accountID: 7)
        let service = LiveService(.init(scope: scope, epoch: 1)), location = LiveLocation(date), storage = LiveStorage()
        let owner = RoamLiveSessionController(service: service, location: location, journal: .init(storage: storage), now: { self.date }, key: { String(repeating: "a", count: 32) })
        owner.prepare(); return (owner, service, location, storage)
    }
    func testCurrentActiveAndPausedProjectionNeverStartsReadsOrWrites() async throws {
        let (owner, service, location, storage) = try fixture()
        XCTAssertNil(owner.localBrowseIdentity); await owner.start(purposeAccepted: true)
        XCTAssertEqual(owner.localBrowseIdentity, service.identity); owner.pause()
        let bytes = storage.bytes, fixes = location.calls, stops = location.stops, reveals = service.reveals
        let reads = service.reads, places = service.placesReads, shops = service.registeredReads
        for _ in 0..<3 { XCTAssertEqual(owner.localBrowseIdentity, service.identity) }
        XCTAssertEqual(owner.phase, .paused); XCTAssertEqual(storage.bytes, bytes)
        XCTAssertEqual(location.calls, fixes); XCTAssertEqual(location.stops, stops)
        XCTAssertEqual(service.reveals, reveals); XCTAssertEqual(service.reads, reads)
        XCTAssertEqual(service.placesReads, places); XCTAssertEqual(service.registeredReads, shops)
        XCTAssertEqual(service.finishes, 0); XCTAssertEqual(service.discoveries, 0); XCTAssertEqual(service.visits, 0)
    }
    func testBackgroundEpochAccountAndRetirementDoNotRetainBrowseOwner() async throws {
        let (owner, service, location, storage) = try fixture(); await owner.start(purposeAccepted: true)
        let identity = try XCTUnwrap(service.identity), bytes = storage.bytes, fixes = location.calls
        owner.setForeground(false); XCTAssertNil(owner.localBrowseIdentity)
        owner.setForeground(true); XCTAssertEqual(owner.phase, .paused); XCTAssertEqual(owner.localBrowseIdentity, identity)
        service.identity = .init(scope: identity.scope, epoch: 2); XCTAssertNil(owner.localBrowseIdentity)
        let other = try RoamHistoryScope(market: "cn", deployment: XCTUnwrap(URL(string: identity.scope.deployment)), accountID: 8)
        service.identity = .init(scope: other, epoch: 1); XCTAssertNil(owner.localBrowseIdentity)
        service.identity = identity; service.isAvailable = false; XCTAssertNil(owner.localBrowseIdentity)
        service.isAvailable = true; owner.invalidate(); XCTAssertNil(owner.localBrowseIdentity)
        XCTAssertEqual(storage.bytes, bytes); XCTAssertEqual(location.calls, fixes)
    }
    func testBusyUnknownPendingAndFinishIntentStayBlockedAndByteExact() async throws {
        let (owner, service, _, _) = try fixture()
        service.onPlacesRead = { XCTAssertTrue(owner.busy); XCTAssertNil(owner.localBrowseIdentity) }
        await owner.start(purposeAccepted: true); XCTAssertNotNil(owner.localBrowseIdentity)
        service.failFinish = true; await owner.finish()
        XCTAssertEqual(owner.record?.finishRequested, true); XCTAssertNil(owner.localBrowseIdentity)
        let (pending, failed, location, storage) = try fixture(); failed.failReveal = true
        await pending.start(purposeAccepted: true)
        let bytes = storage.bytes, fixes = location.calls
        XCTAssertEqual(pending.record?.pendingWrite, .reveal); XCTAssertNil(pending.localBrowseIdentity)
        pending.pause(); XCTAssertEqual(pending.phase, .recoveryRequired)
        XCTAssertNil(pending.localBrowseIdentity); XCTAssertEqual(storage.bytes, bytes); XCTAssertEqual(location.calls, fixes)
    }
}

@MainActor private final class FinishedRouteStorage: RoamHistoryDataStoring {
    enum Failure { case history, clear }
    var bytes: [String: Data] = [:]
    var failure: Failure?
    var onArchiveWrite: (() -> Void)?
    func read(key: String) throws -> Data? { bytes[key] }
    func write(_ data: Data, key: String) throws {
        let history = key.hasPrefix("roam-history-v1-")
        let fields = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let clear = key.hasPrefix("roam-live-v1-") && (fields?["record"] == nil || fields?["record"] is NSNull)
        if (failure == .history && history) || (failure == .clear && clear) { throw APIError.notConfigured }
        bytes[key] = data
        if history || clear { onArchiveWrite?() }
    }
}
@MainActor private final class FinishedRouteService: RoamLiveServing {
    let base: LiveService
    var identity: RoamExperienceIdentity? { get { base.identity } set { base.identity = newValue } }
    var isAvailable: Bool { base.isAvailable }
    var presenceAvailable: Bool { false }
    var onFact: (() -> Void)?
    var response: RoamSessionFact?
    init(_ identity: RoamExperienceIdentity) { base = LiveService(identity) }
    func fact(key: String) async throws -> RoamSessionFact {
        let value = try await base.fact(key: key); onFact?(); return response ?? value
    }
    func reveal(sessionID: Int?, clientSessionKey: String, tiles: [String]) async throws -> RoamLiveRevealReceipt {
        try await base.reveal(sessionID: sessionID, clientSessionKey: clientSessionKey, tiles: tiles)
    }
    func places(fix: RoamDeviceFix) async throws -> [RoamPlace] { try await base.places(fix: fix) }
    func registeredShops(fix: RoamDeviceFix) async throws -> [RoamRouteNode] { try await base.registeredShops(fix: fix) }
    func discover(sessionID: Int, poiID: Int, fix: RoamDeviceFix) async throws -> RoamLiveDiscoveryReceipt { throw APIError.notConfigured }
    func shopVisit(sessionID: Int, sourceType: Int, sourceID: Int, fix: RoamDeviceFix) async throws -> RoamLiveShopReceipt { throw APIError.notConfigured }
    func presence(sessionID: Int, fix: RoamDeviceFix, explorationPercent: Int) async throws { throw APIError.notConfigured }
    func finish(sessionID: Int, poiIDs: [Int], distanceMeters: Int) async throws { try await base.finish(sessionID: sessionID, poiIDs: poiIDs, distanceMeters: distanceMeters) }
}
@MainActor final class RoamFinishedRouteTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_790_932_200)
    private func fixture() throws -> (RoamLiveSessionController, FinishedRouteService, LiveLocation, FinishedRouteStorage, RoamHistoryScope) {
        let scope = try RoamHistoryScope(market: "cn", deployment: XCTUnwrap(URL(string: "https://finished-route.example/native/")), accountID: 7)
        let service = FinishedRouteService(.init(scope: scope, epoch: 1)), location = LiveLocation(date), storage = FinishedRouteStorage()
        let history = RoamHistoryStore(storage: storage, currentScope: { service.identity?.scope })
        let owner = RoamLiveSessionController(service: service, location: location, journal: .init(storage: storage),
            history: history, now: { self.date }, key: { String(repeating: "a", count: 32) })
        owner.prepare(); return (owner, service, location, storage, scope)
    }
    private func walk(_ owner: RoamLiveSessionController, _ location: LiveLocation) async throws -> [RoamHistoryPoint] {
        await owner.start(purposeAccepted: true)
        location.value = try RoamDeviceFix(coordinate: XCTUnwrap(RoamCoordinate(latitude: 31.2001, longitude: 121.4001)),
            accuracyMeters: 10, measuredAt: date.addingTimeInterval(1), datum: .gcj02)
        await owner.pulse()
        let points = try XCTUnwrap(owner.currentRouteTrack); XCTAssertEqual(points.count, 2); return points
    }
    func testOnlyFullyArchivedFinishPublishesExactMemoryWithoutPersistingTrackOrExtraWork() async throws {
        let (owner, service, location, storage, scope) = try fixture()
        XCTAssertNil(owner.finishedRouteTrack)
        let points = try await walk(owner, location); XCTAssertNil(owner.finishedRouteTrack)
        await owner.finish()
        XCTAssertEqual(owner.phase, .finished); XCTAssertNil(owner.record); XCTAssertTrue(owner.track.isEmpty)
        XCTAssertEqual(owner.finishedRouteTrack, points)
        XCTAssertNil(try RoamLiveJournal(storage: storage).read(scope: scope))
        XCTAssertEqual(try owner.makeFinishedHistoryReader().history().first?.track, [])
        let bytes = storage.bytes, fixes = location.calls, reads = service.base.reads, reveals = service.base.reveals
        for _ in 0..<3 { XCTAssertEqual(owner.finishedRouteTrack, points) }
        XCTAssertEqual(bytes, storage.bytes); XCTAssertEqual(fixes, location.calls)
        XCTAssertEqual(reads, service.base.reads); XCTAssertEqual(reveals, service.base.reveals); XCTAssertEqual(service.base.finishes, 1)
        for data in bytes.values {
            let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertNil(fields["finishedRoute"]); XCTAssertNil((fields["record"] as? [String: Any])?["track"])
        }
    }
    func testBothArchiveFailuresKeepRouteUnavailableAndRecoveryDoesNotRedispatchFinish() async throws {
        for failure in [FinishedRouteStorage.Failure.history, .clear] {
            let (owner, service, location, storage, _) = try fixture(); _ = try await walk(owner, location)
            storage.failure = failure; await owner.finish()
            XCTAssertNotEqual(owner.phase, .finished); XCTAssertNil(owner.finishedRouteTrack); XCTAssertNil(owner.completedHistory)
            XCTAssertNotNil(owner.record); XCTAssertNotNil(owner.error)
            storage.failure = nil; await owner.recover()
            XCTAssertEqual(owner.phase, .finished); XCTAssertNotNil(owner.finishedRouteTrack)
            XCTAssertEqual(service.base.finishes, 1)
        }
    }
    func testWrongSessionWrongKeyAndIncompleteFactsCannotExposeFinishedRoute() async throws {
        for (id, key, complete) in [(99, String(repeating: "a", count: 32), true), (12, String(repeating: "b", count: 32), true), (12, String(repeating: "a", count: 32), false)] {
            let (owner, service, location, _, _) = try fixture(); _ = try await walk(owner, location)
            service.response = try service.base.decode(RoamSessionFact.self,
                "{\"state\":\"FINISHED\",\"sessionId\":\(id),\"clientSessionKey\":\"\(key)\",\"resultComplete\":\(complete),\"result\":{\"tileXp\":1,\"poiXp\":0,\"totalXp\":1,\"newTiles\":1,\"newPois\":0,\"tilesEver\":1,\"sessionShops\":0}}")
            await owner.finish(); XCTAssertNotEqual(owner.phase, .finished); XCTAssertNil(owner.finishedRouteTrack)
        }
    }
    func testRestoredFinishedRecordHasExplicitlyMissingRouteAndDoesNotAcquireFix() async throws {
        let (owner, service, location, storage, _) = try fixture(); _ = try await walk(owner, location)
        service.base.failFinish = true; await owner.finish()
        let restored = RoamLiveSessionController(service: service, location: location, journal: .init(storage: storage),
            history: RoamHistoryStore(storage: storage, currentScope: { service.identity?.scope }), now: { self.date })
        restored.prepare(); service.base.factState = "FINISHED"
        let fixes = location.calls, writes = service.base.finishes
        await restored.recover()
        XCTAssertEqual(restored.phase, .finished); XCTAssertEqual(restored.finishedRouteTrack, [])
        XCTAssertEqual(location.calls, fixes); XCTAssertEqual(service.base.finishes, writes)
    }
    func testOwnerEpochAccountAndApprovalChangesRetireRatherThanReviveOldRoute() async throws {
        for mutation in 0..<4 {
            let (owner, service, location, _, scope) = try fixture(); _ = try await walk(owner, location); await owner.finish()
            let identity = try XCTUnwrap(service.identity)
            if mutation == 0 { service.identity = .init(scope: scope, epoch: 2) }
            if mutation == 1 { service.identity = .init(scope: try RoamHistoryScope(market: "cn", deployment: XCTUnwrap(URL(string: scope.deployment)), accountID: 8), epoch: 1) }
            if mutation == 2 { service.identity = nil }
            if mutation == 3 { service.base.isAvailable = false }
            XCTAssertNil(owner.finishedRouteTrack)
            service.identity = identity; service.base.isAvailable = true
            XCTAssertEqual(owner.finishedRouteTrack, [])
        }
    }
    func testPauseBackgroundAndInvalidateRetireFinishedRouteWithoutRestartOrStorageChange() async throws {
        for mutation in 0..<3 {
            let (owner, service, location, storage, _) = try fixture(); _ = try await walk(owner, location); await owner.finish()
            let bytes = storage.bytes, fixes = location.calls, reads = service.base.reads
            if mutation == 0 { owner.pause(); XCTAssertEqual(owner.finishedRouteTrack, []) }
            if mutation == 1 {
                owner.setForeground(false); XCTAssertNil(owner.finishedRouteTrack)
                owner.setForeground(true); XCTAssertEqual(owner.phase, .finished); XCTAssertEqual(owner.finishedRouteTrack, [])
            }
            if mutation == 2 { owner.invalidate(); XCTAssertNil(owner.finishedRouteTrack) }
            XCTAssertEqual(storage.bytes, bytes); XCTAssertEqual(location.calls, fixes); XCTAssertEqual(service.base.reads, reads)
        }
    }
    func testDepartureOrOwnerChangeDuringFactCannotPublishOldReply() async throws {
        for switchOwner in [false, true] {
            let (owner, service, location, _, scope) = try fixture(); _ = try await walk(owner, location)
            service.onFact = {
                if switchOwner { service.identity = .init(scope: scope, epoch: 2) } else { owner.pause() }
            }
            await owner.finish()
            XCTAssertNil(owner.finishedRouteTrack); XCTAssertNil(owner.completedHistory)
        }
    }
    func testReentrantStorageDepartureCannotRecaptureRetiredPointsAfterClear() async throws {
        let (owner, _, location, storage, _) = try fixture(); _ = try await walk(owner, location)
        storage.onArchiveWrite = { owner.pause(); XCTAssertNil(owner.finishedRouteTrack) }
        await owner.finish()
        // Existing persistence outcome is untouched; optional route publication fails closed.
        XCTAssertEqual(owner.finishedRouteTrack, []); XCTAssertTrue(owner.track.isEmpty)
    }
}

@MainActor extension RoamFinishedRouteTests {
    func testCanceledFactReadCannotPublishRouteOrMutateArchivedHistory() async throws {
        let (owner, service, location, storage, _) = try fixture(); _ = try await walk(owner, location)
        service.onFact = { withUnsafeCurrentTask { $0?.cancel() } }
        let task = Task { await owner.finish() }; await task.value
        XCTAssertNil(owner.completedHistory); XCTAssertNil(owner.finishedRouteTrack)
        XCTAssertFalse(storage.bytes.keys.contains { $0.hasPrefix("roam-history-v1-") })
        XCTAssertNotNil(owner.record); XCTAssertEqual(service.base.finishes, 1)
    }
}
