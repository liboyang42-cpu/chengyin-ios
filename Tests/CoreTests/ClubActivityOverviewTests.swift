import XCTest
@testable import QuestifyCore

final class ClubActivityOverviewTests: XCTestCase {
    private final class Token {}
    private let token = Token()
    private let now = Date(timeIntervalSince1970: 1_791_691_200)
    private func context() -> ClubGovernanceReadContext {
        .init(operation: .topics, scope: .init(clubID: 81), identity: .init(accountID: 701, epoch: 1), viewerRevision: 1,
              authorizationGeneration: UUID(), accessIdentity: ObjectIdentifier(token))
    }
    private func overview(_ rows: [ClubGovernanceValue], club: Int = 81) throws -> ClubActivityOverview {
        let scope = ClubGovernanceScope(clubID: club)
        let permissions = try ClubGovernancePermissions(value: .object(["active": .bool(true), "club": .object(["id": .integer(club)]),
            "roleCodes": .array([]), "permissions": .array([])]), scope: scope)
        let snapshot = ClubGovernanceSnapshot(operation: .topics, scope: scope, permissions: permissions, value: .array(rows))
        return try .init(snapshot: snapshot, context: context(), now: now)
    }
    private func row(_ id: Int, _ fields: [String: ClubGovernanceValue] = [:]) -> ClubGovernanceValue {
        .object(["id": .integer(id), "clubId": .integer(81), "name": .string("Synthetic activity")].merging(fields) { _, new in new })
    }
    func testBareChinaSlashAndOffsetInstantsAreDeviceZoneIndependent() {
        for value in ["2026-10-11 12:00:00", "2026/10/11 12:0:0", "2026-10-11T04:00:00Z", "2026-10-11T12:00:00+0800",
                      "2026-10-10T23:00:00-05:00", "1791691200", "1791691200000"] {
            XCTAssertEqual(ClubActivitySourceTime.date(value)?.timeIntervalSince1970, now.timeIntervalSince1970)
        }
        XCTAssertEqual(ClubActivitySourceTime.date("2026-10-11")?.timeIntervalSince1970, 1_791_648_000)
    }
    func testInvalidCalendarsHoursOffsetsAndUnspecifiedNumericFormsAreRejected() {
        for value in ["", "2026-02-29", "2026-02-30", "2026-13-01", "2026-10-11 24:00", "2026-10-11T12:00:00+24:00", "0", "123.4", "not a date"] {
            XCTAssertNil(ClubActivitySourceTime.date(value))
        }
        XCTAssertNotNil(ClubActivitySourceTime.date("2024-02-29"))
    }
    func testVerifiedFractionSemanticsAndProlepticGregorianHistoricalYears() throws {
        XCTAssertEqual(try XCTUnwrap(ClubActivitySourceTime.date("2024-02-29 01:02:03.999")).timeIntervalSince1970, 1_709_139_723)
        XCTAssertEqual(try XCTUnwrap(ClubActivitySourceTime.date("2026-10-11T04:00:00.1239Z")).timeIntervalSince1970, 1_791_691_200.123, accuracy: 0.0001)
        XCTAssertEqual(ClubActivitySourceTime.date("0000-01-01")?.timeIntervalSince1970, -62_167_248_000)
        XCTAssertEqual(ClubActivitySourceTime.date("1500-03-01")?.timeIntervalSince1970, -14_826_700_800)
    }
    func testEndBoundaryIsStrictAndStartBoundaryInclusive() throws {
        let value = try overview([
            row(91, ["startDate": .string("2026-10-11 12:00:00"), "endDate": .string("2026-10-11 12:00:00")]),
            row(92, ["startDate": .string("2026-10-11 12:00:01")]),
            row(93, ["endDate": .string("2026-10-11 11:59:59")])])
        XCTAssertEqual(value.rows.map(\.status), [.live, .recruiting, .ended])
    }
    func testSplitPreservesSourceOrderAndDoesNotTrustUnrelatedStatusFlags() throws {
        let value = try overview([row(93, ["endDate": .string("2026-10-10")]), row(91),
                                  row(94, ["endDate": .string("2026-10-09")]), row(92, ["ended": .bool(true), "status": .string("REJECTED")])])
        XCTAssertEqual(value.current.map(\.id), [91, 92]); XCTAssertEqual(value.ended.map(\.id), [93, 94])
        XCTAssertEqual(value.rows.last?.status, .recruiting); XCTAssertEqual(value.observedAt, now)
    }
    func testProductTypeWinsAndModeOnlyFillsNull() throws {
        let value = try overview([row(91, ["productType": .integer(1), "mode": .integer(2)]),
                                  row(92, ["productType": .string("2"), "mode": .integer(1)]),
                                  row(93, ["productType": .null, "mode": .integer(2)]), row(94, ["productType": .integer(0), "mode": .integer(2)])])
        XCTAssertEqual(value.rows.map(\.category), [.orientation, .exploration, .exploration, .orientation])
    }
    func testUnknownZeroNegativeAndInvalidStatsAreAbsentRatherThanInventedZero() throws {
        let value = try overview([row(91), row(92, ["signupCount": .integer(0), "locationCount": .integer(-2), "totalMileage": .string("invalid")]),
                                  row(93, ["signupCount": .bool(true), "locationCount": .decimal(.infinity), "totalMileage": .decimal(.nan)])])
        for row in value.rows { XCTAssertNil(row.signups); XCTAssertNil(row.stations); XCTAssertNil(row.mileageKM) }
    }
    func testPositiveSourceNumbersAndNumericStringsRemainValues() throws {
        let value = try overview([row(91, ["signupCount": .string(" 12 "), "locationCount": .integer(8), "totalMileage": .string("3.25")])])
        XCTAssertEqual(value.rows[0].signups, 12); XCTAssertEqual(value.rows[0].stations, 8); XCTAssertEqual(value.rows[0].mileageKM, 3.3)
    }
    func testMileageRoundsLikeSourceWithoutCoercingMissingInputs() throws {
        let value = try overview([row(91, ["totalMileage": .decimal(0.04)]), row(92, ["totalMileage": .decimal(1.25)]),
                                  row(93, ["totalMileage": .decimal(100.16)]), row(94, ["totalMileage": .decimal(Double.greatestFiniteMagnitude)])])
        XCTAssertEqual(value.rows.map(\.mileageKM), [0, 1.3, 100.2, nil])
    }
    func testMetadataTrimAndDateOnlyKeepDisplayMeaning() throws {
        let value = try overview([row(91, ["name": .string("  Title  "), "imgUrl": .string(" cover "), "addressName": .string(" Park "), "startDate": .string("2026-10-11")]), row(92, ["name": .string(" ")])])
        XCTAssertEqual(value.rows[0].name, "Title"); XCTAssertEqual(value.rows[0].cover, "cover"); XCTAssertEqual(value.rows[0].address, "Park")
        XCTAssertTrue(value.rows[0].dateOnly); XCTAssertNil(value.rows[1].name)
    }
    func testCalendarAndRichListAlwaysProjectTheSameAcceptedTopicIDs() throws {
        let value = try overview([row(91, ["startDate": .string("2026-10-11")]), row(92)])
        XCTAssertEqual(value.calendar.events.map(\.id), value.rows.map(\.id)); XCTAssertEqual(value.calendar.undated.map(\.id), [92])
        XCTAssertEqual(value.calendar.clubID, 81)
    }
    func testDuplicateIDsAndWrongClubScopeRemainRejected() {
        XCTAssertThrowsError(try overview([row(91), row(91)]))
        XCTAssertThrowsError(try overview([row(91, ["clubId": .integer(82)])]))
        XCTAssertThrowsError(try overview([row(91)], club: 82))
    }
}
