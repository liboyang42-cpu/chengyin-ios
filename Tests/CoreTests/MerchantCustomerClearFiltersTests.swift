import XCTest
@testable import QuestifyCore

final class MerchantCustomerClearFiltersTests: XCTestCase {
    func testClearsAllWorkspaceFieldsAndRestartsPage() {
        var q = MerchantCustomerQuery(); q.page = 4; q.segment = "repeat"; q.tagID = 5; q.sourceType = 2
        q.sourceStart = "2026-10-01"; q.sourceEnd = "2026-10-12"; q.keyword = " Existing search "
        let cleared = q.clearingWorkspaceFilters()
        XCTAssertEqual(cleared.page, 1); XCTAssertEqual(cleared.segment, "all")
        XCTAssertNil(cleared.tagID); XCTAssertNil(cleared.sourceType); XCTAssertNil(cleared.sourceStart); XCTAssertNil(cleared.sourceEnd)
        XCTAssertEqual(cleared.keyword, q.keyword); XCTAssertFalse(cleared.hasWorkspaceFilters)
        XCTAssertEqual(q.page, 4); XCTAssertEqual(q.tagID, 5)
    }
    func testKeywordAloneIsNotWorkspaceFilter() {
        var q = MerchantCustomerQuery(); q.keyword = "Search"
        XCTAssertFalse(q.hasWorkspaceFilters); XCTAssertEqual(q.clearingWorkspaceFilters(), q)
    }
    func testEveryIndependentFilterEnablesClear() {
        var variants = Array(repeating: MerchantCustomerQuery(), count: 5)
        variants[0].segment = "noted"; variants[1].tagID = 1; variants[2].sourceType = 1
        variants[3].sourceStart = "2026-10-01"; variants[4].sourceEnd = "2026-10-12"
        for q in variants { XCTAssertTrue(q.hasWorkspaceFilters); XCTAssertFalse(q.clearingWorkspaceFilters().hasWorkspaceFilters) }
    }
    func testClearIsIdempotentAndKeepsUnicodeSearchBytes() {
        var q = MerchantCustomerQuery(); q.keyword = " e\u{0301} 城瘾 "; q.segment = "new"
        let one = q.clearingWorkspaceFilters(); XCTAssertEqual(one.clearingWorkspaceFilters(), one)
        XCTAssertEqual(Data(one.keyword.utf8), Data(q.keyword.utf8))
    }
    func testBlankDateSentinelsAreInactive() {
        var q = MerchantCustomerQuery(); q.sourceStart = ""; q.sourceEnd = ""
        XCTAssertFalse(q.hasWorkspaceFilters)
    }
    func testClearedQueryUsesExistingReadFields() throws {
        var q = MerchantCustomerQuery(); q.tagID = 8; q.keyword = "needle"
        let cleared = q.clearingWorkspaceFilters(); XCTAssertNoThrow(try cleared.validate())
        XCTAssertEqual(cleared.fields["keyword"], .string("needle")); XCTAssertEqual(cleared.fields["pageNum"], .int(1))
        XCTAssertEqual(cleared.fields["tagId"], .null)
    }
}
