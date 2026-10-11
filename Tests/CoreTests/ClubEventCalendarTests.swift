import XCTest
@testable import QuestifyCore

final class ClubEventCalendarTests: XCTestCase {
    private let scope = ClubGovernanceScope(clubID: 81)
    private func context(identity: ClubReadIdentity? = .init(accountID: 701, epoch: 1), revision: UInt64 = 1) -> ClubGovernanceReadContext {
        .init(operation: .topics, scope: scope, identity: identity, viewerRevision: revision, authorizationGeneration: nil)
    }
    private func row(_ id: ClubGovernanceValue = .integer(91), date: ClubGovernanceValue = .string("2028-02-29 10:00:00"), extra: [String: ClubGovernanceValue] = [:]) -> ClubGovernanceValue {
        var fields: [String: ClubGovernanceValue] = ["id": id, "name": .string("  Night walk  "), "startDate": date]
        fields.merge(extra) { _, new in new }; return .object(fields)
    }
    private func snapshot(_ rows: [ClubGovernanceValue], authority: Bool = true, operation: ClubGovernanceRead = .topics) throws -> ClubGovernanceSnapshot {
        let permission: ClubGovernanceValue = .object(["active": .bool(true), "club": .object(["id": .integer(81)]), "roleCodes": .array([]), "permissions": .array([])])
        return .init(operation: operation, scope: scope, permissions: authority ? try ClubGovernancePermissions(value: permission, scope: scope) : nil, value: .array(rows))
    }
    func testExactMiniLeapMonthMondayFirstSixWeeksAndSameDayGrouping() throws {
        let parsed = try ClubEventCalendarSnapshot(snapshot: snapshot([row(), row(.integer(92)), row(.integer(93), date: .string("2028-03-01"))]), context: context())
        let month = try XCTUnwrap(ClubEventMonth(year: 2028, month: 2))
        let cells = month.cells(events: parsed.events)
        XCTAssertEqual(cells.count, 42)
        XCTAssertEqual(cells.first?.id, "2028-01-31")
        XCTAssertEqual(cells.last?.id, "2028-03-12")
        XCTAssertEqual(cells.first(where: { $0.id == "2028-02-29" })?.events.map(\.id), [91, 92])
        let march = try XCTUnwrap(cells.first(where: { $0.id == "2028-03-01" }))
        XCTAssertFalse(march.inMonth); XCTAssertEqual(march.events.map(\.id), [93])
    }
    func testMonthShiftHandlesYearRolloverAndBounds() throws {
        XCTAssertEqual(ClubEventMonth(year: 2028, month: 1)?.shifted(by: -1)?.key, "2027-12")
        XCTAssertEqual(ClubEventMonth(year: 2028, month: 12)?.shifted(by: 1)?.key, "2029-01")
        XCTAssertNil(ClubEventMonth(year: 1970, month: 1)?.shifted(by: -1))
        XCTAssertNil(ClubEventMonth(year: 9999, month: 12)?.shifted(by: 1))
        XCTAssertNil(ClubEventMonth(year: 2028, month: 1)?.shifted(by: Int.max))
        XCTAssertNil(ClubEventMonth(year: 2028, month: 0)); XCTAssertNil(ClubEventMonth(year: 2028, month: 13))
        XCTAssertNil(ClubEventMonth(year: 1969, month: 12))
    }
    func testSourceDatePrefixDoesNotShiftWithTimestampOffsetOrSpreadAcrossEndDate() throws {
        let row = row(date: .string("2028-02-29T23:00:00-08:00"), extra: ["endDate": .string("2028-03-05"), "dateText": .string("2028-03-01")])
        let result = try ClubEventCalendarSnapshot(snapshot: snapshot([row]), context: context())
        XCTAssertEqual(result.events.first?.startDay?.id, "2028-02-29")
        let cells = ClubEventMonth(year: 2028, month: 3)!.cells(events: result.events)
        XCTAssertFalse(cells.contains(where: { $0.inMonth && !$0.events.isEmpty }))
    }
    func testMissingAndInvalidDatesStayVisibleAsUndated() throws {
        let dates: [ClubGovernanceValue] = [.null, .string(""), .string("TBD"), .string("2027-02-29"), .string("2028-02-30"), .string("2028-13-01"), .integer(172800)]
        let result = try ClubEventCalendarSnapshot(snapshot: snapshot(dates.enumerated().map { row(.integer($0.offset + 1), date: $0.element) }), context: context())
        XCTAssertEqual(result.undated.count, dates.count)
        XCTAssertEqual(result.events.count, dates.count)
        XCTAssertTrue(ClubEventMonth(year: 2028, month: 2)!.cells(events: result.events).allSatisfy { $0.events.isEmpty })
    }
    func testMalformedDuplicateAndForeignClubRowsFailClosed() throws {
        for rows in [[row(), row()], [row(.integer(0))], [row(.decimal(91.5))], [row(.integer(9_007_199_254_740_992))], [row(extra: ["clubId": .integer(82)])], [row(extra: ["clubId": .string("invalid")])], [.null]] {
            XCTAssertThrowsError(try ClubEventCalendarSnapshot(snapshot: snapshot(rows), context: context()))
        }
    }
    func testOnlyExactAuthorizedTopicSnapshotIsAccepted() throws {
        XCTAssertThrowsError(try ClubEventCalendarSnapshot(snapshot: snapshot([row()], authority: false), context: context()))
        XCTAssertThrowsError(try ClubEventCalendarSnapshot(snapshot: snapshot([row()], operation: .eventTopics), context: context()))
        XCTAssertThrowsError(try ClubEventCalendarSnapshot(snapshot: snapshot([row()]), context: context(identity: nil)))
        XCTAssertThrowsError(try ClubEventCalendarSnapshot(snapshot: snapshot([row()]), context: context(identity: .init(accountID: 0, epoch: 1))))
    }
    func testEmptySuccessIsDistinctFromUnavailableAndBlankNamesUseFallback() throws {
        XCTAssertTrue(try ClubEventCalendarSnapshot(snapshot: snapshot([]), context: context()).events.isEmpty)
        let result = try ClubEventCalendarSnapshot(snapshot: snapshot([row(extra: ["name": .string(" \n ")])]), context: context())
        XCTAssertNil(result.events.first?.name)
    }
    func testRouteUsesExactTopicIDAndCannotSubstituteAnActivityID() throws {
        let result = try ClubEventCalendarSnapshot(snapshot: snapshot([row(extra: ["topicId": .integer(200), "activityId": .integer(201)])]), context: context())
        let route = try XCTUnwrap(ClubEventTopicRoute(topicID: 91, snapshot: result, context: context(), snapshotGeneration: 7))
        XCTAssertEqual(route.topicID, 91)
        XCTAssertNil(ClubEventTopicRoute(topicID: 201, snapshot: result, context: context(), snapshotGeneration: 7))
        XCTAssertTrue(route.isCurrent(snapshot: result, context: context(), snapshotGeneration: 7))
    }
    func testRouteInvalidatesOnNewerReadRoleEpochAccountOrRemovedTopic() throws {
        let result = try ClubEventCalendarSnapshot(snapshot: snapshot([row()]), context: context())
        let route = try XCTUnwrap(ClubEventTopicRoute(topicID: 91, snapshot: result, context: context(), snapshotGeneration: 7))
        XCTAssertFalse(route.isCurrent(snapshot: result, context: context(), snapshotGeneration: 8))
        XCTAssertFalse(route.isCurrent(snapshot: result, context: context(revision: 2), snapshotGeneration: 7))
        XCTAssertFalse(route.isCurrent(snapshot: result, context: context(identity: .init(accountID: 701, epoch: 2)), snapshotGeneration: 7))
        XCTAssertFalse(route.isCurrent(snapshot: result, context: context(identity: .init(accountID: 702, epoch: 1)), snapshotGeneration: 7))
        XCTAssertFalse(route.isCurrent(snapshot: nil, context: context(), snapshotGeneration: 7))
        let empty = try ClubEventCalendarSnapshot(snapshot: snapshot([]), context: context())
        XCTAssertFalse(route.isCurrent(snapshot: empty, context: context(), snapshotGeneration: 7))
    }
    func testMonthUsesExplicitDeviceTimeZoneOnlyForInitialMonth() throws {
        let instant = try XCTUnwrap(ISO8601DateFormatter().date(from: "2028-03-01T00:30:00Z"))
        XCTAssertEqual(ClubEventMonth(now: instant, timeZone: TimeZone(secondsFromGMT: -8 * 3600)!).key, "2028-02")
        XCTAssertEqual(ClubEventMonth(now: instant, timeZone: TimeZone(secondsFromGMT: 8 * 3600)!).key, "2028-03")
    }
}
