import SwiftUI
import XCTest
@testable import Questify

@MainActor final class MerchantCustomerContactSummaryTests: XCTestCase {
    private func access(_ permissions: [String]) throws -> MerchantBusinessAccess {
        try .init(["active": .bool(true), "merchant": .object(["id": .int(610)]),
                   "roleCode": .string("MERCHANT_MANAGER"), "permissions": .array(permissions.map(MerchantBusinessValue.string))])
    }
    private func record(_ fields: MerchantBusinessObject) throws -> MerchantBusinessRecord {
        var row: MerchantBusinessObject = ["customerMemberId": .int(61001), "arrivedCount": .int(0), "pendingCount": .int(0), "refundedCount": .int(0), "paidAmount": .null]
        row.merge(fields) { _, new in new }; return try .init(kind: .customer, fields: row)
    }
    func testCurrentAuthorizedRowIsTheOnlyDisplayInput() throws {
        let grant = try access(["merchant:crm:read", "merchant:crm:sensitive:read"])
        let value = MerchantCustomerContactSummary(record: try record(["phone": .string("138****0000")]), access: grant)
        XCTAssertEqual(value.presentation, .maskedPhone("138****0000"))
        let refreshed = MerchantCustomerContactSummary(record: try record(["contactHint": .string("Customer has not shared contact details")]), access: grant)
        XCTAssertEqual(refreshed.presentation, .reason("Customer has not shared contact details"))
    }
    func testRenderProjectionHidesPhoneImmediatelyWhenAccessIsReduced() throws {
        let row = try record(["phone": .string("138****0000")])
        XCTAssertEqual(MerchantCustomerContactSummary(record: row, access: try access(["merchant:crm:read"])).presentation, .unavailable)
        XCTAssertNil(MerchantCustomerContactSummary(record: row, access: try access(["merchant:crm:sensitive:read"])).presentation)
    }
    func testUnexpectedCleartextRemainsUnavailableWithBothPermissions() throws {
        let value = MerchantCustomerContactSummary(record: try record(["phone": .string("13800000000")]), access: try access(["merchant:crm:read", "merchant:crm:sensitive:read"]))
        XCTAssertEqual(value.presentation, .unavailable)
    }
}
