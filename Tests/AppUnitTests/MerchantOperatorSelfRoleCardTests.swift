import XCTest
@testable import Questify

/// Mini-program team/index.wxml:109-114: only operators without canManageOperators see the self card.
final class MerchantOperatorSelfRoleCardTests: XCTestCase {
    private func access(role: String, manage: Bool) throws -> MerchantBusinessAccess {
        try MerchantBusinessAccess(["active": .bool(true), "merchant": .object(["id": .int(31), "name": .string("Example store")]),
            "roleCode": .string(role), "permissions": .array(manage ? [.string("merchant:operator:manage")] : [.string("merchant:verify")]),
            "canManageOperators": .bool(manage)])
    }
    func testOnlyNonAdminOperatorsSeeSelfRoleCard() throws {
        XCTAssertTrue(MerchantOperatorSelfRoleCard.isShown(for: try access(role: "MERCHANT_CHECKIN", manage: false)))
        XCTAssertFalse(MerchantOperatorSelfRoleCard.isShown(for: try access(role: "MERCHANT_OWNER", manage: true)))
    }
}
