import XCTest
@testable import QuestifyCore

final class PresenceProofDistinctFromFogTests: XCTestCase {
    func testFogTilesAreExplorationMemoryNotPresence() throws {
        XCTAssertTrue(PresenceProofDistinctFromFog.isExplorationMemory("u1x0"))
        XCTAssertFalse(PresenceProofDistinctFromFog.isExplorationMemory(""))
        XCTAssertFalse(PresenceProofDistinctFromFog.roamPresenceCapabilityEnabled())
        XCTAssertEqual(RoamExperienceCapabilities.presence, false)
        let memory = try XCTUnwrap(FogExplorationMemory(tiles: ["u1x0", "u1x1"]))
        XCTAssertThrowsError(try PresenceProofDistinctFromFog.certifyPresence(memory: memory, proof: nil)) { error in
            XCTAssertEqual(error as? PresenceProofFailure, .fogIsNotPresence)
        }
        let qr = try XCTUnwrap(SideQuestProof(kind: .qr, attested: true))
        XCTAssertNoThrow(try PresenceProofDistinctFromFog.certifyPresence(memory: memory, proof: qr))
        XCTAssertEqual(fog { try PresenceProofDistinctFromFog.certifyPresenceFromFogTiles(["u1x0"]) },
                       .fogIsNotPresence)
        XCTAssertEqual(fog { try PresenceProofDistinctFromFog.rejectSimulatedGPS() }, .fakeGPSRejected)
        XCTAssertEqual(fog { try PresenceProofDistinctFromFog.proofRequiredWithoutFog() }, .proofRequired)
        XCTAssertNil(FogExplorationMemory(tiles: ["not a tile"]))
    }
    private func fog(_ body: () throws -> Never) -> PresenceProofFailure? {
        do { try body(); return nil } catch let error as PresenceProofFailure { return error } catch { return nil }
    }
}
