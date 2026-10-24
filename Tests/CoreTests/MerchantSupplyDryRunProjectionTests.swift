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
    func testRecoverFromDeskReceiptReadsAppliedWithoutHolding() async throws {
        var supply = MerchantSupplyDryRunProjection()
        do {
            _ = try await supply.recoverFromDeskReceipt(ownerMemberID: 7, requestID: "desk-req-01", receipt: nil)
            XCTFail("missing desk receipt must WAITING_SOURCE")
        } catch let waiting as MerchantSupplyDryRunProjection.WireFailure {
            XCTAssertEqual(waiting, .waitingSource(MerchantSupplyDryRunProjection.deskReceipt))
        }
        XCTAssertEqual(supply.holdCount(originalRequestID: "desk-req-01"), 0)
        let invalidOwner = try await supply.recoverFromDeskReceipt(ownerMemberID: 0, requestID: "desk-req-01",
                                                                   receipt: { _, _ in .string("APPLIED") })
        XCTAssertNil(invalidOwner)
        let missing = try await supply.recoverFromDeskReceipt(ownerMemberID: 7, requestID: "desk-missing",
                                                              receipt: { _, id in
            .object(["requestId": .string(id), "state": .string("NOT_FOUND")])
        })
        XCTAssertEqual(missing, .object(["requestId": .string("desk-missing"), "state": .string("NOT_FOUND")]))
        XCTAssertEqual(supply.holdCount(originalRequestID: "desk-missing"), 0)
        do {
            _ = try await supply.recoverFromDeskReceipt(ownerMemberID: 7, requestID: "desk-req-01",
                                                        receipt: { _, _ in throw MerchantSupplyDryRunProjection.WireFailure.transport("timeout") })
            XCTFail("transport must stay thrown")
        } catch let transport as MerchantSupplyDryRunProjection.WireFailure {
            XCTAssertEqual(transport, .transport("timeout"))
        }
        let recovered = try await supply.recoverFromDeskReceipt(ownerMemberID: 7, requestID: "desk-req-01",
                                                                storeID: 3, expectedSkuID: 44,
                                                                receipt: { owner, id in
            owner == 7 && id == "desk-req-01"
                ? .object(["requestId": .string(id), "state": .string("APPLIED"),
                           "action": .string("SKU_SAVE"), "targetType": .string("pms_sku"),
                           "targetId": .int(44), "storeId": .int(3)])
                : .object(["requestId": .string("other"), "state": .string("APPLIED"),
                           "action": .string("SKU_SAVE"), "targetType": .string("pms_sku"),
                           "targetId": .int(1)])
        })
        XCTAssertEqual(recovered, .object(["requestId": .string("desk-req-01"), "state": .string("APPLIED"),
                                           "action": .string("SKU_SAVE"), "targetType": .string("pms_sku"),
                                           "targetId": .int(44), "storeId": .int(3)]))
        XCTAssertNil(supply.skuSaveRestartPayload(originalRequestID: "desk-req-01"))
        let owner = try MerchantBusinessAccess(MerchantBusinessObject([
            "active": .bool(true),
            "merchant": .object(["id": .int(9), "name": .string("synthetic-shop")]),
            "roleCode": .string("MERCHANT_OWNER"),
            "permissions": .array([.string("merchant:sku:save")])
        ]))
        let staff = try MerchantBusinessAccess(MerchantBusinessObject([
            "active": .bool(true),
            "merchant": .object(["id": .int(9)]),
            "roleCode": .string("MERCHANT_CHECKIN"),
            "permissions": .array([])
        ]))
        let journey = MerchantSkuSaveJourney()
        XCTAssertNil(journey.freeze(access: staff, accountID: 7, productID: 3, skuID: 44,
                                    requestID: "desk-req-01", skuName: "door", price: "1", stock: 2))
        let frozen = try XCTUnwrap(journey.freeze(access: owner, accountID: 7, productID: 3, skuID: 44,
                                                  requestID: "desk-req-01", skuName: "door", price: "1", stock: 2))
        let detail = try XCTUnwrap(journey.detailRequest(productID: 3))
        XCTAssertEqual(detail.path, "api/merchant/desk/products/detail")
        let save = try XCTUnwrap(journey.saveRequest(frozen, currentFormPrice: "99"))
        XCTAssertEqual(save.path, "api/merchant/desk/products/sku/save")
        guard case .json(let body) = save.body else { return XCTFail("json") }
        XCTAssertEqual(body["requestId"], .string("desk-req-01"))
        XCTAssertEqual(body["productId"], .int(3))
        XCTAssertEqual(body["skuId"], .int(44))
        XCTAssertEqual(body["skuName"], .string("door"))
        XCTAssertEqual(body["price"], .string("1"))
        XCTAssertEqual(body["stock"], .int(2))
        XCTAssertNil(body["ownerMemberId"])
        XCTAssertNil(body["action"])
        XCTAssertTrue(journey.detailMatches(44, intent: frozen))
        XCTAssertEqual(journey.accessRequest().path, "api/merchant/access/me")
        let receiptRequest = try XCTUnwrap(journey.receiptRequest(requestID: "desk-req-01"))
        XCTAssertEqual(receiptRequest.path, "api/merchant/desk/receipt")
        guard case .json(let receiptBody) = receiptRequest.body else { return XCTFail("receipt json") }
        XCTAssertEqual(receiptBody["requestId"], .string("desk-req-01"))
        let detailValue = MerchantBusinessValue.object([
            "productId": .int(3),
            "skus": .array([.object([
                "skuId": .int(44), "skuName": .string("door"), "price": .string("1"), "stock": .int(2)
            ])])
        ])
        let row = try XCTUnwrap(journey.readBack(detail: detailValue, intent: frozen, laterFormPrice: "99"))
        XCTAssertEqual(row.price, "1")
        XCTAssertEqual(row.skuName, "door")
        let rebuilt = MerchantBusinessValue.object([
            "productId": .int(3),
            "skus": .array([.object([
                "skuId": .int(44), "skuName": .string("door"), "price": .string("99"), "stock": .int(2)
            ])])
        ])
        XCTAssertNil(journey.readBack(detail: rebuilt, intent: frozen, laterFormPrice: "99"))
        let priced = try XCTUnwrap(journey.freeze(access: owner, accountID: 7, productID: 3, skuID: 44,
                                                  requestID: "desk-req-01", skuName: "door", price: "88.00", stock: 2))
        let numericEightyEight = MerchantBusinessValue.object([
            "productId": .int(3),
            "skus": .array([.object([
                "skuId": .int(44), "skuName": .string("door"), "price": .int(88), "stock": .int(2)
            ])])
        ])
        let sameAmount = try XCTUnwrap(journey.readBack(detail: numericEightyEight, intent: priced, laterFormPrice: "99.00"))
        XCTAssertEqual(sameAmount.price, "88.00")
        let pricedSave = try XCTUnwrap(journey.saveRequest(priced, currentFormPrice: "99.00"))
        guard case .json(let pricedBody) = pricedSave.body else { return XCTFail("priced json") }
        XCTAssertEqual(pricedBody["price"], .string("88.00"))
        let cents = Decimal(string: "88.01", locale: Locale(identifier: "en_US_POSIX"))!
        let offByCent = MerchantBusinessValue.object([
            "productId": .int(3),
            "skus": .array([.object([
                "skuId": .int(44), "skuName": .string("door"), "price": .number(cents), "stock": .int(2)
            ])])
        ])
        XCTAssertNil(journey.readBack(detail: offByCent, intent: priced, laterFormPrice: "88.00"))
        XCTAssertNil(journey.freeze(access: owner, accountID: 7, productID: 3, skuID: 44,
                                    requestID: "desk-req-01", skuName: "door", price: "88.00\u{2028}", stock: 2))
        let trimmedNewline = try XCTUnwrap(journey.freeze(access: owner, accountID: 7, productID: 3, skuID: 44,
                                                          requestID: "desk-req-01", skuName: "door", price: "88.00\n", stock: 2))
        XCTAssertEqual(trimmedNewline.price, "88.00")
        let ruled = try XCTUnwrap(journey.freeze(access: owner, accountID: 7, productID: 3, skuID: 44,
                                                 requestID: "desk-req-01", skuName: "door", price: "88.00", stock: 2,
                                                 originalPrice: "100.00", bookable: true, slotMinutes: 30,
                                                 capacityPerSlot: 2, ruleVersion: 3))
        let ruledSave = try XCTUnwrap(journey.saveRequest(ruled, currentFormPrice: "99.00"))
        guard case .json(let ruledBody) = ruledSave.body else { return XCTFail("ruled json") }
        XCTAssertEqual(ruledBody["price"], .string("88.00"))
        XCTAssertEqual(ruledBody["originalPrice"], .string("100.00"))
        XCTAssertEqual(ruledBody["bookable"], .bool(true))
        XCTAssertEqual(ruledBody["slotMinutes"], .int(30))
        XCTAssertEqual(ruledBody["capacityPerSlot"], .int(2))
        XCTAssertEqual(ruledBody["ruleVersion"], .int(3))
        let ruledDetail = MerchantBusinessValue.object([
            "productId": .int(3),
            "skus": .array([.object([
                "skuId": .int(44), "skuName": .string("door"), "price": .int(88), "stock": .int(2),
                "originalPrice": .string("100.00"), "bookable": .bool(true),
                "slotMinutes": .int(30), "capacityPerSlot": .int(2), "ruleVersion": .int(3)
            ])])
        ])
        XCTAssertEqual(journey.readBack(detail: ruledDetail, intent: ruled, laterFormPrice: "99.00")?.price, "88.00")
        let otherVersion = MerchantBusinessValue.object([
            "productId": .int(3),
            "skus": .array([.object([
                "skuId": .int(44), "skuName": .string("door"), "price": .int(88), "stock": .int(2),
                "ruleVersion": .int(9)
            ])])
        ])
        XCTAssertNil(journey.readBack(detail: otherVersion, intent: ruled, laterFormPrice: "88.00"))
        let restarted = journey.recover(requestID: "desk-req-01", skuID: 44, currentForm: "price=99")
        XCTAssertEqual(restarted.outcome, "UNKNOWN")
        XCTAssertEqual(restarted.requestID, "desk-req-01")
        XCTAssertNil(restarted.payload)
        let missingReceipt = journey.recover(requestID: "desk-req-01", receipt: .object([
            "requestId": .string("desk-req-01"), "state": .string("NOT_FOUND")
        ]), currentForm: "price=99")
        XCTAssertEqual(missingReceipt.outcome, "UNKNOWN")
        XCTAssertNil(missingReceipt.payload)
        let applied = journey.recover(requestID: "desk-req-01", receipt: .object([
            "requestId": .string("desk-req-01"), "state": .string("APPLIED"),
            "action": .string("SKU_SAVE"), "targetType": .string("pms_sku"), "targetId": .int(44)
        ]), currentForm: "price=99")
        XCTAssertEqual(applied.outcome, "APPLIED")
        XCTAssertEqual(applied.skuID, 44)
        XCTAssertNil(applied.payload)
        XCTAssertFalse(String(describing: applied).contains("99"))
        let storeUsedAsAccount = try await supply.recoverFromDeskReceipt(
            ownerMemberID: 7, requestID: "desk-req-01", storeID: 7, receipt: { _, _ in .string("APPLIED") })
        XCTAssertNil(storeUsedAsAccount)
        do {
            _ = try await supply.recoverFromDeskReceipt(ownerMemberID: 7, requestID: "desk-req-01",
                                                        expectedSkuID: 44, receipt: { _, id in
                .object(["requestId": .string(id), "state": .string("APPLIED"),
                         "action": .string("SAVE_SKU"), "targetType": .string("pms_sku"),
                         "targetId": .int(44)])
            })
            XCTFail("SAVE_SKU is not the original writer")
        } catch let wrongAction as MerchantSupplyDryRunProjection.WireFailure {
            XCTAssertEqual(wrongAction, .notThisRequest)
        }
        do {
            _ = try await supply.recoverFromDeskReceipt(ownerMemberID: 7, requestID: "desk-req-01",
                                                        receipt: { _, id in
                .object(["requestId": .string(id), "state": .string("APPLIED"),
                         "action": .string("SKU_SAVE"), "targetType": .string("pms_sku"),
                         "targetId": .int(44), "ownerMemberId": .int(8)])
            })
            XCTFail("another owner is not this desk receipt")
        } catch let wrongOwner as MerchantSupplyDryRunProjection.WireFailure {
            XCTAssertEqual(wrongOwner, .notThisRequest)
        }
        XCTAssertEqual(supply.holdCount(originalRequestID: "desk-req-01"), 0)
        XCTAssertEqual(supply.recoverOriginal(originalRequestID: "desk-req-01").outcome, .unknown)
    }
}
