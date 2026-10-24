import XCTest
@testable import QuestifyCore

final class RouteActionReadbackFlowTests: XCTestCase {
    func testRequestReadMismatchReturnsNilAndSameIdsRecoverTheSameRow() throws {
        let flow = RouteActionReadbackFlow()
        let session: Int64 = 30
        let member: Int64 = 7
        let action = "check:1:alarm:tick"
        let same = RouteActionOriginalRow(
            actionID: action, responseJSON: "{\"ok\":true}", sessionID: session, memberID: member)
        var table = [same]
        var reads = 0

        func read(_ row: RouteActionOriginalRow?) throws -> RouteActionOriginalRow? {
            let before = table
            let result = try flow.recover(sessionID: session, memberID: member, actionID: action, selectAction: { queriedSession, queriedMember, queriedAction in
                reads += 1
                XCTAssertEqual(queriedSession, session)
                XCTAssertEqual(queriedMember, member)
                XCTAssertEqual(queriedAction, action)
                return row
            })
            XCTAssertEqual(table, before)
            return result
        }

        XCTAssertNil(try read(RouteActionOriginalRow(
            actionID: "game:done", responseJSON: "{}", sessionID: session, memberID: member)), "different action")
        XCTAssertNil(try read(RouteActionOriginalRow(
            actionID: action, responseJSON: "{}", sessionID: 99, memberID: member)), "different session")
        XCTAssertNil(try read(RouteActionOriginalRow(
            actionID: action, responseJSON: "{}", sessionID: session, memberID: 8)), "different member")
        XCTAssertNil(try read(RouteActionOriginalRow(
            actionID: "game:done", responseJSON: "{}", sessionID: 99, memberID: 8)), "different session member and action")
        XCTAssertNil(try read(RouteActionOriginalRow(
            actionID: "game:done", responseJSON: "{}")), "different action with absent session and member")
        XCTAssertNil(try read(nil), "missing row")

        let absentSession = RouteActionOriginalRow(actionID: action, responseJSON: "{\"ok\":true}", memberID: member)
        XCTAssertEqual(try read(absentSession), absentSession, "absent session keeps the existing check")
        let absentMember = RouteActionOriginalRow(actionID: action, responseJSON: "{\"ok\":true}", sessionID: session)
        XCTAssertEqual(try read(absentMember), absentMember, "absent member keeps the existing check")
        let absentBoth = RouteActionOriginalRow(actionID: action, responseJSON: "{\"ok\":true}")
        XCTAssertEqual(try read(absentBoth), absentBoth, "absent session and member keep the existing check")

        table = [same]
        let recovered = try read(same)
        XCTAssertEqual(recovered, same)
        XCTAssertEqual(recovered?.actionID, action)
        XCTAssertEqual(recovered?.sessionID, session as Int64?)
        XCTAssertEqual(recovered?.memberID, member as Int64?)
        XCTAssertEqual(table, [same])
        XCTAssertGreaterThan(reads, 0)
        XCTAssertNil(MechanismRequestIdProjection().existing(action))

        var probed = false
        XCTAssertNil(try flow.recover(sessionID: 0, memberID: member, actionID: action, selectAction: { _, _, _ in
            probed = true
            return same
        }))
        XCTAssertNil(try flow.recover(sessionID: nil, memberID: member, actionID: action, selectAction: { _, _, _ in
            probed = true
            return same
        }))
        XCTAssertNil(try flow.recover(sessionID: session, memberID: 0, actionID: "  ", selectAction: { _, _, _ in
            probed = true
            return same
        }))
        XCTAssertFalse(probed)
        do {
            _ = try flow.recover(sessionID: session, memberID: member, actionID: action, selectAction: nil)
            XCTFail("missing reader must stay WAITING_SOURCE")
        } catch let error as MechanismFailure {
            XCTAssertEqual(error, .waitingSource(capability: MechanismRequestIdProjection.selectActionByAction))
        }
        XCTAssertEqual(table, [same])
    }
}
