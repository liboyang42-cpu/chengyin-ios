import Foundation
import XCTest
@testable import QuestifyCore

final class MerchantCoopChargeChoiceTests: XCTestCase {
    private func decode(_ json: String) throws -> MerchantCoopSettings { try JSONDecoder().decode(MerchantCoopSettings.self, from: Data(json.utf8)) }
    func testMissingAndNullRemainUnselectedAndCannotCreateSavePreview() throws {
        for json in [#"{}"#, #"{"chargeType":null}"#, #"{"capacity":12}"#] {
            let value = try decode(json)
            XCTAssertNil(value.chargeType); XCTAssertEqual(value.blocker, "merchant.coopChargeChoice.required")
            XCTAssertThrowsError(try MerchantOperationsDraft.cooperation(value).previews())
        }
    }
    func testUnknownCodeIsPreservedAndStillRejected() throws {
        for code in [-1, 2, 99] {
            let value = try decode("{\"chargeType\":\(code)}")
            XCTAssertEqual(value.chargeType, code); XCTAssertEqual(value.blocker, "merchant.operations.chargeUnknown")
            XCTAssertThrowsError(try MerchantOperationsDraft.cooperation(value).previews())
        }
    }
    func testExplicitFreeAndPaidChoicesKeepExactExistingWireValues() throws {
        for code in [0, 1] {
            let value = try decode("{\"chargeType\":\(code)}")
            XCTAssertNil(value.blocker)
            let preview = try XCTUnwrap(MerchantOperationsDraft.cooperation(value).previews().first)
            XCTAssertEqual(preview.path, "api/merchant/coop-profile/save")
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: preview.json) as? [String: Any])
            XCTAssertEqual(body["chargeType"] as? Int, code); XCTAssertNil(body["capacity"])
        }
    }
    func testExplicitSelectionUnblocksWithoutDefaultingOtherFields() throws {
        var value = try decode(#"{"capacity":12,"availableTime":"Weekends","demand":"Small groups","suitActivityTypes":"walk","coopOpen":1}"#)
        XCTAssertNil(value.chargeType); XCTAssertNotNil(value.blocker)
        value.chargeType = 0
        XCTAssertNil(value.blocker); XCTAssertEqual(value.capacity, "12"); XCTAssertEqual(value.availableTime, "Weekends")
        XCTAssertEqual(value.suitActivityTypes, "walk"); XCTAssertEqual(value.coopOpen, 1)
        value.chargeType = nil; XCTAssertEqual(value.blocker, "merchant.coopChargeChoice.required")
    }
    func testCapacityValidationRemainsIndependentAndRunsBeforeMissingChoice() throws {
        var value = try decode(#"{"chargeType":0}"#)
        XCTAssertNil(value.blocker)
        for capacity in ["-1", "1.5", "bad"] { value.capacity = capacity; XCTAssertEqual(value.blocker, "merchant.operations.capacityInvalid") }
        value.capacity = "0"; XCTAssertNil(value.blocker)
        value.capacity = "-1"; value.chargeType = nil; XCTAssertEqual(value.blocker, "merchant.operations.capacityInvalid")
    }
    func testClearCapacityDoesNotBypassTheRequiredChoice() throws {
        var value = try decode(#"{"capacity":12}"#); value.capacity = ""
        XCTAssertTrue(value.clearsCapacity); XCTAssertEqual(value.blocker, "merchant.coopChargeChoice.required")
        XCTAssertThrowsError(try MerchantOperationsDraft.cooperation(value).previews())
        value.chargeType = 1; XCTAssertNil(value.blocker)
        let preview = try XCTUnwrap(MerchantOperationsDraft.cooperation(value).previews().first)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: preview.json) as? [String: Any])
        XCTAssertTrue(body["capacity"] is NSNull); XCTAssertEqual(body["chargeType"] as? Int, 1)
        XCTAssertEqual(body["params"] as? [String: Bool], ["clearCapacity": true])
    }
}
