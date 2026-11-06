import XCTest
@testable import QuestifyCore

/// Source pages/merchant/customer/index.js shapeRow, relativeTime and customerSummaryText.
final class MerchantCustomerListParityTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_792_339_200) // 2026-10-19 00:00 +08:00
    func testRowTierNoteAndActionParts() {
        let row = MerchantCustomerListParity.row(["name": .string(" Example customer "), "tier": .string("pending"), "latestNote": .string("Prefers mornings"),
                                                  "lastAction": .string("Redeemed a route"), "lastTime": .string("2026-10-16 09:00:00")], now: now)
        XCTAssertEqual(row.name, "Example customer"); XCTAssertEqual(row.tierKey, "merchantOps.customer.tier.pending"); XCTAssertTrue(row.tierUrgent)
        XCTAssertEqual(row.latestNote, "Prefers mornings"); XCTAssertEqual(row.relative, .days(2))
        let bare = MerchantCustomerListParity.row(["tier": .string("future"), "latestNote": .string("  ")], now: now)
        XCTAssertNil(bare.name); XCTAssertNil(bare.tierKey); XCTAssertNil(bare.latestNote); XCTAssertNil(bare.relative)
    }
    func testRelativeBuckets() {
        func ago(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }
        XCTAssertEqual(MerchantCustomerListParity.relative(from: ago(0.5), now: now), .today)
        XCTAssertEqual(MerchantCustomerListParity.relative(from: ago(1.2), now: now), .yesterday)
        XCTAssertEqual(MerchantCustomerListParity.relative(from: ago(29), now: now), .days(29))
        XCTAssertEqual(MerchantCustomerListParity.relative(from: ago(65), now: now), .months(2))
        XCTAssertEqual(MerchantCustomerListParity.relative(from: ago(800), now: now), .years(2))
        XCTAssertNil(MerchantCustomerListParity.relative(from: now.addingTimeInterval(60), now: now))
    }
    func testInstantKeepsOffsetsAndTreatsBareTimeAsChina() throws {
        XCTAssertEqual(MerchantCustomerListParity.instant(.string("2026-10-19 00:00:00")), now)
        XCTAssertEqual(MerchantCustomerListParity.instant(.string("2026-10-18T16:00:00Z")), now)
        XCTAssertEqual(MerchantCustomerListParity.instant(.number(1_792_339_200_000)), now)
        XCTAssertNil(MerchantCustomerListParity.instant(.string("not a time")))
    }
    func testSummaryText() {
        XCTAssertEqual(MerchantCustomerListParity.summary(["all": .number(12), "monthlyNew": .number(3)]), .totalWithMonthly(12, 3))
        XCTAssertEqual(MerchantCustomerListParity.summary(["all": .number(12)]), .total(12))
        XCTAssertNil(MerchantCustomerListParity.summary([:]))
    }
}

final class MerchantCustomerIdentityLineTests: XCTestCase {
    func testIdentityDayUsesChinaCalendar() throws {
        let late = try XCTUnwrap(MerchantCustomerListParity.instant(.string("2026-08-26T17:30:00Z"))) // 2026-08-27 01:30 China
        let day = try XCTUnwrap(MerchantCustomerListParity.identityDay(late))
        XCTAssertEqual(day.month, 8); XCTAssertEqual(day.day, 27)
        XCTAssertNil(MerchantCustomerListParity.identityDay(nil))
    }
    func testNoteCounterAndParticipationRow() {
        XCTAssertEqual(MerchantCustomerListParity.noteCounterText("常来"), "2/500")
        XCTAssertEqual(MerchantCustomerListParity.noteCorrectionHint, "备注仅本店可见")
        XCTAssertTrue(MerchantCustomerListParity.isNoteValid("常来"))
        let row = MerchantCustomerListParity.participationRow(["topicName": .string("夜游西湖"), "occurredAt": .string("2026-10-18 19:00:00"), "paidAmount": .string("39.9")])
        XCTAssertEqual(row.title, "夜游西湖")
        XCTAssertEqual(row.dateText, "2026-10-18")
        XCTAssertEqual(row.paidAmountText, "¥39.90")
    }
}
