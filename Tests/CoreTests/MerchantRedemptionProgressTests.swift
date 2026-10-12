import XCTest
@testable import QuestifyCore

final class MerchantRedemptionProgressTests: XCTestCase {
    private func fields(_ state: String = "PENDING") -> MerchantBusinessObject {
        ["recordKey": .string("redemption:64001"), "settlementRoute": .string("CHAPTER_OFFER"),
         "settlementState": .string(state), "displayState": .string("PENDING_SETTLEMENT"),
         "settlementAmount": .string("12.00"), "occurredAt": .string("2026-10-01 10:00:00"),
         "publicSettlement": .object(["paidAt": .string("2026-10-03 11:00:00")])]
    }
    private func project(_ fields: MerchantBusinessObject, finance: Bool = true) throws -> MerchantRedemptionProgress? {
        var raw = try XCTUnwrap(MerchantBusinessSyntheticFixtures.decode(MerchantBusinessSyntheticFixtures.access).object)
        if !finance { raw["permissions"] = .array([]); raw["canManageOperators"] = .bool(false) }
        return try .init(record: .init(kind: .redemption, fields: fields), access: .init(raw))
    }
    func testPendingHasOnlyNextStepCurrent() throws {
        let value = try XCTUnwrap(project(fields()))
        XCTAssertEqual(value.steps.map(\.state), [.done, .current, .pending, .pending])
        XCTAssertEqual(value.steps.map(\.id), ["redeemed", "generated", "confirmed", "paid"])
    }
    func testSettledAndAdjustmentsRetainCompletedOriginalPayment() throws {
        for state in ["SETTLED", "ADJUSTED", "ADJUSTMENT_PENDING"] {
            XCTAssertEqual(try XCTUnwrap(project(fields(state))).steps.map(\.state), [.done, .done, .done, .done])
        }
    }
    func testTerminalAndUnknownDoNotPromiseProgress() throws {
        for state in ["NOT_APPLICABLE", "ERROR", "FUTURE"] {
            let value = try XCTUnwrap(project(fields(state)))
            XCTAssertEqual(value.steps.map(\.state), [.done, .pending, .pending, .pending])
            XCTAssertNil(value.steps.last?.timestamp)
        }
    }
    func testPaidTimestampCannotPromoteStateOrDateFutureStep() throws {
        let value = try XCTUnwrap(project(fields()))
        XCTAssertEqual(value.steps.compactMap(\.timestamp), ["2026-10-01 10:00:00"])
    }
    func testCompletedDatesAreOnlyExactServerFacts() throws {
        var raw = fields("SETTLED")
        let value = try XCTUnwrap(project(raw))
        XCTAssertEqual(value.steps.compactMap(\.timestamp), ["2026-10-01 10:00:00", "2026-10-03 11:00:00"])
        raw["occurredAt"] = nil; raw["publicSettlement"] = nil
        XCTAssertTrue(try XCTUnwrap(project(raw)).steps.compactMap(\.timestamp).isEmpty)
    }
    func testNoFinancePermissionOrRedactedProjectionHidesTimeline() throws {
        XCTAssertNil(try project(fields(), finance: false))
        for key in ["settlementState", "settlementRoute", "displayState"] {
            var raw = fields(); raw[key] = .null
            XCTAssertNil(try project(raw))
        }
    }
    func testPersonalAndUnknownRoutesDoNotShowPlatformTimeline() throws {
        for route in ["PERSONAL", "TOPIC", "FUTURE", ""] {
            var raw = fields(); raw["settlementRoute"] = .string(route)
            XCTAssertNil(try project(raw))
        }
    }
    func testProjectionLeavesAmountAndInputUntouched() throws {
        let raw = fields(); let original = raw
        _ = try project(raw)
        XCTAssertEqual(raw, original)
    }
}
