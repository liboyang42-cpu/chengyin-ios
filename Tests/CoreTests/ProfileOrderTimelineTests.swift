import XCTest
@testable import QuestifyCore

final class ProfileOrderTimelineTests: XCTestCase {
    private let now = OrderLifecycleTime.date("2026-10-11 12:00:00")!
    private func order(_ fields: String) throws -> ProfileOrder {
        try JSONDecoder().decode(ProfileOrder.self, from: Data(("{\"id\":1," + fields + "}").utf8))
    }
    private func ids(_ order: ProfileOrder) -> [String] { order.sourceTimeline(now: now).map(\.id) }

    func testUnpaidOrderStopsAtAwaitingPayment() throws {
        let row = try order(#""registrationStatus":1,"paymentStatus":1,"createTime":"2026-10-01 09:05:00""#)
        let steps = row.sourceTimeline(now: now)
        XCTAssertEqual(steps.map(\.id), ["created", "payment"])
        XCTAssertEqual(steps[0].time, "2026-10-01 09:05")
        XCTAssertEqual(steps[1].labelKey, "orderLifecycle.timeline.awaitingPayment")
        XCTAssertEqual(steps[1].timeKey, "profile.orderParity.timeline.updatesLater")
        XCTAssertEqual(steps[1].state, .current)
    }

    func testCancelledUnpaidOrderStopsAtCancelled() throws {
        let row = try order(#""registrationStatus":3,"paymentStatus":0"#)
        XCTAssertEqual(ids(row), ["created", "cancelled"])
        XCTAssertNil(row.sourceTimeline(now: now)[0].time)
    }

    func testPaidOrderWaitsForStoreRedemption() throws {
        let row = try order(#""registrationStatus":2,"paymentStatus":2,"paymentTime":"2026-10-01 10:00:00","payableAmount":20,"cmsActivity":{"startDate":"2026-10-20 09:00:00","endDate":"2026-10-20 12:00:00"}"#)
        let steps = row.sourceTimeline(now: now)
        XCTAssertEqual(steps.map(\.id), ["created", "paid", "verification"])
        XCTAssertEqual(steps[1].labelKey, "orderLifecycle.timeline.paid")
        XCTAssertEqual(steps[1].time, "2026-10-01 10:00")
        XCTAssertEqual(steps[2].labelKey, "profile.orderParity.timeline.awaitingStore")
        XCTAssertEqual(steps[2].state, .current)
    }

    func testFreePaidOrderUsesFreeRegistrationLabel() throws {
        let row = try order(#""registrationStatus":2,"paymentStatus":2,"totalAmount":0,"payableAmount":0"#)
        XCTAssertEqual(row.sourceTimeline(now: now)[1].labelKey, "profile.orderParity.timeline.free")
    }

    func testVerifiedOrderShowsFirstScanAndRedemption() throws {
        let row = try order(#""registrationStatus":2,"paymentStatus":2,"verificationStatus":1,"verificationTime":"2026-10-05 08:00:00","firstSuccessfulScanAt":"2026-10-05 07:59:00","payableAmount":20"#)
        let steps = row.sourceTimeline(now: now)
        XCTAssertEqual(steps.map(\.id), ["created", "paid", "first_scan", "verification"])
        XCTAssertEqual(steps[2].time, "2026-10-05 07:59")
        XCTAssertEqual(steps[3].labelKey, "orderLifecycle.timeline.verified")
        XCTAssertEqual(steps[3].time, "2026-10-05 08:00")
        XCTAssertEqual(steps[3].state, .done)
    }

    func testRefundStepUsesPayoutTimeThenUpdateTime() throws {
        let refunded = try order(#""registrationStatus":2,"paymentStatus":2,"payableAmount":20,"refundApplication":{"payoutStatus":1,"status":1,"refundAmount":20,"payoutTime":"2026-10-06 09:00:00","updateTime":"2026-10-06 08:00:00"}"#)
        let last = try XCTUnwrap(refunded.sourceTimeline(now: now).last)
        XCTAssertEqual(last.id, "refund"); XCTAssertEqual(last.labelKey, "profile.orderParity.timeline.refunded")
        XCTAssertEqual(last.time, "2026-10-06 09:00"); XCTAssertEqual(last.state, .done)
        let refunding = try order(#""registrationStatus":2,"paymentStatus":2,"payableAmount":20,"refundApplication":{"status":0,"refundAmount":20,"payoutTime":"","updateTime":"2026-10-06 08:00:00"}"#)
        let step = try XCTUnwrap(refunding.sourceTimeline(now: now).last)
        XCTAssertEqual(step.labelKey, "orderLifecycle.timeline.refunding")
        XCTAssertEqual(step.time, "2026-10-06 08:00"); XCTAssertEqual(step.state, .current)
    }

    func testManualRefundShowsServerReasonOrDefault() throws {
        let withReason = try order(#""registrationStatus":2,"paymentStatus":2,"payableAmount":20,"manualRefundCaseStatus":"NO_REFUND","refundInfo":{"refundable":false,"reason":"Synthetic reason"}"#)
        let steps = withReason.sourceTimeline(now: now)
        XCTAssertEqual(steps.map(\.id), ["created", "paid", "verification", "manual_refund"])
        XCTAssertEqual(steps[2].labelKey, "profile.orderParity.timeline.notVerified"); XCTAssertNil(steps[2].timeKey)
        XCTAssertEqual(steps[3].label, "Synthetic reason"); XCTAssertNil(steps[3].labelKey); XCTAssertEqual(steps[3].state, .done)
        let pending = try order(#""registrationStatus":2,"paymentStatus":2,"payableAmount":20,"manualRefundCaseStatus":"OPEN""#)
        let last = try XCTUnwrap(pending.sourceTimeline(now: now).last)
        XCTAssertEqual(last.labelKey, "profile.orderParity.timeline.manualDefault"); XCTAssertEqual(last.state, .current)
    }

    func testDetailFactsAreLenientAndNeverBreakDecoding() throws {
        let row = try order(#""transactionId":"4200001","refundInfo":{"reason":"  "}"#)
        XCTAssertEqual(row.detailFacts.transactionID, "4200001")
        XCTAssertNil(row.detailFacts.refundReason)
        // A non-string transaction id is absent, and existing decoding is unaffected.
        let odd = try order(#""transactionId":42,"refundApplication":{"payoutTime":7}"#)
        XCTAssertNil(odd.detailFacts.transactionID); XCTAssertNil(odd.detailFacts.refundTime)
    }

    func testPaymentAndVoucherTextsFollowSource() throws {
        let row = try order(#""paymentStatus":2,"verificationStatus":0,"verificationTime":"2026-10-05 08:00:00","expiresAt":"2026-12-31 23:59:00","participateDate":"next week","wechatPaymentAmount":0,"pointPaymentAmount":5"#)
        XCTAssertTrue(row.showsSourcePaymentInfo)
        XCTAssertFalse(row.showsSourceWechatPay); XCTAssertTrue(row.showsSourcePointPay)
        XCTAssertNil(row.sourceVerificationTimeText)
        XCTAssertEqual(row.sourceExpiresAtText, "2026-12-31 23:59")
        XCTAssertEqual(row.sourceParticipateDateText, "next week")
        XCTAssertFalse(try order(#""paymentStatus":1"#).showsSourcePaymentInfo)
    }
}
