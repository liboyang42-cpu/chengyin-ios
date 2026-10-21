import Foundation
import XCTest
@testable import QuestifyCore

/// Mini-program pages/merchant/index todo-summary and access/me gates (w2-17).
final class MerchantWorkbenchTodoContractTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }
    func testPendingPredictBiddingAndProjectRowsDecode() throws {
        let todo = try decode(MerchantTodo.self, #"{"pendingVerify":1,"verifiedCount":0,"pendingScanConfirm":2,"pendingOrders":0,"refundCount":3,"pendingPredict":4,"biddingTopics":5,"byProject":[{"ownerType":"topic","ownerId":"01","pendingVerify":1,"pendingScanConfirm":2},{"ownerType":"activity","ownerId":9}]}"#)
        XCTAssertEqual(todo.pendingPredict, 4)
        XCTAssertEqual(todo.biddingTopics, 5)
        XCTAssertEqual(todo.refundCount, 3)
        XCTAssertEqual(todo.byProject?.count, 2)
        XCTAssertEqual(todo.byProject?.first?.ownerID, "01")
        XCTAssertEqual(todo.byProject?.last?.ownerID, "9")
        XCTAssertEqual(todo.byProject?.last?.pendingVerify, 0)
    }
    func testMissingByProjectStaysUnknownAndNegativeCountsNeverRemind() throws {
        let todo = try decode(MerchantTodo.self, #"{"pendingPredict":-2,"biddingTopics":"x"}"#)
        XCTAssertNil(todo.byProject)
        XCTAssertEqual(todo.pendingPredict, 0)
        XCTAssertEqual(todo.biddingTopics, 0)
        XCTAssertFalse(todo.hasPendingWork)
    }
    func testMalformedProjectRowsDoNotInventPerProjectTodo() throws {
        let todo = try decode(MerchantTodo.self, #"{"byProject":[{"pendingVerify":2}]}"#)
        XCTAssertNil(todo.byProject)
    }
    func testWorkbenchPermissionCodesDecodeOnlyForActiveAccess() throws {
        let active = try decode(MerchantAccess.self, #"{"active":true,"merchant":{"id":31},"roleCode":"MERCHANT_MANAGER","permissions":["merchant:aftercare:read","merchant:crm:read","merchant:coop:manage","merchant:operator:manage","merchant:profile:write","merchant:coupon:manage","merchant:verify"]}"#)
        for permission: MerchantAccess.Permission in [.aftercareRead, .crmRead, .coopManage, .operatorManage, .profileWrite, .couponManage, .verify] {
            XCTAssertTrue(active.allows(permission), permission.rawValue)
        }
        XCTAssertFalse(active.isOwner)
        let inactive = try decode(MerchantAccess.self, #"{"active":false,"roleCode":"MERCHANT_OWNER","permissions":["merchant:aftercare:read"]}"#)
        XCTAssertFalse(inactive.allows(.aftercareRead))
    }
}
