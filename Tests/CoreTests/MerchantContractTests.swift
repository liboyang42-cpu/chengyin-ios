import Foundation
import XCTest
@testable import QuestifyCore

final class MerchantContractTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }
    func testAccessUsesServerMerchantRoleAndWhitelistedPermissions() throws {
        let access = try decode(MerchantAccess.self, #"{"active":true,"merchant":{"id":"31","name":"Fixture Store"},"roleCode":"MERCHANT_OWNER","permissions":["merchant:finance:read","merchant:order:read","invented:grant"]}"#)
        XCTAssertEqual(access.merchantID, 31)
        XCTAssertEqual(access.merchantName, "Fixture Store")
        XCTAssertTrue(access.isOwner)
        XCTAssertTrue(access.canReadDashboard)
        XCTAssertTrue(access.allows(.orders))
        XCTAssertEqual(access.permissions.count, 2)
        XCTAssertFalse(access.allows(.projects))
    }
    func testFinanceStaffCannotReadOwnerDashboard() throws {
        let access = try decode(MerchantAccess.self, #"{"active":true,"merchant":{"id":31},"roleCode":"MERCHANT_FINANCE","permissions":["merchant:finance:read"]}"#)
        XCTAssertTrue(access.allows(.finance))
        XCTAssertFalse(access.isOwner)
        XCTAssertFalse(access.canReadDashboard)
    }
    func testOwnerWithoutFinancePermissionCannotReadRevenue() throws {
        let access = try decode(MerchantAccess.self, #"{"active":true,"merchant":{"id":31},"roleCode":"MERCHANT_OWNER","permissions":[]}"#)
        XCTAssertTrue(access.isOwner)
        XCTAssertFalse(access.canReadDashboard)
    }
    func testNoLegacyAccountRoleOrEntryIntentCanGrantAccess() throws {
        for json in [
            #"{"role":"merchant","userType":2}"#,
            #"{"active":true,"merchant":{"id":31},"role":"merchant","userType":2,"permissions":["merchant:finance:read"]}"#,
            #"{"active":true,"merchant":{"id":31},"roleCode":"ADMIN","permissions":["merchant:finance:read"]}"#,
            #"{"active":"true","merchant":{"id":31},"roleCode":"MERCHANT_OWNER","permissions":[]}"#,
            #"{"active":true,"merchant":{"id":0},"roleCode":"MERCHANT_OWNER","permissions":[]}"#,
            #"{"active":true,"merchant":{"id":1.5},"roleCode":"MERCHANT_OWNER","permissions":[]}"#,
            #"{"active":true,"merchant":{"id":true},"roleCode":"MERCHANT_OWNER","permissions":[]}"#,
            #"{"active":true,"merchant":{"id":31},"roleCode":"MERCHANT_OWNER","permissions":"merchant:finance:read"}"#
        ] { XCTAssertThrowsError(try decode(MerchantAccess.self, json), json) }
    }
    func testMissingPermissionsGrantNothing() throws {
        let access = try decode(MerchantAccess.self, #"{"active":true,"merchant":{"id":31},"roleCode":"MERCHANT_MANAGER"}"#)
        XCTAssertTrue(access.permissions.isEmpty)
        XCTAssertFalse(access.canReadDashboard)
    }
    func testInactiveNeverCarriesPrivileges() throws {
        let access = try decode(MerchantAccess.self, #"{"active":false,"roleCode":"MERCHANT_OWNER","permissions":["merchant:finance:read","merchant:order:read"],"applicationState":"DISABLED","merchant":{"id":31,"status":2,"accountStatus":2,"name":"Fixture Store"}}"#)
        XCTAssertFalse(access.isOwner)
        XCTAssertTrue(access.permissions.isEmpty)
        XCTAssertEqual(access.application?.titleKey, "merchant.access.disabled")
    }
    func testIncompleteApplicationDoesNotInventAState() throws {
        for json in [
            #"{"active":false,"applicationState":"PENDING","roleCode":"MERCHANT_OWNER"}"#,
            #"{"active":false,"applicationState":"PENDING","roleCode":"MERCHANT_MANAGER","merchant":{"id":31,"status":0,"accountStatus":0}}"#,
            #"{"active":false,"applicationState":"OTHER","roleCode":"MERCHANT_OWNER","merchant":{"id":31,"status":0,"accountStatus":0}}"#,
            #"{"active":false,"applicationState":"PENDING","roleCode":"MERCHANT_OWNER","merchant":{"id":31,"status":4,"accountStatus":0}}"#
        ] {
            let access = try decode(MerchantAccess.self, json)
            XCTAssertNil(access.application)
            XCTAssertNil(access.merchantID)
            XCTAssertFalse(access.isOwner)
        }
    }
    func testApplicationStatusAndAccountStateStaySeparate() throws {
        for (status, account, expected) in [(0,0,"pending"), (1,0,"awaitingActivation"), (2,0,"rejected"), (1,1,"effective"), (0,2,"disabled")] {
            let access = try decode(MerchantAccess.self, "{\"active\":false,\"applicationState\":\"PENDING\",\"roleCode\":\"MERCHANT_OWNER\",\"merchant\":{\"id\":31,\"status\":\(status),\"accountStatus\":\(account)}}")
            XCTAssertEqual(access.application?.titleKey, "merchant.access." + expected)
            XCTAssertFalse(access.active)
        }
    }
    func testMoneyDoesNotInventZeroOrRoundTripThroughDouble() {
        XCTAssertEqual(MerchantMoney.display(nil), "—")
        XCTAssertEqual(MerchantMoney.display(""), "—")
        XCTAssertEqual(MerchantMoney.display("NaN"), "—")
        XCTAssertEqual(MerchantMoney.display("12abc"), "—")
        XCTAssertEqual(MerchantMoney.display("0"), "¥0.00")
        XCTAssertEqual(MerchantMoney.display("0.00"), "¥0.00")
        XCTAssertEqual(MerchantMoney.display("12.5"), "¥12.50")
        XCTAssertEqual(MerchantMoney.display("-3.25"), "¥-3.25")
        XCTAssertEqual(MerchantMoney.display("9007199254740993.01"), "¥9007199254740993.01")
    }
    func testDashboardKeepsMoneyStringsAndMissingRevenue() throws {
        let dash = try decode(MerchantDashboard.self, #"{"revenue":"9007199254740993.01","pendingOrders":4,"revenue7d":[{"date":"09-30","amount":"0.00"},{"date":"10-01","amount":null}]}"#)
        XCTAssertEqual(dash.revenue, "9007199254740993.01")
        XCTAssertEqual(dash.pendingOrders, 4)
        XCTAssertEqual(dash.revenue7d.last?.date, "10-01")
        XCTAssertNil(dash.revenue7d.last?.amount)
        let missing = try decode(MerchantDashboard.self, "{}")
        XCTAssertNil(missing.revenue)
        XCTAssertEqual(MerchantMoney.display(missing.revenue), "—")
        XCTAssertThrowsError(try decode(MerchantDashboard.self, #"{"revenue":0}"#))
    }
    func testCompletedVerificationIsNotPendingTodo() throws {
        let todo = try decode(MerchantTodo.self, #"{"verifiedCount":16}"#)
        XCTAssertFalse(todo.hasPendingWork)
        XCTAssertEqual(todo.verifiedCount, 16)
        XCTAssertTrue(try decode(MerchantTodo.self, #"{"refundCount":1}"#).hasPendingWork)
    }
    func testEventTimeIsPreservedWithoutYearOrTimezoneGuess() throws {
        let event = try decode(MerchantEvent.self, #"{"content":"Fixture event","time":"12-31 23:59"}"#)
        XCTAssertEqual(event.time, "12-31 23:59")
    }
    func testOrdersKeepUnknownStatusesAndMissingAmounts() throws {
        let order = try decode(MerchantOrder.self, #"{"id":"7","orderSn":"fixture-order","status":91,"aftersaleStatus":9,"createTime":"source time"}"#)
        XCTAssertEqual(order.id, 7)
        XCTAssertEqual(order.status, 91)
        XCTAssertEqual(order.aftersaleStatus, 9)
        XCTAssertNil(MerchantOrderStatus(rawValue: order.status!))
        XCTAssertNil(order.payAmount)
        XCTAssertEqual(MerchantMoney.display(order.payAmount), "—")
        let numeric = try decode(MerchantOrder.self, #"{"payAmount":12.25}"#)
        XCTAssertEqual(numeric.payAmount, "12.25")
    }
    func testProjectKeepsServerLabelsUnknownTypesAndReportedTotal() throws {
        let page = try decode(MerchantProjectPage.self, #"{"rows":[{"id":7,"bizType":"future-type","title":" Fixture ","projectTypeText":"Server type","stateText":"Server state","acceptStatusText":"Server acceptance","startTime":"2026-10-01 10:00","signupCount":3,"viewCount":8}],"total":"204"}"#)
        XCTAssertEqual(page.rows.first?.id, "future-type:7")
        XCTAssertEqual(page.rows.first?.title, "Fixture")
        XCTAssertEqual(page.rows.first?.stateText, "Server state")
        XCTAssertEqual(page.rows.first?.acceptStatusText, "Server acceptance")
        XCTAssertEqual(page.total, 204)
        XCTAssertTrue(page.hasUnloadedRows)
    }
    func testProjectIdentityIncludesBusinessType() throws {
        let page = try decode(MerchantProjectPage.self, #"{"rows":[{"id":7,"bizType":"topic"},{"id":7,"bizType":"activity"}]}"#)
        XCTAssertNotEqual(page.rows[0].id, page.rows[1].id)
        XCTAssertEqual(page.total, 2)
        XCTAssertFalse(page.hasUnloadedRows)
        XCTAssertThrowsError(try decode(MerchantProject.self, #"{"id":0,"bizType":"activity"}"#))
    }
}
