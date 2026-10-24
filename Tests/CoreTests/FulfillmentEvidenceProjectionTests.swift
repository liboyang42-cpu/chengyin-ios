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
    func testOtherRequestDoesNotRewriteOriginalJourney() {
        var evidence = FulfillmentEvidenceProjection()
        let originalFacts = FulfillmentJourneyFacts(
            orderIssued: true, holdOccupiesCapacity: true,
            appointment: FulfillmentAppointmentFact(slotID: "slot-a", newSlotID: "slot-b", slotKnown: true),
            inStore: FulfillmentInStoreEvidenceFact(attestedInStore: true, simulatedGPS: false),
            refundTrial: FulfillmentRefundTrialFact(now: Date(timeIntervalSince1970: 1),
                                                    snapshotDeadline: Date(timeIntervalSince1970: 2), paid: true),
            aftercare: FulfillmentAftercareFact(caseOpen: true, merchantResponded: false))
        let first = evidence.recordJourney(originalRequestID: "c07-ev-1", facts: originalFacts)
        let otherFacts = FulfillmentJourneyFacts(
            orderIssued: false, holdOccupiesCapacity: false,
            appointment: FulfillmentAppointmentFact(slotID: "slot-z", newSlotID: nil, slotKnown: false),
            inStore: FulfillmentInStoreEvidenceFact(attestedInStore: false, simulatedGPS: true),
            refundTrial: nil, aftercare: FulfillmentAftercareFact(caseOpen: false, merchantResponded: false))
        let steal = evidence.recordJourney(originalRequestID: "c07-ev-1", facts: otherFacts)
        XCTAssertEqual(steal.map(\.outcome), first.map(\.outcome))
        XCTAssertEqual(steal.first?.originalRequestID, "c07-ev-1")
        let independent = evidence.recordJourney(originalRequestID: "c07-ev-other", facts: otherFacts)
        XCTAssertEqual(independent.first?.originalRequestID, "c07-ev-other")
        XCTAssertNotEqual(independent.first?.originalRequestID, first.first?.originalRequestID)
        let recovered = evidence.recoverOriginal(originalRequestID: "c07-ev-1")
        XCTAssertEqual(recovered.count, 7)
        XCTAssertTrue(recovered.allSatisfy { $0.originalRequestID == "c07-ev-1" })
        XCTAssertEqual(recovered.first { $0.stage == .reschedule }?.detail, first.first { $0.stage == .reschedule }?.detail)
    }
    func testInProcessRecoverKeepsOriginalJourneyAndMissingStaysNil() {
        var evidence = FulfillmentEvidenceProjection()
        let facts = FulfillmentJourneyFacts(
            orderIssued: true, holdOccupiesCapacity: true,
            appointment: FulfillmentAppointmentFact(slotID: "slot-a", newSlotID: nil, slotKnown: true),
            inStore: FulfillmentInStoreEvidenceFact(attestedInStore: true, simulatedGPS: false),
            refundTrial: nil, aftercare: FulfillmentAftercareFact(caseOpen: false, merchantResponded: false))
        _ = evidence.recordJourney(originalRequestID: "c07-ev-1", facts: facts)
        let recovered = evidence
        XCTAssertEqual(recovered.recoverOriginal(originalRequestID: "c07-ev-1").first?.originalRequestID, "c07-ev-1")
        XCTAssertEqual(recovered.recoverOriginal(originalRequestID: "c07-ev-missing").first?.outcome, .unknown)
        let blank = evidence.recordJourney(originalRequestID: nil, facts: facts)
        XCTAssertNil(blank.first?.originalRequestID)
        XCTAssertNil(FulfillmentEvidenceProjection.parse(""))
        XCTAssertNil(FulfillmentEvidenceProjection.parse("  "))
    }
    func testRecoverOfNeverSeenIdDoesNotOccupyLedgerThenRecordedApplies() {
        var evidence = FulfillmentEvidenceProjection()
        XCTAssertEqual(evidence.recoverOriginal(originalRequestID: "c07-ev-never-seen").first?.outcome, .unknown)
        let missing = FulfillmentJourneyFacts(
            orderIssued: false, holdOccupiesCapacity: false,
            appointment: nil, inStore: nil, refundTrial: nil,
            aftercare: FulfillmentAftercareFact(caseOpen: false, merchantResponded: false))
        XCTAssertEqual(evidence.recordJourney(originalRequestID: "c07-ev-never-seen", facts: missing)
                        .first { $0.stage == .orderIssue }?.outcome, .unknown)
        XCTAssertEqual(evidence.recoverOriginal(originalRequestID: "c07-ev-never-seen").first?.outcome, .unknown)
        XCTAssertEqual(evidence.recoverOriginal(originalRequestID: "c07-ev-never-seen").count, 1)
        let complete = FulfillmentJourneyFacts(
            orderIssued: true, holdOccupiesCapacity: true,
            appointment: FulfillmentAppointmentFact(slotID: "slot-a", newSlotID: "slot-b", slotKnown: true),
            inStore: FulfillmentInStoreEvidenceFact(attestedInStore: true, simulatedGPS: false),
            refundTrial: FulfillmentRefundTrialFact(now: Date(timeIntervalSince1970: 1),
                                                    snapshotDeadline: Date(timeIntervalSince1970: 2), paid: true),
            aftercare: FulfillmentAftercareFact(caseOpen: true, merchantResponded: false))
        XCTAssertEqual(evidence.recordJourney(originalRequestID: "c07-ev-never-seen", facts: complete)
                        .first { $0.stage == .orderIssue }?.outcome, .recorded)
        XCTAssertEqual(evidence.recoverOriginal(originalRequestID: "c07-ev-never-seen").count, 7)
        XCTAssertEqual(evidence.recoverOriginal(originalRequestID: "c07-ev-never-seen")
                        .first { $0.stage == .reschedule }?.outcome, .recorded)
    }
}
