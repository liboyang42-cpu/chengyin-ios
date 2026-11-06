import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class LocationShareHostCoordinatorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_100_000)
    private let baseURL = URL(string: "https://roam.example.invalid/")!

    private func makeGrant(
        id: String = "grant-1",
        audience: LocationShareAudience = .team(12),
        precision: LocationSharePrecision = .exact,
        expiresAfter: TimeInterval = 600,
        status: LocationShareGrant.Status = .active,
        version: Int = 1
    ) -> LocationShareGrant {
        LocationShareGrant(
            grantID: id,
            audience: audience,
            precision: precision,
            startsAt: now,
            expiresAt: now.addingTimeInterval(expiresAfter),
            status: status,
            version: version
        )
    }

    private func makePointUpdate(
        grantID: String = "grant-1",
        ownerID: Int = 42,
        revision: Int,
        offset: TimeInterval = 0,
        accuracyMeters: Double? = 8.0
    ) throws -> SharedPeerLocation {
        let observation = try MapCoordinateObservation(
            latitude: 31.2304,
            longitude: 121.4737,
            datum: .gcj02,
            source: .backend,
            accuracyMeters: accuracyMeters,
            observedAt: now.addingTimeInterval(offset)
        )
        return SharedPeerLocation(
            grantID: grantID,
            ownerID: ownerID,
            revision: revision,
            payload: .point(observation),
            observedAt: now.addingTimeInterval(offset)
        )
    }

    func testOSPermissionIsNotSharingAndSixDisclosuresInvalidateOnChoiceChange() {
        let coordinator = LocationShareHostCoordinator(osLocationAuthorized: true)
        XCTAssertTrue(coordinator.osLocationAuthorized)
        XCTAssertEqual(coordinator.ownerState.phase, .off)
        XCTAssertFalse(coordinator.isSharingActive)
        XCTAssertFalse(coordinator.roamPresence.isVisible)
        XCTAssertFalse(coordinator.canStartPreciseSharing)
        XCTAssertEqual(coordinator.missingDisclosures.count, 6)

        coordinator.choose(audience: .team(7))
        coordinator.acknowledgeAllDisclosures()
        XCTAssertTrue(coordinator.missingDisclosures.isEmpty)
        XCTAssertFalse(coordinator.canStartPreciseSharing, "Start remains disabled while preciseGrantEnabled is false")

        coordinator.choose(precision: .exact)
        XCTAssertEqual(coordinator.missingDisclosures, [.precision])
        coordinator.choose(audience: .member(9))
        coordinator.choose(duration: .oneHour)
        XCTAssertEqual(Set(coordinator.missingDisclosures), [.precision, .audience, .duration])

        coordinator.acknowledgeAllDisclosures()
        XCTAssertThrowsError(try coordinator.startPreciseShareRequest(consentVersion: "v1")) { error in
            XCTAssertEqual(error as? LocationShareFailure, .featureDisabled)
        }
        XCTAssertEqual(coordinator.ownerState.phase, .off)
    }

    func testOwnerStateStopBeatsLateCreateAndOSPermissionLossEndsSharing() {
        let coordinator = LocationShareHostCoordinator(osLocationAuthorized: true)
        let requestID = UUID()
        let request = LocationShareGrantRequest(
            requestID: requestID,
            audience: .team(12),
            precision: .coarse,
            purpose: .teamActivity,
            duration: .fifteenMinutes,
            consentVersion: "v1",
            background: false
        )

        XCTAssertTrue(coordinator.beginOwnerRequest(request))
        XCTAssertFalse(coordinator.beginOwnerRequest(request))
        XCTAssertEqual(coordinator.ownerState.phase, .requesting(requestID))

        // U04: Stop before create returns must prevent late create from activating sharing.
        coordinator.stopOwnerSharing()
        XCTAssertEqual(coordinator.ownerState.phase, .revoking(""))
        coordinator.finishOwnerCreate(requestID, grant: makeGrant())
        XCTAssertFalse(coordinator.isSharingActive)
        coordinator.finishOwnerRevoke()
        XCTAssertEqual(coordinator.ownerState.phase, .off)

        // Active grant stops immediately when OS location authorization is lost or grant expires.
        let secondID = UUID()
        let secondRequest = LocationShareGrantRequest(
            requestID: secondID,
            audience: .team(12),
            precision: .coarse,
            purpose: .teamActivity,
            duration: .fifteenMinutes,
            consentVersion: "v1",
            background: false
        )
        XCTAssertTrue(coordinator.beginOwnerRequest(secondRequest))
        coordinator.finishOwnerCreate(secondID, grant: makeGrant(expiresAfter: 30))
        XCTAssertTrue(coordinator.isSharingActive)

        coordinator.updateOSLocationAuthorization(false)
        XCTAssertFalse(coordinator.isSharingActive)
        XCTAssertEqual(coordinator.ownerState.phase, .off)
    }

    func testPeerBoardRejectsUnauthorizedOutOfOrderStaleAndPrecisionEscalatingUpdates() throws {
        let coordinator = LocationShareHostCoordinator()
        XCTAssertThrowsError(try coordinator.applyPeerUpdate(makePointUpdate(revision: 1), now: now)) { error in
            XCTAssertEqual(error as? LocationShareFailure, .notAuthorized)
        }

        coordinator.replacePeerGrants(
            [
                makeGrant(id: "grant-1", precision: .exact),
                makeGrant(id: "grant-band", precision: .distanceOnly)
            ],
            now: now
        )

        try coordinator.applyPeerUpdate(makePointUpdate(grantID: "grant-1", revision: 2, offset: 0), now: now)
        XCTAssertNotNil(coordinator.peerBoard.latest["grant-1"])
        XCTAssertFalse(coordinator.isPeerLocationStale(grantID: "grant-1", now: now.addingTimeInterval(15), maxAge: 30))
        XCTAssertTrue(coordinator.isPeerLocationStale(grantID: "grant-1", now: now.addingTimeInterval(31), maxAge: 30))

        // Out-of-order revision and older timestamp are rejected.
        XCTAssertThrowsError(try coordinator.applyPeerUpdate(makePointUpdate(grantID: "grant-1", revision: 1, offset: 5), now: now)) { error in
            XCTAssertEqual(error as? LocationShareFailure, .outOfOrder)
        }
        XCTAssertThrowsError(try coordinator.applyPeerUpdate(makePointUpdate(grantID: "grant-1", revision: 3, offset: -5), now: now)) { error in
            XCTAssertEqual(error as? LocationShareFailure, .outOfOrder)
        }

        // Precision escalation (.distanceOnly receiving a coordinate point or nil accuracy) is rejected.
        XCTAssertThrowsError(try coordinator.applyPeerUpdate(makePointUpdate(grantID: "grant-band", revision: 1), now: now)) { error in
            XCTAssertEqual(error as? LocationShareFailure, .precisionViolation)
        }
        XCTAssertThrowsError(try coordinator.applyPeerUpdate(makePointUpdate(grantID: "grant-1", revision: 3, offset: 5, accuracyMeters: nil), now: now)) { error in
            XCTAssertEqual(error as? LocationShareFailure, .precisionViolation)
        }

        // Future skew > 60s is rejected as stale.
        XCTAssertThrowsError(try coordinator.applyPeerUpdate(makePointUpdate(grantID: "grant-1", revision: 4, offset: 120), now: now)) { error in
            XCTAssertEqual(error as? LocationShareFailure, .stale)
        }

        // Distance band update succeeds on distanceOnly grant, and revoke removes immediately.
        let bandUpdate = SharedPeerLocation(
            grantID: "grant-band",
            ownerID: 55,
            revision: 1,
            payload: .band(.under1km),
            observedAt: now
        )
        try coordinator.applyPeerUpdate(bandUpdate, now: now)
        XCTAssertEqual(coordinator.peerBoard.latest["grant-band"], bandUpdate)

        coordinator.revokePeerGrant(grantID: "grant-1")
        XCTAssertNil(coordinator.peerBoard.latest["grant-1"])
    }

    func testRoamPresenceApproximateToggleStaysGatedDefaultOffAndRequiresDualReadbackConfirmation() throws {
        let coordinator = LocationShareHostCoordinator()
        XCTAssertEqual(coordinator.roamPresence.phase, .off)
        XCTAssertFalse(coordinator.roamPresence.isVisible)

        // Default allowlist is false: read and enable fail closed with .featureDisabled.
        XCTAssertThrowsError(try coordinator.makeRoamPresenceReadRequest(baseURL: baseURL, sessionID: 18)) { error in
            XCTAssertEqual(error as? LocationShareFailure, .featureDisabled)
        }

        // Without consent, enabling throws .consentIncomplete even before allowlist check.
        XCTAssertThrowsError(try coordinator.beginRoamPresenceEnable(baseURL: baseURL, sessionID: 18, endpointAllowlisted: true)) { error in
            XCTAssertEqual(error as? LocationShareFailure, .consentIncomplete)
        }

        coordinator.setRoamPresenceConsent(true)
        XCTAssertThrowsError(try coordinator.beginRoamPresenceEnable(baseURL: baseURL, sessionID: 18, endpointAllowlisted: false)) { error in
            XCTAssertEqual(error as? LocationShareFailure, .featureDisabled)
        }
        XCTAssertEqual(coordinator.roamPresence.phase, .off)

        // When explicitly allowlisted in test, beginEnable transitions to .pendingEnable and requires both echo + readback == true.
        let enableReq = try coordinator.beginRoamPresenceEnable(baseURL: baseURL, sessionID: 18, endpointAllowlisted: true)
        XCTAssertEqual(enableReq.httpMethod, "POST")
        XCTAssertEqual(coordinator.roamPresence.phase, .pendingEnable(sessionID: 18))
        XCTAssertFalse(coordinator.roamPresence.isVisible)

        let trueBody = Data(#"{"code":200,"data":true}"#.utf8)
        let falseBody = Data(#"{"code":200,"data":false}"#.utf8)

        // Mismatch between change echo and readback -> .unknown, never .confirmedVisible.
        coordinator.finishRoamPresenceEnable(sessionID: 18, changeResponseData: trueBody, readbackResponseData: falseBody)
        XCTAssertEqual(coordinator.roamPresence.phase, .unknown(sessionID: 18))
        XCTAssertFalse(coordinator.roamPresence.isVisible)

        // Retry enable and confirm with dual true responses.
        _ = try coordinator.beginRoamPresenceEnable(baseURL: baseURL, sessionID: 18, endpointAllowlisted: true)
        coordinator.finishRoamPresenceEnable(sessionID: 18, changeResponseData: trueBody, readbackResponseData: trueBody)
        XCTAssertEqual(coordinator.roamPresence.phase, .confirmedVisible(sessionID: 18))
        XCTAssertTrue(coordinator.roamPresence.isVisible)
    }

    func testStopAndSessionChangeClearOwnerPeerBoardAndRoamPresenceImmediately() throws {
        let coordinator = LocationShareHostCoordinator(osLocationAuthorized: true)
        coordinator.showsSharingExplainer = true
        coordinator.choose(audience: .team(5))
        coordinator.acknowledgeAllDisclosures()
        coordinator.replacePeerGrants([makeGrant(id: "grant-1")], now: now)
        try coordinator.applyPeerUpdate(makePointUpdate(grantID: "grant-1", revision: 1), now: now)

        coordinator.setRoamPresenceConsent(true)
        _ = try coordinator.beginRoamPresenceEnable(baseURL: baseURL, sessionID: 25, endpointAllowlisted: true)

        // Stop on roam presence beats late enable readback.
        let disableReq = try coordinator.stopRoamPresence(baseURL: baseURL, endpointAllowlisted: true)
        XCTAssertEqual(disableReq.httpMethod, "POST")
        XCTAssertEqual(coordinator.roamPresence.phase, .off)
        coordinator.finishRoamPresenceEnable(
            sessionID: 25,
            changeResponseData: Data(#"{"code":200,"data":true}"#.utf8),
            readbackResponseData: Data(#"{"code":200,"data":true}"#.utf8)
        )
        XCTAssertEqual(coordinator.roamPresence.phase, .off)

        // Re-enable pending state and verify session change resets all 3 subsystems + draft + explainer.
        _ = try coordinator.beginRoamPresenceEnable(baseURL: baseURL, sessionID: 26, endpointAllowlisted: true)
        let reqID = UUID()
        _ = coordinator.beginOwnerRequest(
            LocationShareGrantRequest(
                requestID: reqID,
                audience: .team(5),
                precision: .coarse,
                purpose: .teamActivity,
                duration: .fifteenMinutes,
                consentVersion: "v1",
                background: false
            )
        )

        coordinator.handleSessionChange()
        coordinator.finishOwnerCreate(reqID, grant: makeGrant(id: "grant-late"))
        coordinator.finishRoamPresenceEnable(
            sessionID: 26,
            changeResponseData: Data(#"{"code":200,"data":true}"#.utf8),
            readbackResponseData: Data(#"{"code":200,"data":true}"#.utf8)
        )

        XCTAssertEqual(coordinator.ownerState.phase, .off)
        XCTAssertEqual(coordinator.roamPresence.phase, .off)
        XCTAssertTrue(coordinator.peerBoard.grants.isEmpty)
        XCTAssertTrue(coordinator.peerBoard.latest.isEmpty)
        XCTAssertEqual(coordinator.missingDisclosures.count, 6)
        XCTAssertFalse(coordinator.showsSharingExplainer)
    }
}
