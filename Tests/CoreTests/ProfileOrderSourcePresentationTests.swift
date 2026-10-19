import XCTest
@testable import QuestifyCore

final class ProfileOrderSourcePresentationTests: XCTestCase {
    private let now = OrderLifecycleTime.date("2026-10-11 12:00:00")!
    private func order(_ fields: String = "") throws -> ProfileOrder {
        try JSONDecoder().decode(ProfileOrder.self, from: Data(("{\"id\":1" + (fields.isEmpty ? "" : "," + fields) + "}").utf8))
    }

    func testChipLabelsFollowSourceOnlyWhereTheyDiffer() {
        XCTAssertEqual(ProfileOrderHistoryFilter.all.chipTitleKey, "profile.orderParity.chip.all")
        XCTAssertEqual(ProfileOrderHistoryFilter.refunding.chipTitleKey, "profile.orderParity.chip.refunding")
        for filter in ProfileOrderHistoryFilter.allCases where filter != .all && filter != .refunding {
            XCTAssertEqual(filter.chipTitleKey, filter.titleKey)
        }
        // The shared lifecycle title is unchanged for other screens.
        XCTAssertEqual(ProfileOrderHistoryFilter.refunding.titleKey, "orderLifecycle.state.refunding")
    }

    func testTimeRangeReformatsSourceWallClockWithoutConversion() {
        XCTAssertEqual(ProfileOrderTimeRangeText.text(start: "2026-10-01 09:05:00", end: "2026-10-02 18:30:00"), "10.01 09:05 - 10.02 18:30")
        XCTAssertEqual(ProfileOrderTimeRangeText.text(start: "2026/1/3 7:00", end: "2026-01-03T23:59:59.500"), "01.03 07:00 - 01.03 23:59")
        XCTAssertEqual(ProfileOrderTimeRangeText.text(start: "2026-10-01", end: "2026-10-02"), "10.01 00:00 - 10.02 00:00")
    }

    func testTimeRangeRequiresBothValidEnds() {
        XCTAssertNil(ProfileOrderTimeRangeText.text(start: "2026-10-01 09:00:00", end: nil))
        XCTAssertNil(ProfileOrderTimeRangeText.text(start: nil, end: "2026-10-01 09:00:00"))
        for invalid in ["", "  ", "soon", "2026-13-01 09:00", "2026-10-01 24:00", "2026-10-01 9:5", "26-10-01 09:00", "2026-10-01 09:00:0x", "1696140000"] {
            XCTAssertNil(ProfileOrderTimeRangeText.text(start: invalid, end: "2026-10-02 09:00"), invalid)
        }
    }

    func testRowTimeComesFromOwnerDates() throws {
        let row = try order(#""cmsActivity":{"startDate":"2026-10-12 08:00:00","endDate":"2026-10-12 11:00:00"}"#)
        XCTAssertEqual(ProfileOrderTimeRangeText.text(start: row.startDate, end: row.endDate), "10.12 08:00 - 10.12 11:00")
    }

    func testStateNoticeUsesSourceTitlesAndUnknownHasNoCard() throws {
        XCTAssertNil(try order().stateNotice(now: now))
        let pending = try XCTUnwrap(try order(#""registrationStatus":1,"orderHint":" 请在 15 分钟内完成支付 ""#).stateNotice(now: now))
        XCTAssertEqual(pending, ProfileOrderStateNotice(titleKey: "profile.orderParity.notice.pendingPayment", tagKey: "orderLifecycle.state.pendingPayment", hint: " 请在 15 分钟内完成支付 "))
        XCTAssertEqual(try order(#""registrationStatus":3"#).stateNotice(now: now)?.titleKey, "profile.orderParity.notice.cancelled")
        XCTAssertEqual(try order(#""manualRefundCaseStatus":"REVIEW""#).stateNotice(now: now)?.titleKey, "profile.orderParity.notice.manualRefund")
        XCTAssertNil(try order(#""registrationStatus":1,"orderHint":"   ""#).stateNotice(now: now)?.hint)
    }

    func testFreeOrderNoticeOnlyBeforeOrDuringTheSession() throws {
        let future = #""registrationStatus":2,"totalAmount":0,"payableAmount":0,"cmsActivity":{"startDate":"2026-10-20 09:00:00","endDate":"2026-10-20 12:00:00"}"#
        let free = try order(future)
        XCTAssertTrue(free.isSourceFreeOrder)
        XCTAssertEqual(free.stateNotice(now: now)?.titleKey, "profile.orderParity.notice.free")
        XCTAssertEqual(free.stateNotice(now: now)?.tagKey, "orderLifecycle.state.notStarted")
        let past = try order(#""registrationStatus":2,"totalAmount":0,"payableAmount":0,"cmsActivity":{"startDate":"2026-10-01 09:00:00","endDate":"2026-10-01 12:00:00"}"#)
        XCTAssertEqual(past.stateNotice(now: now)?.titleKey, "profile.orderParity.notice.completed")
        let paid = try order(#""registrationStatus":2,"totalAmount":10,"payableAmount":10,"cmsActivity":{"startDate":"2026-10-20 09:00:00"}"#)
        XCTAssertFalse(paid.isSourceFreeOrder)
        XCTAssertEqual(paid.stateNotice(now: now)?.titleKey, "profile.orderParity.notice.notStarted")
    }

    func testFreeOrderSwitchesSectionAndPaymentLabel() throws {
        let free = try order(#""totalAmount":0,"payableAmount":0,"paymentTypeLabel":"微信支付""#)
        XCTAssertEqual(free.paymentSectionTitleKey, "profile.orderParity.section.fees")
        XCTAssertEqual(free.sourcePaymentTypeLabelKey, "profile.orderParity.paymentType.free")
        let paid = try order(#""totalAmount":0,"payableAmount":0,"wechatPaymentAmount":1"#)
        XCTAssertEqual(paid.paymentSectionTitleKey, "profile.orderParity.section.payment")
        XCTAssertNil(paid.sourcePaymentTypeLabelKey)
    }

    func testOnlySourceDefinedCodesAreLabeled() {
        XCTAssertEqual(ProfileOrderCodeLabel.refundApplication(0), .key("profile.orderParity.refundApplication.review"))
        XCTAssertEqual(ProfileOrderCodeLabel.refundApplication(2), .key("profile.orderParity.refundApplication.rejected"))
        XCTAssertEqual(ProfileOrderCodeLabel.refundApplication(1), .raw(1))
        XCTAssertEqual(ProfileOrderCodeLabel.payment(2), .key("profile.orderParity.payment.paid"))
        for code in [0, 1, 3, -1] { XCTAssertEqual(ProfileOrderCodeLabel.payment(code), .raw(code)) }
    }

    func testOrdersIssueCopyClassifiesSignInForbiddenMalformedAndFailure() {
        XCTAssertEqual(ProfileReadIssueCopy.kind(of: APIError.unauthorized), .signIn)
        XCTAssertEqual(ProfileReadIssueCopy.kind(of: ProfileReadFailure(httpStatus: 401)), .signIn)
        XCTAssertEqual(ProfileReadIssueCopy.kind(of: ProfileReadFailure(code: 401)), .signIn)
        XCTAssertEqual(ProfileReadIssueCopy.kind(of: APIError.httpStatus(403)), .forbidden)
        XCTAssertEqual(ProfileReadIssueCopy.kind(of: ProfileReadFailure(httpStatus: 403, message: "x")), .forbidden)
        XCTAssertEqual(ProfileReadIssueCopy.kind(of: ProfileReadFailure(code: 403)), .forbidden)
        XCTAssertEqual(ProfileReadIssueCopy.kind(of: APIError.malformedResponse), .malformed)
        XCTAssertEqual(ProfileReadIssueCopy.kind(of: APIError.httpStatus(500)), .failure)
        XCTAssertEqual(ProfileReadIssueCopy.orders.signInTitleKey, "profile.orderParity.signIn.title")
        XCTAssertEqual(ProfileReadIssueCopy.orders.forbiddenTitleKey, "profile.orderParity.forbidden.title")
        XCTAssertEqual(ProfileReadIssueCopy.orders.failureTitleKey, "profile.orderParity.error.title")
    }
}
