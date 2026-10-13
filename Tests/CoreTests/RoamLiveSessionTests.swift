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
