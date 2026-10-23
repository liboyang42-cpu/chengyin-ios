import XCTest
@testable import QuestifyCore

final class MerchantSupplyDryRunProjectionTests: XCTestCase {
    private let requestID = "c07-journey-req"
    private func shanghai(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        var parts = DateComponents()
        parts.year = year; parts.month = month; parts.day = day
        parts.hour = hour; parts.minute = minute; parts.second = 0
        return calendar.date(from: parts)!
    }
    private var noon: Date { shanghai(2026, 10, 23, 12, 0) }
    private var validStart: Date { shanghai(2026, 10, 1, 0, 0) }
    private var validEnd: Date { shanghai(2026, 11, 1, 0, 0) }
    private func bookable(stock: Int64 = 10, reserved: Int = 1, total: Int = 4,
                          hoursOpen: Int? = 10 * 60, hoursClose: Int? = 21 * 60,
                          originalRequestID: String? = "c07-journey-req") -> MerchantSupplyDryRunFact {
        MerchantSupplyDryRunFact(skuID: 8, merchantID: 3, stock: stock, bookable: true,
                                 slotMinutes: 60, capacityPerSlot: 4, capacityTotal: total,
                                 capacityReserved: reserved, validStartInclusive: validStart,
                                 validEndExclusive: validEnd, hoursOpenMinute: hoursOpen,
                                 hoursCloseMinute: hoursClose, originalRequestID: originalRequestID)
    }
    func testFirstJourneyEvaluateAcceptDoesNotWriteStockRecoverOriginal() throws {
        var supply = MerchantSupplyDryRunProjection()
        let accept = supply.evaluate(bookable(), serverNow: noon, requestedQty: 1)
        XCTAssertEqual(accept.outcome, .accept)
        XCTAssertEqual(accept.originalRequestID, requestID)
        XCTAssertFalse(accept.writesStock)
        XCTAssertFalse(accept.writesReservation)
        XCTAssertTrue(accept.grantsIssue)
        XCTAssertEqual(supply.holdCount(originalRequestID: requestID), 1)
        let duplicate = supply.evaluate(bookable(), serverNow: noon, requestedQty: 1)
        XCTAssertEqual(duplicate.outcome, .accept)
        XCTAssertEqual(duplicate.originalRequestID, requestID)
        XCTAssertFalse(duplicate.writesStock)
        XCTAssertEqual(supply.holdCount(originalRequestID: requestID), 1)
        let unknown = supply.evaluate(bookable(hoursOpen: nil, hoursClose: nil),
                                      serverNow: noon, requestedQty: 1)
        XCTAssertEqual(unknown.outcome, .unknown)
        XCTAssertEqual(unknown.originalRequestID, requestID)
        XCTAssertFalse(unknown.writesStock)
        let recovered = supply.recoverOriginal(originalRequestID: requestID)
        XCTAssertEqual(recovered.outcome, .accept)
        XCTAssertEqual(recovered.originalRequestID, requestID)
        XCTAssertFalse(recovered.writesStock)
        XCTAssertEqual(supply.holdCount(originalRequestID: requestID), 1)
        var hold = EntitlementHoldProjection()
        let held = hold.project(
            EntitlementHoldFact(originalRequestID: requestID, registrationID: 78, chapterID: 124,
                                merchantID: 3, status: EntitlementHoldStatus.held,
                                validEndExclusive: validEnd, invalidReason: nil),
            serverNow: noon)
        XCTAssertEqual(held.outcome, .held)
        XCTAssertTrue(held.occupiesCapacity)
        XCTAssertFalse(held.holdingIsIssuance)
        XCTAssertFalse(held.executedReserve)
        XCTAssertFalse(held.executedRedeem)
        XCTAssertFalse(held.executedAward)
        XCTAssertEqual(hold.occupyCount(originalRequestID: requestID), 1)
        let heldAgain = hold.project(
            EntitlementHoldFact(originalRequestID: requestID, registrationID: 78, chapterID: 124,
                                merchantID: 3, status: EntitlementHoldStatus.held,
                                validEndExclusive: validEnd, invalidReason: nil),
            serverNow: noon)
        XCTAssertTrue(heldAgain.occupiesCapacity)
        XCTAssertEqual(hold.occupyCount(originalRequestID: requestID), 1)
        var evidence = FulfillmentEvidenceProjection()
        let steps = evidence.recordJourney(
            originalRequestID: requestID,
            facts: FulfillmentJourneyFacts(
                orderIssued: true, holdOccupiesCapacity: held.occupiesCapacity,
                appointment: FulfillmentAppointmentFact(slotID: "slot-noon", newSlotID: "slot-dusk",
                                                        slotKnown: true),
                inStore: FulfillmentInStoreEvidenceFact(attestedInStore: true, simulatedGPS: false),
                refundTrial: FulfillmentRefundTrialFact(now: noon, snapshotDeadline: validEnd, paid: true),
                aftercare: FulfillmentAftercareFact(caseOpen: true, merchantResponded: false)))
        XCTAssertEqual(steps.count, 7)
        XCTAssertTrue(steps.allSatisfy { $0.originalRequestID == requestID })
        XCTAssertTrue(steps.allSatisfy { $0.executedWriter == false })
        XCTAssertEqual(steps.first { $0.stage == .reschedule }?.outcome, .recorded)
        XCTAssertEqual(steps.first { $0.stage == .inStoreRedeem }?.outcome, .recorded)
        XCTAssertEqual(steps.first { $0.stage == .refundEstimate }?.detail, "refund trial; no payout")
        var bills = FourLedgerBillRereadProjection()
        let view = bills.reread(originalRequestID: requestID, facts: [
            FourLedgerBillFact(originalRequestID: requestID, dimension: .wechatTrade,
                               expectedAmount: Decimal(string: "69.00"), actualAmount: nil,
                               billPresent: false, sourceHash: nil),
            FourLedgerBillFact(originalRequestID: requestID, dimension: .registrationOrder,
                               expectedAmount: Decimal(string: "69.00"),
                               actualAmount: Decimal(string: "69.00"),
                               billPresent: true, sourceHash: "reg-hash"),
            FourLedgerBillFact(originalRequestID: requestID, dimension: .memberBalance,
                               expectedAmount: Decimal(0), actualAmount: Decimal(0),
                               billPresent: true, sourceHash: "bal-hash"),
            FourLedgerBillFact(originalRequestID: requestID, dimension: .merchantPayable,
                               expectedAmount: Decimal(string: "12.50"),
                               actualAmount: Decimal(string: "12.50"),
                               billPresent: true, sourceHash: "pay-hash")
        ])
        XCTAssertEqual(view.outcome(.wechatTrade), .unknown)
        XCTAssertEqual(view.outcome(.registrationOrder), .matched)
        XCTAssertFalse(view.startedNewReconcile)
        XCTAssertFalse(view.currentProjectionReplacesOriginal)
        XCTAssertTrue(bills.originalUnknownNotReplacedByProjectionSuccess(view, projectionClaimsSuccess: true))
        XCTAssertEqual(bills.recoverOriginal(originalRequestID: requestID).originalRequestID, requestID)
        var invoice = InvoiceHistoryUnknownProjection()
        let invoiceView = invoice.reread(
            InvoiceApplicationFact(originalRequestID: requestID, status: InvoiceHistoryKnown.submitted,
                                   invoiceNo: nil, fileLocator: nil,
                                   provider: InvoiceHistoryKnown.manualProvider))
        XCTAssertEqual(invoiceView.fileStatus, .unknown)
        XCTAssertFalse(invoiceView.startedNewApply)
        XCTAssertTrue(invoice.originalUnknownNotReplacedByProjectionSuccess(
            invoiceView, projectionClaimsFileSuccess: true))
        XCTAssertEqual(invoice.recoverOriginal(originalRequestID: requestID).originalRequestID, requestID)
        var transfer = TransferSoldPolicyProjection()
        let gate = transfer.evaluate(
            TransferSoldPolicyFact(originalRequestID: requestID, soldPolicySourceHash: nil,
                                   designatedRecipientMemberID: 88, irrevocableEffectRecorded: true,
                                   smsIdentityVerified: true))
        XCTAssertEqual(gate.outcome, .waitingSource)
        XCTAssertFalse(gate.grantsTransfer)
        XCTAssertFalse(gate.usedSmsIdentityAsPolicy)
        XCTAssertEqual(transfer.recoverOriginal(originalRequestID: requestID).originalRequestID, requestID)
    }
    func testMissingHoursOnBookableSkuIsUnknownNotAWrite() {
        var supply = MerchantSupplyDryRunProjection()
        let decision = supply.evaluate(bookable(hoursOpen: nil, hoursClose: nil, originalRequestID: "c07-supply-2"),
                                       serverNow: noon, requestedQty: 1)
        XCTAssertEqual(decision.outcome, .unknown)
        XCTAssertEqual(decision.originalRequestID, "c07-supply-2")
        XCTAssertFalse(decision.grantsIssue)
        XCTAssertEqual(supply.holdCount(originalRequestID: "c07-supply-2"), 0)
    }
    func testBlankOriginalRequestIDIsJSONNullNotEmptyString() throws {
        var supply = MerchantSupplyDryRunProjection()
        let decision = supply.evaluate(bookable(originalRequestID: "  "), serverNow: noon, requestedQty: 1)
        XCTAssertEqual(decision.outcome, .unknown)
        XCTAssertNil(decision.originalRequestID)
        let data = try JSONSerialization.data(withJSONObject: decision.jsonObject(), options: [])
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertTrue(object["originalRequestID"] is NSNull)
        XCTAssertFalse((object["originalRequestID"] as? String) == "")
        let missing = supply.evaluate(bookable(originalRequestID: nil), serverNow: noon, requestedQty: 1)
        XCTAssertNil(missing.originalRequestID)
        XCTAssertEqual(missing.outcome, .unknown)
    }
    func testExhaustedHoursCapacityRejectsAndStillDoesNotReserve() {
        var supply = MerchantSupplyDryRunProjection()
        let decision = supply.evaluate(bookable(reserved: 4, total: 4), serverNow: noon, requestedQty: 1)
        XCTAssertEqual(decision.outcome, .reject)
        XCTAssertEqual(decision.reason, "hours-capacity exhausted")
        XCTAssertFalse(decision.writesReservation)
        XCTAssertEqual(decision.originalRequestID, requestID)
    }
    func testServerNowUsesAsiaShanghaiNotDeviceClockAssumption() {
        XCTAssertEqual(TimeZone(identifier: "Asia/Shanghai")?.identifier,
                       MerchantSupplyDryRunProjection.shanghaiTimeZone.identifier)
        let evening = shanghai(2026, 10, 23, 22, 0)
        var supply = MerchantSupplyDryRunProjection()
        let decision = supply.evaluate(bookable(), serverNow: evening, requestedQty: 1)
        XCTAssertEqual(decision.outcome, .reject)
        XCTAssertEqual(decision.reason, "outside business hours")
        XCTAssertEqual(MerchantSupplyDryRunProjection.minuteOfDay(serverNow: noon), 12 * 60)
    }
    func testRecoverOfNeverSeenIdDoesNotOccupyLedgerThenAcceptApplies() {
        var supply = MerchantSupplyDryRunProjection()
        let recovered = supply.recoverOriginal(originalRequestID: "c07-supply-never-seen")
        XCTAssertEqual(recovered.outcome, .unknown)
        XCTAssertEqual(recovered.originalRequestID, "c07-supply-never-seen")
        XCTAssertEqual(supply.holdCount(originalRequestID: "c07-supply-never-seen"), 0)
        let missing = supply.evaluate(bookable(hoursOpen: nil, hoursClose: nil,
                                               originalRequestID: "c07-supply-never-seen"),
                                      serverNow: noon, requestedQty: 1)
        XCTAssertEqual(missing.outcome, .unknown)
        XCTAssertEqual(supply.holdCount(originalRequestID: "c07-supply-never-seen"), 0)
        XCTAssertEqual(supply.recoverOriginal(originalRequestID: "c07-supply-never-seen").outcome, .unknown)
        let accept = supply.evaluate(bookable(originalRequestID: "c07-supply-never-seen"),
                                     serverNow: noon, requestedQty: 1)
        XCTAssertEqual(accept.outcome, .accept)
        XCTAssertEqual(supply.holdCount(originalRequestID: "c07-supply-never-seen"), 1)
        XCTAssertEqual(supply.recoverOriginal(originalRequestID: "c07-supply-never-seen").outcome, .accept)
    }
}
