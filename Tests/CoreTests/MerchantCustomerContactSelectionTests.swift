import XCTest
@testable import QuestifyCore

final class MerchantCustomerContactSelectionTests: XCTestCase {
    private func fields(merchant: Int = 610, sensitive: Bool = true) -> MerchantBusinessObject {
        ["active": .bool(true), "merchant": .object(["id": .int(merchant)]), "roleCode": .string("MERCHANT_MANAGER"),
         "permissions": .array((["merchant:crm:read"] + (sensitive ? ["merchant:crm:sensitive:read"] : [])).map(MerchantBusinessValue.string))]
    }
    private func snapshot(phone: String = "138****0000", sensitive: Bool = true, customer: Int = 61001) throws -> MerchantBusinessSnapshot {
        let row: MerchantBusinessObject = ["customerMemberId": .int(customer), "displayName": .string("Synthetic customer"),
            "arrivedCount": .int(0), "pendingCount": .int(0), "refundedCount": .int(0), "paidAmount": .null, "phone": .string(phone)]
        return try .init(access: .init(fields(sensitive: sensitive)), document: .init(query: .customers(.init()), payload: .object(["total": .int(1), "rows": .array([.object(row)])])))
    }
    private let scope = MerchantBusinessScope(realm: "fixture", accountID: 12, epoch: 1)
    private func select(_ snap: MerchantBusinessSnapshot, purpose: MerchantContactPurpose = .call) -> MerchantCustomerContactSelection? {
        .init(scope: scope, authorizationGeneration: nil, snapshot: snap, record: snap.document.rows[0], purpose: purpose)
    }
    func testSelectedCustomerNotMerchantIdentity() throws {
        let s = try XCTUnwrap(select(snapshot())); XCTAssertEqual(s.customerID.rawValue, 61001); XCTAssertEqual(s.merchantID, 610)
    }
    func testBothSourcePurposesUseExistingCommands() throws {
        for p in MerchantContactPurpose.allCases { let s = try XCTUnwrap(select(snapshot(), purpose: p)); XCTAssertEqual(s.command, .contact(try .init(61001), p)) }
    }
    func testMissingScopeRefusesSelection() throws {
        let s = try snapshot(); XCTAssertNil(MerchantCustomerContactSelection(scope: nil, authorizationGeneration: nil, snapshot: s, record: s.document.rows[0], purpose: .call))
    }
    func testMissingSnapshotRefusesSelection() throws {
        let s = try snapshot(); XCTAssertNil(MerchantCustomerContactSelection(scope: scope, authorizationGeneration: nil, snapshot: nil, record: s.document.rows[0], purpose: .call))
    }
    func testUnreturnedCustomerRefused() throws {
        let s = try snapshot(), other = try snapshot(customer: 61002)
        XCTAssertNil(MerchantCustomerContactSelection(scope: scope, authorizationGeneration: nil, snapshot: s, record: other.document.rows[0], purpose: .call))
    }
    func testSensitivePermissionRequired() throws { XCTAssertNil(select(try snapshot(sensitive: false))) }
    func testCleartextNeverBecomesActionSource() throws { XCTAssertNil(select(try snapshot(phone: "13800000000"))) }
    func testMissingPhoneDoesNotInventContactConsent() throws { XCTAssertNil(select(try snapshot(phone: ""))) }
    func testMaskedPhoneIsNotPartOfCommand() throws {
        let s = try XCTUnwrap(select(snapshot())); XCTAssertEqual(s.command, .contact(try .init(61001), .call))
    }
    func testSnapshotReplacementInvalidates() throws {
        let s = try XCTUnwrap(select(snapshot())); XCTAssertFalse(s.matches(scope: scope, authorizationGeneration: nil, snapshot: try snapshot(customer: 61002)))
    }
    func testScopeAndAuthorizationReplacementInvalidate() throws {
        let snap = try snapshot(), s = try XCTUnwrap(select(snap))
        XCTAssertFalse(s.matches(scope: .init(realm: "fixture", accountID: 13, epoch: 1), authorizationGeneration: nil, snapshot: snap))
        XCTAssertFalse(s.matches(scope: scope, authorizationGeneration: UUID(), snapshot: snap))
    }
    func testExactCurrentSnapshotMatches() throws {
        let snap = try snapshot(), s = try XCTUnwrap(select(snap)); XCTAssertTrue(s.matches(scope: scope, authorizationGeneration: nil, snapshot: snap))
    }
}
