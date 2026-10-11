import XCTest
@testable import QuestifyCore

final class RoamSharePhotoSaveStateTests: XCTestCase {
    private func selection(route: Bool = false, distance: Double = 1) throws -> RoamSharePhotoSaveState.Selection {
        let record = try JSONDecoder().decode(RoamHistoryRecord.self, from: Data("{\"ts\":1,\"distance\":\(distance)}".utf8))
        return .init(record: record, includeRoute: route)
    }
    func testUnpreparedCardCannotStart() throws {
        var state = RoamSharePhotoSaveState()
        XCTAssertNil(state.begin(for: try selection()))
    }
    func testRepeatedBeginIsBlockedDuringPermissionAndWrite() throws {
        var state = RoamSharePhotoSaveState(); let card = try selection()
        state.prepare(card); let attempt = try XCTUnwrap(state.begin(for: card))
        XCTAssertNil(state.begin(for: card))
        XCTAssertTrue(state.authorize(.authorized, for: attempt))
        XCTAssertEqual(state.phase, .saving); XCTAssertNil(state.begin(for: card))
    }
    func testSuccessBlocksDuplicateSaveOfSamePreparedCard() throws {
        var state = RoamSharePhotoSaveState(); let card = try selection()
        state.prepare(card); let attempt = try XCTUnwrap(state.begin(for: card))
        XCTAssertTrue(state.authorize(.authorized, for: attempt)); state.complete(saved: true, for: attempt)
        state.prepare(card)
        XCTAssertEqual(state.phase, .saved); XCTAssertNil(state.begin(for: card))
    }
    func testDeniedPermissionCanBeRetriedWithFreshAttempt() throws {
        var state = RoamSharePhotoSaveState(); let card = try selection()
        state.prepare(card); let first = try XCTUnwrap(state.begin(for: card))
        XCTAssertFalse(state.authorize(.denied, for: first)); XCTAssertEqual(state.phase, .permissionDenied)
        let second = try XCTUnwrap(state.begin(for: card))
        XCTAssertNotEqual(first, second); XCTAssertFalse(state.authorize(.authorized, for: first))
        XCTAssertTrue(state.authorize(.authorized, for: second))
    }
    func testRestrictedUnavailableAndUnsettledAuthorizationAreDistinct() throws {
        let cases: [(RoamSharePhotoSaveState.Authorization, RoamSharePhotoSaveState.Phase)] = [
            (.restricted, .restricted), (.unavailable, .unavailable), (.notDetermined, .failed)
        ]
        for (authorization, phase) in cases {
            var state = RoamSharePhotoSaveState(); let card = try selection()
            state.prepare(card); let attempt = try XCTUnwrap(state.begin(for: card))
            XCTAssertFalse(state.authorize(authorization, for: attempt)); XCTAssertEqual(state.phase, phase)
            state.complete(saved: true, for: attempt); XCTAssertEqual(state.phase, phase)
        }
    }
    func testWriteFailureRetainsCardAndAllowsExplicitRetry() throws {
        var state = RoamSharePhotoSaveState(); let card = try selection()
        state.prepare(card); let attempt = try XCTUnwrap(state.begin(for: card))
        XCTAssertTrue(state.authorize(.authorized, for: attempt)); state.complete(saved: false, for: attempt)
        XCTAssertEqual(state.selection, card); XCTAssertEqual(state.phase, .failed)
        XCTAssertNotNil(state.begin(for: card))
    }
    func testDismissalRejectsLatePermissionAndCompletion() throws {
        var state = RoamSharePhotoSaveState(); let card = try selection()
        state.prepare(card); let attempt = try XCTUnwrap(state.begin(for: card)); state.invalidate()
        XCTAssertFalse(state.authorize(.authorized, for: attempt)); state.complete(saved: true, for: attempt)
        XCTAssertNil(state.selection); XCTAssertEqual(state.phase, .ready)
    }
    func testRouteSelectionChangeRejectsOldImage() throws {
        var state = RoamSharePhotoSaveState(); let first = try selection(), second = try selection(route: true)
        state.prepare(first); let attempt = try XCTUnwrap(state.begin(for: first)); state.prepare(second)
        XCTAssertFalse(state.accepts(attempt)); XCTAssertFalse(state.authorize(.authorized, for: attempt))
        XCTAssertNil(state.begin(for: first)); XCTAssertNotNil(state.begin(for: second))
    }
    func testSameTimestampWithChangedRecordRejectsOldImage() throws {
        var state = RoamSharePhotoSaveState(); let first = try selection(), second = try selection(distance: 2)
        XCTAssertEqual(first.record.ts, second.record.ts)
        state.prepare(first); let attempt = try XCTUnwrap(state.begin(for: first))
        XCTAssertTrue(state.authorize(.authorized, for: attempt)); state.prepare(second)
        state.complete(saved: true, for: attempt); XCTAssertEqual(state.phase, .ready)
        XCTAssertEqual(state.selection, second)
    }
    func testDismissAndReopenSameCardRejectsPriorGeneration() throws {
        var state = RoamSharePhotoSaveState(); let card = try selection()
        state.prepare(card); let old = try XCTUnwrap(state.begin(for: card)); state.invalidate(); state.prepare(card)
        let current = try XCTUnwrap(state.begin(for: card))
        XCTAssertFalse(state.authorize(.authorized, for: old)); XCTAssertTrue(state.authorize(.authorized, for: current))
        state.complete(saved: true, for: old); XCTAssertEqual(state.phase, .saving)
    }
}
