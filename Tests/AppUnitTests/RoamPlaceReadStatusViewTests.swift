import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class RoamPlaceReadStatusViewTests: XCTestCase {
    private func item() throws -> RoamMapItem {
        .place(try JSONDecoder().decode(RoamPlace.self,
            from: Data(#"{"id":11,"type":2,"name":"Synthetic","found":true,"pendingRedeem":true}"#.utf8)))
    }
    func testRetainedAndDefaultRowsCannotAccidentallyExposeCurrentFactBadges() throws {
        XCTAssertFalse(try RoamItemRow(item: item()).showsCurrentReadStatus)
        XCTAssertFalse(try RoamItemRow(item: item(), navigable: false).showsCurrentReadStatus)
        XCTAssertTrue(try RoamItemRow(item: item(), showsCurrentReadStatus: true).showsCurrentReadStatus)
    }
    func testUnknownAndKnownFieldsUseIndependentReadOnlyLabels() {
        let unknown = RoamPlaceReadStatusLabel(status: .init(found: nil, pendingRedeem: nil))
        XCTAssertEqual(unknown.discoveryKey, "roamPlaceRead.discoveryUnknown")
        XCTAssertEqual(unknown.redemptionKey, "roamPlaceRead.redemptionUnknown")
        let independent = RoamPlaceReadStatusLabel(status: .init(found: false, pendingRedeem: true))
        XCTAssertEqual(independent.discoveryKey, "roamPlaceRead.notDiscovered")
        XCTAssertEqual(independent.redemptionKey, "roamPlaceRead.pending")
    }
    func testReadOnlyLabelBuildsWithoutReaderOrRewardAction() {
        let host = UIHostingController(rootView: RoamPlaceReadStatusLabel(status: .init(found: true, pendingRedeem: true))
            .environment(\.dynamicTypeSize, .accessibility3))
        host.loadViewIfNeeded(); host.view.layoutIfNeeded()
        XCTAssertNotNil(host.view)
    }
}

@MainActor private final class RoamCoverageUIStorage: RoamHistoryDataStoring {
    var bytes: [String: Data] = [:]
    var writes = 0
    func read(key: String) throws -> Data? { bytes[key] }
    func write(_ data: Data, key: String) throws { writes += 1; bytes[key] = data }
}
@MainActor private final class RoamCoverageUILocation: RoamDeviceLocationProviding {
    let value: RoamDeviceFix
    var calls = 0
    init(date: Date) throws {
        value = try RoamDeviceFix(coordinate: XCTUnwrap(RoamCoordinate(latitude: 31.2, longitude: 121.4)),
                                  accuracyMeters: 10, measuredAt: date, datum: .gcj02)
    }
    func currentFix() async throws -> RoamDeviceFix { calls += 1; return value }
    func stop() {}
}
@MainActor private final class RoamCoverageUIService: RoamLiveServing {
    let captured: RoamExperienceIdentity
    var identity: RoamExperienceIdentity?
    var enabled = true
    var isAvailable: Bool { enabled && identity == captured }
    var presenceAvailable: Bool { false }
    var calls = 0
    init(identity: RoamExperienceIdentity) { captured = identity; self.identity = identity }
    private func decode<T: Decodable>(_ type: T.Type, _ text: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(text.utf8))
    }
    func reveal(sessionID: Int?, clientSessionKey: String, tiles: [String]) async throws -> RoamLiveRevealReceipt {
        calls += 1
        return try decode(RoamLiveRevealReceipt.self, #"{"sessionId":12,"newlyRevealed":0}"#)
    }
    func fact(key: String) async throws -> RoamSessionFact {
        calls += 1
        return try decode(RoamSessionFact.self, "{\"state\":\"ACTIVE\",\"sessionId\":12,\"clientSessionKey\":\"\(key)\"}")
    }
    func places(fix: RoamDeviceFix) async throws -> [RoamPlace] { calls += 1; return [] }
    func registeredShops(fix: RoamDeviceFix) async throws -> [RoamRouteNode] { calls += 1; return [] }
    func discover(sessionID: Int, poiID: Int, fix: RoamDeviceFix) async throws -> RoamLiveDiscoveryReceipt {
        calls += 1; throw APIError.notConfigured
    }
    func shopVisit(sessionID: Int, sourceType: Int, sourceID: Int, fix: RoamDeviceFix) async throws -> RoamLiveShopReceipt {
        calls += 1; throw APIError.notConfigured
    }
    func presence(sessionID: Int, fix: RoamDeviceFix, explorationPercent: Int) async throws {
        calls += 1; throw APIError.notConfigured
    }
    func finish(sessionID: Int, poiIDs: [Int], distanceMeters: Int) async throws {
        calls += 1; throw APIError.notConfigured
    }
}

@MainActor final class RoamLiveCoverageViewTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_790_932_200)
    private let key = String(repeating: "a", count: 32)
    private func fixture(record: Bool = false, finishRequested: Bool = false, pending: RoamLivePending? = nil) throws
        -> (RoamLiveSessionController, RoamCoverageUIService, RoamCoverageUILocation, RoamCoverageUIStorage) {
        let scope = try RoamHistoryScope(market: "cn", deployment: XCTUnwrap(URL(string: "https://coverage.example/api/")), accountID: 7)
        let identity = RoamExperienceIdentity(scope: scope, epoch: 1)
        let service = RoamCoverageUIService(identity: identity), location = try RoamCoverageUILocation(date: date)
        let storage = RoamCoverageUIStorage(), journal = RoamLiveJournal(storage: storage)
        if record {
            var value = RoamLiveRecord(scope: scope, clientSessionKey: key, startedAt: date)
            value.sessionID = 12; value.allTiles = ["wtw3sjq"]
            value.finishRequested = finishRequested; value.pendingWrite = pending
            try journal.write(value)
        }
        let owner = RoamLiveSessionController(service: service, location: location, journal: journal,
            now: { self.date }, key: { self.key })
        owner.prepare()
        return (owner, service, location, storage)
    }
    func testCurrentAcceptedSamplesShowExistingPercentWithoutAdditionalWork() async throws {
        let (owner, service, location, storage) = try fixture()
        XCTAssertNil(RoamLiveCoveragePresentation(controller: owner).percentage)
        await owner.start(purposeAccepted: true)
        XCTAssertEqual(owner.phase, .active); XCTAssertFalse(owner.track.isEmpty)
        let calls = service.calls, fixes = location.calls, writes = storage.writes, bytes = storage.bytes
        for _ in 0..<3 {
            let value = RoamLiveCoveragePresentation(controller: owner)
            XCTAssertEqual(value.percentage, owner.explorationPercent)
            XCTAssertEqual(value.value(locale: Locale(identifier: "en")), "\(owner.explorationPercent)%")
        }
        XCTAssertEqual(service.calls, calls); XCTAssertEqual(location.calls, fixes)
        XCTAssertEqual(storage.writes, writes); XCTAssertEqual(storage.bytes, bytes)
    }
    func testRecoveredTileCountDoesNotInventLocalOriginOrZeroPercent() async throws {
        let (owner, service, location, storage) = try fixture(record: true)
        XCTAssertFalse(try XCTUnwrap(owner.record).allTiles.isEmpty)
        XCTAssertNil(RoamLiveCoveragePresentation(controller: owner).percentage)
        await owner.recover()
        XCTAssertEqual(owner.phase, .paused); XCTAssertTrue(owner.track.isEmpty)
        let calls = service.calls, writes = storage.writes, bytes = storage.bytes
        let value = RoamLiveCoveragePresentation(controller: owner)
        XCTAssertNil(value.percentage)
        XCTAssertEqual(value.value(locale: Locale(identifier: "en")), "Unavailable")
        XCTAssertEqual(service.calls, calls); XCTAssertEqual(location.calls, 0)
        XCTAssertEqual(storage.writes, writes); XCTAssertEqual(storage.bytes, bytes)
    }
    func testPauseBackgroundOwnerEpochAndRevocationFenceTheDisplay() async throws {
        let (owner, service, location, _) = try fixture()
        await owner.start(purposeAccepted: true); owner.pause()
        XCTAssertEqual(RoamLiveCoveragePresentation(controller: owner).percentage, owner.explorationPercent)
        let calls = service.calls, fixes = location.calls
        owner.setForeground(false)
        XCTAssertNil(RoamLiveCoveragePresentation(controller: owner).percentage)
        owner.setForeground(true)
        XCTAssertNotNil(RoamLiveCoveragePresentation(controller: owner).percentage)
        service.identity = .init(scope: service.captured.scope, epoch: 2)
        XCTAssertNil(RoamLiveCoveragePresentation(controller: owner).percentage)
        service.identity = nil
        XCTAssertNil(RoamLiveCoveragePresentation(controller: owner).percentage)
        service.identity = service.captured; service.enabled = false
        XCTAssertNil(RoamLiveCoveragePresentation(controller: owner).percentage)
        owner.invalidate()
        XCTAssertNil(RoamLiveCoveragePresentation(controller: owner).percentage)
        XCTAssertEqual(service.calls, calls); XCTAssertEqual(location.calls, fixes)
    }
    func testUnknownPendingAndFinishIntentAreNotChangedByPresentation() throws {
        for pending in [RoamLivePending.reveal, .finish] {
            for finishedIntent in [false, true] {
                let (owner, service, location, storage) = try fixture(record: true, finishRequested: finishedIntent, pending: pending)
                let bytes = storage.bytes, writes = storage.writes
                XCTAssertNil(RoamLiveCoveragePresentation(controller: owner).percentage)
                XCTAssertEqual(owner.record?.pendingWrite, pending)
                XCTAssertEqual(owner.record?.finishRequested, finishedIntent)
                XCTAssertEqual(storage.bytes, bytes); XCTAssertEqual(storage.writes, writes)
                XCTAssertEqual(service.calls, 0); XCTAssertEqual(location.calls, 0)
            }
        }
    }
    func testEnglishChineseUnknownAndKnownRowsMountWithLargeText() async throws {
        let (owner, service, location, storage) = try fixture()
        let unknown = RoamLiveCoveragePresentation(controller: owner)
        await owner.start(purposeAccepted: true)
        let known = RoamLiveCoveragePresentation(controller: owner)
        let calls = service.calls, fixes = location.calls, writes = storage.writes
        for (identifier, title, placeholder) in [("en", "Local area explored", "Unavailable"), ("zh-Hans", "本地片区探索度", "暂无可靠数据")] {
            let locale = Locale(identifier: identifier), copy = RoamLiveCoverageCopy(locale: Locale(identifier: identifier))
            XCTAssertEqual(copy.title, title); XCTAssertEqual(unknown.value(locale: locale), placeholder)
            XCTAssertEqual(known.value(locale: locale), "\(owner.explorationPercent)%")
            XCTAssertTrue(copy.hint.contains(identifier == "en" ? "not citywide coverage" : "不代表全城覆盖"))
            for value in [unknown, known] {
                let host = UIHostingController(rootView: RoamLiveCoverageRow(presentation: value)
                    .environment(\.locale, locale).environment(\.dynamicTypeSize, .accessibility3))
                host.loadViewIfNeeded(); host.view.layoutIfNeeded()
                XCTAssertNotNil(host.view)
            }
        }
        XCTAssertEqual(service.calls, calls); XCTAssertEqual(location.calls, fixes); XCTAssertEqual(storage.writes, writes)
    }
}

@MainActor final class RoamForegroundElapsedViewTests: XCTestCase {
    func testKnownZeroAndMinuteBoundariesAreFormattedWithoutDates() {
        let copy = RoamLiveElapsedCopy(locale: Locale(identifier: "en"))
        for (seconds, value) in [(0, "00:00"), (9, "00:09"), (59, "00:59"), (60, "01:00"), (3661, "61:01")] {
            XCTAssertEqual(copy.value(seconds: seconds), value)
        }
        XCTAssertEqual(copy.value(seconds: nil), "Unavailable")
        XCTAssertEqual(copy.value(seconds: -1), "Unavailable")
    }
    func testEnglishChineseUnknownAndKnownRowsMountWithLargeText() {
        for (language, title, unknown) in [("en", "Foreground time", "Unavailable"), ("zh-Hans", "本次前台用时", "暂无可靠数据")] {
            let locale = Locale(identifier: language), copy = RoamLiveElapsedCopy(locale: locale)
            XCTAssertEqual(copy.title, title); XCTAssertEqual(copy.value(seconds: nil), unknown)
            XCTAssertTrue(copy.hint.contains(language == "en" ? "Recovery cannot restore" : "恢复记录无法还原"))
            for seconds in [nil, 0, 65] as [Int?] {
                let host = UIHostingController(rootView: RoamLiveElapsedRow(seconds: seconds)
                    .environment(\.locale, locale).environment(\.dynamicTypeSize, .accessibility3))
                host.loadViewIfNeeded(); host.view.layoutIfNeeded(); XCTAssertNotNil(host.view)
            }
        }
    }
    func testNormalLiveStatusRetainsCoverageAndHasReadOnlyElapsedValue() async throws {
        let date = Date(timeIntervalSince1970: 1_790_932_200)
        let scope = try RoamHistoryScope(market: "cn", deployment: URL(string: "https://elapsed-ui.example/native")!, accountID: 7)
        let service = RoamCoverageUIService(identity: .init(scope: scope, epoch: 1))
        let location = try RoamCoverageUILocation(date: date), storage = RoamCoverageUIStorage()
        var uptime: TimeInterval = 100
        let owner = RoamLiveSessionController(service: service, location: location, journal: .init(storage: storage),
            now: { date }, monotonicNow: { uptime })
        owner.prepare(); await owner.start(purposeAccepted: true); uptime = 165
        XCTAssertEqual(owner.localForegroundElapsedSeconds, 65)
        XCTAssertEqual(RoamLiveCoveragePresentation(controller: owner).percentage, owner.explorationPercent)
        let calls = service.calls, fixes = location.calls, bytes = storage.bytes, writes = storage.writes
        let host = UIHostingController(rootView: NavigationStack { RoamLiveSessionView(controller: owner) })
        host.loadViewIfNeeded(); host.view.layoutIfNeeded(); XCTAssertNotNil(host.view)
        _ = RoamLiveElapsedCopy(locale: Locale(identifier: "en")).value(seconds: owner.localForegroundElapsedSeconds)
        XCTAssertEqual(service.calls, calls); XCTAssertEqual(location.calls, fixes)
        XCTAssertEqual(storage.bytes, bytes); XCTAssertEqual(storage.writes, writes)
    }
}

@MainActor private final class RoamFinishedMedalsStorage: RoamHistoryDataStoring {
    enum Failure { case history, clear }
    var bytes: [String: Data] = [:]
    var writes = 0
    var failure: Failure?
    func read(key: String) throws -> Data? { bytes[key] }
    func write(_ data: Data, key: String) throws {
        writes += 1
        if failure == .history, key.hasPrefix("roam-history-v1-") { throw APIError.notConfigured }
        if failure == .clear, key.hasPrefix("roam-live-v1-"),
           let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           object["record"] == nil || object["record"] is NSNull { throw APIError.notConfigured }
        bytes[key] = data
    }
}
@MainActor private final class RoamFinishedMedalsLocation: RoamDeviceLocationProviding {
    var fixes = 0
    func currentFix() async throws -> RoamDeviceFix { fixes += 1; throw APIError.notConfigured }
    func stop() {}
}
@MainActor private final class RoamFinishedMedalsService: RoamLiveServing {
    let captured: RoamExperienceIdentity
    var identity: RoamExperienceIdentity?
    var enabled = true
    var isAvailable: Bool { enabled && identity == captured }
    var presenceAvailable: Bool { false }
    var factCalls = 0
    var mutations = 0
    var onFact: (() -> Void)?
    var response: RoamSessionFact
    init(identity: RoamExperienceIdentity, response: RoamSessionFact) {
        captured = identity; self.identity = identity; self.response = response
    }
    func fact(key: String) async throws -> RoamSessionFact { factCalls += 1; onFact?(); return response }
    func places(fix: RoamDeviceFix) async throws -> [RoamPlace] { throw APIError.notConfigured }
    func registeredShops(fix: RoamDeviceFix) async throws -> [RoamRouteNode] { throw APIError.notConfigured }
    func reveal(sessionID: Int?, clientSessionKey: String, tiles: [String]) async throws -> RoamLiveRevealReceipt {
        mutations += 1; throw APIError.notConfigured
    }
    func discover(sessionID: Int, poiID: Int, fix: RoamDeviceFix) async throws -> RoamLiveDiscoveryReceipt {
        mutations += 1; throw APIError.notConfigured
    }
    func shopVisit(sessionID: Int, sourceType: Int, sourceID: Int, fix: RoamDeviceFix) async throws -> RoamLiveShopReceipt {
        mutations += 1; throw APIError.notConfigured
    }
    func presence(sessionID: Int, fix: RoamDeviceFix, explorationPercent: Int) async throws {
        mutations += 1; throw APIError.notConfigured
    }
    func finish(sessionID: Int, poiIDs: [Int], distanceMeters: Int) async throws {
        mutations += 1; throw APIError.notConfigured
    }
}

@MainActor final class RoamFinishedMedalsViewTests: XCTestCase {
    private let key = String(repeating: "b", count: 32)
    private func fact(journey: String? = "Returned journey", shop: String? = "Returned shop",
                      complete: Bool = true, sessionID: Int = 12) throws -> RoamSessionFact {
        var result: [String: Any] = ["tileXp": 1, "poiXp": 2, "totalXp": 3,
            "newTiles": 1, "newPois": 1, "tilesEver": 1, "sessionShops": 1]
        if let journey { result["medal"] = journey }
        if let shop { result["shopMedal"] = ["code": "returned-code", "name": shop] }
        let object: [String: Any] = ["state": "FINISHED", "sessionId": sessionID,
            "clientSessionKey": key, "resultComplete": complete, "result": result]
        return try JSONDecoder().decode(RoamSessionFact.self, from: JSONSerialization.data(withJSONObject: object))
    }
    private func fixture(_ response: RoamSessionFact? = nil) throws
        -> (RoamLiveSessionController, RoamFinishedMedalsService, RoamFinishedMedalsStorage, RoamFinishedMedalsLocation) {
        let scope = try RoamHistoryScope(market: "cn", deployment: XCTUnwrap(URL(string: "https://medals.example/native/")), accountID: 7)
        let service = try RoamFinishedMedalsService(identity: .init(scope: scope, epoch: 1), response: response ?? fact())
        let storage = RoamFinishedMedalsStorage(), location = RoamFinishedMedalsLocation()
        let journal = RoamLiveJournal(storage: storage)
        var record = RoamLiveRecord(scope: scope, clientSessionKey: key, startedAt: Date(timeIntervalSince1970: 1_790_932_200))
        record.sessionID = 12; record.finishRequested = true
        try journal.write(record)
        let history = RoamHistoryStore(storage: storage, currentScope: { service.identity?.scope })
        let owner = RoamLiveSessionController(service: service, location: location, journal: journal, history: history)
        owner.prepare()
        return (owner, service, storage, location)
    }
    func testOnlySavedCompleteCurrentSettlementExposesProvidedMedalsWithoutWork() async throws {
        let (owner, service, storage, location) = try fixture()
        XCTAssertNil(RoamFinishedMedalsPresentation(controller: owner))
        await owner.recover()
        XCTAssertEqual(owner.phase, .finished); XCTAssertNil(owner.record)
        XCTAssertEqual(owner.completedHistory?.serverSessionID, 12)
        let value = try XCTUnwrap(RoamFinishedMedalsPresentation(controller: owner))
        XCTAssertEqual(value.journey, "Returned journey"); XCTAssertEqual(value.shop, "Returned shop")
        let calls = service.factCalls, writes = storage.writes, bytes = storage.bytes
        for _ in 0..<3 { XCTAssertEqual(RoamFinishedMedalsPresentation(controller: owner), value) }
        XCTAssertEqual(service.factCalls, calls); XCTAssertEqual(service.mutations, 0); XCTAssertEqual(location.fixes, 0)
        XCTAssertEqual(storage.writes, writes); XCTAssertEqual(storage.bytes, bytes)
    }
    func testMissingAndBlankFieldsRemainUnavailableWithoutZeroOrNameFallback() async throws {
        for strings in [(nil, nil), (" \n", nil)] as [(String?, String?)] {
            let (owner, service, _, location) = try fixture(fact(journey: strings.0, shop: strings.1))
            await owner.recover()
            let value = try XCTUnwrap(RoamFinishedMedalsPresentation(controller: owner))
            XCTAssertNil(value.journey); XCTAssertNil(value.shop)
            XCTAssertEqual(service.mutations, 0); XCTAssertEqual(location.fixes, 0)
        }
    }
    func testJourneyAndShopFieldsAreIndependentAndNeverSubstituteEachOther() async throws {
        for strings in [("Journey only", nil), (nil, "Shop only")] as [(String?, String?)] {
            let (owner, _, _, _) = try fixture(fact(journey: strings.0, shop: strings.1))
            await owner.recover()
            let value = try XCTUnwrap(RoamFinishedMedalsPresentation(controller: owner))
            XCTAssertEqual(value.journey, strings.0); XCTAssertEqual(value.shop, strings.1)
        }
    }
    func testHistoryAndJournalClearFailuresCannotPublishMedalSummary() async throws {
        for failure in [RoamFinishedMedalsStorage.Failure.history, .clear] {
            let (owner, service, storage, location) = try fixture(); storage.failure = failure
            await owner.recover()
            XCTAssertTrue(owner.settlement?.hasCompleteSettlement == true)
            XCTAssertNotEqual(owner.phase, .finished); XCTAssertNil(owner.completedHistory)
            let writes = storage.writes, bytes = storage.bytes
            XCTAssertNil(RoamFinishedMedalsPresentation(controller: owner))
            XCTAssertEqual(storage.writes, writes); XCTAssertEqual(storage.bytes, bytes)
            XCTAssertEqual(service.mutations, 0); XCTAssertEqual(location.fixes, 0)
        }
    }
    func testIncompleteAndWrongSessionRepliesCannotPublishMedalSummary() async throws {
        for response in [try fact(complete: false), try fact(sessionID: 99)] {
            let (owner, service, storage, location) = try fixture(response)
            await owner.recover()
            XCTAssertNil(owner.completedHistory); XCTAssertNil(RoamFinishedMedalsPresentation(controller: owner))
            let writes = storage.writes, bytes = storage.bytes
            _ = RoamFinishedMedalsPresentation(controller: owner)
            XCTAssertEqual(storage.writes, writes); XCTAssertEqual(storage.bytes, bytes)
            XCTAssertEqual(service.mutations, 0); XCTAssertEqual(location.fixes, 0)
        }
    }
    func testBackgroundEpochAccountRevocationAndRetirementHideExistingResult() async throws {
        let (owner, service, storage, location) = try fixture(); await owner.recover()
        XCTAssertNotNil(RoamFinishedMedalsPresentation(controller: owner))
        let writes = storage.writes, bytes = storage.bytes, calls = service.factCalls
        owner.setForeground(false); XCTAssertNil(RoamFinishedMedalsPresentation(controller: owner))
        owner.setForeground(true); XCTAssertNotNil(RoamFinishedMedalsPresentation(controller: owner))
        service.identity = .init(scope: service.captured.scope, epoch: 2)
        XCTAssertNil(RoamFinishedMedalsPresentation(controller: owner))
        let other = try RoamHistoryScope(market: "cn", deployment: XCTUnwrap(URL(string: "https://medals.example/native/")), accountID: 8)
        service.identity = .init(scope: other, epoch: 1)
        XCTAssertNil(RoamFinishedMedalsPresentation(controller: owner))
        service.identity = service.captured; service.enabled = false
        XCTAssertNil(RoamFinishedMedalsPresentation(controller: owner))
        service.enabled = true; owner.invalidate()
        XCTAssertNil(RoamFinishedMedalsPresentation(controller: owner))
        XCTAssertEqual(storage.writes, writes); XCTAssertEqual(storage.bytes, bytes)
        XCTAssertEqual(service.factCalls, calls); XCTAssertEqual(service.mutations, 0); XCTAssertEqual(location.fixes, 0)
    }
    func testLatePreviousOwnerFactCannotRestoreFinishedMedals() async throws {
        let (owner, service, storage, location) = try fixture()
        let bytes = storage.bytes, writes = storage.writes
        service.onFact = { service.identity = .init(scope: service.captured.scope, epoch: 2) }
        await owner.recover()
        XCTAssertNil(owner.completedHistory); XCTAssertNil(RoamFinishedMedalsPresentation(controller: owner))
        XCTAssertEqual(storage.bytes, bytes); XCTAssertEqual(storage.writes, writes)
        XCTAssertEqual(service.mutations, 0); XCTAssertEqual(location.fixes, 0)
    }
    func testNormalFinishedHostAndBothLocalesKeepIndependentUnknownLabels() async throws {
        let (owner, service, storage, location) = try fixture(fact(journey: "Source journey", shop: nil))
        await owner.recover(); let value = try XCTUnwrap(RoamFinishedMedalsPresentation(controller: owner))
        let calls = service.factCalls, writes = storage.writes, bytes = storage.bytes
        for (language, journey, shop, unknown) in [
            ("en", "Journey medal", "Shop medal", "Not provided in this settlement"),
            ("zh-Hans", "漫游勋章", "探店勋章", "本次结算未提供")
        ] {
            let locale = Locale(identifier: language), copy = RoamFinishedMedalsCopy(locale: locale)
            XCTAssertEqual(copy.journey, journey); XCTAssertEqual(copy.shop, shop); XCTAssertEqual(copy.unavailable, unknown)
            XCTAssertTrue(copy.hint.contains(language == "en" ? "missing field does not mean" : "缺失字段不代表"))
            let section = UIHostingController(rootView: List { RoamFinishedMedalsSection(presentation: value) }
                .environment(\.locale, locale).environment(\.dynamicTypeSize, .accessibility3))
            section.loadViewIfNeeded(); section.view.layoutIfNeeded(); XCTAssertNotNil(section.view)
            let normal = UIHostingController(rootView: NavigationStack { RoamLiveSessionView(controller: owner) }
                .environment(\.locale, locale).environment(\.dynamicTypeSize, .accessibility3))
            normal.loadViewIfNeeded(); normal.view.layoutIfNeeded(); XCTAssertNotNil(normal.view)
        }
        XCTAssertEqual(service.factCalls, calls); XCTAssertEqual(service.mutations, 0); XCTAssertEqual(location.fixes, 0)
        XCTAssertEqual(storage.writes, writes); XCTAssertEqual(storage.bytes, bytes)
    }
}
