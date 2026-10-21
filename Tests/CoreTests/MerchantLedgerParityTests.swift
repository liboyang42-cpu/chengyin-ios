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

    func testRedemptionDetailHeroUsesDetailCopyAndAccrual() throws {
        let hero = MerchantLedgerParity.redemptionHero(try redemption { $0["unitFee"] = .string("3"); $0["headCount"] = .number(2); $0["storeName"] = .null; $0["refundState"] = .string("REFUNDED") })
        XCTAssertTrue(hero.showsIncome); XCTAssertEqual(hero.title, "Example route · Example chapter")
        XCTAssertEqual(hero.state, .key("merchantOps.ledger.detail.pendingPersonal")); XCTAssertEqual(hero.amountKey, "merchantOps.ledger.amount.pending")
        XCTAssertEqual(hero.accrual, "¥3.00/人 × 2"); XCTAssertNil(hero.store); XCTAssertEqual(hero.refundKey, "merchantOps.ledger.refund.refunded")
        let chapter = MerchantLedgerParity.redemptionHero(try redemption { $0["displayState"] = .string("SETTLED"); $0["settlementRoute"] = .string("CHAPTER_OFFER"); $0["settlementAmount"] = .string("8") })
        XCTAssertEqual(chapter.state, .key("merchantOps.ledger.state.settledPaid")); XCTAssertEqual(chapter.amount, "¥8.00")
        let redacted = MerchantLedgerParity.redemptionHero(try redemption { $0["settlementState"] = .null; $0["settlementRoute"] = .null; $0["displayState"] = .null })
        XCTAssertFalse(redacted.showsIncome); XCTAssertNil(redacted.amountKey); XCTAssertNil(redacted.accrual)
        XCTAssertEqual(redacted.state, .key("merchantOps.ledger.fulfilment.active"))
    }
    func testBatchHeroPaymentTextAndInvoiceFallback() throws {
        let hero = MerchantLedgerParity.batchHero(try object(MerchantBusinessSyntheticFixtures.batch))
        XCTAssertEqual(hero.period, "2026-09"); XCTAssertEqual(hero.amount, "¥0.00")
        XCTAssertEqual(hero.stateKey, "merchantOps.ledger.batch.reconciling"); XCTAssertEqual(hero.invoiceKey, "merchantOps.ledger.invoice.unknown")
        let paid = MerchantLedgerParity.batchHero(["paymentState": .string("PAID"), "netDirection": .string("PLATFORM_PAYS_MERCHANT")])
        XCTAssertEqual(paid.stateKey, "merchantOps.ledger.state.settledPaid"); XCTAssertEqual(paid.variant, .success)
        XCTAssertEqual(MerchantLedgerParity.batchHero(["netDirection": .string("MERCHANT_OWES_PLATFORM")]).variant, .danger)
    }
    func testBatchStatementAndRedemptionIssueState() {
        let emptyStatement = MerchantLedgerParity.batchStatementSummary(["amountTotal": .string("18.00")], lineCount: 0)
        XCTAssertEqual(emptyStatement.title, "对账单")
        XCTAssertNil(emptyStatement.totalText)
        XCTAssertEqual(emptyStatement.emptyText, "当前批次暂无对账明细")

        let populatedStatement = MerchantLedgerParity.batchStatementSummary(
            ["amountTotal": .string("18.00"), "createdAt": .string("2026-10-19 10:00:00"), "paidAt": .string("2026-10-20 12:30:00")],
            lineCount: 2
        )
        XCTAssertEqual(populatedStatement.totalText, "¥18.00")
        XCTAssertNil(populatedStatement.emptyText)
        XCTAssertEqual(populatedStatement.stepTimestamps, ["2026-10-19 10:00", "2026-10-20 12:30"])

        XCTAssertEqual(MerchantLedgerParity.redemptionRecordIssueState(record: nil)?.title, "找不到这条核销记录")
        XCTAssertEqual(MerchantLedgerParity.redemptionRecordIssueState(record: [:], denied: true)?.title, "当前账号无权查看该核销记录")
    }
}
