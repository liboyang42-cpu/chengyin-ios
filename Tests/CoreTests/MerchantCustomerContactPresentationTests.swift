import XCTest
@testable import QuestifyCore

final class MerchantCustomerContactPresentationTests: XCTestCase {
    private func access(read: Bool = true, sensitive: Bool = true) throws -> MerchantBusinessAccess {
        var permissions: [String] = []
        if read { permissions.append("merchant:crm:read") }
        if sensitive { permissions.append("merchant:crm:sensitive:read") }
        return try .init(["active": .bool(true), "merchant": .object(["id": .int(610)]),
                          "roleCode": .string("MERCHANT_MANAGER"), "permissions": .array(permissions.map(MerchantBusinessValue.string))])
    }
    private func row(phone: MerchantBusinessValue? = nil, hint: MerchantBusinessValue? = nil) throws -> MerchantBusinessRecord {
        var fields: MerchantBusinessObject = ["customerMemberId": .int(61001), "displayName": .string("Synthetic customer"),
            "arrivedCount": .int(0), "pendingCount": .int(0), "refundedCount": .int(0), "paidAmount": .null]
        fields["phone"] = phone; fields["contactHint"] = hint
        return try .init(kind: .customer, fields: fields)
    }
    func testBothPermissionsDisplayOnlyReturnedSourceMaskAndPreserveItsDigits() throws {
        for phone in ["138****0000", "1****3", "12****56", "*", "+8****34"] {
            let record = try row(phone: .string(" \(phone) \n"), hint: .string("unused reason"))
            XCTAssertEqual(MerchantCustomerContactPresentation(record: record, access: try access()), .maskedPhone(phone))
        }
    }
    func testPlaintextAndUnexpectedMaskFormatsAreNeverDisplayedOrRemasked() throws {
        for phone in ["13800000000", "+8613800000000", "138*0000000", "138*****0000", "tel:13800000000", "123456****123456"] {
            XCTAssertEqual(MerchantCustomerContactPresentation(record: try row(phone: .string(phone)), access: try access()), .unavailable)
        }
    }
    func testSourceContactReasonSurvivesWithoutAnySensitivePermission() throws {
        for hint in ["需要客户敏感信息权限", "由俱乐部带团，联系请找俱乐部负责人", "客户未授权联系方式共享", "客户未留电话"] {
            let record = try row(hint: .string(hint))
            XCTAssertEqual(MerchantCustomerContactPresentation(record: record, access: try access(sensitive: false)), .reason(hint))
        }
    }
    func testNoCRMReadPermissionReturnsNoPresentationEvenWithSensitivePermission() throws {
        let record = try row(phone: .string("138****0000"), hint: .string("A server reason"))
        XCTAssertNil(MerchantCustomerContactPresentation(record: record, access: try access(read: false)))
        XCTAssertNil(MerchantCustomerContactPresentation(record: record, access: try access(read: false, sensitive: false)))
    }
    func testRevokedSensitivePermissionCannotExposeRetainedPhoneField() throws {
        let record = try row(phone: .string("138****0000"), hint: .string("Contact is unavailable"))
        XCTAssertEqual(MerchantCustomerContactPresentation(record: record, access: try access()), .maskedPhone("138****0000"))
        XCTAssertEqual(MerchantCustomerContactPresentation(record: record, access: try access(sensitive: false)), .reason("Contact is unavailable"))
        XCTAssertEqual(MerchantCustomerContactPresentation(record: try row(phone: .string("138****0000")), access: try access(sensitive: false)), .unavailable)
    }
    func testMissingNullBlankAndMalformedContactAreUnknownNotNoPhoneClaim() throws {
        for value in [MerchantBusinessValue.null, .string("  \n"), .int(138), .bool(true), .array([]), .object([:])] {
            XCTAssertEqual(MerchantCustomerContactPresentation(record: try row(phone: value, hint: value), access: try access()), .unavailable)
        }
        XCTAssertEqual(MerchantCustomerContactPresentation(record: try row(), access: try access()), .unavailable)
    }
    func testMalformedPhoneFallsBackToExactServerReason() throws {
        XCTAssertEqual(MerchantCustomerContactPresentation(record: try row(phone: .int(138), hint: .string("  Shared through the organizer  ")), access: try access()), .reason("Shared through the organizer"))
    }
    func testNonCustomerRecordCannotLeakContactFields() throws {
        let other = try MerchantBusinessRecord(kind: .verification, fields: ["id": .int(3), "phone": .string("138****0000"), "contactHint": .string("hidden")])
        XCTAssertNil(MerchantCustomerContactPresentation(record: other, access: try access()))
    }
    func testRefreshReplacesContactRatherThanKeepingPriorCustomerState() throws {
        let grant = try access()
        let previous = try row(phone: .string("138****0000"))
        let refreshed = try row(hint: .string("客户未授权联系方式共享"))
        XCTAssertEqual(MerchantCustomerContactPresentation(record: previous, access: grant), .maskedPhone("138****0000"))
        XCTAssertEqual(MerchantCustomerContactPresentation(record: refreshed, access: grant), .reason("客户未授权联系方式共享"))
        XCTAssertEqual(previous.fields["phone"], .string("138****0000"))
        XCTAssertNil(refreshed.fields["phone"])
    }
}
