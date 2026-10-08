import XCTest
@testable import QuestifyCore

final class ProjectTicketMeetingPointTests: XCTestCase {
    private func ticket() -> ProjectEditTicket {
        var value = ProjectEditTicket(); value.meetingPoint = "Fixture pier"
        value.localMetadata = ["meetingPointAddress": .string("Fixture boardwalk"),
                              "gatherLng": .number(Decimal(string: "121.5")!), "gatherLat": .number(Decimal(string: "31.2")!),
                              "future": .object(["retained": .bool(true)])]
        return value
    }
    func testNumericReadbackProjectsWithoutLosingCoordinatesOrUnknownSiblings() throws {
        let source = ticket(), value = ProjectTicketMeetingPoint(ticket: source)
        XCTAssertEqual(value.longitude, "121.5"); XCTAssertEqual(value.latitude, "31.2")
        XCTAssertEqual(value.address, "Fixture boardwalk"); XCTAssertTrue(value.canApply)
        XCTAssertEqual(try value.applying(to: source), source)
        let wire = try ProjectTicketMeetingPoint.wireFields(source)
        XCTAssertEqual(wire["gatherLng"], .number(Decimal(string: "121.5")!))
        XCTAssertEqual(wire["gatherLat"], .number(Decimal(string: "31.2")!))
        XCTAssertEqual(wire["meetingPointAddress"], .string("Fixture boardwalk"))
        XCTAssertEqual(Set(wire.keys), ["meetingPoint", "meetingPointAddress", "gatherLng", "gatherLat"])
        XCTAssertNil(wire["future"])
    }
    func testMissingNullAndZeroHaveDistinctWireMeanings() throws {
        var source = ProjectEditTicket(); source.meetingPoint = "Fixture pier"
        XCTAssertNil(try ProjectTicketMeetingPoint.wireFields(source)["gatherLng"])
        source.localMetadata["gatherLng"] = .null; source.localMetadata["gatherLat"] = .null
        XCTAssertEqual(try ProjectTicketMeetingPoint.wireFields(source)["gatherLng"], .null)
        var edit = ProjectTicketMeetingPoint(ticket: source); edit.longitude = "0"; edit.latitude = "0"
        let updated = try edit.applying(to: source)
        XCTAssertEqual(try ProjectTicketMeetingPoint.wireFields(updated)["gatherLng"], .number(0))
        XCTAssertEqual(try ProjectTicketMeetingPoint.wireFields(updated)["gatherLat"], .number(0))
    }
    func testCoordinatePairBoundsFiniteDecimalAndZeroValidation() throws {
        for (longitude, latitude, valid) in [
            ("", "", true), ("0", "0", true), ("-180", "-90", true), ("180", "90", true),
            ("121.500001", "31.200001", true), (" 0 ", " 1 ", true),
            ("181", "0", false), ("0", "-91", false), ("0", "", false), ("", "0", false),
            ("NaN", "31", false), ("inf", "31", false), ("1e2", "31", false), ("1,2", "31", false)
        ] {
            var value = ProjectTicketMeetingPoint(ticket: ticket()); value.longitude = longitude; value.latitude = latitude
            XCTAssertEqual(value.hasValidCoordinates, valid, "\(longitude),\(latitude)")
            if valid { XCTAssertNoThrow(try value.applying(to: ticket())) }
            else { XCTAssertThrowsError(try value.applying(to: ticket())) }
        }
    }
    func testExplicitClearUsesNullAndNeverResurrectsNumericReadback() throws {
        let source = ticket(); var value = ProjectTicketMeetingPoint(ticket: source)
        value.longitude = ""; value.latitude = ""; value.address = ""
        let updated = try value.applying(to: source)
        XCTAssertEqual(updated.localMetadata["future"], source.localMetadata["future"])
        XCTAssertEqual(updated.id, source.id); XCTAssertEqual(updated.meetingPoint, source.meetingPoint)
        XCTAssertEqual(ProjectTicketMeetingPoint(ticket: updated).longitude, "")
        let wire = try ProjectTicketMeetingPoint.wireFields(updated)
        for key in ["gatherLng", "gatherLat", "meetingPointAddress"] { XCTAssertEqual(wire[key], .null) }
        let restored = try JSONDecoder().decode(ProjectEditTicket.self, from: JSONEncoder().encode(updated))
        XCTAssertEqual(try ProjectTicketMeetingPoint.wireFields(restored), wire)
        var malformed = source; malformed.gatherLng = " "; malformed.gatherLat = " "
        XCTAssertThrowsError(try ProjectTicketMeetingPoint.wireFields(malformed))
    }
    func testUntouchedKnownFieldsKeepMissingNullAndLocalEnvelopeBytes() throws {
        for raw in [ProjectEditJSON.null, .string("")] {
            var source = ProjectEditTicket(); source.meetingPoint = "Fixture pier"
            source.localMetadata["meetingPointAddress"] = raw
            let applied = try ProjectTicketMeetingPoint(ticket: source).applying(to: source)
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(applied), ProjectEditPendingMaterials.exactData(source))
            XCTAssertEqual(try ProjectTicketMeetingPoint.wireFields(applied)["meetingPointAddress"], raw)
        }
        let source = ticket() // Simulates an older envelope with numeric metadata and empty strings.
        let restored = try JSONDecoder().decode(ProjectEditTicket.self, from: JSONEncoder().encode(source))
        XCTAssertTrue(restored.gatherLng.isEmpty)
        XCTAssertEqual(ProjectTicketMeetingPoint(ticket: restored).longitude, "121.5")
        var clearedName = source; clearedName.localMetadata["meetingPoint"] = .string(source.meetingPoint)
        clearedName.meetingPoint = ""
        XCTAssertEqual(try ProjectTicketMeetingPoint.wireFields(clearedName)["meetingPoint"], .string(""))
    }
    func testUnsupportedOriginalTypesAreRetainedReadOnlyAndFailFullWire() throws {
        for key in ["meetingPoint", "meetingPointAddress", "gatherLng", "gatherLat"] {
            let invalid: [ProjectEditJSON] = key.hasPrefix("gather")
                ? [.string("121.5"), .bool(false), .object(["future": .number(1)]), .array([])]
                : [.number(3), .bool(false), .object(["future": .number(1)]), .array([])]
            for raw in invalid {
                var source = ticket(); source.localMetadata[key] = raw
                let before = ProjectEditPendingMaterials.exactData(source)
                XCTAssertFalse(ProjectTicketMeetingPoint.supportsEditing(source), key)
                var edit = ProjectTicketMeetingPoint(ticket: source); edit.name = "Changed"
                XCTAssertThrowsError(try edit.applying(to: source))
                XCTAssertThrowsError(try ProjectTicketMeetingPoint.wireFields(source))
                let restored = try JSONDecoder().decode(ProjectEditTicket.self, from: JSONEncoder().encode(source))
                XCTAssertEqual(restored.localMetadata[key], raw)
                XCTAssertEqual(ProjectEditPendingMaterials.exactData(source), before)
            }
        }
    }
    func testOnlyExplicitFieldsChangeAndNoLocationConversionOccurs() throws {
        let source = ticket(); var edit = ProjectTicketMeetingPoint(ticket: source)
        edit.name = "Fixture gate"; edit.address = "Fixture east gate"; edit.longitude = "121.500002"
        let updated = try edit.applying(to: source)
        var expected = source; expected.meetingPoint = edit.name
        expected.localMetadata["meetingPointAddress"] = .string(edit.address)
        expected.gatherLng = edit.longitude; expected.localMetadata["gatherLng"] = .number(Decimal(string: edit.longitude)!)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(updated), ProjectEditPendingMaterials.exactData(expected))
        XCTAssertEqual(try ProjectTicketMeetingPoint.wireFields(updated)["gatherLat"], source.localMetadata["gatherLat"])
    }
    func testEmptyMeetingNameCannotApplyButOptionalCoordinatesMayRemainAbsent() throws {
        var edit = ProjectTicketMeetingPoint(ticket: ticket()); edit.name = " \n"
        XCTAssertFalse(edit.canApply); XCTAssertThrowsError(try edit.applying(to: ticket()))
        edit.name = "Fixture pier"; edit.longitude = ""; edit.latitude = ""
        XCTAssertTrue(edit.canApply)
    }
    func testAuthoritativeDecodeAndFullPayloadUseBackendNumberTypes() throws {
        let data = Data(#"{"code":200,"data":{"editScope":"FULL","topic":{"id":71,"productType":1,"name":"Route","description":"Description","imgUrl":"fixture://cover","categoryIds":"7","updateTime":"r1","startDate":"2030-05-01","endDate":"2030-05-30"},"chapters":[{"id":11,"name":"Opening","description":"An actual fixture story","cmsTopicNodeList":[{"id":22,"name":"Stop","longitude":"121","latitude":"31"}]}],"tickets":[{"name":"Fixture ticket","price":0,"totalInventory":15,"startTime":"2030-05-02 10:00","endTime":"2030-05-02 12:00","meetingPoint":"Fixture pier","meetingPointAddress":"Fixture boardwalk","gatherLng":121.5,"gatherLat":31.2,"future":{"keep":true}}]}}"#.utf8)
        let draft = try ProjectEditContract.decodeEditDetail(data, expectedTopicID: 71, owner: .personal).draft
        XCTAssertEqual(draft.tickets[0].gatherLng, "121.5"); XCTAssertEqual(draft.tickets[0].gatherLat, "31.2")
        let row = try XCTUnwrap(try ProjectEditContract.payload(draft, topicID: 71, scope: .full)["tickets"]?.array?.first?.object)
        XCTAssertEqual(row["gatherLng"], .number(Decimal(string: "121.5")!))
        XCTAssertEqual(row["gatherLat"], .number(Decimal(string: "31.2")!))
        XCTAssertEqual(row["meetingPointAddress"], .string("Fixture boardwalk")); XCTAssertNil(row["future"])
        XCTAssertEqual(draft.tickets[0].localMetadata["future"], .object(["keep": .bool(true)]))
        XCTAssertNil(try ProjectEditContract.payload(draft, topicID: 71, scope: .whitelist)["tickets"])
    }
    func testInvalidImportedCoordinateBlocksFullButNotWhitelistWithoutChangingDraft() throws {
        var draft = ProjectEditSyntheticFixtures.draft(); draft.tickets[0] = ticket()
        draft.tickets[0].localMetadata["gatherLat"] = .object(["future": .number(1)])
        let before = ProjectEditPendingMaterials.exactData(draft)
        XCTAssertTrue(ProjectEditValidation.issues(draft).contains { $0.key == "projectTicketMeetingPoint.invalidStored" })
        XCTAssertThrowsError(try ProjectEditContract.payload(draft, topicID: 71, scope: .full))
        XCTAssertFalse(ProjectEditValidation.issues(draft, scope: .whitelist).contains { $0.key == "projectTicketMeetingPoint.invalidStored" })
        XCTAssertNil(try ProjectEditContract.payload(draft, topicID: 71, scope: .whitelist)["tickets"])
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(draft), before)
    }
}
