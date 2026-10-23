import XCTest
@testable import QuestifyCore

final class SideQuestAcceptHoldTests: XCTestCase {
    private func place(compliant: Bool = true, hidden: Bool = false, capacity: Int = 3) throws -> SideQuestPlace {
        try XCTUnwrap(SideQuestPlace(placeID: 44, questID: 90, compliant: compliant,
                                     capacity: capacity, hiddenCoordinateShipped: hidden))
    }
    func testFirstJourneyDiscoverHoldProofCompleteRecoverOriginal() throws {
        var quest = SideQuestAcceptHold()
        try quest.discover(try place())
        XCTAssertEqual(quest.phase, .discovered)
        try quest.acceptHold(holdID: "hold-1", originalRequestID: "req-9", seats: 1)
        XCTAssertEqual(quest.phase, .holdAccepted)
        XCTAssertEqual(quest.hold?.originalRequestID, "req-9")
        let proof = try XCTUnwrap(SideQuestProof(kind: .qr, attested: true))
        try quest.submitProof(proof)
        XCTAssertEqual(quest.phase, .proofPending)
        try quest.complete()
        XCTAssertEqual(quest.phase, .completed)
        let recovered = try quest.recoverOriginal(originalRequestID: "req-9")
        XCTAssertEqual(quest.phase, .recovered)
        XCTAssertEqual(recovered.originalRequestID, "req-9")
        XCTAssertEqual(recovered.terminal, .completed)
        XCTAssertEqual(recovered.proofKind, .qr)
        XCTAssertThrowsError(try quest.recoverOriginal(originalRequestID: "req-other")) { error in
            XCTAssertEqual(error as? SideQuestFailure, .staleHold)
        }
    }
    func testFailExitAndApprovedAlternative() throws {
        var quest = SideQuestAcceptHold()
        try quest.discover(try place())
        try quest.acceptHold(holdID: "hold-2", originalRequestID: "req-2")
        let photo = try XCTUnwrap(SideQuestProof(kind: .photo, attested: true))
        try quest.submitProof(photo)
        try quest.failQuest()
        XCTAssertEqual(quest.phase, .failed)
        XCTAssertEqual(try quest.recoverOriginal(originalRequestID: "req-2").terminal, .failed)
        quest = SideQuestAcceptHold()
        try quest.discover(try place())
        try quest.acceptHold(holdID: "hold-3", originalRequestID: "req-3")
        try quest.exit()
        XCTAssertEqual(quest.phase, .exited)
        XCTAssertEqual(try quest.recoverOriginal(originalRequestID: "req-3").terminal, .exited)
        XCTAssertNil(SideQuestProof(kind: .gps, attested: false, simulated: true))
        XCTAssertNil(SideQuestProof(kind: .gps, attested: true, fogTileKey: "u1x0"))
        let alternative = try XCTUnwrap(SideQuestProof(kind: .approvedAlternative, attested: false))
        XCTAssertEqual(alternative.kind, .approvedAlternative)
    }
    func testNonCompliantHiddenCapacityAndFakeGPS() throws {
        var quest = SideQuestAcceptHold()
        XCTAssertThrowsError(try quest.discover(try place(compliant: false))) { error in
            XCTAssertEqual(error as? SideQuestFailure, .notCompliant)
        }
        XCTAssertThrowsError(try quest.discover(try place(hidden: true))) { error in
            XCTAssertEqual(error as? SideQuestFailure, .hiddenCoordinateShipped)
        }
        XCTAssertThrowsError(try quest.discover(try place(capacity: 0))) { error in
            XCTAssertEqual(error as? SideQuestFailure, .capacityUnavailable)
        }
        try quest.discover(try place())
        XCTAssertThrowsError(try quest.submitProof(try XCTUnwrap(SideQuestProof(kind: .ar, attested: true)))) { error in
            XCTAssertEqual(error as? SideQuestFailure, .holdRequired)
        }
        XCTAssertEqual(never { try quest.rejectSimulatedGPS() }, .fakeGPSRejected)
        XCTAssertEqual(never { try quest.rejectFogAsPresence() }, .fogIsNotPresence)
        XCTAssertEqual(never { try quest.commitScoringWriter() },
                       .waitingSource(capability: OfflinePackSourceInventory.t41ScoringWriter))
    }
    private func never(_ body: () throws -> Never) -> SideQuestFailure? {
        do { try body(); return nil } catch let error as SideQuestFailure { return error } catch { return nil }
    }
}
