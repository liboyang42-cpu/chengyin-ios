import XCTest
@testable import Questify

/// Mini-program index.wxml:113-132: aftercare needs canReadAftercare, prediction needs
/// canManageProjects, both need a loaded positive count and never show while loading.
@MainActor final class MerchantWorkbenchRemindersTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }
    private func access(_ permissions: [String], role: String = "MERCHANT_OWNER") throws -> MerchantAccess {
        let names = permissions.map { "\"\($0)\"" }.joined(separator: ",")
        return try decode(MerchantAccess.self, #"{"active":true,"merchant":{"id":31},"roleCode":""# + role + #"","permissions":["# + names + "]}")
    }
    func testRemindersFollowMiniProgramPermissionGates() throws {
        let todo = try decode(MerchantTodo.self, #"{"refundCount":2,"pendingPredict":3}"#)
        let both = try access(["merchant:aftercare:read", "merchant:project:manage"], role: "MERCHANT_MANAGER")
        XCTAssertFalse(both.isOwner)
        XCTAssertTrue(both.canReadAftercare)
        XCTAssertEqual(MerchantWorkbenchReminders.aftercareCount(todo, access: both, isLoading: false), 2)
        XCTAssertEqual(MerchantWorkbenchReminders.predictCount(todo, access: both, isLoading: false), 3)
        let ownerWithoutAftercare = try access(["merchant:finance:read"], role: "MERCHANT_OWNER")
        XCTAssertTrue(ownerWithoutAftercare.isOwner)
        XCTAssertFalse(ownerWithoutAftercare.canReadAftercare)
        XCTAssertNil(MerchantWorkbenchReminders.aftercareCount(todo, access: ownerWithoutAftercare, isLoading: false))
        XCTAssertNil(MerchantWorkbenchReminders.predictCount(todo, access: ownerWithoutAftercare, isLoading: false))
    }
    func testRemindersHideWhileLoadingUnknownOrZero() throws {
        let both = try access(["merchant:aftercare:read", "merchant:project:manage"])
        let todo = try decode(MerchantTodo.self, #"{"refundCount":2,"pendingPredict":3}"#)
        XCTAssertNil(MerchantWorkbenchReminders.aftercareCount(todo, access: both, isLoading: true))
        XCTAssertNil(MerchantWorkbenchReminders.predictCount(nil, access: both, isLoading: false))
        let zero = try decode(MerchantTodo.self, #"{"refundCount":0,"pendingPredict":0}"#)
        XCTAssertNil(MerchantWorkbenchReminders.aftercareCount(zero, access: both, isLoading: false))
        XCTAssertNil(MerchantWorkbenchReminders.predictCount(zero, access: both, isLoading: false))
    }
}
