import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class PartyRosterProjectionTests: XCTestCase {
    private func row(_ status: String = "CONFIRMED", id: Int = 8) -> PlayWireValue {
        .object(["memberId": .int(id), "displayName": .string("Synthetic teammate"), "roleCode": .string("OBSERVER"), "status": .string(status)])
    }
    func testTeamActionsReuseExistingMemberTypeAndServerOrder() {
        let projection = PartyRosterProjection.read(teamActions: .array([row("JOINED", id: 3), row("SUBMITTED", id: 9)]))
        XCTAssertEqual(projection.availability, .ready)
        XCTAssertEqual(projection.members.map(\.id), [3, 9])
        XCTAssertEqual(projection.members.map(\.status), [.joined, .submitted])
        XCTAssertNil(projection.advanced)
    }
    func testMissingPartyAPIIsWaitingSourceNotAnEmptySuccessRoster() {
        XCTAssertEqual(PartyRosterProjection.read(party: .null), .waitingSource)
        XCTAssertEqual(PartyRosterProjection.waitingSource.availability, .waitingSource)
        XCTAssertTrue(PartyRosterProjection.waitingSource.members.isEmpty)
        XCTAssertNotEqual(PartyRosterProjection.waitingSource.availability, .ready)
    }
    func testMalformedAndUnknownStatusesAreUnknownNotAssigned() {
        XCTAssertEqual(PartyRosterProjection.read(teamActions: .array([row("UNKNOWN")])).availability, .unknown)
        XCTAssertEqual(PartyRosterProjection.read(teamActions: .object([:])).availability, .unknown)
        XCTAssertEqual(PartyRosterProjection.read(party: .bool(true)).availability, .unknown)
        XCTAssertEqual(PartyRosterProjection.read(teamActions: .array([])).availability, .ready)
        if case .empty = PartyRosterProjection.read(teamActions: .array([])).team { } else { XCTFail("signed empty roster") }
    }
    func testAdvancedMultiplayerReusesExistingProjection() throws {
        let raw = #"{"sessionId":501,"activityId":41,"topicId":71,"nodeId":701,"ownerType":2,"version":1,"status":"RUNNING","config":{"multiplayer":{"enabled":true,"assignment":"AUTO","requiredTurns":2,"roles":[]}},"multiplayer":{"members":[{"memberId":9001,"name":"Synthetic actor"},{"memberId":9002,"name":"Synthetic teammate"}],"leaderMemberId":9001,"myRole":"starter","roleAssignments":{},"turnIndex":0,"completedUnitIds":[]}}"#
        let state = try PlayAdvancedState(JSONDecoder().decode(PlayWireValue.self, from: Data(raw.utf8)))
        let projection = PartyRosterProjection.read(advanced: state, actorID: 9001)
        XCTAssertEqual(projection.availability, .ready)
        XCTAssertEqual(projection.advanced?.members.map(\.id), [9001, 9002])
        XCTAssertEqual(PartyRosterProjection.read(advanced: try PlayAdvancedState(PlayExperienceSyntheticFixtures.wire(PlayExperienceSyntheticFixtures.advanced)), actorID: 9001).availability, .unknown)
    }
}

final class WorldEquipmentProjectionTests: XCTestCase {
    func testMissingInventoryIsWaitingSource() {
        XCTAssertEqual(WorldEquipmentProjection.read(.object(["rpg": .object(["enabled": .bool(true)])])), .waitingSource)
        XCTAssertTrue(WorldEquipmentProjection.waitingSource.items.isEmpty)
    }
    func testSignedInventoryKeepsServerExpiryAndRejectsClientClockSuccess() {
        let future = Int64(Date().timeIntervalSince1970 * 1000) + 86_400_000
        let projection = WorldEquipmentProjection.read(.object(["inventory": .object([
            "lantern": .object(["quantity": .int(1), "expiresAt": .integer(future)])
        ])]))
        XCTAssertEqual(projection.availability, .ready)
        XCTAssertEqual(projection.items.first?.id, "lantern")
        XCTAssertEqual(projection.items.first?.quantity, 1)
        XCTAssertEqual(projection.items.first?.expiry.availability, .waitingSource)
        XCTAssertFalse(projection.items.first?.expiry.isValid == true)
        XCTAssertEqual(WorldEquipmentProjection.read(.object(["equipped": .array([.string("lantern"), .string("lantern")])])).availability, .unknown)
    }
    func testServerValidityOnEquipmentDoesNotUseDate() {
        let projection = WorldEquipmentProjection.read(.object(["equipment": .array([
            .object(["id": .string("coat"), "count": .int(1), "status": .string("VALID")])
        ])]))
        XCTAssertTrue(projection.items.first?.expiry.isValid == true)
        XCTAssertEqual(projection.items.first?.expiry.expired, false)
    }
}
