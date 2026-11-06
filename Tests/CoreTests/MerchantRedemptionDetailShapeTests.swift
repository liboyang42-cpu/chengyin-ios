import XCTest
@testable import QuestifyCore

final class MerchantRedemptionDetailShapeTests: XCTestCase {
    private var source: MerchantBusinessObject {
        ["recordKey": .string("redemption:42"), "recordId": .string("42"),
         "recordType": .string("redemption"), "fulfillmentState": .string("ACTIVE")]
    }
    private func decode(_ fields: MerchantBusinessObject) throws {
        _ = try MerchantBusinessDocument(query: .redemption(recordID: "42"), payload: .object(fields))
    }
    func testOriginalIdentityAndFulfillmentAreRequired() {
        for key in ["recordId", "recordType", "fulfillmentState"] {
            var value = source; value.removeValue(forKey: key)
            XCTAssertThrowsError(try decode(value), key)
        }
    }
    func testForeignIdentityIsRejected() {
        var value = source; value["recordId"] = .string("43")
        XCTAssertThrowsError(try decode(value))
    }
    func testFullyRedactedDetailRemainsReadable() throws {
        try decode(source)
        var value = source
        for key in ["settlementState", "settlementRoute", "displayState", "settlementAmount", "publicSettlement"] {
            value[key] = .null
        }
        try decode(value)
    }
    func testUnknownNonemptyStatesAreNotInventedOrRejected() throws {
        var value = source; value["fulfillmentState"] = .string("FUTURE")
        value["settlementState"] = .string("FUTURE")
        value["settlementRoute"] = .string("FUTURE")
        value["displayState"] = .string("FUTURE")
        try decode(value)
    }
    func testPartialFinanceCannotLookLikeRedactedDetail() {
        for key in ["settlementState", "settlementRoute", "displayState", "settlementAmount", "publicSettlement"] {
            var value = source
            value[key] = key == "publicSettlement" ? .object([:]) : .string(key == "settlementAmount" ? "1.00" : "PENDING")
            XCTAssertThrowsError(try decode(value), key)
        }
    }
}
