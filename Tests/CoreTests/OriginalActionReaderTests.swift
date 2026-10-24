import XCTest
@testable import QuestifyCore

final class OriginalActionReaderTests: XCTestCase {
    func testExistingPageAsksOriginalQueryOnceAndShowsOnlyMatchingIds() throws {
        let session: Int64 = 30
        let member: Int64 = 7
        let action = "check:1:alarm:tick"
        let same = RouteActionOriginalRow(
            actionID: action, responseJSON: "{\"ok\":true}", sessionID: session, memberID: member)
        var table = [same]
        var staged: RouteActionOriginalRow? = nil
        var originalQueries = 0
        var reader = OriginalActionReader { queriedSession, queriedMember, queriedAction in
            originalQueries += 1
            XCTAssertEqual(queriedSession, session)
            XCTAssertEqual(queriedMember, member)
            XCTAssertEqual(queriedAction, action)
            return staged
        }
        var page = RouteActionPageRead()

        page.appear()
        reader.appear()
        XCTAssertTrue(page.appeared)
        XCTAssertTrue(reader.appeared)
        XCTAssertEqual(page.reads, 0)
        XCTAssertEqual(reader.queries, 0)
        XCTAssertEqual(originalQueries, 0, "appearance does not read")
        XCTAssertEqual(reader.writes, 0)
        XCTAssertEqual(reader.sends, 0)
        XCTAssertNil(reader.httpPath)
        XCTAssertEqual(table, [same], "appearance does not write")

        func show() throws -> RouteActionOriginalRow? {
            let beforeQueries = originalQueries
            let beforeReads = page.reads
            let before = table
            let shown = try page.shownRow(
                sessionID: session, memberID: member, actionID: action, selectAction: reader.selectAction)
            XCTAssertEqual(originalQueries, beforeQueries + 1, "original query once")
            XCTAssertEqual(reader.queries, originalQueries)
            XCTAssertEqual(page.reads, beforeReads + 1)
            XCTAssertEqual(table, before, "read does not write")
            XCTAssertEqual(page.writes, 0)
            XCTAssertEqual(reader.writes, 0)
            XCTAssertEqual(reader.sends, 0)
            XCTAssertNil(reader.httpPath)
            return shown
        }

        staged = RouteActionOriginalRow(
            actionID: "game:done", responseJSON: "{}", sessionID: session, memberID: member)
        XCTAssertNil(try show(), "different action")
        staged = RouteActionOriginalRow(
            actionID: action, responseJSON: "{}", sessionID: 99, memberID: member)
        XCTAssertNil(try show(), "different session")
        staged = RouteActionOriginalRow(
            actionID: action, responseJSON: "{}", sessionID: session, memberID: 8)
        XCTAssertNil(try show(), "different member")
        staged = RouteActionOriginalRow(
            actionID: "game:done", responseJSON: "{}", sessionID: 99, memberID: 8)
        XCTAssertNil(try show(), "different session member and action")
        staged = nil
        XCTAssertNil(try show(), "missing row")

        staged = same
        let first = try show()
        let second = try show()
        XCTAssertEqual(first, same, "same row")
        XCTAssertEqual(second, same, "same ids show the same row")
        XCTAssertEqual(first, second)
        XCTAssertEqual(table, [same])
        XCTAssertEqual(reader.writes, 0)
        XCTAssertEqual(reader.sends, 0)
        XCTAssertNil(reader.httpPath)
        XCTAssertNil(MechanismRequestIdProjection().existing(action))

        var foreignQueries = 0
        let foreign = OriginalActionReader { queriedSession, queriedMember, queriedAction in
            foreignQueries += 1
            XCTAssertEqual(queriedSession, 99)
            XCTAssertEqual(queriedMember, member)
            XCTAssertEqual(queriedAction, action)
            return same
        }
        XCTAssertNil(try page.shownRow(
            sessionID: 99, memberID: member, actionID: action, selectAction: foreign.selectAction),
            "different session is not this action")
        XCTAssertEqual(foreignQueries, 1)
        XCTAssertEqual(foreign.queries, 1)
        XCTAssertEqual(foreign.sends, 0)
        XCTAssertEqual(table, [same])

        let closed = OriginalActionReader(selectActionByAction: nil)
        XCTAssertNil(closed.selectAction)
        XCTAssertEqual(closed.queries, 0)
        XCTAssertEqual(closed.sends, 0)
        var closedPage = RouteActionPageRead()
        do {
            _ = try closedPage.shownRow(
                sessionID: session, memberID: member, actionID: action, selectAction: closed.selectAction)
            XCTFail("missing original query must stay WAITING_SOURCE and must not send")
        } catch let error as MechanismFailure {
            XCTAssertEqual(error, .waitingSource(capability: MechanismRequestIdProjection.selectActionByAction))
        }
        XCTAssertEqual(closed.queries, 0)
        XCTAssertEqual(closed.writes, 0)
        XCTAssertEqual(closed.sends, 0)
        XCTAssertNil(closed.httpPath)
        XCTAssertEqual(table, [same], "stopped send does not write")
    }
}
