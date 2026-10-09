import XCTest
@testable import Questify

@MainActor private final class HistoryLiveEntryReaderFixture: RoamExperienceReading {
    var identity: RoamExperienceIdentity?
    var isConfigured = true
    let isOfflineExample = true
    var calls = 0
    init() throws { identity = try Self.identity() }
    static func identity(account: Int = 7, epoch: UInt64 = 1, market: String = "cn",
                         deployment: String = "https://example.com/roam", namespace: String = "history") throws -> RoamExperienceIdentity {
        .init(scope: try .init(market: market, deployment: XCTUnwrap(URL(string: deployment)), accountID: account, namespace: namespace), epoch: epoch)
    }
    func history() throws -> [RoamHistoryRecord] { calls += 1; return [] }
    func sessionFact(_ query: RoamRecoveryQuery) async throws -> RoamSessionFact { calls += 1; throw APIError.notConfigured }
    func album(page: Int, pageSize: Int) async throws -> RoamAlbumPage { calls += 1; throw APIError.notConfigured }
    func tilePage(afterID: Int, limit: Int) async throws -> RoamTileMemoryPage { calls += 1; throw APIError.notConfigured }
    func shopBadge() async throws -> RoamShopBadge? { calls += 1; throw APIError.notConfigured }
}

@MainActor final class RoamHistoryLiveEntryTests: XCTestCase {
    private func ready(_ reader: HistoryLiveEntryReaderFixture) -> RoamHistoryLiveEntry {
        var value = RoamHistoryLiveEntry(); value.appear()
        let snapshot = value.beginRead(reader: reader)
        value.acceptRead(isEmpty: true, snapshot: snapshot, reader: reader)
        return value
    }
    private func activate(_ entry: inout RoamHistoryLiveEntry, _ reader: HistoryLiveEntryReaderFixture) throws -> RoamHistoryLiveEntry.Target {
        entry.activate(reader: reader, hasDestination: true, presentationID: entry.presentationID)
        return try XCTUnwrap(entry.target)
    }
    func testLoadingAndFailedReadNeverOfferLiveEntry() throws {
        let reader = try HistoryLiveEntryReaderFixture(); var entry = RoamHistoryLiveEntry(); entry.appear()
        XCTAssertFalse(entry.canOpen(reader: reader, hasDestination: true))
        _ = entry.beginRead(reader: reader) // Failed reads never call acceptRead.
        XCTAssertFalse(entry.canOpen(reader: reader, hasDestination: true))
        entry.activate(reader: reader, hasDestination: true, presentationID: entry.presentationID)
        XCTAssertNil(entry.target); XCTAssertEqual(reader.calls, 0)
    }
    func testOnlyAcceptedEmptyReadCanOfferEntry() throws {
        let reader = try HistoryLiveEntryReaderFixture(); var entry = ready(reader)
        XCTAssertTrue(entry.canOpen(reader: reader, hasDestination: true))
        let snapshot = entry.beginRead(reader: reader)
        entry.acceptRead(isEmpty: false, snapshot: snapshot, reader: reader)
        XCTAssertFalse(entry.canOpen(reader: reader, hasDestination: true)); XCTAssertEqual(reader.calls, 0)
    }
    func testMissingDestinationDoesNotCreateFallback() throws {
        let reader = try HistoryLiveEntryReaderFixture(); var entry = ready(reader)
        XCTAssertFalse(entry.canOpen(reader: reader, hasDestination: false))
        entry.activate(reader: reader, hasDestination: false, presentationID: entry.presentationID)
        XCTAssertNil(entry.target); XCTAssertEqual(reader.calls, 0)
    }
    func testSignedOutAndUnconfiguredOwnersCannotActivate() throws {
        let reader = try HistoryLiveEntryReaderFixture(); var entry = ready(reader)
        reader.identity = nil
        XCTAssertFalse(entry.canOpen(reader: reader, hasDestination: true))
        reader.identity = try HistoryLiveEntryReaderFixture.identity(); reader.isConfigured = false
        entry = ready(reader)
        XCTAssertFalse(entry.canOpen(reader: reader, hasDestination: true))
        entry.activate(reader: reader, hasDestination: true, presentationID: entry.presentationID)
        XCTAssertNil(entry.target); XCTAssertEqual(reader.calls, 0)
    }
    func testOwnerChangeDuringReadCannotAcceptAnOldEmptyReceipt() throws {
        let reader = try HistoryLiveEntryReaderFixture(); var entry = RoamHistoryLiveEntry(); entry.appear()
        let snapshot = entry.beginRead(reader: reader)
        reader.identity = try HistoryLiveEntryReaderFixture.identity(epoch: 2)
        entry.acceptRead(isEmpty: true, snapshot: snapshot, reader: reader)
        XCTAssertFalse(entry.canOpen(reader: reader, hasDestination: true))
    }
    func testReaderReplacementCannotReuseEmptyReceiptOrDestination() throws {
        let reader = try HistoryLiveEntryReaderFixture(), replacement = try HistoryLiveEntryReaderFixture()
        var entry = ready(reader); let target = try activate(&entry, reader)
        XCTAssertFalse(entry.matches(target, reader: replacement, hasDestination: true))
        entry.retireIfOwnerChanged(reader: replacement, hasDestination: true)
        XCTAssertNil(entry.target); XCTAssertFalse(entry.canOpen(reader: replacement, hasDestination: true))
    }
    func testEveryScopeComponentAndEpochFencesDestination() throws {
        let reader = try HistoryLiveEntryReaderFixture(); var entry = ready(reader); let target = try activate(&entry, reader)
        let changed = [try HistoryLiveEntryReaderFixture.identity(account: 8),
                       try HistoryLiveEntryReaderFixture.identity(epoch: 2),
                       try HistoryLiveEntryReaderFixture.identity(market: "us"),
                       try HistoryLiveEntryReaderFixture.identity(deployment: "https://example.com/other"),
                       try HistoryLiveEntryReaderFixture.identity(namespace: "other")]
        for identity in changed {
            reader.identity = identity
            XCTAssertFalse(entry.matches(target, reader: reader, hasDestination: true))
        }
    }
    func testCanonicallyEquivalentNamespaceBytesRemainDifferentOwners() throws {
        let reader = try HistoryLiveEntryReaderFixture()
        reader.identity = try HistoryLiveEntryReaderFixture.identity(namespace: "\u{00E9}")
        var entry = ready(reader); let target = try activate(&entry, reader)
        reader.identity = try HistoryLiveEntryReaderFixture.identity(namespace: "e\u{0301}")
        XCTAssertFalse(entry.matches(target, reader: reader, hasDestination: true))
    }
    func testDuplicateTapDoesNotReplaceActiveTargetOrMakeRequests() throws {
        let reader = try HistoryLiveEntryReaderFixture(); var entry = ready(reader); let target = try activate(&entry, reader)
        entry.activate(reader: reader, hasDestination: true, presentationID: entry.presentationID)
        XCTAssertEqual(entry.target, target); XCTAssertEqual(reader.calls, 0)
    }
    func testPushPreservesDestinationButRetiresOriginTap() throws {
        let reader = try HistoryLiveEntryReaderFixture(); var entry = ready(reader)
        let presentation = entry.presentationID; let target = try activate(&entry, reader)
        entry.disappear()
        XCTAssertTrue(entry.matches(target, reader: reader, hasDestination: true))
        XCTAssertFalse(entry.canOpen(reader: reader, hasDestination: true))
        entry.target = nil // Native navigation binding on Back.
        entry.appear()
        entry.activate(reader: reader, hasDestination: true, presentationID: presentation)
        XCTAssertNil(entry.target); XCTAssertFalse(entry.matches(target, reader: reader, hasDestination: true))
        let reopened = try activate(&entry, reader); XCTAssertNotEqual(reopened.id, target.id)
    }
    func testLogoutConfigurationLossAndDestinationRemovalRetireSelection() throws {
        let reader = try HistoryLiveEntryReaderFixture(); var entry = ready(reader)
        let target = try activate(&entry, reader); reader.identity = nil
        XCTAssertFalse(entry.matches(target, reader: reader, hasDestination: true))
        entry.retireIfOwnerChanged(reader: reader, hasDestination: true); XCTAssertNil(entry.target)
        reader.identity = try HistoryLiveEntryReaderFixture.identity(); entry = ready(reader)
        _ = try activate(&entry, reader); reader.isConfigured = false
        entry.retireIfOwnerChanged(reader: reader, hasDestination: true); XCTAssertNil(entry.target)
        reader.isConfigured = true; entry = ready(reader); _ = try activate(&entry, reader)
        entry.retireIfOwnerChanged(reader: reader, hasDestination: false); XCTAssertNil(entry.target)
    }
    func testReloadRetiresSelectionAndNeedsNewSuccessfulEmptyReceipt() throws {
        let reader = try HistoryLiveEntryReaderFixture(); var entry = ready(reader); let target = try activate(&entry, reader)
        let snapshot = entry.beginRead(reader: reader)
        XCTAssertNil(entry.target); XCTAssertFalse(entry.matches(target, reader: reader, hasDestination: true))
        XCTAssertFalse(entry.canOpen(reader: reader, hasDestination: true))
        entry.acceptRead(isEmpty: true, snapshot: snapshot, reader: reader)
        XCTAssertTrue(entry.canOpen(reader: reader, hasDestination: true)); XCTAssertEqual(reader.calls, 0)
    }
}
