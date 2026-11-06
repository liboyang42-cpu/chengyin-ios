import XCTest
@testable import QuestifyCore

final class SideQuestAcceptHoldTests: XCTestCase {
    private final class MemoryPlaceCapacity: SideQuestPlaceCapacitySourcing {
        func reserve(originalRequestID: String, placeID: Int, seats: Int) -> Bool { true }
        func release(originalRequestID: String) {}
    }
    private func place(compliant: Bool = true, hidden: Bool = false, capacity: Int = 3) throws -> SideQuestPlace {
        try XCTUnwrap(SideQuestPlace(placeID: 44, questID: 90, compliant: compliant,
                                     capacity: capacity, hiddenCoordinateShipped: hidden))
    }
    private func heldQuest() -> SideQuestAcceptHold {
        SideQuestAcceptHold(capacitySource: MemoryPlaceCapacity())
    }
    func testFirstJourneyDiscoverHoldProofCompleteRecoverOriginal() throws {
        var quest = heldQuest()
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
        var quest = heldQuest()
        try quest.discover(try place())
        try quest.acceptHold(holdID: "hold-2", originalRequestID: "req-2")
        let photo = try XCTUnwrap(SideQuestProof(kind: .photo, attested: true))
        try quest.submitProof(photo)
        try quest.failQuest()
        XCTAssertEqual(quest.phase, .failed)
        XCTAssertEqual(try quest.recoverOriginal(originalRequestID: "req-2").terminal, .failed)
        quest = heldQuest()
        try quest.discover(try place())
        try quest.acceptHold(holdID: "hold-3", originalRequestID: "req-3")
        try quest.exit()
        XCTAssertEqual(quest.phase, .exited)
        XCTAssertEqual(try quest.recoverOriginal(originalRequestID: "req-3").terminal, .exited)
        XCTAssertNil(SideQuestProof(kind: .gps, attested: false, simulated: true))
        XCTAssertNil(SideQuestProof(kind: .gps, attested: true, fogTileKey: "u1x0"))
        XCTAssertNil(SideQuestProof(kind: .approvedAlternative, attested: false))
        let alternative = try XCTUnwrap(SideQuestProof(kind: .approvedAlternative, attested: true,
                                                       approvalAuthority: "authorizer-1"))
        XCTAssertEqual(alternative.kind, .approvedAlternative)
        XCTAssertTrue(alternative.attested)
    }
    func testOtherRequestIdDoesNotRewriteOriginalHold() throws {
        var quest = heldQuest()
        try quest.discover(try place())
        try quest.acceptHold(holdID: "hold-1", originalRequestID: "req-9", seats: 1)
        try quest.acceptHold(holdID: "hold-1", originalRequestID: "req-9", seats: 1)
        XCTAssertEqual(quest.hold?.originalRequestID, "req-9")
        XCTAssertThrowsError(try quest.acceptHold(holdID: "hold-other", originalRequestID: "req-other")) { error in
            XCTAssertEqual(error as? SideQuestFailure, .staleHold)
        }
        XCTAssertEqual(quest.hold?.originalRequestID, "req-9")
        XCTAssertEqual(quest.hold?.holdID, "hold-1")
        let proof = try XCTUnwrap(SideQuestProof(kind: .qr, attested: true))
        try quest.submitProof(proof)
        try quest.complete()
        XCTAssertEqual(try quest.recoverOriginal(originalRequestID: "req-9").originalRequestID, "req-9")
        XCTAssertThrowsError(try quest.discover(try place())) { error in
            XCTAssertEqual(error as? SideQuestFailure, .alreadyTerminal)
        }
        XCTAssertEqual(quest.original?.originalRequestID, "req-9")
    }
    func testMissingRequestIdStaysNilNeverEmptyString() throws {
        var quest = heldQuest()
        try quest.discover(try place())
        XCTAssertNil(quest.hold)
        XCTAssertThrowsError(try quest.acceptHold(holdID: "hold-1", originalRequestID: nil)) { error in
            XCTAssertEqual(error as? SideQuestFailure, .capacityUnavailable)
        }
        XCTAssertNil(quest.hold)
        XCTAssertThrowsError(try quest.acceptHold(holdID: "hold-1", originalRequestID: "")) { error in
            XCTAssertEqual(error as? SideQuestFailure, .capacityUnavailable)
        }
        XCTAssertNil(quest.hold)
        XCTAssertNil(quest.original)
        XCTAssertNotEqual(quest.hold?.originalRequestID, "")
        let restarted = SideQuestAcceptHold()
        XCTAssertNil(restarted.original)
        XCTAssertEqual(restarted.phase, .idle)
    }
    func testRecoverOriginalOfNeverSeenIdDoesNotOccupyLedgerThenUniqueHoldApplies() throws {
        var quest = heldQuest()
        XCTAssertThrowsError(try quest.recoverOriginal(originalRequestID: "sq-orig-unk")) { error in
            XCTAssertEqual(error as? SideQuestFailure, .originalRecordUnknown)
        }
        XCTAssertNil(quest.original)
        XCTAssertNil(quest.hold)
        XCTAssertEqual(quest.phase, .idle)
        try quest.discover(try place())
        XCTAssertThrowsError(try quest.recoverOriginal(originalRequestID: "sq-orig-unk")) { error in
            XCTAssertEqual(error as? SideQuestFailure, .originalRecordUnknown)
        }
        XCTAssertNil(quest.original)
        XCTAssertNil(quest.hold)
        XCTAssertEqual(quest.phase, .discovered)
        try quest.acceptHold(holdID: "hold-unk", originalRequestID: "sq-orig-unk", seats: 1)
        XCTAssertEqual(quest.hold?.originalRequestID, "sq-orig-unk")
        try quest.submitProof(try XCTUnwrap(SideQuestProof(kind: .qr, attested: true)))
        try quest.complete()
        let recovered = try quest.recoverOriginal(originalRequestID: "sq-orig-unk")
        XCTAssertEqual(recovered.originalRequestID, "sq-orig-unk")
        XCTAssertEqual(recovered.terminal, .completed)
        XCTAssertThrowsError(try quest.discover(try place())) { error in
            XCTAssertEqual(error as? SideQuestFailure, .alreadyTerminal)
        }
        XCTAssertEqual(quest.original?.originalRequestID, "sq-orig-unk")
    }
    func testUnusedAcceptHoldBeforeDiscoverDoesNotOccupyThenUniqueHoldApplies() throws {
        var quest = heldQuest()
        XCTAssertThrowsError(try quest.acceptHold(holdID: "hold-idle", originalRequestID: "sq-idle-unk", seats: 1)) { error in
            XCTAssertEqual(error as? SideQuestFailure, .notCompliant)
        }
        XCTAssertNil(quest.hold, "未发现地点的 hold 观察不得占账")
        XCTAssertNil(quest.original)
        XCTAssertEqual(quest.phase, .idle)
        try quest.discover(try place())
        XCTAssertEqual(quest.phase, .discovered)
        XCTAssertNil(quest.hold)
        try quest.acceptHold(holdID: "hold-idle", originalRequestID: "sq-idle-unk", seats: 1)
        XCTAssertEqual(quest.hold?.originalRequestID, "sq-idle-unk")
        XCTAssertEqual(quest.phase, .holdAccepted)
        XCTAssertNil(quest.original)
    }
    func testUnusedCompleteBeforeHoldDoesNotOccupyThenUniqueCompleteApplies() throws {
        var quest = heldQuest()
        try quest.discover(try place())
        XCTAssertThrowsError(try quest.complete()) { error in
            XCTAssertEqual(error as? SideQuestFailure, .holdRequired)
        }
        XCTAssertNil(quest.original, "未预占完赛观察不得占原文")
        XCTAssertNil(quest.hold)
        XCTAssertEqual(quest.phase, .discovered)
        try quest.acceptHold(holdID: "hold-comp", originalRequestID: "sq-comp-unk", seats: 1)
        try quest.submitProof(try XCTUnwrap(SideQuestProof(kind: .qr, attested: true)))
        try quest.complete()
        XCTAssertEqual(quest.phase, .completed)
        XCTAssertEqual(quest.original?.originalRequestID, "sq-comp-unk")
        XCTAssertEqual(quest.original?.terminal, .completed)
        XCTAssertEqual(try quest.recoverOriginal(originalRequestID: "sq-comp-unk").originalRequestID, "sq-comp-unk")
    }
    func testUnusedSubmitProofBeforeHoldDoesNotOccupyThenUniqueSubmitApplies() throws {
        var quest = heldQuest()
        try quest.discover(try place())
        XCTAssertThrowsError(try quest.submitProof(try XCTUnwrap(SideQuestProof(kind: .qr, attested: true)))) { error in
            XCTAssertEqual(error as? SideQuestFailure, .holdRequired)
        }
        XCTAssertEqual(quest.phase, .discovered, "未见预占 submitProof 观察不得占 proof")
        XCTAssertNil(quest.proof)
        XCTAssertNil(quest.hold)
        XCTAssertNil(quest.original)
        try quest.acceptHold(holdID: "hold-proof", originalRequestID: "sq-proof-unk", seats: 1)
        XCTAssertEqual(quest.phase, .holdAccepted)
        XCTAssertNil(quest.proof)
        try quest.submitProof(try XCTUnwrap(SideQuestProof(kind: .qr, attested: true)))
        XCTAssertEqual(quest.phase, .proofPending)
        XCTAssertEqual(quest.proof?.kind, .qr)
        XCTAssertEqual(quest.hold?.originalRequestID, "sq-proof-unk")
        XCTAssertNil(quest.original)
    }
    func testUnusedExitBeforeHoldDoesNotOccupyThenUniqueExitApplies() throws {
        var quest = heldQuest()
        try quest.discover(try place())
        XCTAssertThrowsError(try quest.exit()) { error in
            XCTAssertEqual(error as? SideQuestFailure, .holdRequired)
        }
        XCTAssertNil(quest.original, "未见预占 exit 观察不得占原文")
        XCTAssertNil(quest.hold)
        XCTAssertEqual(quest.phase, .discovered)
        try quest.acceptHold(holdID: "hold-exit", originalRequestID: "sq-exit-unk", seats: 1)
        try quest.exit()
        XCTAssertEqual(quest.phase, .exited)
        XCTAssertEqual(quest.original?.originalRequestID, "sq-exit-unk")
        XCTAssertEqual(quest.original?.terminal, .exited)
    }
    func testNonCompliantHiddenCapacityAndFakeGPS() throws {
        var quest = heldQuest()
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
