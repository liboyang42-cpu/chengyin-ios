import XCTest
@testable import QuestifyCore

final class RouteActionPageReadTests: XCTestCase {
    func testAppearanceDoesNotWriteAndWrongIdsAreNotThisAction() throws {
        var page = RouteActionPageRead()
        let session: Int64 = 30
        let member: Int64 = 7
        let action = "check:1:alarm:tick"
        let same = RouteActionOriginalRow(
            actionID: action, responseJSON: "{\"ok\":true}", sessionID: session, memberID: member)
        var table = [same]
        var probes = 0

        page.appear()
        XCTAssertTrue(page.appeared)
        XCTAssertEqual(page.reads, 0)
        XCTAssertEqual(page.writes, 0)
        XCTAssertEqual(probes, 0, "appearance does not read")
        XCTAssertEqual(table, [same], "appearance does not write")

        func show(_ row: RouteActionOriginalRow?) throws -> RouteActionOriginalRow? {
            let before = table
            let shown = try page.shownRow(sessionID: session, memberID: member, actionID: action, selectAction: { queriedSession, queriedMember, queriedAction in
                probes += 1
                XCTAssertEqual(queriedSession, session)
                XCTAssertEqual(queriedMember, member)
                XCTAssertEqual(queriedAction, action)
                return row
            })
            XCTAssertEqual(table, before, "read does not write")
            XCTAssertEqual(page.writes, 0)
            return shown
        }

        XCTAssertNil(try show(RouteActionOriginalRow(
            actionID: "game:done", responseJSON: "{}", sessionID: session, memberID: member)), "different action")
        XCTAssertNil(try show(RouteActionOriginalRow(
            actionID: action, responseJSON: "{}", sessionID: 99, memberID: member)), "different session")
        XCTAssertNil(try show(RouteActionOriginalRow(
            actionID: action, responseJSON: "{}", sessionID: session, memberID: 8)), "different member")
        XCTAssertNil(try show(RouteActionOriginalRow(
            actionID: "game:done", responseJSON: "{}", sessionID: 99, memberID: 8)), "different session member and action")
        XCTAssertNil(try show(nil), "missing row")

        let first = try show(same)
        let second = try show(same)
        XCTAssertEqual(first, same, "same row")
        XCTAssertEqual(second, same, "same ids show the same row")
        XCTAssertEqual(first, second)
        XCTAssertEqual(table, [same])
        XCTAssertGreaterThan(page.reads, 0)
        XCTAssertEqual(page.writes, 0)
        XCTAssertNil(MechanismRequestIdProjection().existing(action))

        var probed = false
        XCTAssertNil(try page.shownRow(sessionID: 99, memberID: member, actionID: action, selectAction: { _, _, _ in
            probed = true
            return same
        }), "different session is not this action")
        XCTAssertNil(try page.shownRow(sessionID: session, memberID: 8, actionID: action, selectAction: { _, _, _ in
            probed = true
            return same
        }), "different member is not this action")
        XCTAssertNil(try page.shownRow(sessionID: session, memberID: member, actionID: "game:done", selectAction: { _, _, _ in
            probed = true
            return same
        }), "different action is not this action")
        XCTAssertTrue(probed)
        XCTAssertEqual(table, [same])
        XCTAssertEqual(page.writes, 0)
    }
}
