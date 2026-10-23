import XCTest
@testable import QuestifyCore

final class EntitlementHoldProjectionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_766_793_600)
    private let end = Date(timeIntervalSince1970: 1_793_491_200)
    func testSoldUnredeemedOccupiesCapacityWithoutCallingReserveOrRedeem() {
        var projection = EntitlementHoldProjection()
        let fact = EntitlementHoldFact(originalRequestID: "c07-hold-1", registrationID: 78,
                                       chapterID: 124, merchantID: 9, status: EntitlementHoldStatus.held,
                                       validEndExclusive: end, invalidReason: nil)
        let view = projection.project(fact, serverNow: now)
        XCTAssertEqual(view.outcome, .held)
        XCTAssertTrue(view.occupiesCapacity)
        XCTAssertFalse(view.executedReserve)
        XCTAssertFalse(view.executedRedeem)
        XCTAssertFalse(view.executedAward)
        XCTAssertFalse(view.holdingIsIssuance)
        XCTAssertEqual(view.originalRequestID, "c07-hold-1")
        XCTAssertEqual(projection.requery(fact, serverNow: now).outcome, view.outcome)
        XCTAssertEqual(projection.occupyCount(originalRequestID: "c07-hold-1"), 1)
        _ = projection.project(fact, serverNow: now)
        XCTAssertEqual(projection.occupyCount(originalRequestID: "c07-hold-1"), 1)
        XCTAssertEqual(projection.recoverOriginal(originalRequestID: "c07-hold-1").outcome, .held)
    }
    func testMissingStatusIsUnknownNotANewRequest() throws {
        var projection = EntitlementHoldProjection()
        let fact = EntitlementHoldFact(originalRequestID: "c07-hold-2", registrationID: 78,
                                       chapterID: 124, merchantID: 9, status: nil,
                                       validEndExclusive: end, invalidReason: "")
        let view = projection.project(fact, serverNow: now)
        XCTAssertEqual(view.outcome, .unknown)
        XCTAssertEqual(view.originalRequestID, "c07-hold-2")
        XCTAssertFalse(view.occupiesCapacity)
        XCTAssertFalse(view.holdingIsIssuance)
        let data = try JSONSerialization.data(withJSONObject: view.jsonObject(), options: [])
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(object["originalRequestID"] as? String, "c07-hold-2")
        XCTAssertEqual(object["outcome"] as? String, "UNKNOWN")
    }
    func testRefundInvalidReasonDoesNotOccupyCapacity() {
        var projection = EntitlementHoldProjection()
        let fact = EntitlementHoldFact(originalRequestID: "c07-hold-3", registrationID: 78,
                                       chapterID: 124, merchantID: 9, status: EntitlementHoldStatus.held,
                                       validEndExclusive: end,
                                       invalidReason: EntitlementHoldInvalidReason.refund)
        let view = projection.project(fact, serverNow: now)
        XCTAssertEqual(view.outcome, .invalid)
        XCTAssertFalse(view.occupiesCapacity)
        XCTAssertFalse(view.executedRedeem)
    }
    func testBlankOriginalRequestIDIsJSONNull() throws {
        var projection = EntitlementHoldProjection()
        let view = projection.project(
            EntitlementHoldFact(originalRequestID: nil, registrationID: 78, chapterID: 124,
                                merchantID: 9, status: EntitlementHoldStatus.held,
                                validEndExclusive: end, invalidReason: nil),
            serverNow: now)
        XCTAssertNil(view.originalRequestID)
        XCTAssertEqual(view.outcome, .unknown)
        let object = try JSONSerialization.jsonObject(
            with: try JSONSerialization.data(withJSONObject: view.jsonObject())) as! [String: Any]
        XCTAssertTrue(object["originalRequestID"] is NSNull)
    }
    func testOtherRequestDoesNotRewriteOriginalHold() {
        var projection = EntitlementHoldProjection()
        let original = EntitlementHoldFact(originalRequestID: "c07-hold-1", registrationID: 78,
                                           chapterID: 124, merchantID: 9, status: EntitlementHoldStatus.held,
                                           validEndExclusive: end, invalidReason: nil)
        XCTAssertEqual(projection.project(original, serverNow: now).outcome, .held)
        let steal = EntitlementHoldFact(originalRequestID: "c07-hold-1", registrationID: 99,
                                        chapterID: 1, merchantID: 2, status: EntitlementHoldStatus.redeemed,
                                        validEndExclusive: end, invalidReason: nil)
        XCTAssertEqual(projection.project(steal, serverNow: now).outcome, .held)
        XCTAssertEqual(projection.occupyCount(originalRequestID: "c07-hold-1"), 1)
        let other = EntitlementHoldFact(originalRequestID: "c07-hold-other", registrationID: 80,
                                        chapterID: 125, merchantID: 10, status: EntitlementHoldStatus.held,
                                        validEndExclusive: end, invalidReason: nil)
        XCTAssertEqual(projection.project(other, serverNow: now).originalRequestID, "c07-hold-other")
        XCTAssertEqual(projection.recoverOriginal(originalRequestID: "c07-hold-1").outcome, .held)
        XCTAssertEqual(projection.recoverOriginal(originalRequestID: "c07-hold-1").originalRequestID, "c07-hold-1")
        XCTAssertNotEqual(projection.recoverOriginal(originalRequestID: "c07-hold-other").originalRequestID,
                          "c07-hold-1")
    }
}
