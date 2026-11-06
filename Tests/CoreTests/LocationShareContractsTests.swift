import XCTest
@testable import QuestifyCore

final class LocationShareContractsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000)
    private func grant(_ id: String = "g1", precision: LocationSharePrecision = .exact, expires: TimeInterval = 600,
                       status: LocationShareGrant.Status = .active, version: Int = 1) -> LocationShareGrant {
        .init(grantID: id, audience: .team(5), precision: precision, startsAt: now, expiresAt: now.addingTimeInterval(expires), status: status, version: version)
    }
    private func pointUpdate(_ id: String = "g1", revision: Int, offset: TimeInterval = 0, accuracy: Double? = 10) throws -> SharedPeerLocation {
        .init(grantID: id, ownerID: 9, revision: revision,
              payload: .point(try .init(latitude: 31.2, longitude: 121.4, datum: .gcj02, source: .backend, accuracyMeters: accuracy)),
              observedAt: now.addingTimeInterval(offset))
    }
    func testPreciseSharingIsDisabledAndDefaultOff() {
        XCTAssertFalse(LocationShareFeature.preciseGrantEnabled)
        XCTAssertEqual(LocationShareOwnerState().phase, .off)
        var draft = LocationShareDraft(); draft.choose(audience: .team(1))
        LocationShareDisclosure.allCases.forEach { draft.acknowledge($0) }
        XCTAssertThrowsError(try draft.request(consentVersion: "v1")) { XCTAssertEqual($0 as? LocationShareFailure, .featureDisabled) }
    }
    func testChangingChoicesResetsTheirAcknowledgement() {
        var draft = LocationShareDraft(); draft.choose(audience: .member(3))
        LocationShareDisclosure.allCases.forEach { draft.acknowledge($0) }
        XCTAssertTrue(draft.missingDisclosures.isEmpty)
        draft.choose(precision: .exact)
        XCTAssertEqual(draft.missingDisclosures, [.precision])
        draft.choose(audience: .team(4)); draft.choose(duration: .oneHour)
        XCTAssertEqual(Set(draft.missingDisclosures), [.precision, .audience, .duration])
        XCTAssertEqual(draft.precision, .exact)
        XCTAssertFalse(LocationShareAudience.member(0).isValid)
    }
    func testStopBeatsLateCreateSuccess() {
        var state = LocationShareOwnerState()
        let request = LocationShareGrantRequest(requestID: UUID(), audience: .team(1), precision: .coarse, purpose: .teamActivity,
                                                duration: .fifteenMinutes, consentVersion: "v1", background: false)
        XCTAssertTrue(state.begin(request))
        XCTAssertFalse(state.begin(request))
        state.stop()
        state.finishCreate(request.requestID, grant: grant())
        XCTAssertFalse(state.isSharing)
        state.finishRevoke()
        XCTAssertEqual(state.phase, .off)
    }
    func testActiveGrantExpiresAndSessionChangeEndsSharing() {
        var state = LocationShareOwnerState()
        let request = LocationShareGrantRequest(requestID: UUID(), audience: .team(1), precision: .coarse, purpose: .teamActivity,
                                                duration: .fifteenMinutes, consentVersion: "v1", background: false)
        _ = state.begin(request); state.finishCreate(request.requestID, grant: grant(expires: 60))
        XCTAssertTrue(state.isSharing)
        state.expireIfNeeded(now: now.addingTimeInterval(61))
        XCTAssertEqual(state.phase, .off)
        _ = state.begin(request); state.endForSessionChange()
        state.finishCreate(request.requestID, grant: grant())
        XCTAssertEqual(state.phase, .off)
    }
    func testMissingCreateResponseIsUnknownNotActive() {
        var state = LocationShareOwnerState()
        let request = LocationShareGrantRequest(requestID: UUID(), audience: .team(1), precision: .coarse, purpose: .teamActivity,
                                                duration: .fifteenMinutes, consentVersion: "v1", background: false)
        _ = state.begin(request); state.finishCreate(request.requestID, grant: nil)
        XCTAssertEqual(state.phase, .unknown)
        state.stop(); XCTAssertEqual(state.phase, .revoking(""))
    }
    func testDistanceBandsAreCoarse() {
        XCTAssertEqual(MapDistanceBand.band(meters: 10), .under500m)
        XCTAssertEqual(MapDistanceBand.band(meters: 999), .under1km)
        XCTAssertEqual(MapDistanceBand.band(meters: 2_999), .under3km)
        XCTAssertEqual(MapDistanceBand.band(meters: 50_000), .beyond3km)
        XCTAssertNil(MapDistanceBand.band(meters: -1)); XCTAssertNil(MapDistanceBand.band(meters: .infinity))
    }
    func testReceiverRejectsUnauthorizedOutOfOrderAndPrecisionEscalation() throws {
        var board = SharedPeerLocationBoard()
        XCTAssertThrowsError(try board.apply(pointUpdate(revision: 1), now: now)) { XCTAssertEqual($0 as? LocationShareFailure, .notAuthorized) }
        board.replaceGrants([grant(), grant("g2", precision: .distanceOnly)], now: now)
        try board.apply(pointUpdate(revision: 2), now: now)
        XCTAssertThrowsError(try board.apply(pointUpdate(revision: 1, offset: 5), now: now)) { XCTAssertEqual($0 as? LocationShareFailure, .outOfOrder) }
        XCTAssertThrowsError(try board.apply(pointUpdate(revision: 3, offset: -5), now: now)) { XCTAssertEqual($0 as? LocationShareFailure, .outOfOrder) }
        XCTAssertThrowsError(try board.apply(pointUpdate("g2", revision: 1), now: now)) { XCTAssertEqual($0 as? LocationShareFailure, .precisionViolation) }
        try board.apply(.init(grantID: "g2", ownerID: 4, revision: 1, payload: .band(.under1km), observedAt: now), now: now)
        XCTAssertThrowsError(try board.apply(pointUpdate(revision: 9, offset: 600), now: now)) { XCTAssertEqual($0 as? LocationShareFailure, .stale) }
    }
    func testRevokeAndGrantLossRemovePointsImmediately() throws {
        var board = SharedPeerLocationBoard()
        board.replaceGrants([grant(), grant("g2")], now: now)
        try board.apply(pointUpdate(revision: 1), now: now)
        try board.apply(pointUpdate("g2", revision: 1), now: now)
        board.revoke(grantID: "g1")
        XCTAssertNil(board.latest["g1"])
        board.replaceGrants([], now: now)
        XCTAssertTrue(board.latest.isEmpty)
        board.replaceGrants([grant("g3", expires: -1), grant("g4", status: .revoked)], now: now)
        XCTAssertTrue(board.grants.isEmpty)
    }
    func testStaleEntryIsNotLive() throws {
        var board = SharedPeerLocationBoard(); board.replaceGrants([grant()], now: now)
        try board.apply(pointUpdate(revision: 1), now: now)
        XCTAssertFalse(board.isStale(grantID: "g1", now: now.addingTimeInterval(10), maxAge: 30))
        XCTAssertTrue(board.isStale(grantID: "g1", now: now.addingTimeInterval(31), maxAge: 30))
        XCTAssertTrue(board.isStale(grantID: "none", now: now, maxAge: 30))
    }
    func testRoamPresenceVisibilityMatchesMiniProgramContract() throws {
        let base = URL(string: "https://example.invalid/")!
        let read = try RoamPresenceVisibilityContract.readRequest(baseURL: base, sessionID: 12)
        XCTAssertEqual(read.httpMethod, "GET")
        XCTAssertEqual(read.url?.absoluteString, "https://example.invalid/api/roam/presence-visibility?sessionId=12")
        XCTAssertThrowsError(try RoamPresenceVisibilityContract.changeRequest(baseURL: base, sessionID: 12, visible: true, consentAccepted: false))
        XCTAssertThrowsError(try RoamPresenceVisibilityContract.changeRequest(baseURL: base, sessionID: nil, visible: true, consentAccepted: true))
        let on = try RoamPresenceVisibilityContract.changeRequest(baseURL: base, sessionID: 12, visible: true, consentAccepted: true)
        XCTAssertEqual(String(data: on.httpBody!, encoding: .utf8), "sessionId=12&visible=true&consentVersion=roam-presence-v1")
        let off = try RoamPresenceVisibilityContract.changeRequest(baseURL: base, sessionID: nil, visible: false, consentAccepted: false)
        XCTAssertEqual(String(data: off.httpBody!, encoding: .utf8), "sessionId=&visible=false&consentVersion=")
    }
    func testRoamPresenceDecodeAndConfirmation() {
        XCTAssertEqual(RoamPresenceVisibilityContract.decode(Data(#"{"code":200,"data":true}"#.utf8)), true)
        XCTAssertEqual(RoamPresenceVisibilityContract.decode(Data(#"{"code":200,"data":false}"#.utf8)), false)
        XCTAssertNil(RoamPresenceVisibilityContract.decode(Data(#"{"code":500,"data":true}"#.utf8)))
        XCTAssertNil(RoamPresenceVisibilityContract.decode(Data(#"{"code":200,"data":1}"#.utf8)))
        XCTAssertNil(RoamPresenceVisibilityContract.decode(Data(#"{"code":true,"data":true}"#.utf8)))
        XCTAssertEqual(RoamPresenceVisibilityContract.confirmedEnabled(changeEcho: true, readback: true), true)
        XCTAssertNil(RoamPresenceVisibilityContract.confirmedEnabled(changeEcho: true, readback: false))
        XCTAssertNil(RoamPresenceVisibilityContract.confirmedEnabled(changeEcho: false, readback: true))
        XCTAssertNil(RoamPresenceVisibilityContract.confirmedEnabled(changeEcho: nil, readback: nil))
    }
}
