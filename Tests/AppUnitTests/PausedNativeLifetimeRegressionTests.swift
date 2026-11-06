import XCTest
import SwiftUI
import UIKit
import Combine
import Observation
@testable import Questify

@MainActor private final class IsolatedRoamCoverageUIStorage: RoamHistoryDataStoring {
    var bytes: [String: Data] = [:]
    var writes = 0
    func read(key: String) throws -> Data? { bytes[key] }
    func write(_ data: Data, key: String) throws { writes += 1; bytes[key] = data }
}

@MainActor private final class IsolatedRoamCoverageUILocation: RoamDeviceLocationProviding {
    let value: RoamDeviceFix
    var calls = 0
    init(date: Date) throws {
        value = try RoamDeviceFix(coordinate: XCTUnwrap(RoamCoordinate(latitude: 31.2, longitude: 121.4)),
                                  accuracyMeters: 10, measuredAt: date, datum: .gcj02)
    }
    func currentFix() async throws -> RoamDeviceFix { calls += 1; return value }
    func stop() {}
}

@MainActor private final class IsolatedRoamCoverageUIService: RoamLiveServing {
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

@MainActor private final class IsolatedRoamPausedBrowseTestReader: RoamExperienceReading {
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

@MainActor private final class IsolatedRoamReadOnlyAlbumTestReader: RoamExperienceReading {
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

// New teardown tests enter through the existing persisted-session recovery path.
// The old start fixtures and their current geometry-overload failure remain untouched.
@MainActor private enum IsolatedRoamPausedBrowseTeardownSetup {
    static func owner() async throws -> (RoamLiveSessionController, IsolatedRoamCoverageUIService, IsolatedRoamCoverageUILocation, IsolatedRoamCoverageUIStorage) {
        let date = Date(timeIntervalSince1970: 1_790_932_200)
        let scope = try RoamHistoryScope(market: "cn", deployment: XCTUnwrap(URL(string: "https://paused-teardown.example/native/")), accountID: 7)
        let service = IsolatedRoamCoverageUIService(identity: .init(scope: scope, epoch: 1))
        let location = try IsolatedRoamCoverageUILocation(date: date), storage = IsolatedRoamCoverageUIStorage()
        let journal = RoamLiveJournal(storage: storage)
        var saved = RoamLiveRecord(scope: scope, clientSessionKey: String(repeating: "c", count: 32), startedAt: date)
        saved.sessionID = 12
        try journal.write(saved)
        let owner = RoamLiveSessionController(service: service, location: location, journal: journal, now: { date })
        owner.prepare(); XCTAssertEqual(owner.phase, .recoveryRequired)
        await owner.recover()
        XCTAssertEqual(owner.phase, .paused); XCTAssertNil(owner.record?.pendingWrite)
        XCTAssertEqual(owner.record?.clientSessionKey, saved.clientSessionKey)
        XCTAssertEqual(service.calls, 1); XCTAssertEqual(location.calls, 0)
        return (owner, service, location, storage)
    }
}

// Regression candidates for the original GraphHost.invalidate -> native dismantle crash.
@MainActor final class PausedNativeLifetimeRegressionTests: XCTestCase {
    private func teardownFixture() async throws -> (RoamLiveSessionController, IsolatedRoamCoverageUIService, IsolatedRoamCoverageUILocation, IsolatedRoamCoverageUIStorage, IsolatedRoamPausedBrowseTestReader) {
        let (owner, service, location, storage) = try await IsolatedRoamPausedBrowseTeardownSetup.owner()
        return (owner, service, location, storage, .init(try XCTUnwrap(service.identity)))
    }
    func testNativeDismantleRevokesHistorySynchronouslyWithoutPublishing() async throws {
        let (owner, service, location, storage, reader) = try await teardownFixture()
        let model = RoamPausedBrowsePresentation(); model.appear()
        let anchor = RoamPausedBrowseLifetimeController(presentation: model)
        let context = try XCTUnwrap(RoamPausedBrowseContext.capture(kind: .history, owner: owner, reader: reader))
        model.open(context, entryID: model.entryID, owner: owner, reader: reader)
        let target = try XCTUnwrap(model.target), local = try XCTUnwrap(target.historyReader)
        let binding = model.binding(for: target, owner: owner, reader: reader), entry = model.entryID
        let record = owner.record, bytes = storage.bytes, calls = service.calls, fixes = location.calls
        var publications = 0
        let subscription = model.objectWillChange.sink { publications += 1 }
        defer { subscription.cancel() }

        RoamPausedBrowseLifetimeAnchor.dismantleUIViewController(anchor, coordinator: ())
        // No yield: authority must already be gone inside the native teardown stack.
        XCTAssertEqual(publications, 0); XCTAssertNil(model.target); XCTAssertNotEqual(model.entryID, entry)
        XCTAssertNil(binding.wrappedValue); XCTAssertNil(local.identity)
        XCTAssertThrowsError(try local.history()); XCTAssertThrowsError(try local.localWalkStatus())
        anchor.viewDidAppear(false); anchor.viewDidDisappear(false)
        model.open(context, entryID: model.entryID, owner: owner, reader: reader)
        XCTAssertNil(model.target); XCTAssertEqual(publications, 0)
        XCTAssertEqual(owner.phase, .paused); XCTAssertEqual(owner.record, record)
        XCTAssertEqual(storage.bytes, bytes); XCTAssertEqual(service.calls, calls); XCTAssertEqual(location.calls, fixes)
        XCTAssertEqual(reader.reads, 0); XCTAssertEqual(reader.localReads, 0); XCTAssertEqual(reader.remoteReads, 0)
    }

    func testEmptyNativeTeardownAndParentHideDoNotPublish() {
        let model = RoamPausedBrowsePresentation(); model.appear()
        let anchor = RoamPausedBrowseLifetimeController(presentation: model)
        let entry = model.entryID
        var publications = 0
        let subscription = model.objectWillChange.sink { publications += 1 }
        defer { subscription.cancel() }
        model.parentHidden(); anchor.viewDidDisappear(false)
        RoamPausedBrowseLifetimeAnchor.dismantleUIViewController(anchor, coordinator: ())
        RoamPausedBrowseLifetimeAnchor.dismantleUIViewController(anchor, coordinator: ())
        XCTAssertEqual(publications, 0); XCTAssertNil(model.target); XCTAssertNotEqual(model.entryID, entry)
    }

    func testOldNativeCallbacksCannotRetireOrReactivateReplacementBrowse() async throws {
        let (owner, _, _, _, reader) = try await teardownFixture()
        let model = RoamPausedBrowsePresentation(); model.appear()
        let oldAnchor = RoamPausedBrowseLifetimeController(presentation: model)
        let context = try XCTUnwrap(RoamPausedBrowseContext.capture(kind: .history, owner: owner, reader: reader))
        model.open(context, entryID: model.entryID, owner: owner, reader: reader)
        let oldTarget = try XCTUnwrap(model.target), oldEntry = model.entryID
        let oldBinding = model.binding(for: oldTarget, owner: owner, reader: reader)
        let newAnchor = RoamPausedBrowseLifetimeController(presentation: model)
        XCTAssertNil(model.target); XCTAssertNil(oldTarget.historyReader?.identity)
        newAnchor.viewDidAppear(false)
        model.open(context, entryID: oldEntry, owner: owner, reader: reader)
        XCTAssertNil(model.target)
        model.open(context, entryID: model.entryID, owner: owner, reader: reader)
        let current = try XCTUnwrap(model.target), entry = model.entryID
        oldAnchor.viewDidDisappear(false); oldAnchor.viewDidAppear(false)
        RoamPausedBrowseLifetimeAnchor.dismantleUIViewController(oldAnchor, coordinator: ())
        oldBinding.wrappedValue = nil; model.close(id: oldTarget.id)
        XCTAssertEqual(model.target?.id, current.id); XCTAssertEqual(model.entryID, entry)
        XCTAssertNil(oldBinding.wrappedValue); XCTAssertThrowsError(try oldTarget.historyReader?.history())
        XCTAssertEqual(try current.historyReader?.history(), []); XCTAssertEqual(owner.phase, .paused)
        RoamPausedBrowseLifetimeAnchor.dismantleUIViewController(newAnchor, coordinator: ())
        XCTAssertNil(model.target); XCTAssertNil(current.historyReader?.identity)
    }

    func testPauseCallbackCannotOpenAfterSynchronousSourceDeparture() async throws {
        let (owner, service, location, storage, reader) = try await teardownFixture()
        let model = RoamPausedBrowsePresentation(); model.appear()
        let context = try XCTUnwrap(RoamPausedBrowseContext.capture(kind: .history, owner: owner, reader: reader))
        let entry = model.entryID, record = owner.record, bytes = storage.bytes
        let calls = service.calls, fixes = location.calls
        owner.onChange = { model.disappear() }
        model.open(context, entryID: entry, owner: owner, reader: reader)
        XCTAssertNil(model.target); XCTAssertNotEqual(model.entryID, entry); XCTAssertEqual(owner.phase, .paused)
        XCTAssertEqual(owner.record, record); XCTAssertEqual(storage.bytes, bytes)
        XCTAssertEqual(service.calls, calls); XCTAssertEqual(location.calls, fixes); XCTAssertEqual(reader.reads, 0)
    }

    func testNormalClosePublishesAfterRevocationAndFreshExplicitOpenStillWorks() async throws {
        let (owner, service, location, storage, reader) = try await teardownFixture()
        let model = RoamPausedBrowsePresentation(); model.appear()
        let context = try XCTUnwrap(RoamPausedBrowseContext.capture(kind: .history, owner: owner, reader: reader))
        model.open(context, entryID: model.entryID, owner: owner, reader: reader)
        let old = try XCTUnwrap(model.target), oldEntry = model.entryID
        let record = owner.record, bytes = storage.bytes, calls = service.calls, fixes = location.calls
        var publications = 0
        let subscription = model.objectWillChange.sink {
            publications += 1
            XCTAssertNil(old.historyReader?.identity)
            XCTAssertNotEqual(model.entryID, oldEntry)
        }
        defer { subscription.cancel() }
        model.close(id: old.id)
        XCTAssertEqual(publications, 1); XCTAssertNil(model.target)
        model.open(context, entryID: oldEntry, owner: owner, reader: reader)
        XCTAssertNil(model.target); XCTAssertEqual(publications, 1)
        model.open(context, entryID: model.entryID, owner: owner, reader: reader)
        let current = try XCTUnwrap(model.target)
        XCTAssertNotEqual(current.id, old.id); XCTAssertEqual(publications, 2)
        XCTAssertEqual(try current.historyReader?.history(), [])
        XCTAssertEqual(owner.phase, .paused); XCTAssertEqual(owner.record, record)
        XCTAssertEqual(storage.bytes, bytes); XCTAssertEqual(service.calls, calls); XCTAssertEqual(location.calls, fixes)
    }

    func testAccountReplacementClosesBrowseBeforeAnyOldReadOrPublication() async throws {
        let (owner, service, location, storage, reader) = try await teardownFixture()
        let model = RoamPausedBrowsePresentation(); model.appear()
        let context = try XCTUnwrap(RoamPausedBrowseContext.capture(kind: .history, owner: owner, reader: reader))
        model.open(context, entryID: model.entryID, owner: owner, reader: reader)
        let target = try XCTUnwrap(model.target), local = try XCTUnwrap(target.historyReader)
        let binding = model.binding(for: target, owner: owner, reader: reader)
        let record = owner.record, bytes = storage.bytes, calls = service.calls, fixes = location.calls
        service.identity = .init(scope: context.identity.scope, epoch: context.identity.epoch + 1)
        XCTAssertNil(binding.wrappedValue); XCTAssertNil(local.identity); XCTAssertThrowsError(try local.history())
        var publications = 0
        let subscription = model.objectWillChange.sink {
            publications += 1; XCTAssertNil(model.target); XCTAssertNil(local.identity)
        }
        defer { subscription.cancel() }
        model.retireIfStale(owner: owner, reader: reader)
        XCTAssertEqual(publications, 1); XCTAssertNil(model.target)
        model.appear(); model.open(context, entryID: model.entryID, owner: owner, reader: reader)
        XCTAssertNil(model.target); XCTAssertEqual(reader.reads, 0)
        XCTAssertEqual(owner.record, record); XCTAssertEqual(storage.bytes, bytes)
        XCTAssertEqual(service.calls, calls); XCTAssertEqual(location.calls, fixes)
    }

    func testNormalWholePageHostTeardownExpiresRetainedHistoryWithoutResume() async throws {
        let (owner, service, location, storage, reader) = try await teardownFixture()
        let model = RoamPausedBrowsePresentation()
        var host: UIHostingController<AnyView>? = UIHostingController(rootView: AnyView(NavigationStack {
            RoamLiveSessionView(controller: owner, localHistoryReader: reader, browsePresentation: model)
        }.environment(\.scenePhase, .active)))
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; host = nil }
        host?.loadViewIfNeeded(); host?.view.layoutIfNeeded()
        for _ in 0..<10 { try await Task.sleep(for: .milliseconds(20)) }
        let context = try XCTUnwrap(RoamPausedBrowseContext.capture(kind: .history, owner: owner, reader: reader))
        let calls = service.calls, fixes = location.calls, bytes = storage.bytes
        model.open(context, entryID: model.entryID, owner: owner, reader: reader)
        let target = try XCTUnwrap(model.target), local = try XCTUnwrap(target.historyReader)
        for _ in 0..<100 where host?.presentedViewController == nil { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertNotNil(host?.presentedViewController)
        autoreleasepool { window.isHidden = true; window.rootViewController = nil; host = nil }
        for _ in 0..<100 where model.target != nil { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertNil(model.target); XCTAssertNil(local.identity); XCTAssertThrowsError(try local.history())
        XCTAssertEqual(owner.phase, .paused); XCTAssertEqual(service.calls, calls)
        XCTAssertEqual(location.calls, fixes); XCTAssertEqual(storage.bytes, bytes); XCTAssertEqual(reader.remoteReads, 0)
    }
}

@MainActor final class PausedNativeAlbumLifetimeRegressionTests: XCTestCase {
    private func teardownFixture() async throws -> (RoamLiveSessionController, IsolatedRoamCoverageUIService, IsolatedRoamCoverageUILocation, IsolatedRoamCoverageUIStorage, IsolatedRoamReadOnlyAlbumTestReader) {
        let (owner, service, location, storage) = try await IsolatedRoamPausedBrowseTeardownSetup.owner()
        return (owner, service, location, storage, .init(try XCTUnwrap(service.identity)))
    }
    func testNativeDismantleImmediatelyExpiresAlbumAndRejectsInFlightPageWithoutPublication() async throws {
        let (owner, service, location, storage, reader) = try await teardownFixture()
        let model = RoamPausedBrowsePresentation(); model.appear()
        let anchor = RoamPausedBrowseLifetimeController(presentation: model)
        let context = try XCTUnwrap(RoamPausedBrowseContext.capture(kind: .album, owner: owner, reader: reader))
        model.open(context, entryID: model.entryID, owner: owner, reader: reader)
        let target = try XCTUnwrap(model.target), scope = try XCTUnwrap(target.albumScope)
        let calls = service.calls, fixes = location.calls, bytes = storage.bytes
        let pager = RoamAlbumPager(reader: scope); reader.hold = true
        let pending = Task { await pager.loadNext() }
        for _ in 0..<50 { if reader.suspended != nil { break }; await Task.yield() }
        guard reader.suspended != nil else {
            reader.hold = false; pending.cancel(); await pending.value
            return XCTFail("Original album read did not suspend")
        }
        var publications = 0
        let subscription = model.objectWillChange.sink { publications += 1 }
        defer { subscription.cancel() }
        withObservationTracking { _ = scope.isCurrent } onChange: {
            XCTFail("Native graph teardown must not mutate observed album storage")
        }
        RoamPausedBrowseLifetimeAnchor.dismantleUIViewController(anchor, coordinator: ())
        XCTAssertEqual(publications, 0); XCTAssertNil(model.target); XCTAssertNil(scope.identity)
        XCTAssertFalse(scope.isConfigured); XCTAssertFalse(RoamStampAlbumView(reader: reader, readOnlyScope: scope).canShowAlbum)
        reader.release(); await pending.value
        XCTAssertTrue(pager.stamps.isEmpty); XCTAssertFalse(pager.loaded); XCTAssertEqual(reader.pages, [1])
        do { _ = try await scope.album(page: 2, pageSize: 20); XCTFail("Retired album dispatched") } catch {}
        XCTAssertEqual(reader.pages, [1]); XCTAssertEqual(reader.otherReads, 0); XCTAssertEqual(publications, 0)
        XCTAssertEqual(owner.phase, .paused); XCTAssertEqual(service.calls, calls)
        XCTAssertEqual(location.calls, fixes); XCTAssertEqual(storage.bytes, bytes)
    }
}
