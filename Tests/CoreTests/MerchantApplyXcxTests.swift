import XCTest
@testable import QuestifyCore

/// w2-07: mini-program `pages/topic/merchantapply` validation, pre-fill, edit rules and create body.
final class MerchantApplyXcxTests: XCTestCase {
    func testFirstMissingFollowsSourceOrder() {
        XCTAssertEqual(MerchantApplyXcx.firstMissing(address: " ", startDay: nil, endDay: nil, description: "", photoCount: 0), .address)
        XCTAssertEqual(MerchantApplyXcx.firstMissing(address: "Street", startDay: "2026-10-20", endDay: nil, description: "", photoCount: 0), .dates)
        XCTAssertEqual(MerchantApplyXcx.firstMissing(address: "Street", startDay: "2026-10-20", endDay: "2026-10-20", description: " ", photoCount: 0), .description)
        XCTAssertEqual(MerchantApplyXcx.firstMissing(address: "Street", startDay: "2026-10-20", endDay: "2026-10-21", description: "Room", photoCount: 0), .photos)
        XCTAssertNil(MerchantApplyXcx.firstMissing(address: "Street", startDay: "2026-10-20", endDay: "2026-10-21", description: "Room", photoCount: 1))
    }

    func testDateRangeRejectsReversedOrMalformedDays() throws {
        XCTAssertNil(try MerchantApplyXcx.dateRange(start: nil, end: ""))
        XCTAssertThrowsError(try MerchantApplyXcx.dateRange(start: "2026-10-21", end: "2026-10-20"))
        XCTAssertThrowsError(try MerchantApplyXcx.dateRange(start: "2026-13-01", end: "2026-13-02"))
        XCTAssertThrowsError(try MerchantApplyXcx.dateRange(start: "2026-10-20", end: nil))
    }

    func testCooperateDatePrefillFromBusinessTime() {
        XCTAssertEqual(MerchantApplyXcx.cooperateDate(fromBusinessTime: "09:00 — 18:30 · 周一休息"), "09:00-18:30")
        XCTAssertEqual(MerchantApplyXcx.cooperateDate(fromBusinessTime: "10:00～22:00"), "10:00-22:00")
        XCTAssertNil(MerchantApplyXcx.cooperateDate(fromBusinessTime: "全天营业"))
        XCTAssertNil(MerchantApplyXcx.cooperateDate(fromBusinessTime: "25:00-26:00"))
    }

    func testEditBlockRules() {
        XCTAssertEqual(MerchantApplyXcx.editBlock(status: 0, auditStatus: 0, topicStartDay: "2026-10-19 09:00:00", today: "2026-10-19"), .topicStarted)
        XCTAssertNil(MerchantApplyXcx.editBlock(status: 0, auditStatus: 0, topicStartDay: "2026-11-01", today: "2026-10-19"))
        XCTAssertNil(MerchantApplyXcx.editBlock(status: 2, auditStatus: 2, topicStartDay: nil, today: "2026-10-19"))
        XCTAssertEqual(MerchantApplyXcx.editBlock(status: 1, auditStatus: 1, topicStartDay: nil, today: "2026-10-19"), .approved)
        XCTAssertEqual(MerchantApplyXcx.editBlock(status: 4, auditStatus: nil, topicStartDay: nil, today: "2026-10-19"), .stateChanged)
    }

    func testCreateBodyCarriesSourceDateRangeOnlyWhenChosen() throws {
        var draft = MerchantRegistrationContentDraft()
        draft.addressName = "Synthetic shop"; draft.address = "Synthetic street"; draft.activityDesc = "Room for 6"
        draft.picUrl = "https://example.invalid/1.png"
        guard case .json(let plain) = try MerchantContentCommand.register(topicID: 3, nodeID: 4, draft: draft, cooperateDate: "").request().body else { return XCTFail() }
        XCTAssertNil(plain["startDate"]); XCTAssertNil(plain["endDate"])
        draft.createStartDay = "2026-10-20"; draft.createEndDay = "2026-10-22"
        let request = try MerchantContentCommand.register(topicID: 3, nodeID: 4, draft: draft, cooperateDate: "09:00-18:00").request()
        XCTAssertEqual(request.path, "api/registration/merchant/create")
        guard case .json(let fields) = request.body else { return XCTFail() }
        XCTAssertEqual(fields["startDate"], .string("2026-10-20 00:00:00"))
        XCTAssertEqual(fields["endDate"], .string("2026-10-22 23:59:59"))
        XCTAssertEqual(fields["cooperateDate"], .string("09:00-18:00"))
        XCTAssertEqual(fields["mode"], .integer(1))
        draft.createEndDay = "2026-10-19"
        XCTAssertThrowsError(try MerchantContentCommand.register(topicID: 3, nodeID: 4, draft: draft, cooperateDate: "").request())
    }
}
