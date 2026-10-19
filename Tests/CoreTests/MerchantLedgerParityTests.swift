import XCTest
@testable import QuestifyCore

/// Source pages/merchant/ledger/index.js row and summary presentation.
final class MerchantLedgerParityTests: XCTestCase {
    private func object(_ json: String) throws -> MerchantBusinessObject { try XCTUnwrap(MerchantBusinessSyntheticFixtures.decode(json).object) }
    private func redemption(_ change: (inout MerchantBusinessObject) -> Void = { _ in }) throws -> MerchantBusinessObject {
        var fields = try object(MerchantBusinessSyntheticFixtures.redemption); change(&fields); return fields
    }
    func testRedemptionTitleCustomerTimeAndPendingThemeState() throws {
        let line = MerchantLedgerParity.redemption(try redemption(), canReadFinance: true)
        XCTAssertEqual(line.title, "Example route · Example chapter"); XCTAssertEqual(line.subtitle, "Example visitor"); XCTAssertEqual(line.timeText, "15:00")
        XCTAssertEqual(line.state, .key("merchantOps.ledger.state.pendingTheme")); XCTAssertEqual(line.variant, .warning)
        XCTAssertNil(line.amount); XCTAssertEqual(line.amountKey, "merchantOps.ledger.amount.pending"); XCTAssertEqual(line.tone, .muted)
    }
    func testRedemptionAmountsAndNoCashReason() throws {
        let paid = MerchantLedgerParity.redemption(try redemption { $0["settlementAmount"] = .string("12.5"); $0["displayState"] = .string("SETTLED"); $0["destination"] = .string("PERSONAL_ACCOUNT") }, canReadFinance: true)
        XCTAssertEqual(paid.amount, "+¥12.50"); XCTAssertEqual(paid.tone, .positive); XCTAssertEqual(paid.state, .key("merchantOps.ledger.state.settledPersonal"))
        let noCash = MerchantLedgerParity.redemption(try redemption { $0["displayState"] = .string("NO_CASH_SETTLEMENT"); $0["noCashReason"] = .string("Example reason") }, canReadFinance: true)
        XCTAssertEqual(noCash.state, .server("Example reason")); XCTAssertEqual(noCash.amountKey, "merchantOps.ledger.amount.none")
        let anonymous = MerchantLedgerParity.redemption(try redemption { $0["customerDisplayName"] = .null; $0["topicName"] = .null; $0["chapterName"] = .null }, canReadFinance: true)
        XCTAssertEqual(anonymous.titleKey, "merchantOps.ledger.redemptionTitle"); XCTAssertEqual(anonymous.subtitleKey, "merchantOps.ledger.customerProtected")
    }
    func testWithoutFinanceOnlyFulfilmentShows() throws {
        let line = MerchantLedgerParity.redemption(try redemption { $0["settlementAmount"] = .string("9.00") }, canReadFinance: false)
        XCTAssertNil(line.amount); XCTAssertNil(line.amountKey); XCTAssertEqual(line.state, .key("merchantOps.ledger.fulfilment.active"))
        XCTAssertEqual(MerchantLedgerParity.redemption(try redemption { $0["fulfillmentState"] = .string("REVERSED") }, canReadFinance: false).state, .key("merchantOps.ledger.fulfilment.reversed"))
    }
    func testEntrySourceDateAndSignedAmount() throws {
        let line = MerchantLedgerParity.entry(try object(MerchantBusinessSyntheticFixtures.entry))
        XCTAssertEqual(line.titleKey, "merchantOps.ledger.source.adjustment"); XCTAssertEqual(line.timeText, "09-30")
        XCTAssertEqual(line.amount, "-¥12.00"); XCTAssertEqual(line.tone, .negative)
        var clawback = try object(MerchantBusinessSyntheticFixtures.entry); clawback["source"] = .string("MERCHANT_CLAWBACK")
        XCTAssertEqual(MerchantLedgerParity.entry(clawback).titleKey, "merchantOps.ledger.source.clawback")
    }
    func testBatchStatesFollowSourcePrecedence() {
        func state(_ fields: [String: String]) -> MerchantLedgerParity.State {
            MerchantLedgerParity.batch(fields.mapValues { .string($0) }).state
        }
        XCTAssertEqual(state(["displayState": "LEDGER_ERROR", "netDirection": "ZERO"]), .key("merchantOps.ledger.state.ledgerError"))
        XCTAssertEqual(state(["netDirection": "ZERO", "paymentState": "PAID"]), .key("merchantOps.ledger.batch.zero"))
        XCTAssertEqual(state(["netDirection": "MERCHANT_OWES_PLATFORM"]), .key("merchantOps.ledger.batch.owes"))
        XCTAssertEqual(state(["netDirection": "PLATFORM_PAYS_MERCHANT", "holdState": "FROZEN", "paymentState": "PAID"]), .key("merchantOps.ledger.batch.frozen"))
        XCTAssertEqual(state(["netDirection": "PLATFORM_PAYS_MERCHANT", "paymentState": "PAID", "invoiceState": "ISSUED"]), .key("merchantOps.ledger.batch.paidInvoiced"))
        XCTAssertEqual(state(["netDirection": "PLATFORM_PAYS_MERCHANT", "paymentState": "CONFIRMED"]), .key("merchantOps.ledger.batch.confirmed"))
        XCTAssertEqual(state(["netDirection": "PLATFORM_PAYS_MERCHANT"]), .key("merchantOps.ledger.batch.reconciling"))
    }
    func testSummaryUsesOnlyServerTotals() {
        XCTAssertEqual(MerchantLedgerParity.summary(["count": .number(3), "pendingAmount": .string("1"), "arrivedAmount": .string("2.5")], canReadFinance: true),
                       .init(count: 3, pending: "¥1.00", arrived: "¥2.50"))
        XCTAssertNil(MerchantLedgerParity.summary(["count": .number(3), "pendingAmount": .string("1")], canReadFinance: true))
        XCTAssertEqual(MerchantLedgerParity.summary(["count": .number(3)], canReadFinance: false), .init(count: 3, pending: nil, arrived: nil))
        XCTAssertNil(MerchantLedgerParity.summary([:], canReadFinance: false))
    }
}
