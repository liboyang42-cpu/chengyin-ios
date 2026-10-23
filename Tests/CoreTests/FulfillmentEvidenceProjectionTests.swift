import XCTest
@testable import QuestifyCore

final class FulfillmentEvidenceProjectionTests: XCTestCase {
    func testRescheduleKeepsOriginalRequestIDAndRedeemDoesNotCallWriter() {
        var evidence = FulfillmentEvidenceProjection()
        let now = Date(timeIntervalSince1970: 1)
        let deadline = Date(timeIntervalSince1970: 2)
        let facts = FulfillmentJourneyFacts(
            orderIssued: true, holdOccupiesCapacity: true,
            appointment: FulfillmentAppointmentFact(slotID: "slot-a", newSlotID: "slot-b", slotKnown: true),
            inStore: FulfillmentInStoreEvidenceFact(attestedInStore: true, simulatedGPS: false),
            refundTrial: FulfillmentRefundTrialFact(now: now, snapshotDeadline: deadline, paid: true),
            aftercare: FulfillmentAftercareFact(caseOpen: true, merchantResponded: false))
        let steps = evidence.recordJourney(originalRequestID: "c07-ev-1", facts: facts)
        XCTAssertEqual(steps.count, 7)
        XCTAssertTrue(steps.allSatisfy { $0.originalRequestID == "c07-ev-1" })
        XCTAssertTrue(steps.allSatisfy { $0.executedWriter == false })
        let reschedule = steps.first { $0.stage == .reschedule }!
        XCTAssertEqual(reschedule.outcome, .recorded)
        XCTAssertTrue(reschedule.detail?.contains("slot-b") == true)
        let redeem = steps.first { $0.stage == .inStoreRedeem }!
        XCTAssertEqual(redeem.outcome, .recorded)
        XCTAssertFalse(redeem.executedWriter)
        let refund = steps.first { $0.stage == .refundEstimate }!
        XCTAssertEqual(refund.outcome, .recorded)
        XCTAssertEqual(refund.detail, "refund trial; no payout")
        XCTAssertEqual(evidence.requery(originalRequestID: "c07-ev-1", facts: facts)
                        .first { $0.stage == .hold }?.outcome,
                       steps.first { $0.stage == .hold }?.outcome)
        XCTAssertEqual(evidence.recoverOriginal(originalRequestID: "c07-ev-1").count, 7)
    }
    func testMissingBookingIsUnknownNotANewRequest() {
        var evidence = FulfillmentEvidenceProjection()
        let facts = FulfillmentJourneyFacts(
            orderIssued: true, holdOccupiesCapacity: true,
            appointment: FulfillmentAppointmentFact(slotID: "", newSlotID: "", slotKnown: false),
            inStore: nil, refundTrial: nil,
            aftercare: FulfillmentAftercareFact(caseOpen: false, merchantResponded: false))
        let steps = evidence.recordJourney(originalRequestID: "c07-ev-2", facts: facts)
        XCTAssertEqual(steps.first { $0.stage == .booking }?.outcome, .unknown)
        XCTAssertEqual(steps.first { $0.stage == .booking }?.originalRequestID, "c07-ev-2")
        XCTAssertEqual(steps.first { $0.stage == .refundEstimate }?.outcome, .unknown)
        XCTAssertEqual(steps.first { $0.stage == .inStoreRedeem }?.outcome, .unknown)
    }
    func testInStoreEvidenceRejectsGPSFake() throws {
        var evidence = FulfillmentEvidenceProjection()
        let facts = FulfillmentJourneyFacts(
            orderIssued: true, holdOccupiesCapacity: true,
            appointment: FulfillmentAppointmentFact(slotID: "slot-a", newSlotID: nil, slotKnown: true),
            inStore: FulfillmentInStoreEvidenceFact(attestedInStore: true, simulatedGPS: true),
            refundTrial: FulfillmentRefundTrialFact(now: Date(), snapshotDeadline: Date(), paid: true),
            aftercare: FulfillmentAftercareFact(caseOpen: true, merchantResponded: true))
        let steps = evidence.recordJourney(originalRequestID: "c07-ev-3", facts: facts)
        let redeem = steps.first { $0.stage == .inStoreRedeem }!
        XCTAssertEqual(redeem.outcome, .unknown)
        XCTAssertTrue(redeem.detail?.contains("GPS fake") == true)
        XCTAssertFalse(redeem.executedWriter)
        XCTAssertEqual(steps.first { $0.stage == .reschedule }?.outcome, .unknown)
        let blank = evidence.recordJourney(originalRequestID: "  ", facts: facts)
        XCTAssertNil(blank.first?.originalRequestID)
        let object = try JSONSerialization.jsonObject(
            with: try JSONSerialization.data(withJSONObject: blank[0].jsonObject())) as! [String: Any]
        XCTAssertTrue(object["originalRequestID"] is NSNull)
    }
}
