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

@MainActor private final class RoamPlaceMemoryUIService: RoamLiveServing {
    let base: RoamCoverageUIService
    let row: RoamPlace
    var identity: RoamExperienceIdentity? { base.identity }
    var isAvailable: Bool { base.isAvailable }
    var presenceAvailable: Bool { false }
    var discoveries = 0
    init(identity: RoamExperienceIdentity) throws {
        base = RoamCoverageUIService(identity: identity)
        row = try JSONDecoder().decode(RoamPlace.self,
            from: Data(#"{"id":6,"type":1,"lat":31.2,"lng":121.4,"name":"Returned place"}"#.utf8))
    }
    func reveal(sessionID: Int?, clientSessionKey: String, tiles: [String]) async throws -> RoamLiveRevealReceipt {
        try await base.reveal(sessionID: sessionID, clientSessionKey: clientSessionKey, tiles: tiles)
    }
    func fact(key: String) async throws -> RoamSessionFact { try await base.fact(key: key) }
    func places(fix: RoamDeviceFix) async throws -> [RoamPlace] { [row] }
    func registeredShops(fix: RoamDeviceFix) async throws -> [RoamRouteNode] { [] }
    func discover(sessionID: Int, poiID: Int, fix: RoamDeviceFix) async throws -> RoamLiveDiscoveryReceipt {
        discoveries += 1
        return try JSONDecoder().decode(RoamLiveDiscoveryReceipt.self,
            from: Data(#"{"discovered":false,"poiId":6,"meaning":"Returned place description"}"#.utf8))
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
@MainActor final class RoamPlaceMemoryViewTests: XCTestCase {
    func testLocalLabelsAndProvidedTextMountInBothLanguagesWithLargeText() {
        for (language, title, close) in [("en", "Place memory", "Close place note"), ("zh-Hans", "地点记忆", "关闭地点提示")] {
            let locale = Locale(identifier: language), copy = RoamPlaceMemoryCopy(locale: locale)
            XCTAssertEqual(copy.title, title); XCTAssertEqual(copy.close, close)
            var closes = 0
            let section = RoamPlaceMemorySection(placeName: "Returned place", text: "  Cafe\u{301} memory\n", close: { closes += 1 })
            XCTAssertEqual(Array(section.text.utf8), Array("  Cafe\u{301} memory\n".utf8))
            let host = UIHostingController(rootView: List { section }
                .environment(\.locale, locale).environment(\.dynamicTypeSize, .accessibility3))
            host.loadViewIfNeeded(); host.view.layoutIfNeeded(); XCTAssertNotNil(host.view); XCTAssertEqual(closes, 0)
            section.close(); XCTAssertEqual(closes, 1)
        }
    }
    func testNormalLiveHostUsesCurrentReceiptAndClosingDoesNoProviderWork() async throws {
        let date = Date(timeIntervalSince1970: 1_790_932_200)
        let scope = try RoamHistoryScope(market: "cn", deployment: XCTUnwrap(URL(string: "https://memory-ui.example/native/")), accountID: 7)
        let service = try RoamPlaceMemoryUIService(identity: .init(scope: scope, epoch: 1))
        let storage = RoamCoverageUIStorage(), location = try RoamCoverageUILocation(date: date)
        let owner = RoamLiveSessionController(service: service, location: location, journal: .init(storage: storage), now: { date })
        owner.prepare(); await owner.start(purposeAccepted: true); await owner.discover(service.row)
        let value = try XCTUnwrap(owner.placeMemory)
        let calls = service.base.calls, discoveries = service.discoveries, fixes = location.calls, bytes = storage.bytes
        let host = UIHostingController(rootView: NavigationStack { RoamLiveSessionView(controller: owner) })
        host.loadViewIfNeeded(); host.view.layoutIfNeeded(); XCTAssertNotNil(host.view)
        let row = RoamPlaceMemorySection(placeName: value.placeName, text: value.text) { owner.dismissPlaceMemory(id: value.id) }
        XCTAssertNotNil(owner.placeMemory); row.close(); XCTAssertNil(owner.placeMemory)
        XCTAssertEqual(service.base.calls, calls); XCTAssertEqual(service.discoveries, discoveries)
        XCTAssertEqual(location.calls, fixes); XCTAssertEqual(storage.bytes, bytes)
    }
}

@MainActor final class RoamFinishedStoryViewTests: XCTestCase {
    private let key = String(repeating: "c", count: 32)
    private func fact(_ story: Any? = "Returned reflection", complete: Bool = true,
                      sessionID: Int = 12) throws -> RoamSessionFact {
        var result: [String: Any] = ["tileXp": 1, "poiXp": 2, "totalXp": 3,
            "newTiles": 1, "newPois": 1, "tilesEver": 1, "sessionShops": 1]
        if let story { result["routeStory"] = story }
        let object: [String: Any] = ["state": "FINISHED", "sessionId": sessionID,
            "clientSessionKey": key, "resultComplete": complete, "result": result]
        return try JSONDecoder().decode(RoamSessionFact.self, from: JSONSerialization.data(withJSONObject: object))
    }
    private func fixture(_ response: RoamSessionFact? = nil) throws
        -> (RoamLiveSessionController, RoamFinishedMedalsService, RoamFinishedMedalsStorage, RoamFinishedMedalsLocation) {
        let scope = try RoamHistoryScope(market: "cn", deployment: XCTUnwrap(URL(string: "https://story.example/native/")), accountID: 7)
        let service = try RoamFinishedMedalsService(identity: .init(scope: scope, epoch: 1), response: response ?? fact())
        let storage = RoamFinishedMedalsStorage(), location = RoamFinishedMedalsLocation()
        let journal = RoamLiveJournal(storage: storage)
        var record = RoamLiveRecord(scope: scope, clientSessionKey: key, startedAt: Date(timeIntervalSince1970: 1_790_932_200))
        record.sessionID = 12; record.finishRequested = true
        try journal.write(record)
        let history = RoamHistoryStore(storage: storage, currentScope: { service.identity?.scope })
        let owner = RoamLiveSessionController(service: service, location: location, journal: journal, history: history)
        owner.prepare(); return (owner, service, storage, location)
    }
    func testOnlyCurrentSavedCompleteSettlementShowsStoryWithoutAdditionalWork() async throws {
        let (owner, service, storage, location) = try fixture()
        XCTAssertNil(RoamFinishedStoryPresentation(controller: owner))
        await owner.recover()
        XCTAssertEqual(owner.phase, .finished); XCTAssertNil(owner.record)
        XCTAssertEqual(owner.completedHistory?.serverSessionID, 12)
        let value = try XCTUnwrap(RoamFinishedStoryPresentation(controller: owner))
        XCTAssertEqual(value.text, "Returned reflection")
        let calls = service.factCalls, writes = storage.writes, bytes = storage.bytes
        for _ in 0..<3 { XCTAssertEqual(RoamFinishedStoryPresentation(controller: owner), value) }
        XCTAssertEqual(service.factCalls, calls); XCTAssertEqual(service.mutations, 0); XCTAssertEqual(location.fixes, 0)
        XCTAssertEqual(storage.writes, writes); XCTAssertEqual(storage.bytes, bytes)
    }
    func testMissingNullEmptyAndWrongTypeHaveNoFallbackButStillFinish() async throws {
        for text in [nil, NSNull(), "", " \n", 2, ["text": "Do not coerce"]] as [Any?] {
            let (owner, service, _, location) = try fixture(fact(text))
            await owner.recover()
            XCTAssertEqual(owner.phase, .finished); XCTAssertNotNil(owner.completedHistory)
            XCTAssertNil(RoamFinishedStoryPresentation(controller: owner))
            XCTAssertEqual(owner.settlement?.result?.totalXp, 3)
            XCTAssertEqual(service.mutations, 0); XCTAssertEqual(location.fixes, 0)
        }
    }
    func testArchiveOrJournalClearFailureCannotShowStory() async throws {
        for failure in [RoamFinishedMedalsStorage.Failure.history, .clear] {
            let (owner, service, storage, location) = try fixture(); storage.failure = failure
            await owner.recover()
            XCTAssertTrue(owner.settlement?.hasCompleteSettlement == true)
            XCTAssertNotEqual(owner.phase, .finished); XCTAssertNil(owner.completedHistory)
            let writes = storage.writes, bytes = storage.bytes
            XCTAssertNil(RoamFinishedStoryPresentation(controller: owner))
            XCTAssertEqual(storage.writes, writes); XCTAssertEqual(storage.bytes, bytes)
            XCTAssertEqual(service.mutations, 0); XCTAssertEqual(location.fixes, 0)
        }
    }
    func testIncompleteWrongSessionAndLateOwnerFactCannotShowStory() async throws {
        for response in [try fact(complete: false), try fact(sessionID: 99)] {
            let (owner, service, _, location) = try fixture(response); await owner.recover()
            XCTAssertNil(owner.completedHistory); XCTAssertNil(RoamFinishedStoryPresentation(controller: owner))
            XCTAssertEqual(service.mutations, 0); XCTAssertEqual(location.fixes, 0)
        }
        let (owner, service, storage, location) = try fixture()
        let bytes = storage.bytes, writes = storage.writes
        service.onFact = { service.identity = .init(scope: service.captured.scope, epoch: 2) }
        await owner.recover()
        XCTAssertNil(owner.completedHistory); XCTAssertNil(RoamFinishedStoryPresentation(controller: owner))
        XCTAssertEqual(storage.bytes, bytes); XCTAssertEqual(storage.writes, writes)
        XCTAssertEqual(service.mutations, 0); XCTAssertEqual(location.fixes, 0)
    }
    func testBackgroundAccountEpochRevocationAndInvalidationHideFinishedStory() async throws {
        let (owner, service, storage, location) = try fixture(); await owner.recover()
        XCTAssertNotNil(RoamFinishedStoryPresentation(controller: owner))
        let writes = storage.writes, bytes = storage.bytes, calls = service.factCalls
        owner.setForeground(false); XCTAssertNil(RoamFinishedStoryPresentation(controller: owner))
        owner.setForeground(true); XCTAssertNotNil(RoamFinishedStoryPresentation(controller: owner))
        service.identity = .init(scope: service.captured.scope, epoch: 2)
        XCTAssertNil(RoamFinishedStoryPresentation(controller: owner))
        let other = try RoamHistoryScope(market: "cn", deployment: XCTUnwrap(URL(string: "https://story.example/native/")), accountID: 8)
        service.identity = .init(scope: other, epoch: 1)
        XCTAssertNil(RoamFinishedStoryPresentation(controller: owner))
        service.identity = service.captured; service.enabled = false
        XCTAssertNil(RoamFinishedStoryPresentation(controller: owner))
        service.enabled = true; owner.invalidate()
        XCTAssertNil(RoamFinishedStoryPresentation(controller: owner))
        XCTAssertEqual(storage.writes, writes); XCTAssertEqual(storage.bytes, bytes)
        XCTAssertEqual(service.factCalls, calls); XCTAssertEqual(service.mutations, 0); XCTAssertEqual(location.fixes, 0)
    }
    func testNormalFinishedHostAndStorySectionUseBothLanguagesWithLargeText() async throws {
        let text = "  Returned e\u{301} reflection 👩🏽‍🚀\n"
        let (owner, service, storage, location) = try fixture(fact(text)); await owner.recover()
        let value = try XCTUnwrap(RoamFinishedStoryPresentation(controller: owner))
        XCTAssertEqual(Array(value.text.utf8), Array(text.utf8))
        let calls = service.factCalls, writes = storage.writes, bytes = storage.bytes
        for (language, title) in [("en", "This walk"), ("zh-Hans", "这段足迹")] {
            let locale = Locale(identifier: language), copy = RoamFinishedStoryCopy(locale: Locale(identifier: language))
            XCTAssertEqual(copy.title, title)
            XCTAssertTrue(copy.hint.contains(language == "en" ? "saved settlement" : "已保存的结算"))
            let section = UIHostingController(rootView: List { RoamFinishedStorySection(presentation: value) }
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

@MainActor final class RoamLiveMerchantDescriptionViewTests: XCTestCase {
    func testBothLanguagesAndLargeTextShowReadOnlyDescription() {
        let description = "Returned merchant text e\u{301}\nNo generated information"
        for (language, title) in [("en", "About this merchant"), ("zh-Hans", "商家介绍")] {
            let locale = Locale(identifier: language)
            XCTAssertEqual(RoamLiveMerchantDescriptionCopy(locale: locale).title, title)
            let row = RoamLiveMerchantDescriptionRow(text: description)
            XCTAssertEqual(Array(row.text.utf8), Array(description.utf8))
            let host = UIHostingController(rootView: List { row }
                .environment(\.locale, locale).environment(\.dynamicTypeSize, .accessibility3))
            host.loadViewIfNeeded(); host.view.layoutIfNeeded(); XCTAssertNotNil(host.view)
        }
    }
}

@MainActor private final class RoamMerchantDescriptionUIService: RoamLiveServing {
    let base: RoamCoverageUIService
    let row: RoamPlace
    var identity: RoamExperienceIdentity? { base.identity }
    var isAvailable: Bool { base.isAvailable }
    var presenceAvailable: Bool { false }
    init(identity: RoamExperienceIdentity) throws {
        base = RoamCoverageUIService(identity: identity)
        row = try JSONDecoder().decode(RoamPlace.self,
            from: Data(#"{"id":6,"type":2,"name":"Merchant","description":"Provided merchant information","lat":31.2,"lng":121.4}"#.utf8))
    }
    func places(fix: RoamDeviceFix) async throws -> [RoamPlace] { base.calls += 1; return [row] }
    func registeredShops(fix: RoamDeviceFix) async throws -> [RoamRouteNode] { [] }
    func reveal(sessionID: Int?, clientSessionKey: String, tiles: [String]) async throws -> RoamLiveRevealReceipt {
        try await base.reveal(sessionID: sessionID, clientSessionKey: clientSessionKey, tiles: tiles)
    }
    func fact(key: String) async throws -> RoamSessionFact { try await base.fact(key: key) }
    func discover(sessionID: Int, poiID: Int, fix: RoamDeviceFix) async throws -> RoamLiveDiscoveryReceipt {
        try await base.discover(sessionID: sessionID, poiID: poiID, fix: fix)
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
@MainActor final class RoamLiveMerchantDescriptionHostTests: XCTestCase {
    func testNormalActiveNearbyHostMountsWithoutAdditionalRequestOrMutation() async throws {
        let date = Date(timeIntervalSince1970: 1_790_932_200)
        let scope = try RoamHistoryScope(market: "cn", deployment: XCTUnwrap(URL(string: "https://merchant-description-ui.example/native/")), accountID: 7)
        let service = try RoamMerchantDescriptionUIService(identity: .init(scope: scope, epoch: 1))
        let location = try RoamCoverageUILocation(date: date), storage = RoamCoverageUIStorage()
        let owner = RoamLiveSessionController(service: service, location: location, journal: .init(storage: storage), now: { date })
        owner.prepare(); await owner.start(purposeAccepted: true)
        XCTAssertEqual(owner.phase, .active)
        XCTAssertEqual(owner.merchantDescription(for: service.row), "Provided merchant information")
        XCTAssertFalse(owner.actionConfirmed(service.row, shop: false)); XCTAssertFalse(owner.actionConfirmed(service.row, shop: true))
        XCTAssertNil(owner.placeMemory)
        let calls = service.base.calls, fixes = location.calls, writes = storage.writes, bytes = storage.bytes
        let host = UIHostingController(rootView: NavigationStack { RoamLiveSessionView(controller: owner) })
        host.loadViewIfNeeded(); host.view.layoutIfNeeded(); XCTAssertNotNil(host.view)
        XCTAssertEqual(service.base.calls, calls); XCTAssertEqual(location.calls, fixes)
        XCTAssertEqual(storage.writes, writes); XCTAssertEqual(storage.bytes, bytes)
    }
}

@MainActor final class RoamNearbyVisibilityViewTests: XCTestCase {
    func testUserToggleReversesOnlyBindingAndUsesBothAccessibleLabels() {
        for (language, hide, show, expandedValue, collapsedValue) in [
            ("en", "Hide nearby cards", "Show nearby cards", "Expanded", "Collapsed"),
            ("zh-Hans", "收起附近卡片", "展开附近卡片", "已展开", "已收起")
        ] {
            let locale = Locale(identifier: language), copy = RoamNearbyVisibilityCopy(locale: locale)
            XCTAssertEqual(copy.hide, hide); XCTAssertEqual(copy.show, show)
            XCTAssertEqual(copy.expanded, expandedValue); XCTAssertEqual(copy.collapsed, collapsedValue)
            XCTAssertTrue(copy.hint.contains(language == "en" ? "pending results and retries stay visible" : "待确认结果和重试仍会显示"))
            var expanded = true, changes = 0
            let button = RoamNearbyVisibilityButton(expanded: Binding(get: { expanded }, set: { expanded = $0; changes += 1 }))
            let host = UIHostingController(rootView: List { button }
                .environment(\.locale, locale).environment(\.dynamicTypeSize, .accessibility3))
            host.loadViewIfNeeded(); host.view.layoutIfNeeded(); XCTAssertNotNil(host.view)
            XCTAssertTrue(expanded); XCTAssertEqual(changes, 0)
            button.toggle(); XCTAssertFalse(expanded); XCTAssertEqual(changes, 1)
            button.toggle(); XCTAssertTrue(expanded); XCTAssertEqual(changes, 2)
            button.toggle(); XCTAssertFalse(expanded); XCTAssertEqual(changes, 3)
        }
    }
    private func fixture() async throws
        -> (RoamLiveSessionController, RoamMerchantDescriptionUIService, RoamCoverageUILocation, RoamCoverageUIStorage) {
        let date = Date(timeIntervalSince1970: 1_790_932_200)
        let scope = try RoamHistoryScope(market: "cn", deployment: XCTUnwrap(URL(string: "https://nearby-visibility.example/native/")), accountID: 7)
        let service = try RoamMerchantDescriptionUIService(identity: .init(scope: scope, epoch: 1))
        let location = try RoamCoverageUILocation(date: date), storage = RoamCoverageUIStorage()
        let owner = RoamLiveSessionController(service: service, location: location, journal: .init(storage: storage), now: { date })
        owner.prepare(); await owner.start(purposeAccepted: true)
        XCTAssertEqual(owner.phase, .active)
        return (owner, service, location, storage)
    }
    func testHideAndReopenPreserveCurrentReadWithoutAdditionalProviderWork() async throws {
        let (owner, service, location, storage) = try await fixture()
        let rows = owner.places, registered = owner.registeredShops, record = owner.record
        let calls = service.base.calls, fixes = location.calls, writes = storage.writes, bytes = storage.bytes
        var expanded = true
        let button = RoamNearbyVisibilityButton(expanded: Binding(get: { expanded }, set: { expanded = $0 }))
        for _ in 0..<2 {
            button.toggle(); XCTAssertFalse(expanded)
            XCTAssertEqual(owner.places, rows); XCTAssertEqual(owner.registeredShops, registered)
            button.toggle(); XCTAssertTrue(expanded)
            XCTAssertEqual(owner.merchantDescription(for: service.row), "Provided merchant information")
        }
        let host = UIHostingController(rootView: NavigationStack { RoamLiveSessionView(controller: owner) })
        host.loadViewIfNeeded(); host.view.layoutIfNeeded(); XCTAssertNotNil(host.view)
        XCTAssertEqual(owner.record, record); XCTAssertEqual(service.base.calls, calls)
        XCTAssertEqual(location.calls, fixes); XCTAssertEqual(storage.writes, writes); XCTAssertEqual(storage.bytes, bytes)
    }
    func testVisibilityGestureDoesNotClearUnknownArrivalOrIssueRetry() async throws {
        let (owner, service, location, storage) = try await fixture()
        await owner.visitShop(service.row)
        XCTAssertEqual(owner.phase, .active); XCTAssertTrue(owner.actionUnresolved(service.row, shop: true))
        XCTAssertFalse(owner.actionConfirmed(service.row, shop: true)); XCTAssertNotNil(owner.error)
        let record = owner.record, pending = owner.pendingActionCount
        let calls = service.base.calls, fixes = location.calls, writes = storage.writes, bytes = storage.bytes
        var expanded = true
        let button = RoamNearbyVisibilityButton(expanded: Binding(get: { expanded }, set: { expanded = $0 }))
        button.toggle(); XCTAssertFalse(expanded)
        XCTAssertTrue(owner.actionUnresolved(service.row, shop: true)); XCTAssertNotNil(owner.error)
        button.toggle(); XCTAssertTrue(expanded)
        XCTAssertEqual(owner.pendingActionCount, pending); XCTAssertEqual(owner.record, record)
        XCTAssertEqual(service.base.calls, calls); XCTAssertEqual(location.calls, fixes)
        XCTAssertEqual(storage.writes, writes); XCTAssertEqual(storage.bytes, bytes)
    }
    func testVisibilityGestureDoesNotRepublishPriorOwnerDescriptionOrConfirmedNote() async throws {
        let date = Date(timeIntervalSince1970: 1_790_932_200)
        let scope = try RoamHistoryScope(market: "cn", deployment: XCTUnwrap(URL(string: "https://nearby-note.example/native/")), accountID: 7)
        let service = try RoamPlaceMemoryUIService(identity: .init(scope: scope, epoch: 1))
        let location = try RoamCoverageUILocation(date: date), storage = RoamCoverageUIStorage()
        let owner = RoamLiveSessionController(service: service, location: location, journal: .init(storage: storage), now: { date })
        owner.prepare(); await owner.start(purposeAccepted: true); await owner.discover(service.row)
        XCTAssertTrue(owner.actionConfirmed(service.row, shop: false)); XCTAssertNotNil(owner.placeMemory)
        var expanded = true
        let button = RoamNearbyVisibilityButton(expanded: Binding(get: { expanded }, set: { expanded = $0 }))
        let calls = service.base.calls, discoveries = service.discoveries, fixes = location.calls, bytes = storage.bytes
        button.toggle(); XCTAssertFalse(expanded)
        XCTAssertTrue(owner.actionConfirmed(service.row, shop: false)); XCTAssertNotNil(owner.placeMemory)
        service.base.identity = .init(scope: scope, epoch: 2)
        button.toggle(); XCTAssertTrue(expanded); XCTAssertNil(owner.placeMemory)
        XCTAssertNil(owner.merchantDescription(for: service.row))
        owner.invalidate(); button.toggle(); button.toggle()
        XCTAssertNil(owner.record); XCTAssertTrue(owner.places.isEmpty); XCTAssertNil(owner.placeMemory)
        XCTAssertEqual(service.base.calls, calls); XCTAssertEqual(service.discoveries, discoveries)
        XCTAssertEqual(location.calls, fixes); XCTAssertEqual(storage.bytes, bytes)
    }
}

@MainActor final class RoamPauseRouteOverviewViewTests: XCTestCase {
    private func point(_ latitude: Double, _ longitude: Double) throws -> RoamHistoryPoint {
        .init(coordinate: try XCTUnwrap(RoamCoordinate(latitude: latitude, longitude: longitude)))
    }
    func testEmptyAndSinglePointNeverDrawFabricatedRouteAndHaveBilingualExplanation() throws {
        for language in ["en", "zh-Hans"] {
            let locale = Locale(identifier: language), copy = RoamLiveRouteOverviewCopy(locale: locale)
            XCTAssertTrue(copy.missing.contains(language == "en" ? "cannot restore" : "不能还原"))
            XCTAssertTrue(copy.onePoint.contains(language == "en" ? "one route point" : "一个路线点"))
            XCTAssertTrue(copy.pausedHint.contains(language == "en" ? "Resume button" : "继续按钮"))
            for track in [[], [try point(31.2, 121.4)]] {
                let section = RoamLiveRouteOverviewSection(track: track, paused: true)
                XCTAssertFalse(section.hasDrawableRoute); XCTAssertEqual(section.track, track)
                let host = UIHostingController(rootView: List { section }
                    .environment(\.locale, locale).environment(\.dynamicTypeSize, .accessibility3))
                host.loadViewIfNeeded(); host.view.layoutIfNeeded(); XCTAssertNotNil(host.view)
            }
        }
    }
    func testOverviewRetainsWholeLocalGeometryWithoutMapSourceOrNetwork() throws {
        let track = [try point(31.2, 121.4), try point(31.2001, 121.4001), try point(31.2002, 121.4002)]
        for paused in [false, true] {
            let section = RoamLiveRouteOverviewSection(track: track, paused: paused)
            XCTAssertTrue(section.hasDrawableRoute); XCTAssertEqual(section.track, track)
            let sketch = RoamRouteSketch(track: section.track, places: [])
            XCTAssertEqual(sketch.track.count, track.count); XCTAssertTrue(sketch.places.isEmpty)
            let host = UIHostingController(rootView: List { section })
            host.loadViewIfNeeded(); host.view.layoutIfNeeded(); XCTAssertNotNil(host.view)
        }
    }
    func testNormalPausedHostMountsFromExistingTrackAndDoesNotResumeOrFetch() async throws {
        let date = Date(timeIntervalSince1970: 1_790_932_200)
        let scope = try RoamHistoryScope(market: "cn", deployment: XCTUnwrap(URL(string: "https://paused-overview-ui.example/native/")), accountID: 7)
        let service = RoamCoverageUIService(identity: .init(scope: scope, epoch: 1))
        let location = try RoamCoverageUILocation(date: date), storage = RoamCoverageUIStorage()
        let owner = RoamLiveSessionController(service: service, location: location, journal: .init(storage: storage), now: { date })
        owner.prepare(); await owner.start(purposeAccepted: true); owner.pause()
        let track = try XCTUnwrap(owner.currentRouteTrack), record = owner.record
        let calls = service.calls, fixes = location.calls, writes = storage.writes, bytes = storage.bytes
        for language in ["en", "zh-Hans"] {
            let host = UIHostingController(rootView: NavigationStack { RoamLiveSessionView(controller: owner) }
                .environment(\.locale, Locale(identifier: language)).environment(\.dynamicTypeSize, .accessibility3))
            host.loadViewIfNeeded(); host.view.layoutIfNeeded(); XCTAssertNotNil(host.view)
        }
        XCTAssertEqual(owner.phase, .paused); XCTAssertEqual(owner.currentRouteTrack, track); XCTAssertEqual(owner.record, record)
        XCTAssertEqual(service.calls, calls); XCTAssertEqual(location.calls, fixes)
        XCTAssertEqual(storage.writes, writes); XCTAssertEqual(storage.bytes, bytes)
    }
}

@MainActor private final class RoamPausedBrowseTestReader: RoamExperienceReading {
    var identity: RoamExperienceIdentity?
    var isConfigured: Bool { false }
    var isOfflineExample: Bool { true }
    var reads = 0, localReads = 0, remoteReads = 0
    var onRead: (() -> Void)?
    init(_ identity: RoamExperienceIdentity) { self.identity = identity }
    func history() throws -> [RoamHistoryRecord] { reads += 1; onRead?(); return [] }
    func localWalkStatus() throws -> RoamLocalWalkStatus { localReads += 1; onRead?(); return .unfinished }
    func sessionFact(_ query: RoamRecoveryQuery) async throws -> RoamSessionFact { remoteReads += 1; throw APIError.notConfigured }
    func album(page: Int, pageSize: Int) async throws -> RoamAlbumPage { remoteReads += 1; throw APIError.notConfigured }
    func tilePage(afterID: Int, limit: Int) async throws -> RoamTileMemoryPage { remoteReads += 1; throw APIError.notConfigured }
    func shopBadge() async throws -> RoamShopBadge? { remoteReads += 1; throw APIError.notConfigured }
}
@MainActor final class RoamPausedBrowseViewTests: XCTestCase {
    private func fixture() async throws -> (RoamLiveSessionController, RoamCoverageUIService, RoamCoverageUILocation, RoamCoverageUIStorage, RoamPausedBrowseTestReader) {
        let date = Date(timeIntervalSince1970: 1_790_932_200)
        let scope = try RoamHistoryScope(market: "cn", deployment: XCTUnwrap(URL(string: "https://paused-browse-ui.example/native")), accountID: 7)
        let identity = RoamExperienceIdentity(scope: scope, epoch: 1), service = RoamCoverageUIService(identity: .init(scope: scope, epoch: 1))
        let location = try RoamCoverageUILocation(date: date), storage = RoamCoverageUIStorage()
        let owner = RoamLiveSessionController(service: service, location: location, journal: .init(storage: storage), now: { date })
        owner.prepare(); await owner.start(purposeAccepted: true); XCTAssertEqual(owner.phase, .active)
        return (owner, service, location, storage, RoamPausedBrowseTestReader(identity))
    }
    func testExplicitHistoryOpenPausesBeforeLocalReadAndReturnDoesNotResume() async throws {
        let (owner, service, location, storage, reader) = try await fixture()
        let model = RoamPausedBrowsePresentation(), context = try XCTUnwrap(RoamPausedBrowseContext.capture(kind: .history, owner: owner, reader: reader))
        let calls = service.calls, fixes = location.calls, writes = storage.writes, bytes = storage.bytes
        XCTAssertNil(model.target); XCTAssertEqual(reader.reads, 0)
        model.appear(); model.open(context, entryID: model.entryID, owner: owner, reader: reader)
        XCTAssertEqual(owner.phase, .paused); XCTAssertNil(owner.lastFix); XCTAssertFalse(owner.presenceEnabled)
        let target = try XCTUnwrap(model.target), local = try XCTUnwrap(target.historyReader)
        reader.onRead = { XCTAssertEqual(owner.phase, .paused) }
        XCTAssertEqual(try local.history(), []); XCTAssertEqual(try local.localWalkStatus(), .unfinished)
        model.close(id: target.id); XCTAssertNil(model.target); XCTAssertNil(local.identity)
        XCTAssertEqual(owner.phase, .paused); XCTAssertEqual(service.calls, calls); XCTAssertEqual(location.calls, fixes)
        XCTAssertEqual(storage.writes, writes); XCTAssertEqual(storage.bytes, bytes); XCTAssertEqual(reader.remoteReads, 0)
    }
    func testSettingsNeedsNoHistoryReaderAndDoesNotReadSystemOrResumeDuringSelection() async throws {
        let (owner, service, location, storage, _) = try await fixture()
        XCTAssertNil(RoamPausedBrowseContext.capture(kind: .history, owner: owner, reader: nil))
        let context = try XCTUnwrap(RoamPausedBrowseContext.capture(kind: .settings, owner: owner, reader: nil))
        let model = RoamPausedBrowsePresentation(); model.appear()
        let fixes = location.calls, calls = service.calls, bytes = storage.bytes
        model.open(context, entryID: model.entryID, owner: owner, reader: nil)
        let target = try XCTUnwrap(model.target); XCTAssertNil(target.historyReader); XCTAssertEqual(owner.phase, .paused)
        model.close(id: target.id); XCTAssertNil(model.target); XCTAssertEqual(owner.phase, .paused)
        XCTAssertEqual(location.calls, fixes); XCTAssertEqual(service.calls, calls); XCTAssertEqual(storage.bytes, bytes)
    }
    func testWrongReaderEpochOldOwnerAndOtherControllerCannotActivate() async throws {
        let (owner, service, _, storage, reader) = try await fixture()
        let identity = try XCTUnwrap(reader.identity), bytes = storage.bytes
        let context = try XCTUnwrap(RoamPausedBrowseContext.capture(kind: .history, owner: owner, reader: reader))
        let model = RoamPausedBrowsePresentation(); model.appear()
        let replacement = RoamPausedBrowseTestReader(identity)
        model.open(context, entryID: model.entryID, owner: owner, reader: replacement)
        XCTAssertNil(model.target); XCTAssertEqual(owner.phase, .active)
        reader.identity = .init(scope: identity.scope, epoch: 2)
        model.open(context, entryID: model.entryID, owner: owner, reader: reader); XCTAssertNil(model.target)
        reader.identity = identity; service.identity = .init(scope: identity.scope, epoch: 2)
        model.open(context, entryID: model.entryID, owner: owner, reader: reader); XCTAssertNil(model.target)
        XCTAssertEqual(storage.bytes, bytes); XCTAssertEqual(reader.reads, 0)
        let (other, _, _, _, otherReader) = try await fixture()
        model.open(context, entryID: model.entryID, owner: other, reader: otherReader)
        XCTAssertNil(model.target); XCTAssertEqual(other.phase, .active)
    }
    func testOldNilBindingAndCloseCannotCancelReplacementOrReopenHiddenPage() async throws {
        let (owner, _, _, _, reader) = try await fixture()
        let context = try XCTUnwrap(RoamPausedBrowseContext.capture(kind: .history, owner: owner, reader: reader))
        let model = RoamPausedBrowsePresentation(); model.appear()
        let initial = model.binding(for: model.target, owner: owner, reader: reader), oldEntryID = model.entryID
        model.open(context, entryID: oldEntryID, owner: owner, reader: reader)
        let a = try XCTUnwrap(model.target), old = model.binding(for: model.target, owner: owner, reader: reader)
        model.close(id: a.id); model.open(context, entryID: oldEntryID, owner: owner, reader: reader)
        XCTAssertNil(model.target)
        model.open(context, entryID: model.entryID, owner: owner, reader: reader)
        let b = try XCTUnwrap(model.target); XCTAssertNotEqual(a.id, b.id)
        initial.wrappedValue = nil; old.wrappedValue = nil; model.close(id: a.id)
        XCTAssertEqual(model.target?.id, b.id); XCTAssertNil(old.wrappedValue)
        model.disappear(); model.open(context, entryID: model.entryID, owner: owner, reader: reader)
        XCTAssertNil(model.target); XCTAssertEqual(owner.phase, .paused)
    }
    func testReadRevalidatesLiveOwnerAfterStorageCallbackAndDoesNotReturnOldData() async throws {
        let (owner, service, _, _, reader) = try await fixture()
        let model = RoamPausedBrowsePresentation(); model.appear()
        let context = try XCTUnwrap(RoamPausedBrowseContext.capture(kind: .history, owner: owner, reader: reader))
        model.open(context, entryID: model.entryID, owner: owner, reader: reader)
        let target = try XCTUnwrap(model.target), local = try XCTUnwrap(target.historyReader)
        reader.onRead = { service.identity = nil }
        XCTAssertThrowsError(try local.history()); XCTAssertNil(local.identity)
        XCTAssertFalse(model.matches(target, owner: owner, reader: reader))
        model.retireIfStale(owner: owner, reader: reader); XCTAssertNil(model.target)
        XCTAssertEqual(reader.reads, 1); XCTAssertEqual(reader.remoteReads, 0)
    }
    func testCloseBackgroundAndOwnerInvalidationBlockAllOldLocalReads() async throws {
        for mode in [0, 1, 2] {
            let (owner, _, location, storage, reader) = try await fixture()
            let model = RoamPausedBrowsePresentation(); model.appear()
            let context = try XCTUnwrap(RoamPausedBrowseContext.capture(kind: .history, owner: owner, reader: reader))
            model.open(context, entryID: model.entryID, owner: owner, reader: reader)
            let target = try XCTUnwrap(model.target), local = try XCTUnwrap(target.historyReader)
            let bytes = storage.bytes, fixes = location.calls
            if mode == 0 { model.close(id: target.id) }
            if mode == 1 { model.retire(); owner.setForeground(false); owner.setForeground(true) }
            if mode == 2 { owner.invalidate() }
            XCTAssertThrowsError(try local.history()); XCTAssertThrowsError(try local.localWalkStatus())
            XCTAssertEqual(reader.reads, 0); XCTAssertEqual(reader.localReads, 0)
            XCTAssertEqual(location.calls, fixes); XCTAssertEqual(storage.bytes, bytes)
            XCTAssertNotEqual(owner.phase, .active)
        }
    }
    func testLocalOnlyReaderRejectsRemoteCapabilitiesWithoutDelegation() async throws {
        let (owner, _, _, _, reader) = try await fixture()
        let model = RoamPausedBrowsePresentation(); model.appear()
        let context = try XCTUnwrap(RoamPausedBrowseContext.capture(kind: .history, owner: owner, reader: reader))
        model.open(context, entryID: model.entryID, owner: owner, reader: reader)
        let local = try XCTUnwrap(model.target?.historyReader)
        XCTAssertFalse(local.isConfigured)
        do { _ = try await local.album(page: 1, pageSize: 20); XCTFail("Remote album must stay closed") } catch {}
        do { _ = try await local.tilePage(afterID: 0, limit: 20); XCTFail("Remote tiles must stay closed") } catch {}
        do { _ = try await local.shopBadge(); XCTFail("Remote badge must stay closed") } catch {}
        XCTAssertEqual(reader.remoteReads, 0); XCTAssertEqual(owner.phase, .paused)
    }
    func testNormalHostConstructionKeepsExistingStateAndBilingualReturnInstructions() async throws {
        let (owner, service, location, storage, reader) = try await fixture(); owner.pause()
        let bytes = storage.bytes, calls = service.calls, fixes = location.calls
        for language in ["en", "zh-Hans"] {
            let locale = Locale(identifier: language), copy = RoamPausedBrowseCopy(locale: locale)
            XCTAssertTrue(copy.hint.contains(language == "en" ? "does not resume" : "不会自动继续"))
            XCTAssertFalse(copy.history.isEmpty); XCTAssertFalse(copy.settings.isEmpty)
            let host = UIHostingController(rootView: NavigationStack {
                RoamLiveSessionView(controller: owner, localHistoryReader: reader)
            }.environment(\.locale, locale).environment(\.dynamicTypeSize, .accessibility3))
            host.loadViewIfNeeded(); host.view.layoutIfNeeded(); XCTAssertNotNil(host.view)
        }
        XCTAssertEqual(owner.phase, .paused); XCTAssertEqual(storage.bytes, bytes)
        XCTAssertEqual(service.calls, calls); XCTAssertEqual(location.calls, fixes); XCTAssertEqual(reader.remoteReads, 0)
    }
}

@MainActor extension RoamPausedBrowseViewTests {
    func testExistingPausedFailureAndRecordStayVisibleAfterBrowseReturn() async throws {
        let (owner, service, location, storage, reader) = try await fixture()
        owner.pause(); await owner.resume(purposeAccepted: false)
        XCTAssertNotNil(owner.error); XCTAssertEqual(owner.phase, .paused)
        let record = owner.record, bytes = storage.bytes, calls = service.calls, fixes = location.calls
        let model = RoamPausedBrowsePresentation(); model.appear()
        let context = try XCTUnwrap(RoamPausedBrowseContext.capture(kind: .history, owner: owner, reader: reader))
        model.open(context, entryID: model.entryID, owner: owner, reader: reader)
        let target = try XCTUnwrap(model.target); model.close(id: target.id)
        XCTAssertNotNil(owner.error); XCTAssertEqual(owner.phase, .paused); XCTAssertEqual(owner.record, record)
        XCTAssertEqual(storage.bytes, bytes); XCTAssertEqual(service.calls, calls); XCTAssertEqual(location.calls, fixes)
        XCTAssertEqual(reader.reads, 0); XCTAssertEqual(reader.remoteReads, 0)
    }
}

@MainActor extension RoamPausedBrowseViewTests {
    func testFirstExplicitTargetPresentsThroughNormalWholePageHostAndClosesPaused() async throws {
        let (owner, service, location, storage, reader) = try await fixture()
        let model = RoamPausedBrowsePresentation()
        let host = UIHostingController(rootView: NavigationStack {
            RoamLiveSessionView(controller: owner, localHistoryReader: reader, browsePresentation: model)
        }.environment(\.scenePhase, .active))
        let window = UIWindow(frame: UIScreen.main.bounds); window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        host.loadViewIfNeeded(); host.view.layoutIfNeeded()
        for _ in 0..<10 { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertNil(model.target); XCTAssertNil(host.presentedViewController)
        let context = try XCTUnwrap(RoamPausedBrowseContext.capture(kind: .history, owner: owner, reader: reader))
        let calls = service.calls, fixes = location.calls, bytes = storage.bytes
        model.open(context, entryID: model.entryID, owner: owner, reader: reader)
        let target = try XCTUnwrap(model.target)
        for _ in 0..<100 where host.presentedViewController == nil { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertNotNil(host.presentedViewController)
        XCTAssertEqual(model.target?.id, target.id); XCTAssertEqual(owner.phase, .paused)
        XCTAssertEqual(try target.historyReader?.history(), [])
        model.close(id: target.id)
        for _ in 0..<100 where host.presentedViewController != nil { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertNil(host.presentedViewController); XCTAssertNil(model.target); XCTAssertEqual(owner.phase, .paused)
        XCTAssertEqual(service.calls, calls); XCTAssertEqual(location.calls, fixes); XCTAssertEqual(storage.bytes, bytes)
        XCTAssertEqual(reader.remoteReads, 0)
    }
    func testCoveringSheetKeepsConcreteTargetWhileParentCannotOpenAnother() async throws {
        let (owner, _, _, _, reader) = try await fixture()
        let model = RoamPausedBrowsePresentation(); model.appear()
        let context = try XCTUnwrap(RoamPausedBrowseContext.capture(kind: .history, owner: owner, reader: reader))
        model.open(context, entryID: model.entryID, owner: owner, reader: reader)
        let target = try XCTUnwrap(model.target), bound = model.binding(for: model.target, owner: owner, reader: reader)
        model.parentHidden(); model.parentDisappeared(departing: false, coveredByPresentation: true)
        XCTAssertEqual(bound.wrappedValue?.id, target.id); XCTAssertEqual(try target.historyReader?.history(), [])
        model.open(context, entryID: model.entryID, owner: owner, reader: reader)
        XCTAssertEqual(model.target?.id, target.id); XCTAssertEqual(owner.phase, .paused)
        model.close(id: target.id); XCTAssertThrowsError(try target.historyReader?.history())
        model.appear(); XCTAssertNil(model.target); XCTAssertEqual(owner.phase, .paused)
    }
    func testRealDepartureWinsOverCoverAndNativeDismantleRetiresTarget() async throws {
        for departure in [0, 1, 2] {
            let (owner, _, _, _, reader) = try await fixture()
            let model = RoamPausedBrowsePresentation(); model.appear()
            let context = try XCTUnwrap(RoamPausedBrowseContext.capture(kind: .history, owner: owner, reader: reader))
            model.open(context, entryID: model.entryID, owner: owner, reader: reader)
            let target = try XCTUnwrap(model.target), local = try XCTUnwrap(target.historyReader)
            if departure == 0 { model.parentDisappeared(departing: true, coveredByPresentation: true) }
            if departure == 1 { model.parentDisappeared(departing: false, coveredByPresentation: false) }
            if departure == 2 {
                let controller = RoamPausedBrowseLifetimeController(presentation: model)
                RoamPausedBrowseLifetimeAnchor.dismantleUIViewController(controller, coordinator: ())
            }
            XCTAssertNil(model.target); XCTAssertNil(local.identity); XCTAssertThrowsError(try local.history())
            model.open(context, entryID: model.entryID, owner: owner, reader: reader)
            XCTAssertNil(model.target); XCTAssertEqual(owner.phase, .paused)
        }
    }
    func testConcreteOldPresenterDismissalCannotClearNewTargetAfterReturn() async throws {
        let (owner, _, _, _, reader) = try await fixture()
        let model = RoamPausedBrowsePresentation(); model.appear()
        let context = try XCTUnwrap(RoamPausedBrowseContext.capture(kind: .history, owner: owner, reader: reader))
        model.open(context, entryID: model.entryID, owner: owner, reader: reader)
        let a = try XCTUnwrap(model.target), bindingA = model.binding(for: a, owner: owner, reader: reader)
        model.parentDisappeared(departing: false, coveredByPresentation: true); model.close(id: a.id); model.appear()
        model.open(context, entryID: model.entryID, owner: owner, reader: reader)
        let b = try XCTUnwrap(model.target), bindingB = model.binding(for: b, owner: owner, reader: reader)
        model.close(id: a.id); bindingA.wrappedValue = nil
        XCTAssertNil(bindingA.wrappedValue); XCTAssertEqual(bindingB.wrappedValue?.id, b.id)
        XCTAssertThrowsError(try a.historyReader?.history()); XCTAssertEqual(try b.historyReader?.history(), [])
        bindingB.wrappedValue = nil; XCTAssertNil(model.target); XCTAssertEqual(owner.phase, .paused)
    }
    func testOwnerChangeWhileCoveredRetiresBeforeAnyStoredHistoryRead() async throws {
        let (owner, service, _, storage, reader) = try await fixture()
        let model = RoamPausedBrowsePresentation(); model.appear()
        let context = try XCTUnwrap(RoamPausedBrowseContext.capture(kind: .history, owner: owner, reader: reader))
        model.open(context, entryID: model.entryID, owner: owner, reader: reader)
        let a = try XCTUnwrap(model.target), old = model.binding(for: a, owner: owner, reader: reader), bytes = storage.bytes
        model.parentHidden(); model.parentDisappeared(departing: false, coveredByPresentation: true)
        service.identity = .init(scope: context.identity.scope, epoch: context.identity.epoch + 1)
        XCTAssertNil(old.wrappedValue); XCTAssertThrowsError(try a.historyReader?.history())
        model.retireIfStale(owner: owner, reader: reader); XCTAssertNil(model.target)
        model.appear(); XCTAssertNil(old.wrappedValue); XCTAssertNil(model.target)
        XCTAssertEqual(reader.reads, 0); XCTAssertEqual(storage.bytes, bytes)
    }
}

@MainActor private final class RoamReadOnlyAlbumTestReader: RoamExperienceReading {
    var identity: RoamExperienceIdentity?
    var isConfigured = true
    var isOfflineExample: Bool { true }
    var pages: [Int] = [], otherReads = 0
    var hold = false, fail = false
    var suspended: CheckedContinuation<Void, Never>?
    init(_ identity: RoamExperienceIdentity) { self.identity = identity }
    func history() throws -> [RoamHistoryRecord] { otherReads += 1; return [] }
    func localWalkStatus() throws -> RoamLocalWalkStatus { otherReads += 1; return .none }
    func sessionFact(_ query: RoamRecoveryQuery) async throws -> RoamSessionFact { otherReads += 1; throw APIError.notConfigured }
    func tilePage(afterID: Int, limit: Int) async throws -> RoamTileMemoryPage { otherReads += 1; throw APIError.notConfigured }
    func shopBadge() async throws -> RoamShopBadge? { otherReads += 1; throw APIError.notConfigured }
    func album(page: Int, pageSize: Int) async throws -> RoamAlbumPage {
        pages.append(page)
        if hold { await withCheckedContinuation { suspended = $0 } }
        if fail { throw APIError.notConfigured }
        let data = try JSONSerialization.data(withJSONObject: [
            "list": [["id": page, "picUrl": "", "caption": "Synthetic stamp", "checkState": 1]],
            "total": 2, "pageNum": page, "pageSize": pageSize
        ])
        return try JSONDecoder().decode(RoamAlbumPage.self, from: data)
    }
    func release() { hold = false; suspended?.resume(); suspended = nil }
}
@MainActor final class RoamReadOnlyAlbumScopeTests: XCTestCase {
    private func reader(account: Int = 7, epoch: UInt64 = 1) throws -> RoamReadOnlyAlbumTestReader {
        let scope = try RoamHistoryScope(market: "cn", deployment: XCTUnwrap(URL(string: "https://readonly-album.example/native/")), accountID: account)
        return .init(.init(scope: scope, epoch: epoch))
    }
    private func stamp() throws -> RoamAlbumStamp {
        try JSONDecoder().decode(RoamAlbumStamp.self, from: Data(#"{"id":1,"picUrl":"","caption":"Synthetic stamp","checkState":1}"#.utf8))
    }
    func testDefaultNilRetainsLegacyCaptureAndInjectedDestination() throws {
        let reader = try reader(); var constructions = 0
        let normal = RoamStampAlbumView(reader: reader, stampDestination: { constructions += 1; return AnyView(Text("Synthetic capture")) })
        XCTAssertTrue(normal.allowsCapture); XCTAssertTrue(normal.canShowAlbum)
        let host = UIHostingController(rootView: normal.captureDestination)
        host.loadViewIfNeeded(); host.view.layoutIfNeeded()
        XCTAssertEqual(constructions, 1)
        XCTAssertTrue(RoamStampAlbumView(reader: reader).allowsCapture)
        XCTAssertTrue(RoamStampDetailView(stamp: try stamp(), offline: true).canShowStamp)
        XCTAssertTrue(reader.pages.isEmpty)
    }
    func testExplicitReadonlyNeverConstructsInjectedOrDefaultCapture() throws {
        let reader = try reader(), identity = try XCTUnwrap(reader.identity)
        let scope = RoamStampAlbumReadOnlyScope(reader: reader, identity: identity, isCurrent: { true })
        var constructions = 0
        for injected in [false, true] {
            let destination: (() -> AnyView)? = injected ? { constructions += 1; return AnyView(Text("Forbidden")) } : nil
            let view = RoamStampAlbumView(reader: reader, stampDestination: destination, readOnlyScope: scope)
            XCTAssertFalse(view.allowsCapture); XCTAssertTrue(view.canShowAlbum)
            let host = UIHostingController(rootView: view.captureDestination)
            host.loadViewIfNeeded(); host.view.layoutIfNeeded()
            XCTAssertEqual(constructions, 0)
        }
        XCTAssertTrue(reader.pages.isEmpty); XCTAssertEqual(reader.otherReads, 0)
    }
    func testWrongReaderAndNilOrChangedIdentityNeverRenderOrDispatch() async throws {
        let reader = try reader(), identity = try XCTUnwrap(reader.identity), other = try self.reader()
        let scope = RoamStampAlbumReadOnlyScope(reader: reader, identity: identity, isCurrent: { true })
        XCTAssertFalse(scope.matches(other))
        XCTAssertFalse(RoamStampAlbumView(reader: other, readOnlyScope: scope).canShowAlbum)
        let detail = RoamStampDetailView(stamp: try stamp(), offline: true, readOnlyScope: scope)
        for invalid in [nil, try self.reader(account: 8).identity, try self.reader(epoch: 2).identity] {
            reader.identity = invalid
            XCTAssertNil(scope.identity); XCTAssertFalse(scope.isConfigured); XCTAssertFalse(detail.canShowStamp)
            do { _ = try await scope.album(page: 1, pageSize: 20); XCTFail("Stale album dispatched") } catch {}
        }
        XCTAssertTrue(reader.pages.isEmpty); XCTAssertEqual(reader.otherReads, 0)
    }
    func testReadOnlyScopeRejectsEveryUnrelatedCapability() async throws {
        let reader = try reader(), scope = RoamStampAlbumReadOnlyScope(reader: reader, identity: try XCTUnwrap(reader.identity), isCurrent: { true })
        XCTAssertThrowsError(try scope.history()); XCTAssertThrowsError(try scope.localWalkStatus())
        do { _ = try await scope.sessionFact(.sessionID(1)); XCTFail() } catch {}
        do { _ = try await scope.tilePage(afterID: 0, limit: 20); XCTFail() } catch {}
        do { _ = try await scope.shopBadge(); XCTFail() } catch {}
        XCTAssertEqual(reader.otherReads, 0); XCTAssertTrue(reader.pages.isEmpty)
    }
    func testUnconfiguredReaderStaysBlockedWithoutDelegateDispatch() async throws {
        let reader = try reader(); reader.isConfigured = false
        let scope = RoamStampAlbumReadOnlyScope(reader: reader, identity: try XCTUnwrap(reader.identity), isCurrent: { true })
        let pager = RoamAlbumPager(reader: scope); await pager.loadNext()
        XCTAssertFalse(scope.isConfigured); XCTAssertTrue(pager.stamps.isEmpty)
        XCTAssertEqual(pager.error as? APIError, .notConfigured); XCTAssertTrue(reader.pages.isEmpty)
    }
    func testSameScopePageRetryAndDetailPushPreserveRowsWithoutAdvancingFailure() async throws {
        let reader = try reader(), scope = RoamStampAlbumReadOnlyScope(reader: reader, identity: try XCTUnwrap(reader.identity), isCurrent: { true })
        let pager = RoamAlbumPager(reader: scope, pageSize: 1); await pager.loadNext()
        XCTAssertEqual(pager.stamps.map(\.id), [1]); XCTAssertTrue(pager.hasMore)
        let detail = RoamStampDetailView(stamp: try XCTUnwrap(pager.stamps.first), offline: true, readOnlyScope: scope)
        pager.cancelPending(); XCTAssertEqual(pager.stamps.map(\.id), [1]); XCTAssertTrue(detail.canShowStamp)
        reader.fail = true; await pager.loadNext(); XCTAssertEqual(pager.stamps.map(\.id), [1]); XCTAssertNotNil(pager.error)
        reader.fail = false; await pager.loadNext()
        XCTAssertEqual(reader.pages, [1, 2, 2]); XCTAssertEqual(pager.stamps.map(\.id), [1, 2]); XCTAssertFalse(pager.hasMore)
        XCTAssertEqual(reader.otherReads, 0)
    }
    func testHiddenOrOwnerChangedWhileReadIsSuspendedCannotPublishRows() async throws {
        for changeOwner in [false, true] {
            let reader = try reader(); var visible = true
            let identity = try XCTUnwrap(reader.identity)
            let scope = RoamStampAlbumReadOnlyScope(reader: reader, identity: identity, isCurrent: { visible })
            let pager = RoamAlbumPager(reader: scope); reader.hold = true
            let task = Task { await pager.loadNext() }
            for _ in 0..<50 { if reader.suspended != nil { break }; await Task.yield() }
            guard reader.suspended != nil else { reader.hold = false; task.cancel(); await task.value; return XCTFail("Read did not suspend") }
            if changeOwner { reader.identity = .init(scope: identity.scope, epoch: identity.epoch + 1) } else { visible = false }
            reader.release(); await task.value
            XCTAssertNil(scope.identity); XCTAssertTrue(pager.stamps.isEmpty); XCTAssertFalse(pager.loaded)
            XCTAssertEqual(reader.pages, [1]); XCTAssertEqual(reader.otherReads, 0)
        }
    }
    func testCanceledReadCannotPublishEvenWhenOwnerStillMatches() async throws {
        let reader = try reader(), scope = RoamStampAlbumReadOnlyScope(reader: reader, identity: try XCTUnwrap(reader.identity), isCurrent: { true })
        reader.hold = true; let pager = RoamAlbumPager(reader: scope)
        let task = Task { await pager.loadNext() }
        for _ in 0..<50 { if reader.suspended != nil { break }; await Task.yield() }
        guard reader.suspended != nil else { reader.hold = false; task.cancel(); await task.value; return XCTFail("Read did not suspend") }
        task.cancel(); reader.release(); await task.value
        XCTAssertTrue(scope.isCurrent); XCTAssertTrue(pager.stamps.isEmpty); XCTAssertFalse(pager.loaded)
        XCTAssertEqual(reader.pages, [1]); XCTAssertEqual(reader.otherReads, 0)
    }
}

@MainActor final class RoamPausedAlbumEntryTests: XCTestCase {
    private func fixture() async throws -> (RoamLiveSessionController, RoamCoverageUIService, RoamCoverageUILocation, RoamCoverageUIStorage, RoamReadOnlyAlbumTestReader) {
        let date = Date(timeIntervalSince1970: 1_790_932_200)
        let scope = try RoamHistoryScope(market: "cn", deployment: XCTUnwrap(URL(string: "https://paused-readonly-album.example/native/")), accountID: 7)
        let identity = RoamExperienceIdentity(scope: scope, epoch: 1), service = RoamCoverageUIService(identity: .init(scope: scope, epoch: 1))
        let location = try RoamCoverageUILocation(date: date), storage = RoamCoverageUIStorage()
        let owner = RoamLiveSessionController(service: service, location: location, journal: .init(storage: storage), now: { date })
        owner.prepare(); await owner.start(purposeAccepted: true); XCTAssertEqual(owner.phase, .active)
        return (owner, service, location, storage, .init(identity))
    }
    func testAlbumEntryPausesBeforeReadAndCloseNeverResumesOrMutatesJournal() async throws {
        let (owner, service, location, storage, reader) = try await fixture()
        let model = RoamPausedBrowsePresentation(); model.appear()
        let context = try XCTUnwrap(RoamPausedBrowseContext.capture(kind: .album, owner: owner, reader: reader))
        let calls = service.calls, fixes = location.calls, bytes = storage.bytes
        model.open(context, entryID: model.entryID, owner: owner, reader: reader)
        let target = try XCTUnwrap(model.target), scope = try XCTUnwrap(target.albumScope)
        XCTAssertEqual(owner.phase, .paused); XCTAssertNil(target.historyReader); XCTAssertTrue(reader.pages.isEmpty)
        _ = try await scope.album(page: 1, pageSize: 20); XCTAssertEqual(reader.pages, [1])
        model.close(id: target.id)
        do { _ = try await scope.album(page: 1, pageSize: 20); XCTFail() } catch {}
        XCTAssertEqual(reader.pages, [1]); XCTAssertEqual(reader.otherReads, 0); XCTAssertEqual(owner.phase, .paused)
        XCTAssertEqual(service.calls, calls); XCTAssertEqual(location.calls, fixes); XCTAssertEqual(storage.bytes, bytes)
    }
    func testOldAlbumUUIDCannotReadOrClearNewAlbumAfterExplicitReopen() async throws {
        let (owner, _, _, _, reader) = try await fixture()
        let model = RoamPausedBrowsePresentation(); model.appear()
        let context = try XCTUnwrap(RoamPausedBrowseContext.capture(kind: .album, owner: owner, reader: reader))
        model.open(context, entryID: model.entryID, owner: owner, reader: reader)
        let a = try XCTUnwrap(model.target), old = model.binding(for: a, owner: owner, reader: reader)
        model.close(id: a.id); model.appear(); model.open(context, entryID: model.entryID, owner: owner, reader: reader)
        let b = try XCTUnwrap(model.target)
        old.wrappedValue = nil; model.close(id: a.id)
        XCTAssertEqual(model.target?.id, b.id); XCTAssertNil(old.wrappedValue); XCTAssertNil(a.albumScope?.identity)
        _ = try await XCTUnwrap(b.albumScope).album(page: 1, pageSize: 20)
        XCTAssertEqual(reader.pages, [1]); XCTAssertEqual(owner.phase, .paused)
    }
    func testDepartureBackgroundAndOwnerChangeImmediatelyExpireAlbumAndDetail() async throws {
        for invalidation in [0, 1, 2] {
            let (owner, service, _, _, reader) = try await fixture()
            let model = RoamPausedBrowsePresentation(); model.appear()
            let context = try XCTUnwrap(RoamPausedBrowseContext.capture(kind: .album, owner: owner, reader: reader))
            model.open(context, entryID: model.entryID, owner: owner, reader: reader)
            let target = try XCTUnwrap(model.target), scope = try XCTUnwrap(target.albumScope)
            model.parentDisappeared(departing: false, coveredByPresentation: true)
            XCTAssertTrue(scope.isCurrent)
            if invalidation == 0 { model.parentDisappeared(departing: true, coveredByPresentation: true) }
            if invalidation == 1 { model.retire(); owner.setForeground(false); owner.setForeground(true) }
            if invalidation == 2 { service.identity = .init(scope: context.identity.scope, epoch: 2) }
            XCTAssertNil(scope.identity)
            do { _ = try await scope.album(page: 1, pageSize: 20); XCTFail() } catch {}
            model.retireIfStale(owner: owner, reader: reader); XCTAssertNil(model.target)
            XCTAssertTrue(reader.pages.isEmpty); XCTAssertEqual(reader.otherReads, 0)
        }
    }
    func testNormalFirstAlbumSheetHasConcreteOwnerAndReturnsPausedWithoutCapture() async throws {
        let (owner, service, location, storage, reader) = try await fixture()
        let model = RoamPausedBrowsePresentation()
        let host = UIHostingController(rootView: NavigationStack {
            RoamLiveSessionView(controller: owner, localHistoryReader: reader, browsePresentation: model)
        }.environment(\.scenePhase, .active))
        let window = UIWindow(frame: UIScreen.main.bounds); window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        host.loadViewIfNeeded(); host.view.layoutIfNeeded()
        for _ in 0..<10 { try await Task.sleep(for: .milliseconds(20)) }
        let context = try XCTUnwrap(RoamPausedBrowseContext.capture(kind: .album, owner: owner, reader: reader))
        let calls = service.calls, fixes = location.calls, bytes = storage.bytes
        model.open(context, entryID: model.entryID, owner: owner, reader: reader)
        let target = try XCTUnwrap(model.target)
        for _ in 0..<100 where host.presentedViewController == nil || reader.pages.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertNotNil(host.presentedViewController); XCTAssertEqual(model.target?.id, target.id)
        XCTAssertEqual(reader.pages, [1]); XCTAssertEqual(owner.phase, .paused)
        XCTAssertFalse(RoamStampAlbumView(reader: reader, readOnlyScope: try XCTUnwrap(target.albumScope)).allowsCapture)
        model.close(id: target.id)
        for _ in 0..<100 where host.presentedViewController != nil { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertNil(host.presentedViewController); XCTAssertNil(target.albumScope?.identity); XCTAssertEqual(owner.phase, .paused)
        XCTAssertEqual(service.calls, calls); XCTAssertEqual(location.calls, fixes); XCTAssertEqual(storage.bytes, bytes)
        XCTAssertEqual(reader.otherReads, 0)
        XCTAssertEqual(RoamPausedBrowseCopy(locale: Locale(identifier: "en")).label(.album), "View stamp album (read-only)")
        XCTAssertEqual(RoamPausedBrowseCopy(locale: Locale(identifier: "zh-Hans")).label(.album), "只读查看集邮册")
    }
}

@MainActor private final class FinishedRouteUIService: RoamLiveServing {
    var identity: RoamExperienceIdentity?
    var isAvailable: Bool { identity != nil }
    var presenceAvailable: Bool { false }
    var calls = 0
    init(_ identity: RoamExperienceIdentity) { self.identity = identity }
    private func decode<T: Decodable>(_ type: T.Type, _ text: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(text.utf8))
    }
    func reveal(sessionID: Int?, clientSessionKey: String, tiles: [String]) async throws -> RoamLiveRevealReceipt {
        calls += 1; return try decode(RoamLiveRevealReceipt.self, #"{"sessionId":12,"newlyRevealed":1}"#)
    }
    func fact(key: String) async throws -> RoamSessionFact {
        calls += 1
        return try decode(RoamSessionFact.self, "{\"state\":\"FINISHED\",\"sessionId\":12,\"clientSessionKey\":\"\(key)\",\"resultComplete\":true,\"result\":{\"tileXp\":1,\"poiXp\":0,\"totalXp\":1,\"newTiles\":1,\"newPois\":0,\"tilesEver\":1,\"sessionShops\":0}}")
    }
    func places(fix: RoamDeviceFix) async throws -> [RoamPlace] { calls += 1; return [] }
    func registeredShops(fix: RoamDeviceFix) async throws -> [RoamRouteNode] { calls += 1; return [] }
    func discover(sessionID: Int, poiID: Int, fix: RoamDeviceFix) async throws -> RoamLiveDiscoveryReceipt { calls += 1; throw APIError.notConfigured }
    func shopVisit(sessionID: Int, sourceType: Int, sourceID: Int, fix: RoamDeviceFix) async throws -> RoamLiveShopReceipt { calls += 1; throw APIError.notConfigured }
    func presence(sessionID: Int, fix: RoamDeviceFix, explorationPercent: Int) async throws { calls += 1; throw APIError.notConfigured }
    func finish(sessionID: Int, poiIDs: [Int], distanceMeters: Int) async throws { calls += 1 }
}
@MainActor final class RoamFinishedRouteViewTests: XCTestCase {
    private func fixture(restored: Bool = false) async throws -> (RoamLiveSessionController, FinishedRouteUIService, RoamCoverageUILocation, RoamFinishedMedalsStorage) {
        let date = Date(timeIntervalSince1970: 1_790_932_200)
        let scope = try RoamHistoryScope(market: "cn", deployment: XCTUnwrap(URL(string: "https://finished-route-ui.example/native/")), accountID: 7)
        let service = FinishedRouteUIService(.init(scope: scope, epoch: 1)), location = try RoamCoverageUILocation(date: date)
        let storage = RoamFinishedMedalsStorage(), journal = RoamLiveJournal(storage: storage)
        if restored {
            var record = RoamLiveRecord(scope: scope, clientSessionKey: String(repeating: "a", count: 32), startedAt: date)
            record.sessionID = 12; record.finishRequested = true; record.distanceMeters = 800
            try journal.write(record)
        }
        let owner = RoamLiveSessionController(service: service, location: location, journal: journal,
            history: RoamHistoryStore(storage: storage, currentScope: { service.identity?.scope }), now: { date })
        owner.prepare()
        if !restored { await owner.start(purposeAccepted: true) }
        return (owner, service, location, storage)
    }
    func testFinishedRouteSectionExplainsMissingAndSinglePointWithoutInventingLine() throws {
        let point = RoamHistoryPoint(coordinate: try XCTUnwrap(RoamCoordinate(latitude: 31.2, longitude: 121.4)))
        XCTAssertFalse(RoamLiveRouteOverviewSection(track: [], paused: false, finished: true).hasDrawableRoute)
        XCTAssertFalse(RoamLiveRouteOverviewSection(track: [point], paused: false, finished: true).hasDrawableRoute)
        XCTAssertFalse(RoamLiveRouteOverviewSection(track: [point], paused: true).finished)
        for language in ["en", "zh-Hans"] {
            let copy = RoamLiveRouteOverviewCopy(locale: Locale(identifier: language))
            XCTAssertTrue(copy.finishedHint.contains(language == "en" ? "may be incomplete" : "可能不完整"))
            XCTAssertTrue(copy.finishedHint.contains(language == "en" ? "background" : "后台"))
            XCTAssertFalse(copy.missing.isEmpty); XCTAssertFalse(copy.onePoint.isEmpty)
            let host = UIHostingController(rootView: List {
                RoamLiveRouteOverviewSection(track: [], paused: false, finished: true)
            }.environment(\.locale, Locale(identifier: language)).environment(\.dynamicTypeSize, .accessibility3))
            host.loadViewIfNeeded(); host.view.layoutIfNeeded(); XCTAssertNotNil(host.view)
        }
    }
    func testDrawableFinishedRouteUsesSameReadOnlySketchWithNoExternalMap() throws {
        let points = try [RoamCoordinate(latitude: 31.2, longitude: 121.4), RoamCoordinate(latitude: 31.2001, longitude: 121.4001)]
            .map { RoamHistoryPoint(coordinate: try XCTUnwrap($0)) }
        let section = RoamLiveRouteOverviewSection(track: points, paused: false, finished: true)
        XCTAssertTrue(section.hasDrawableRoute); XCTAssertEqual(section.track, points)
        let host = UIHostingController(rootView: List { section }.environment(\.dynamicTypeSize, .accessibility5))
        host.loadViewIfNeeded(); host.view.layoutIfNeeded(); XCTAssertNotNil(host.view)
    }
    func testNormalFinishedHostDepartureRetiresMemoryAndReturnDoesNotRestart() async throws {
        let (owner, service, location, storage) = try await fixture()
        let points = owner.currentRouteTrack; await owner.finish()
        XCTAssertEqual(owner.finishedRouteTrack, points); XCTAssertEqual(points?.count, 1)
        let bytes = storage.bytes, calls = service.calls, fixes = location.calls
        let host = UIHostingController(rootView: RoamLiveSessionView(controller: owner).environment(\.scenePhase, .active))
        let navigation = UINavigationController(rootViewController: host)
        let window = UIWindow(frame: UIScreen.main.bounds); window.rootViewController = navigation; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        host.loadViewIfNeeded(); host.view.layoutIfNeeded()
        for _ in 0..<10 { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(owner.finishedRouteTrack, points)
        navigation.pushViewController(UIViewController(), animated: false)
        for _ in 0..<50 where owner.finishedRouteTrack?.isEmpty == false { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(owner.finishedRouteTrack, [])
        navigation.popViewController(animated: false)
        for _ in 0..<10 { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(owner.phase, .finished); XCTAssertEqual(owner.finishedRouteTrack, [])
        XCTAssertEqual(service.calls, calls); XCTAssertEqual(location.calls, fixes); XCTAssertEqual(storage.bytes, bytes)
    }
    func testRecoveredCompletionRendersUnavailableRouteWithoutLocationOrNewFinish() async throws {
        let (owner, service, location, storage) = try await fixture(restored: true)
        await owner.recover(); XCTAssertEqual(owner.phase, .finished); XCTAssertEqual(owner.finishedRouteTrack, [])
        let calls = service.calls, bytes = storage.bytes
        let host = UIHostingController(rootView: NavigationStack { RoamLiveSessionView(controller: owner) }
            .environment(\.scenePhase, .active))
        host.loadViewIfNeeded(); host.view.layoutIfNeeded(); XCTAssertNotNil(host.view)
        XCTAssertEqual(owner.finishedRouteTrack, []); XCTAssertEqual(service.calls, calls)
        XCTAssertEqual(location.calls, 0); XCTAssertEqual(storage.bytes, bytes)
    }
    func testArchiveFailureAndChangedOwnerCannotSupplyFinishedSection() async throws {
        for failure in [RoamFinishedMedalsStorage.Failure.history, .clear] {
            let (owner, service, _, storage) = try await fixture(); storage.failure = failure
            await owner.finish(); XCTAssertNil(owner.finishedRouteTrack); XCTAssertNotEqual(owner.phase, .finished)
            XCTAssertNotNil(owner.error); XCTAssertNotNil(owner.record)
            let calls = service.calls, bytes = storage.bytes
            let host = UIHostingController(rootView: RoamLiveSessionView(controller: owner))
            host.loadViewIfNeeded(); host.view.layoutIfNeeded(); XCTAssertNotNil(host.view)
            XCTAssertEqual(service.calls, calls); XCTAssertEqual(storage.bytes, bytes)
        }
        let (owner, service, _, _) = try await fixture(); await owner.finish()
        let identity = try XCTUnwrap(service.identity); service.identity = .init(scope: identity.scope, epoch: 2)
        XCTAssertNil(owner.finishedRouteTrack)
    }
}
