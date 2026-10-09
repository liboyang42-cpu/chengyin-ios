import XCTest
@testable import QuestifyCore

final class ProjectEditDateSelectionTests: XCTestCase {
    private func instant(_ text: String) throws -> Date { try XCTUnwrap(ISO8601DateFormatter().date(from: text)) }
    func testFixedBeijingOffsetAndCalendarYearCrossUTCYearBoundary() throws {
        let date = try XCTUnwrap(ProjectEditDateSelection.date("2021-01-01 00:00:00", ending: false))
        XCTAssertEqual(date, try instant("2020-12-31T16:00:00Z"))
        XCTAssertEqual(ProjectEditDateSelection.beijingValue(date), "2021-01-01 00:00:00")
        XCTAssertEqual(ProjectEditDateSelection.beijingValue(try instant("2030-05-01T20:15:00Z")), "2030-05-02 04:15:00")
    }
    func testKnownDateOnlyMinuteISOSeparatorAndWhitespaceNoOpsKeepExactOriginalBytes() throws {
        for raw in ["2030-05-01", "2030-05-01 09:15", "2030-05-01T09:15:42", " 2030-05-01 09:15:42 \n"] {
            var draft = ProjectEditSyntheticFixtures.draft(product: .freeExplore); draft.startDate = raw
            let date = try XCTUnwrap(ProjectEditDateSelection.date(raw, ending: false))
            let next = try ProjectEditDateSelection.applying(date, field: .start, to: draft)
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(next), ProjectEditPendingMaterials.exactData(draft))
            XCTAssertEqual(Array(next.startDate.utf8), Array(raw.utf8))
        }
        XCTAssertEqual(ProjectEditDateSelection.beijingValue(try XCTUnwrap(ProjectEditDateSelection.date("2030-05-30", ending: true))), "2030-05-30 23:59:59")
    }
    func testDSTRepeatedPhoneHourRemainsTwoDifferentInstantsAndBeijingValues() throws {
        let first = try instant("2026-11-01T08:30:00Z"), second = try instant("2026-11-01T09:30:00Z")
        let format = DateFormatter(); format.locale = Locale(identifier: "en_US_POSIX")
        format.calendar = Calendar(identifier: .gregorian); format.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles")); format.dateFormat = "yyyy-MM-dd HH:mm"
        XCTAssertEqual(format.string(from: first), format.string(from: second))
        XCTAssertEqual(ProjectEditDateSelection.beijingValue(first), "2026-11-01 16:30:00")
        XCTAssertEqual(ProjectEditDateSelection.beijingValue(second), "2026-11-01 17:30:00")
        XCTAssertEqual(second.timeIntervalSince(first), 3600)
    }
    func testUnknownStoredFormatsAndNonFiniteInstantsAreNotGuessed() throws {
        for raw in ["tomorrow", "2026-02-30", "2026-10-09T09:00:00Z", "01/02/26"] {
            XCTAssertNil(ProjectEditDateSelection.date(raw, ending: false))
            var draft = ProjectEditSyntheticFixtures.draft(product: .freeExplore); draft.startDate = raw
            XCTAssertThrowsError(try ProjectEditDateSelection.applying(try instant("2030-05-03T00:00:00Z"), field: .start, to: draft))
            XCTAssertEqual(draft.startDate, raw)
        }
        XCTAssertNil(ProjectEditDateSelection.beijingValue(Date(timeIntervalSince1970: .infinity)))
    }
    func testEndBeforeStartAndCityEqualBoundaryAreRejectedWithoutChangingDraft() throws {
        var draft = ProjectEditSyntheticFixtures.draft(product: .city)
        let before = ProjectEditPendingMaterials.exactData(draft), ticketID = draft.tickets[0].id
        XCTAssertThrowsError(try ProjectEditDateSelection.applying(try instant("2030-04-01T00:00:00Z"), field: .end, to: draft))
        let ticketStart = try XCTUnwrap(ProjectEditDateSelection.date(draft.tickets[0].startTime, ending: false))
        XCTAssertThrowsError(try ProjectEditDateSelection.applying(ticketStart, field: .ticketEnd(ticketID), to: draft))
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(draft), before)
        draft.product = .freeExplore
        let equal = try ProjectEditDateSelection.applying(ticketStart, field: .ticketEnd(ticketID), to: draft)
        XCTAssertEqual(equal.tickets[0].endTime, "2030-05-02 10:00:00")
    }
    func testSyncedTicketAndUnsupportedStoredSaleTypeAreReadOnly() throws {
        var draft = ProjectEditSyntheticFixtures.draft(product: .freeExplore); let id = draft.tickets[0].id
        draft.tickets[0].localMetadata["syncWithTheme"] = .bool(true)
        XCTAssertFalse(ProjectEditDateSelection.Field.ticketStart(id).editable(in: draft))
        XCTAssertThrowsError(try ProjectEditDateSelection.applying(try instant("2030-05-03T00:00:00Z"), field: .ticketStart(id), to: draft))
        draft.tickets[0].localMetadata["saleStartTime"] = .number(8)
        XCTAssertFalse(ProjectEditDateSelection.Field.saleStart(id).editable(in: draft))
        XCTAssertThrowsError(try ProjectEditDateSelection.applying(try instant("2030-05-03T00:00:00Z"), field: .saleStart(id), to: draft))
    }
    func testConfirmChangesOnlyTargetAndKeepsExistingMetadataAndSaleRangeRules() throws {
        var draft = ProjectEditSyntheticFixtures.draft(product: .freeExplore); let id = draft.tickets[0].id
        draft.tickets[0].saleStartTime = "2030-04-01"; draft.tickets[0].saleEndTime = "2030-04-20"
        draft.tickets[0].localMetadata["future"] = .string(" e\u{301} ")
        let selected = try instant("2030-04-10T02:30:00Z")
        let next = try ProjectEditDateSelection.applying(selected, field: .saleStart(id), to: draft)
        var expected = draft; expected.tickets[0].saleStartTime = "2030-04-10 10:30:00"
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(next), ProjectEditPendingMaterials.exactData(expected))
        XCTAssertThrowsError(try ProjectEditDateSelection.applying(try instant("2030-03-01T00:00:00Z"), field: .saleEnd(id), to: draft))
    }
}
