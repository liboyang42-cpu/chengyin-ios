import XCTest
@testable import QuestifyCore

final class NearbyMerchantRowParityTests: XCTestCase {
    private func rows(_ text: String) throws -> [NearbyMerchantRow] {
        try (JSONDecoder().decode(CoopFlowJSON.self, from: Data(text.utf8)).rows ?? []).map(NearbyMerchantRow.init)
    }

    func testOrderingPutsUnknownDistanceLastAndDropsClosedRows() throws {
        let ordered = NearbyMerchantRow.ordered(try rows("""
        [{"id":1,"name":"Far","distance":900},{"id":2,"name":"Unknown"},{"id":3,"name":"Near","distance":"20"},
         {"id":4,"name":"Closed","distance":1,"coopOpen":"0"},{"id":5,"name":"Tie","distance":900}]
        """))
        XCTAssertEqual(ordered.map(\.id), [3, 1, 5, 2])
    }

    func testCallActionOnlyForCallableUnregisteredLeads() throws {
        let parsed = try rows("""
        [{"id":1,"name":"Lead","phone":"021-000","canCall":true},{"id":2,"name":"Hidden","phone":"021-000","canCall":false},
         {"id":3,"name":"Member","memberId":9,"phone":"021-000","canCall":true},{"id":4,"name":"Blank","phone":" ","canCall":true}]
        """)
        XCTAssertEqual(parsed.map(\.callablePhone), ["021-000", nil, nil, nil])
    }
}
