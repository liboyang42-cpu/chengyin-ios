import XCTest
@testable import QuestifyCore

final class ClubSeriesOccurrencePresentationTests: XCTestCase {
    private let scope = ClubGovernanceScope(clubID: 81, topicID: 91, seriesID: 111)
    private func context(_ scope: ClubGovernanceScope? = nil, identity: ClubReadIdentity? = .init(accountID: 701, epoch: 1)) -> ClubGovernanceReadContext {
        .init(operation: .occurrences, scope: scope ?? self.scope, identity: identity, viewerRevision: 0, authorizationGeneration: nil)
    }
    private func row(_ id: Int = 112, activity: ClubGovernanceValue = .integer(101), fields: [String: ClubGovernanceValue] = [:]) -> ClubGovernanceValue {
        .object(["occurrenceId": .integer(id), "activityId": activity, "occurrenceAt": .string("2026-10-08 09:00:00")].merging(fields) { _, new in new })
    }
    private func snapshot(_ rows: [ClubGovernanceValue], permitted: Bool = true) throws -> ClubGovernanceSnapshot {
        let permission = try ClubGovernancePermissions(value: .object(["active": .bool(true), "club": .object(["id": .integer(81)]),
            "roleCodes": .array([]), "permissions": .array(permitted ? [.string("club:activity:manage")] : []), "canManageRoles": .bool(false)]), scope: scope)
        return .init(operation: .occurrences, scope: scope, permissions: permission, value: .array(rows))
    }
    private func presentation(_ rows: [ClubGovernanceValue]) throws -> ClubSeriesOccurrencePresentation { try .init(snapshot: snapshot(rows), context: context()) }
    func testSourceOrderIncludesPastCancelledAndUnknownCounts() throws {
        let value = try presentation([row(114, fields: ["status": .string("CANCELLED"), "refundedCount": .integer(0)]), row(112)])
        XCTAssertEqual(value.rows.map(\.occurrenceID), [114, 112]); XCTAssertEqual(value.rows.map(\.id), [0, 1])
        XCTAssertTrue(value.rows[0].cancelled); XCTAssertEqual(value.rows[0].refundedCount, 0)
        XCTAssertNil(value.rows[1].signupCount); XCTAssertNil(value.rows[1].refundedCount); XCTAssertNil(value.rows[1].editable)
        XCTAssertEqual(value.rows[1].dateText, "2026-10-08 09:00")
    }
    func testKnownZeroEditabilityAndLockReasonRemainDistinctFromUnknown() throws {
        let value = try presentation([row(fields: ["signupCount": .integer(0), "editable": .bool(false), "lockReason": .string(" Count pending ")]), row(113, fields: ["editable": .bool(true), "signupCount": .integer(4)])])
        XCTAssertEqual(value.rows[0].signupCount, 0); XCTAssertEqual(value.rows[0].editable, false)
        XCTAssertEqual(value.rows[0].lockReason, "Count pending"); XCTAssertEqual(value.rows[1].editable, true)
        XCTAssertEqual(value.rows[1].signupCount, 4)
    }
    func testEmptyIsGenuineAndUnparseableDateIsNotFabricated() throws {
        XCTAssertTrue(try presentation([]).rows.isEmpty)
        let value = try presentation([row(fields: ["occurrenceAt": .string(" Pending date ")]), row(113, fields: ["occurrenceAt": .null])])
        XCTAssertEqual(value.rows[0].dateText, "Pending date"); XCTAssertFalse(value.rows[0].dateIsParsed)
        XCTAssertNil(value.rows[1].dateText); XCTAssertFalse(value.rows[1].dateIsParsed)
    }
    func testRouteUsesOnlyReturnedActivityIDNotOccurrenceIDOrIndex() throws {
        let value = try presentation([row(), row(113, activity: .null)]), nonce = UUID()
        let route = try XCTUnwrap(value.route(rowID: 0, context: context(), snapshotID: nonce))
        XCTAssertEqual(route.scope, .init(clubID: 81, topicID: 91, activityID: 101))
        XCTAssertNil(value.route(rowID: 1, context: context(), snapshotID: nonce))
        XCTAssertNil(value.route(rowID: 112, context: context(), snapshotID: nonce))
        XCTAssertTrue(route.isCurrent(presentation: value, context: context(), snapshotID: nonce))
    }
    func testRouteRetiresForNewReadNonceAccountEpochScopeOrChangedRow() throws {
        let value = try presentation([row()]), nonce = UUID(), route = try XCTUnwrap(value.route(rowID: 0, context: context(), snapshotID: nonce))
        XCTAssertFalse(route.isCurrent(presentation: value, context: context(), snapshotID: UUID()))
        XCTAssertFalse(route.isCurrent(presentation: value, context: context(identity: .init(accountID: 702, epoch: 1)), snapshotID: nonce))
        XCTAssertFalse(route.isCurrent(presentation: value, context: context(identity: .init(accountID: 701, epoch: 2)), snapshotID: nonce))
        XCTAssertFalse(route.isCurrent(presentation: value, context: context(.init(clubID: 81, topicID: 91, seriesID: 112)), snapshotID: nonce))
        XCTAssertFalse(route.isCurrent(presentation: try presentation([row(activity: .integer(102))]), context: context(), snapshotID: nonce))
    }
    func testContradictoryScopeInvalidIDsAndCountsReject() {
        for fields: [String: ClubGovernanceValue] in [["clubId": .integer(82)], ["topicId": .integer(92)], ["seriesId": .integer(112)], ["activityId": .integer(0)], ["occurrenceId": .bool(true)], ["signupCount": .integer(-1)], ["refundedCount": .bool(false)]] {
            XCTAssertThrowsError(try presentation([row(fields: fields)]))
        }
        XCTAssertThrowsError(try presentation([row(), row()]))
        XCTAssertThrowsError(try presentation([.null]))
    }
    func testFreshPermissionExactOperationScopeAndSignedInViewerRequired() throws {
        XCTAssertThrowsError(try ClubSeriesOccurrencePresentation(snapshot: snapshot([row()], permitted: false), context: context())) { XCTAssertEqual($0 as? ClubGovernanceFailure, .forbidden) }
        let source = try snapshot([row()])
        XCTAssertThrowsError(try ClubSeriesOccurrencePresentation(snapshot: source, context: context(identity: nil)))
        XCTAssertThrowsError(try ClubSeriesOccurrencePresentation(snapshot: source, context: context(.init(clubID: 81, seriesID: 112))))
        let wrong = ClubGovernanceReadContext(operation: .seriesDetail, scope: scope, identity: .init(accountID: 701, epoch: 1), viewerRevision: 0, authorizationGeneration: nil)
        XCTAssertThrowsError(try ClubSeriesOccurrencePresentation(snapshot: source, context: wrong))
    }
    func testWallDateAndOffsetUseFixedChinaClockAcrossMidnight() {
        for raw in ["2026-10-08 00:30:00", "2026/10/8 0:30", "2026-10-07T16:30:00Z", "2026-10-07T12:30:00-04:00", "2026-10-08T00:30:00+0800"] {
            XCTAssertEqual(ClubOccurrenceClock.display(.string(raw)), "2026-10-08 00:30", raw)
        }
        XCTAssertEqual(ClubOccurrenceClock.display(.string("2026-10-08")), "2026-10-08 00:00")
        XCTAssertEqual(ClubOccurrenceClock.display(.string("2024-02-29 23:59:59.999")), "2024-02-29 23:59")
    }
    func testEpochSecondsMillisecondsAndStringSentinelContract() {
        let seconds = 1_000_000_000, milliseconds = 1_000_000_000_000
        for raw: ClubGovernanceValue in [.integer(seconds), .integer(milliseconds), .string(String(seconds)), .string(String(milliseconds))] {
            XCTAssertEqual(ClubOccurrenceClock.display(raw), "2001-09-09 09:46")
        }
        XCTAssertNil(ClubOccurrenceClock.display(.integer(0)))
        XCTAssertEqual(ClubOccurrenceClock.display(.string("0000000000")), "1970-01-01 08:00")
        XCTAssertEqual(ClubOccurrenceClock.display(.integer(-1000)), "1970-01-01 07:59")
    }
    func testMalformedCalendarTimesAndUnsupportedValuesStayUnparsed() {
        for raw in ["2026-02-29", "2026-02-30T00:00Z", "2026-13-01", "2026-10-08 24:00", "2026-10-08 09:60", "2026-10-08 09:00:60", "2026-10-08T09:00:00+24:00", "unknown", "0", "12345678901"] {
            XCTAssertNil(ClubOccurrenceClock.display(.string(raw)), raw)
        }
        for raw: ClubGovernanceValue in [.null, .bool(true), .array([]), .object([:]), .decimal(.infinity), .decimal(8.64e15 + 1)] {
            XCTAssertNil(ClubOccurrenceClock.display(raw))
        }
    }
}
