import XCTest
@testable import QuestifyCore

final class OfficialPrivateFactsDecodingTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T { try JSONDecoder().decode(type, from: Data(json.utf8)) }
    func testInboxRowCarriesServiceWindowFromTheSameRow() throws {
        let row = try decode(OfficialPartyInvite.self, #"{"partyId":5,"status":"INVITED","windowStart":1758502800000}"#)
        XCTAssertEqual(row.windowFacts?.window, .range(.time(month: 9, day: 22, hour: 9, minute: 0), .open))
        let open = try decode(OfficialPartyInvite.self, #"{"partyId":6,"status":"ACCEPTED"}"#)
        XCTAssertEqual(open.windowFacts?.window, .unbounded)
        let text = try decode(OfficialPartyInvite.self, #"{"partyId":7,"windowEnd":"2026-10-01 18:00"}"#)
        XCTAssertEqual(text.windowFacts?.window, .range(.open, .text("2026-10-01 18:00")))
    }
    func testBroadcastRowCarriesSourceFactsWithoutGuessing() throws {
        let row = try decode(OfficialBroadcast.self, #"{"id":3,"title":"t","copyMode":1,"audience":"player,merchant","status":2,"city":" 杭州 ","reachedCount":4}"#)
        XCTAssertEqual(row.reach, 4)
        XCTAssertEqual(row.facts?.mode, .together); XCTAssertEqual(row.facts?.status, .sent)
        XCTAssertEqual(row.facts?.audience, [.player, .merchant]); XCTAssertEqual(row.facts?.city, "杭州")
        let unknown = try decode(OfficialBroadcast.self, #"{"id":4,"title":"t","audience":"player,staff"}"#)
        XCTAssertEqual(unknown.facts?.mode, .unknown); XCTAssertEqual(unknown.facts?.status, .unknown)
        XCTAssertNil(unknown.facts?.audience); XCTAssertNil(unknown.facts?.city)
    }
}
