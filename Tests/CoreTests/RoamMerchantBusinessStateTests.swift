import XCTest
@testable import QuestifyCore

final class RoamMerchantBusinessStateTests: XCTestCase {
    private func merchant(status: Int?, hours: String = "", address: String = "") throws -> RoamPublicMerchant {
        var fields: [String: Any] = ["id":22,"name":"Synthetic merchant","businessTime":hours,"address":address]
        if let status { fields["businessStatus"] = status }
        return try JSONDecoder().decode(RoamPublicMerchant.self, from: JSONSerialization.data(withJSONObject: fields))
    }
    func testOnlySourceOneMeansOpenAndZeroMeansClosed() throws {
        XCTAssertEqual(try merchant(status: 1).businessState, .open)
        XCTAssertEqual(try merchant(status: 0).businessState, .closed)
    }
    func testMissingAndFutureCodesRemainUnknown() throws {
        let statuses: [Int?] = [nil, -1, 2, 9, Int.max]
        for status in statuses {
            XCTAssertEqual(try merchant(status: status).businessState, .unknown)
        }
    }
    func testBusinessHoursAndPublicAddressCannotTurnUnknownIntoOpen() throws {
        XCTAssertEqual(try merchant(status: nil, hours: "Open 24 hours", address: "Public address").businessState, .unknown)
        XCTAssertEqual(try merchant(status: 2, hours: "每天营业", address: "公开地点").businessState, .unknown)
    }
    func testExplicitClosedStatusIsNotOverriddenByHoursText() throws {
        let value = try merchant(status: 0, hours: "Open 24 hours")
        XCTAssertEqual(value.businessState, .closed)
        XCTAssertEqual(value.businessTime, "Open 24 hours")
        XCTAssertEqual(value.businessStatus, 0)
    }
    func testUnexpectedStringCodeRetainsExistingDecoderFailure() {
        XCTAssertThrowsError(try JSONDecoder().decode(RoamPublicMerchant.self,
            from: Data(#"{"id":22,"businessStatus":"1"}"#.utf8)))
    }
}
