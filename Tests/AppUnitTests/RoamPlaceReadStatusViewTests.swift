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
