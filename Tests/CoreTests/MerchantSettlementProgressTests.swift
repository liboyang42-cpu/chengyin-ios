import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

final class MerchantSettlementProgressTests: XCTestCase {
    private func fields(_ payment: String = "PENDING") -> MerchantBusinessObject {
        ["batchId": .string("66001"), "periodYm": .string("2026-09"), "amountTotal": .string("12.50"),
         "netDirection": .string("PLATFORM_PAYS_MERCHANT"), "paymentState": .string(payment),
         "invoiceState": .string("NONE"), "holdState": .string("NORMAL"), "displayState": .null,
         "paidAt": .string("2026-10-08 10:00:00"), "payVoucherNo": .string("SYNTHETIC-VOUCHER")]
    }
    private func project(_ fields: MerchantBusinessObject) throws -> MerchantSettlementProgress {
        try .init(record: .init(kind: .batch, fields: fields))
    }
    func testThreePaymentStatesHaveStateDrivenProgress() throws {
        let expected: [[MerchantSettlementProgress.StepState]] = [[.done, .current, .pending], [.done, .done, .current], [.done, .done, .done]]
        for (index, payment) in ["PENDING", "CONFIRMED", "PAID"].enumerated() {
            let value = try project(fields(payment))
            XCTAssertEqual(value.steps.map(\.state), expected[index])
            XCTAssertEqual(value.isPaid, payment == "PAID")
            XCTAssertEqual(value.steps.compactMap(\.timestamp).count, payment == "PAID" ? 1 : 0)
        }
    }
    func testTimestampAndVoucherNeverPromotePendingOrConfirmedToPaid() throws {
        for payment in ["PENDING", "CONFIRMED", "FUTURE"] {
            let value = try project(fields(payment))
            XCTAssertFalse(value.isPaid); XCTAssertNil(value.voucherForCopy)
            XCTAssertTrue(value.steps.compactMap(\.timestamp).isEmpty)
        }
    }
    func testZeroAndOwedAmountsHaveNoPlatformPayoutTimeline() throws {
        for (direction, amount, suffix) in [("ZERO", "0.00", "zero"), ("MERCHANT_OWES_PLATFORM", "-12.50", "owes")] {
            var data = fields("PAID"); data["netDirection"] = .string(direction); data["amountTotal"] = .string(amount)
            let value = try project(data)
            XCTAssertTrue(value.steps.isEmpty); XCTAssertNil(value.voucherForCopy)
            XCTAssertEqual(value.paymentKey, "merchant.settlementProgress.status." + suffix)
            XCTAssertEqual(value.amount.raw, amount)
        }
    }
    func testInvoiceAndHoldNeverPromotePayment() throws {
        for invoice in ["NONE", "ISSUED", "RED", "FUTURE"] {
            for hold in ["NORMAL", "FROZEN"] {
                var data = fields(); data["invoiceState"] = .string(invoice); data["holdState"] = .string(hold)
                let value = try project(data)
                XCTAssertFalse(value.isPaid); XCTAssertNil(value.voucherForCopy)
                XCTAssertEqual(value.steps[1].state, hold == "FROZEN" ? .paused : .current)
            }
        }
    }
    func testPaidButFrozenRetainsHistoricalPaymentFact() throws {
        var data = fields("PAID"); data["holdState"] = .string("FROZEN"); data["invoiceState"] = .string("NONE")
        let value = try project(data)
        XCTAssertTrue(value.isPaid); XCTAssertEqual(value.steps.map(\.state), [.done, .done, .done])
        XCTAssertEqual(value.paymentKey, "merchant.settlementProgress.status.frozen")
        XCTAssertEqual(value.invoiceKey, "merchant.settlementProgress.invoice.none")
    }
    func testLedgerErrorBlocksProgressAndCopyDespitePaidArtifacts() throws {
        for payment in ["PENDING", "PAID"] {
            var data = fields(payment); data["displayState"] = .string("LEDGER_ERROR")
            let value = try project(data)
            XCTAssertTrue(value.steps.isEmpty); XCTAssertNil(value.voucherForCopy)
            XCTAssertEqual(value.paymentKey, "merchant.settlementProgress.status.ledgerError")
        }
    }
    func testIncompletePaidEvidenceNeverOffersCopy() throws {
        for key in ["paidAt", "payVoucherNo", "amountTotal"] {
            for bad in [MerchantBusinessValue.null, .string("")] {
                var data = fields("PAID"); data[key] = bad
                if key == "amountTotal", bad == .string("") { XCTAssertThrowsError(try project(data)); continue }
                let value = try project(data)
                XCTAssertFalse(value.isPaid); XCTAssertNil(value.voucherForCopy)
                XCTAssertFalse(value.steps.contains { $0.state == .current })
                XCTAssertEqual(value.paymentKey, "merchant.settlementProgress.status.incomplete")
            }
        }
        for amount in ["0.00", "-1.00"] {
            var data = fields("PAID"); data["amountTotal"] = .string(amount)
            XCTAssertNil(try project(data).voucherForCopy)
        }
    }
    func testUnknownAxesPreserveRawAndDoNotInventMilestones() throws {
        for key in ["netDirection", "paymentState", "holdState"] {
            var data = fields(); data[key] = .string("FUTURE_STATE")
            let value = try project(data)
            XCTAssertTrue(value.steps.isEmpty); XCTAssertNil(value.voucherForCopy)
        }
        var data = fields(); data["invoiceState"] = .string("FUTURE_INVOICE")
        XCTAssertEqual(try project(data).invoiceKey, "merchant.settlementProgress.invoice.unknown")
    }
    func testMissingAmountIsUnknownAndSignedAmountsAreNotRecomputed() throws {
        var data = fields(); data.removeValue(forKey: "amountTotal")
        XCTAssertNil(try project(data).amount.raw)
        data["amountTotal"] = .string("-12.345")
        XCTAssertEqual(try project(data).amount.display, "CNY -12.345")
    }
    func testMissingOrMalformedAxisFallsBackToExistingGenericFields() throws {
        for key in ["periodYm", "netDirection", "paymentState", "invoiceState", "holdState"] {
            for bad in [MerchantBusinessValue.null, .int(0), .string("   ")] {
                var data = fields(); data[key] = bad
                XCTAssertThrowsError(try project(data))
            }
        }
        var data = fields("PAID"); data["payVoucherNo"] = .bool(true)
        XCTAssertThrowsError(try project(data))
    }
    func testCopyPreservesExactVoucherWithoutLoggingOrAddingPaymentFields() throws {
        var data = fields("PAID"); data["payVoucherNo"] = .string("  SYNTHETIC-ABC-001  ")
        XCTAssertEqual(try project(data).voucherForCopy, "  SYNTHETIC-ABC-001  ")
    }
    func testShanghaiBareAndJacksonISOResolveTheSamePaymentInstant() throws {
        let bare = try XCTUnwrap(MerchantSettlementProgress.paymentTimestamp("2026-10-08 01:15:00"))
        let iso = try XCTUnwrap(MerchantSettlementProgress.paymentTimestamp("2026-10-08T01:15:00.000+08:00"))
        let utc = try XCTUnwrap(MerchantSettlementProgress.paymentTimestamp("2026-10-07T17:15:00Z"))
        XCTAssertEqual(bare, iso); XCTAssertEqual(iso, utc)
        let fractional = try XCTUnwrap(MerchantSettlementProgress.paymentTimestamp("2026-10-08T01:15:00.125+08:00"))
        XCTAssertEqual(fractional.timeIntervalSince(bare), 0.125, accuracy: 0.001)
    }
    func testPaymentDisplayCrossesDayAndFollowsChangedPhoneTimeZone() throws {
        let date = try XCTUnwrap(MerchantSettlementProgress.paymentTimestamp("2026-10-08T01:15:00.000+08:00"))
        let la = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let utc = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        XCTAssertEqual(MerchantAftercareTime.event(date, phoneTimeZone: la), "2026-10-07 10:15:00 -07:00")
        XCTAssertEqual(MerchantAftercareTime.event(date, phoneTimeZone: utc), "2026-10-07 17:15:00 Z")
        XCTAssertEqual(MerchantAftercareTime.event(date, phoneTimeZone: MerchantAftercareTime.beijing), "2026-10-08 01:15:00 +08:00")
    }
    func testPaymentDisplayPreservesDSTGapAndRepeatedHourOffsets() throws {
        let la = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let cases = [
            ("2026-03-08T17:30:00.000+08:00", "2026-03-08 01:30:00 -08:00"),
            ("2026-03-08T18:30:00.000+08:00", "2026-03-08 03:30:00 -07:00"),
            ("2026-11-01T16:30:00.000+08:00", "2026-11-01 01:30:00 -07:00"),
            ("2026-11-01T17:30:00.000+08:00", "2026-11-01 01:30:00 -08:00")]
        for (raw, expected) in cases {
            let date = try XCTUnwrap(MerchantSettlementProgress.paymentTimestamp(raw))
            XCTAssertEqual(MerchantAftercareTime.event(date, phoneTimeZone: la), expected)
        }
    }
    func testMissingMalformedAndOffsetlessISOTimesNeverInventDates() {
        let invalid: [String?] = [nil, "", " ", "tomorrow", "0", "2026-02-30 12:00:00",
            "2026-02-30T12:00:00.000+08:00", "2026-10-08T25:00:00+08:00",
            "2026-10-08T01:15:00", "2026-10-08T01:15:00.000", "2026-10-08 01:15", "2026-10-08T01:15:00+25:00",
            "2026-10-08T01:15:00+08:99"]
        for raw in invalid {
            XCTAssertNil(MerchantSettlementProgress.paymentTimestamp(raw))
        }
    }
    func testTimePresentationNeverChangesPaidPendingFactsOrCopyAuthorization() throws {
        let la = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        for payment in ["PAID", "PENDING", "CONFIRMED"] {
            for raw in ["2026-10-08T01:15:00.000+08:00", "2026-10-08 01:15:00", "malformed"] {
                var data = fields(payment); data["paidAt"] = .string(raw)
                let before = try project(data)
                if let date = MerchantSettlementProgress.paymentTimestamp(before.paidAt) {
                    _ = MerchantAftercareTime.event(date, phoneTimeZone: la)
                    _ = MerchantAftercareTime.event(date, phoneTimeZone: MerchantAftercareTime.beijing)
                }
                let after = try project(data)
                XCTAssertEqual(before, after); XCTAssertEqual(before.isPaid, payment == "PAID")
                XCTAssertEqual(before.voucherForCopy != nil, payment == "PAID")
                XCTAssertEqual(before.steps.compactMap(\.timestamp).count, payment == "PAID" ? 1 : 0)
            }
        }
    }
    func testFreshReadUsesExistingOwnedBatchRouteAndNoMerchantOverride() async throws {
        let data = MerchantBusinessValue.object(["code": .int(200), "data": .object([
            "batch": .object(fields("PAID")), "earningEntries": .array([]), "adjustments": .array([])])])
        let transport = SettlementProgressTransport(data: try JSONEncoder().encode(data))
        let service = try MerchantBusinessService(configuration: .init(baseURL: URL(string: "https://example.test")!), readTransport: transport)
        let access = try MerchantBusinessAccess(MerchantBusinessSyntheticFixtures.decode(MerchantBusinessSyntheticFixtures.access).object!)
        let document = try await service.document(.batch(.init(66001)), access: access, token: "synthetic-token")
        XCTAssertTrue(try project(document.rows[0].fields).isPaid)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1); XCTAssertEqual(requests[0].httpMethod, "POST")
        XCTAssertEqual(requests[0].url?.path, "/api/merchant/finance/public-transfer-batch-detail")
        XCTAssertEqual(try JSONDecoder().decode(MerchantBusinessValue.self, from: XCTUnwrap(requests[0].httpBody)), .object(["batchId": .int(66001)]))
        XCTAssertFalse(service.canExecuteSyntheticMutation)
    }
}
private actor SettlementProgressTransport: HTTPTransport {
    let data: Data
    private(set) var requests: [URLRequest] = []
    init(data: Data) { self.data = data }
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return (data, 200) }
}
