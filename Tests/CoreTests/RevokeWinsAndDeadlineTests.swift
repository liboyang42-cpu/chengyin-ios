import XCTest
@testable import QuestifyCore

final class RevokeWinsAndDeadlineTests: XCTestCase {
    private func event(_ kind: RevokeWinsEvent.Kind, _ version: Int64?, _ source: RevokeWinsEvent.Source = .serverReadback) throws -> RevokeWinsEvent {
        try RevokeWinsEvent(subjectId: "invite-1", kind: kind, serverVersion: version, source: source)
    }

    func testRevokeBeatsLateAcceptAndRestoredCache() throws {
        var state = try RevokeWinsState(subjectId: "invite-1")
        XCTAssertTrue(try state.apply(event(.offered, 1)))
        XCTAssertTrue(try state.apply(event(.revoked, 2, .serverPush)))
        XCTAssertFalse(try state.apply(event(.accepted, 3, .lateResponse)))
        XCTAssertFalse(try state.apply(event(.offered, nil, .restoredCache)))
        XCTAssertEqual(state.display, .revoked)
    }

    func testRevokeWithOlderVersionStillWinsOverAccepted() throws {
        var state = try RevokeWinsState(subjectId: "invite-1")
        try state.apply(event(.accepted, 5))
        XCTAssertEqual(state.notificationToShow(), .accepted)
        XCTAssertTrue(try state.apply(event(.revoked, 4, .lateResponse)))
        XCTAssertEqual(state.display, .revoked)
        XCTAssertEqual(state.notificationToShow(), .revoked)
        XCTAssertNil(state.notificationToShow())
    }

    func testLocalSourcesCannotCarryVersionsOrSetTerminalState() throws {
        XCTAssertThrowsError(try event(.accepted, 9, .localRetry))
        var state = try RevokeWinsState(subjectId: "invite-1")
        XCTAssertFalse(try state.apply(event(.accepted, nil, .localRetry)))
        XCTAssertEqual(state.display, .unknown)
        XCTAssertThrowsError(try state.apply(RevokeWinsEvent(subjectId: "invite-2", kind: .revoked, serverVersion: 1, source: .serverPush))) { XCTAssertEqual($0 as? RevokeWinsIssue, .wrongSubject) }
    }

    func testDuplicateAndOlderServerResponsesAreIgnored() throws {
        var state = try RevokeWinsState(subjectId: "invite-1")
        try state.apply(event(.offered, 3))
        XCTAssertFalse(try state.apply(event(.offered, 3)))
        XCTAssertFalse(try state.apply(event(.accepted, 2, .lateResponse)))
        XCTAssertEqual(state.display, .pending)
    }

    // U03: 2026-11-01 12:00:00 Beijing = 2026-11-01T04:00:00Z = 1793505600000 ms.
    private let deadlineMillis: Int64 = 1_793_505_600_000

    func testDeadlineCivilTextMustMatchInstantInBeijing() throws {
        XCTAssertNoThrow(try BeijingDeadline(epochMilliseconds: deadlineMillis, beijingCivil: "2026-11-01T12:00:00"))
        XCTAssertThrowsError(try BeijingDeadline(epochMilliseconds: deadlineMillis, beijingCivil: "2026-11-01T04:00:00")) { XCTAssertEqual($0 as? BeijingDeadlineIssue, .zoneMismatch) }
        XCTAssertThrowsError(try BeijingDeadline(epochMilliseconds: deadlineMillis, beijingCivil: "2026-11-01T12:00:00", zone: "America/New_York")) { XCTAssertEqual($0 as? BeijingDeadlineIssue, .zoneMismatch) }
        XCTAssertThrowsError(try BeijingDeadline(epochMilliseconds: deadlineMillis, beijingCivil: "2026-02-30T12:00:00"))
    }

    func testPhoneZoneChangesDisplayButNotInstant() throws {
        let deadline = try BeijingDeadline(epochMilliseconds: deadlineMillis, beijingCivil: "2026-11-01T12:00:00")
        let shanghai = deadline.display(phoneZone: TimeZone(identifier: "Asia/Shanghai")!, locale: Locale(identifier: "en_US_POSIX"))
        XCTAssertNil(shanghai.beijing)
        // 2026-11-01 is the US DST fall-back day; New York is UTC-4 before 06:00Z.
        let newYork = deadline.display(phoneZone: TimeZone(identifier: "America/New_York")!, locale: Locale(identifier: "en_US_POSIX"))
        XCTAssertNotNil(newYork.beijing)
        XCTAssertNotEqual(newYork.local, shanghai.local)
        XCTAssertEqual(deadline.instant, Date(timeIntervalSince1970: 1_793_505_600))
    }

    func testHintUsesServerOffsetNotDeviceClock() throws {
        let deadline = try BeijingDeadline(epochMilliseconds: deadlineMillis, beijingCivil: "2026-11-01T12:00:00")
        let instant = deadline.instant
        // Device clock was moved 1 hour forward; server offset corrects it back.
        XCTAssertEqual(deadline.hint(deviceNow: instant.addingTimeInterval(3600 - 60), serverOffset: -3600), .open(remainingSeconds: 60))
        XCTAssertEqual(deadline.hint(deviceNow: instant.addingTimeInterval(1), serverOffset: 0), .boundary)
        XCTAssertEqual(deadline.hint(deviceNow: instant.addingTimeInterval(-1), serverOffset: 0), .boundary)
        XCTAssertEqual(deadline.hint(deviceNow: instant.addingTimeInterval(30), serverOffset: 0), .likelyClosed)
    }
}
