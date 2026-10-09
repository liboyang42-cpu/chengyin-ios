import XCTest
@testable import QuestifyCore

final class PublicMerchantHomeBusinessStateTests: XCTestCase {
    private func home(_ status: Int?, hours: String = "") throws -> PublicMerchantHome {
        var value: [String: Any] = ["id":22,"memberId":41,"businessTime":hours]
        if let status { value["businessStatus"] = status }
        return try JSONDecoder().decode(PublicMerchantHome.self, from: JSONSerialization.data(withJSONObject: value))
    }
    func testKnownStatusValuesKeepExistingMeaning() throws {
        XCTAssertEqual(try home(1).businessState, .open)
        XCTAssertEqual(try home(0).businessState, .closed)
    }
    func testMissingNegativeAndFutureStatusAreUnknownNotClosed() throws {
        let statuses: [Int?] = [nil, -1, 2, 99, Int.max]
        for status in statuses { XCTAssertEqual(try home(status).businessState, .unknown) }
    }
    func testHoursAndIdentityDoNotSupplyMissingStatusOrChangeExistingTargets() throws {
        let value = try home(nil, hours: "Open 24 hours")
        XCTAssertEqual(value.businessState, .unknown)
        XCTAssertEqual(value.businessTime, "Open 24 hours")
        XCTAssertEqual(value.reviewTarget?.merchantRowID.rawValue, 22)
        XCTAssertEqual(value.reviewTarget?.ownerMemberID.rawValue, 41)
        XCTAssertFalse(value.canOfferNPCChat(shopNpcChat: false))
    }
    func testUnexpectedStringCodeStillFailsOriginalTypedDecoder() {
        XCTAssertThrowsError(try JSONDecoder().decode(PublicMerchantHome.self,
            from: Data(#"{"id":22,"memberId":41,"businessStatus":"1"}"#.utf8)))
    }
}
