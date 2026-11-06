import XCTest
@testable import QuestifyCore

/// Source pages/merchant/aftercare/detail/view-model.js listRowView, groupAftercareItems and buildAftercareTimeline.
final class MerchantAftercareParityTests: XCTestCase {
    private func row(_ change: (inout MerchantBusinessObject) -> Void = { _ in }) throws -> MerchantAftercareParity.ListRow {
        var fields = try XCTUnwrap(MerchantBusinessSyntheticFixtures.decode(MerchantBusinessSyntheticFixtures.refund).object)
        change(&fields)
        return try XCTUnwrap(MerchantAftercareParity.ListRow(MerchantBusinessRecord(kind: .refund, fields: fields)))
    }
    private let today = DateComponents(year: 2026, month: 10, day: 19)

    func testTitlePrefersNicknameThenRefundNumberThenID() throws {
        XCTAssertEqual(try row { $0["customerNickname"] = .string(" Example visitor ") }.title, "Example visitor")
        XCTAssertEqual(try row().title, "EXAMPLE-REFUND")
        XCTAssertEqual(try row { $0["refundNo"] = .null }.title, "#62001")
    }
    func testStatusOverridesPendingBucketAndReturnedFunds() throws {
        XCTAssertEqual(try row { $0["bucket"] = .string("PENDING") }.statusKey, "merchantOps.aftercare.status.awaitingResponse")
        let refunded = try row { $0["bucket"] = .string("COMPLETED"); $0["processing"] = .string("REFUNDED"); $0["refunded"] = .bool(true) }
        XCTAssertEqual(refunded.statusKey, "merchantOps.aftercare.status.returned"); XCTAssertEqual(refunded.tone, .success)
        XCTAssertEqual(try row { $0["bucket"] = .string("PROCESSING") }.statusKey, "merchantOps.aftercare.processing.WAITING_PLATFORM_REVIEW")
    }
    func testTimeTakeoverAndAmount() throws {
        let value = try row { $0["createTime"] = .string("2026-10-19T08:05:09"); $0["platformTakeoverAt"] = .string("2026-10-20 08:05:00") }
        XCTAssertEqual(value.timeText, "08:05"); XCTAssertEqual(value.dayKey, "2026-10-19"); XCTAssertTrue(value.isTakenOver)
        XCTAssertEqual(value.amountCents, 1200); XCTAssertEqual(value.amountDisplay, "¥12.00")
        let unknown = try row { $0["refundAmount"] = .null; $0["createTime"] = .null }
        XCTAssertNil(unknown.amountCents); XCTAssertNil(unknown.dayKey); XCTAssertNil(unknown.timeText); XCTAssertFalse(unknown.isTakenOver)
    }
    func testDayGroupsKeepServerOrderAndOnlyCompleteTotals() throws {
        let a = try row { $0["refundId"] = .number(1); $0["createTime"] = .string("2026-10-19 09:00:00"); $0["refundAmount"] = .string("1.50") }
        let b = try row { $0["refundId"] = .number(2); $0["createTime"] = .string("2026-10-19 08:00:00"); $0["refundAmount"] = .string("2.25") }
        let c = try row { $0["refundId"] = .number(3); $0["createTime"] = .string("2026-10-18 08:00:00"); $0["refundAmount"] = .null }
        let d = try row { $0["refundId"] = .number(4); $0["createTime"] = .string("2026-03-02 08:00:00") }
        let e = try row { $0["refundId"] = .number(5); $0["createTime"] = .string("2025-12-31 08:00:00") }
        let groups = MerchantAftercareParity.groups([a, b, c, d, e], today: today)
        XCTAssertEqual(groups.map(\.label), [.today, .yesterday, .sameYear(month: 3, day: 2), .otherYear(year: 2025, month: 12, day: 31)])
        XCTAssertEqual(groups[0].rows.map(\.id), ["1", "2"]); XCTAssertEqual(groups[0].total, "¥3.75")
        XCTAssertNil(groups[1].total)
        XCTAssertNil(MerchantAftercareParity.groups([a, b], today: today, allowTotals: false)[0].total)
        XCTAssertNil(MerchantAftercareParity.groups([a, b], today: today, lastGroupComplete: false)[0].total)
        XCTAssertEqual(MerchantAftercareParity.leadingGroup(rowID: "1", in: [a, b], today: today, allowTotals: true, lastGroupComplete: true)?.id, "2026-10-19")
        XCTAssertNil(MerchantAftercareParity.leadingGroup(rowID: "2", in: [a, b], today: today, allowTotals: true, lastGroupComplete: true))
        let unknown = try row { $0["createTime"] = .null }
        XCTAssertEqual(MerchantAftercareParity.groups([unknown], today: today).first?.label, .unknown)
    }
    func testYesterdayCrossesMonthAndYear() {
        XCTAssertEqual(MerchantAftercareParity.label("2025-12-31", todayKey: "2026-01-01",
            yesterdayKey: MerchantAftercareParity.dayKey(MerchantAftercareParity.shift(DateComponents(year: 2026, month: 1, day: 1), by: -1)), year: 2026), .yesterday)
    }
    func testEmptySourcePolicyAndReadOnlyCopy() {
        XCTAssertEqual(MerchantAftercareParity.emptyKey("PENDING"), "merchantOps.aftercare.empty.PENDING")
        XCTAssertEqual(MerchantAftercareParity.emptyKey("COMPLETED"), "merchantOps.aftercare.empty.COMPLETED")
        XCTAssertEqual(MerchantAftercareParity.sourceKey("REGISTRATION"), "merchantOps.aftercare.source.registration")
        XCTAssertEqual(MerchantAftercareParity.sourceKey(nil), "merchantOps.aftercare.source.other")
        XCTAssertEqual(MerchantAftercareParity.policyKey("EXPLORE_END_100_0"), "merchantOps.aftercare.policy.exploreEnd")
        XCTAssertEqual(MerchantAftercareParity.policyKey("OTHER"), "merchantOps.aftercare.policy.snapshot")
        XCTAssertEqual(MerchantAftercareParity.policyKey(nil), "merchantOps.aftercare.policy.unknown")
        XCTAssertEqual(MerchantAftercareParity.readOnlyReason(canRespondPermission: false, detailCanRespond: true), .roleViewOnly)
        XCTAssertEqual(MerchantAftercareParity.readOnlyReason(canRespondPermission: true, detailCanRespond: false), .platformClosed)
        XCTAssertNil(MerchantAftercareParity.readOnlyReason(canRespondPermission: true, detailCanRespond: true))
    }
    func testPlatformStepsNeverClaimFundsFromOpinion() {
        XCTAssertEqual(MerchantAftercareParity.platformSteps(.waiting).map(\.state), [.doing, .todo])
        XCTAssertEqual(MerchantAftercareParity.platformSteps(.waiting).last?.hintKey, "merchantOps.aftercare.funds.unconfirmed")
        XCTAssertEqual(MerchantAftercareParity.platformSteps(.rejected).map(\.state), [.rejected])
        XCTAssertEqual(MerchantAftercareParity.platformSteps(.refunded).map(\.state), [.done, .done])
        for processing in [MerchantAftercareProgress.Processing.refunding, .manualPending, .manualReview] {
            XCTAssertEqual(MerchantAftercareParity.platformSteps(processing).map(\.state), [.done, .doing])
        }
        XCTAssertEqual(MerchantAftercareParity.platformSteps(.unknown).map(\.state), [.todo])
    }
}
