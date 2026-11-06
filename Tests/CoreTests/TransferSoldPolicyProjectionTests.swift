import XCTest
@testable import QuestifyCore

final class TransferSoldPolicyProjectionTests: XCTestCase {
    func testMissingRemoteOriginalIsWaitingSourceAndKeepsRequestID() {
        var gate = TransferSoldPolicyProjection()
        let fact = TransferSoldPolicyFact(originalRequestID: "c07-xfer-1", soldPolicySourceHash: nil,
                                          designatedRecipientMemberID: 88,
                                          irrevocableEffectRecorded: true, smsIdentityVerified: false)
        let decision = gate.evaluate(fact)
        XCTAssertEqual(decision.outcome, .waitingSource)
        XCTAssertEqual(decision.originalRequestID, "c07-xfer-1")
        XCTAssertFalse(decision.grantsTransfer)
        XCTAssertFalse(TransferSoldPolicyProjection.remoteSoldPolicyOriginalPresent)
        XCTAssertTrue(decision.reason?.contains(TransferSoldPolicyProjection.waitingSource) == true)
        XCTAssertEqual(gate.requery(fact).outcome, decision.outcome)
        XCTAssertEqual(gate.recoverOriginal(originalRequestID: "c07-xfer-1").outcome, .waitingSource)
    }
    func testSmsIdentityIsNotSoldPolicyEvenWhenVerified() {
        var gate = TransferSoldPolicyProjection()
        let fact = TransferSoldPolicyFact(originalRequestID: "c07-xfer-2",
                                          soldPolicySourceHash: "not-a-remote-hash",
                                          designatedRecipientMemberID: 88,
                                          irrevocableEffectRecorded: true, smsIdentityVerified: true)
        let decision = gate.evaluate(fact)
        XCTAssertEqual(decision.outcome, .waitingSource)
        XCTAssertFalse(decision.usedSmsIdentityAsPolicy)
        XCTAssertFalse(decision.grantsTransfer)
        XCTAssertTrue(decision.reason?.contains("SMS identity is not transfer-sold policy") == true)
    }
    func testMissingDesignatedRecipientIsWaitingSourceNotSuccess() {
        var gate = TransferSoldPolicyProjection()
        let decision = gate.evaluate(
            TransferSoldPolicyFact(originalRequestID: "c07-xfer-3", soldPolicySourceHash: nil,
                                   designatedRecipientMemberID: nil, irrevocableEffectRecorded: true,
                                   smsIdentityVerified: false))
        XCTAssertEqual(decision.outcome, .waitingSource)
        XCTAssertEqual(decision.originalRequestID, "c07-xfer-3")
        XCTAssertFalse(decision.grantsTransfer)
        XCTAssertNotEqual(decision.outcome, .allow)
    }
    func testBlankPolicyHashAndBlankRequestIDStayUnknownOrWaiting() throws {
        var gate = TransferSoldPolicyProjection()
        let blank = gate.evaluate(
            TransferSoldPolicyFact(originalRequestID: "  ", soldPolicySourceHash: "",
                                   designatedRecipientMemberID: 1, irrevocableEffectRecorded: true,
                                   smsIdentityVerified: false))
        XCTAssertEqual(blank.outcome, .waitingSource)
        XCTAssertNil(blank.originalRequestID)
        let object = try JSONSerialization.jsonObject(
            with: try JSONSerialization.data(withJSONObject: blank.jsonObject())) as! [String: Any]
        XCTAssertTrue(object["originalRequestID"] is NSNull)
        XCTAssertFalse((object["originalRequestID"] as? String) == "")
    }
    func testRecoverOriginalOfNeverSeenIdDoesNotOccupyThenUniqueWaitingSourceApplies() {
        var gate = TransferSoldPolicyProjection()
        let neverTransfer = gate.recoverOriginal(originalRequestID: "c07-xfer-never-seen")
        XCTAssertEqual(neverTransfer.outcome, .waitingSource)
        XCTAssertEqual(neverTransfer.originalRequestID, "c07-xfer-never-seen")
        XCTAssertTrue(neverTransfer.reason?.contains("original intent unknown") == true)
        XCTAssertNil(gate.originalByRequestID["c07-xfer-never-seen"], "未见 recover 不得占账")
        let firstWrite = gate.evaluate(
            TransferSoldPolicyFact(originalRequestID: "c07-xfer-never-seen", soldPolicySourceHash: nil,
                                   designatedRecipientMemberID: 88,
                                   irrevocableEffectRecorded: true, smsIdentityVerified: true))
        XCTAssertEqual(firstWrite.outcome, .waitingSource)
        XCTAssertEqual(firstWrite.originalRequestID, "c07-xfer-never-seen")
        XCTAssertTrue(firstWrite.reason?.contains("sold-policy") == true
                      || firstWrite.reason?.contains(TransferSoldPolicyProjection.waitingSource) == true)
        XCTAssertEqual(gate.recoverOriginal(originalRequestID: "c07-xfer-never-seen").reason, firstWrite.reason)
        XCTAssertEqual(gate.recoverOriginal(originalRequestID: "c07-xfer-never-seen").outcome, .waitingSource)
        XCTAssertEqual(gate.originalByRequestID["c07-xfer-never-seen"]?.reason, firstWrite.reason)
    }
}
