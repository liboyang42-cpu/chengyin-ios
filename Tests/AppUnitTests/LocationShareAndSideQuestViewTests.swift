import SwiftUI
import XCTest
#if canImport(Questify)
@testable import Questify
#elseif canImport(QuestifyApp)
@testable import QuestifyApp
#endif
#if canImport(QuestifyCore)
@testable import QuestifyCore
#endif

@MainActor final class LocationShareAndSideQuestViewTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_760_000_000)

    func testLocationShareHostSectionViewDecouplesOSPermissionEnforcesDisclosuresAndSupportsImmediateStop() throws {
        let coordinator = LocationShareHostCoordinator(osLocationAuthorized: false)
        var stopCallbackCount = 0

        let initialView = LocationShareHostSectionView(
            coordinator: coordinator,
            now: now,
            onStopOwnerSharing: { stopCallbackCount += 1 }
        )
        _ = initialView.body

        XCTAssertFalse(coordinator.osLocationAuthorized)
        XCTAssertFalse(coordinator.isSharingActive)
        XCTAssertEqual(coordinator.ownerState.phase, .off)
        XCTAssertEqual(coordinator.roamPresence.phase, .off)

        // W13.5: Granting OS location permission never turns on location sharing or roam presence.
        coordinator.updateOSLocationAuthorization(true)
        XCTAssertTrue(coordinator.osLocationAuthorized)
        XCTAssertFalse(coordinator.isSharingActive)
        XCTAssertEqual(coordinator.ownerState.phase, .off)
        XCTAssertEqual(coordinator.roamPresence.phase, .off)
        _ = initialView.body

        // Six-disclosure gate: all six disclosures are required, and changing precision/duration invalidates matching disclosures.
        XCTAssertEqual(coordinator.missingDisclosures.count, 6)
        coordinator.choose(audience: .team(42))
        coordinator.acknowledgeAllDisclosures()
        XCTAssertTrue(coordinator.missingDisclosures.isEmpty)
        // Precise sharing remains gated off by default while LocationShareFeature.preciseGrantEnabled == false.
        XCTAssertFalse(coordinator.isPreciseSharingFeatureEnabled)
        XCTAssertFalse(coordinator.canStartPreciseSharing)

        coordinator.choose(precision: .coarse)
        XCTAssertEqual(coordinator.missingDisclosures, [.precision])
        coordinator.acknowledge(.precision)
        XCTAssertTrue(coordinator.missingDisclosures.isEmpty)

        // Exercise owner state transitions (.requesting -> .active -> .revoking -> .off) and render the view in each phase.
        let requestID = UUID()
        let syntheticRequest = LocationShareGrantRequest(
            requestID: requestID,
            audience: .team(42),
            precision: .coarse,
            purpose: .teamActivity,
            duration: .fifteenMinutes,
            consentVersion: "v1",
            background: false
        )
        XCTAssertTrue(coordinator.beginOwnerRequest(syntheticRequest))
        XCTAssertEqual(coordinator.ownerState.phase, .requesting(requestID))
        _ = initialView.body

        let grant = LocationShareGrant(
            grantID: "grant-team-42",
            audience: .team(42),
            precision: .coarse,
            startsAt: now,
            expiresAt: now.addingTimeInterval(900),
            status: .active,
            version: 1
        )
        coordinator.finishOwnerCreate(requestID, grant: grant)
        XCTAssertTrue(coordinator.isSharingActive)
        XCTAssertEqual(coordinator.ownerState.phase, .active(grant))
        _ = initialView.body

        coordinator.stopOwnerSharing()
        initialView.onStopOwnerSharing?()
        XCTAssertFalse(coordinator.isSharingActive)
        XCTAssertEqual(coordinator.ownerState.phase, .revoking("grant-team-42"))
        XCTAssertEqual(stopCallbackCount, 1)
        _ = initialView.body

        coordinator.finishOwnerRevoke()
        XCTAssertEqual(coordinator.ownerState.phase, .off)
        _ = initialView.body
    }

    func testLocationShareHostSectionViewRendersPeerBoardAndRoamPresenceStates() throws {
        let coordinator = LocationShareHostCoordinator(osLocationAuthorized: true)
        let bandGrant = LocationShareGrant(
            grantID: "grant-band-1",
            audience: .member(7),
            precision: .distanceOnly,
            startsAt: now,
            expiresAt: now.addingTimeInterval(1_800),
            status: .active,
            version: 1
        )
        let pointGrant = LocationShareGrant(
            grantID: "grant-point-2",
            audience: .team(9),
            precision: .exact,
            startsAt: now,
            expiresAt: now.addingTimeInterval(1_800),
            status: .active,
            version: 1
        )

        coordinator.replacePeerGrants([bandGrant, pointGrant], now: now)
        XCTAssertEqual(coordinator.peerBoard.grants.count, 2)

        try coordinator.applyPeerUpdate(
            SharedPeerLocation(
                grantID: "grant-band-1",
                ownerID: 101,
                revision: 1,
                payload: .band(.under1km),
                observedAt: now.addingTimeInterval(-30)
            ),
            now: now
        )
        let pointObservation = try MapCoordinateObservation(
            latitude: 31.2304,
            longitude: 121.4737,
            datum: .gcj02,
            source: .backend,
            accuracyMeters: 12,
            observedAt: now.addingTimeInterval(-400)
        )
        try coordinator.applyPeerUpdate(
            SharedPeerLocation(
                grantID: "grant-point-2",
                ownerID: 102,
                revision: 2,
                payload: .point(pointObservation),
                observedAt: now.addingTimeInterval(-400)
            ),
            now: now
        )

        XCTAssertFalse(coordinator.isPeerLocationStale(grantID: "grant-band-1", now: now, maxAge: 300))
        XCTAssertTrue(coordinator.isPeerLocationStale(grantID: "grant-point-2", now: now, maxAge: 300))

        coordinator.setRoamPresenceConsent(true)
        XCTAssertTrue(coordinator.roamPresence.consentAccepted)

        let view = LocationShareHostSectionView(coordinator: coordinator, now: now)
        _ = view.body

        coordinator.revokePeerGrant(grantID: "grant-band-1")
        XCTAssertEqual(coordinator.peerBoard.grants.count, 1)
        _ = view.body

        coordinator.handleSessionChange()
        XCTAssertTrue(coordinator.peerBoard.grants.isEmpty)
        XCTAssertFalse(coordinator.roamPresence.consentAccepted)
        XCTAssertEqual(coordinator.ownerState.phase, .off)
        _ = view.body
    }

    func testMerchantSideQuestHostSectionViewRendersIndependentAndThemeBoundSpawnsAndPhotoEvidenceGuard() throws {
        let storePlace = try MapSourceKey(type: .store, id: "store-101")
        let poiPlace = try MapSourceKey(type: .roamPOI, id: "poi-202")

        let independentSpawn = try SideQuestSpawnInstance(
            instanceID: "sq-independent-1",
            definitionID: "def-1",
            definitionVersion: 1,
            place: storePlace,
            themeReleaseID: nil,
            visibleFrom: now.addingTimeInterval(-600),
            visibleUntil: now.addingTimeInterval(1_800),
            status: .open,
            remainingCapacity: 5,
            title: "Independent Roaster Challenge"
        )
        let themeBoundSpawn = try SideQuestSpawnInstance(
            instanceID: "sq-theme-2",
            definitionID: "def-2",
            definitionVersion: 2,
            place: poiPlace,
            themeReleaseID: "theme-rel-9",
            visibleFrom: now.addingTimeInterval(-600),
            visibleUntil: now.addingTimeInterval(1_800),
            status: .full,
            remainingCapacity: 0,
            title: "Autumn Lantern Side-Quest"
        )
        let expiredSpawn = try SideQuestSpawnInstance(
            instanceID: "sq-expired-3",
            definitionID: "def-3",
            definitionVersion: 1,
            place: storePlace,
            themeReleaseID: nil,
            visibleFrom: now.addingTimeInterval(-3_600),
            visibleUntil: now.addingTimeInterval(-60),
            status: .open,
            remainingCapacity: 2,
            title: "Expired Spawn"
        )

        var presentation = MerchantSideQuestHostPresentation(
            instances: [independentSpawn, themeBoundSpawn, expiredSpawn]
        )
        let cards = presentation.discoverableCards(now: now)
        XCTAssertEqual(cards.map(\.instanceID), ["sq-independent-1", "sq-theme-2"])
        XCTAssertTrue(cards[0].isIndependentOfTheme)
        XCTAssertFalse(cards[1].isIndependentOfTheme)
        XCTAssertEqual(cards[1].themeReleaseID, "theme-rel-9")
        XCTAssertFalse(cards[0].canTriggerClientAccept)

        var acceptedInstanceID: String?
        var submittedPhotoInstanceID: String?
        let initialView = MerchantSideQuestHostSectionView(
            presentation: presentation,
            now: now,
            onRequestAccept: { acceptedInstanceID = $0.instanceID },
            onSubmitPhotoEvidence: { submittedPhotoInstanceID = $0 }
        )
        _ = initialView.body

        // Move sq-independent-1 into .active via authoritative readback and submit photo evidence.
        try presentation.applyAttemptReadback(
            instanceID: "sq-independent-1",
            attemptNo: 1,
            status: .active,
            revision: 1
        )
        let activeView = MerchantSideQuestHostSectionView(
            presentation: presentation,
            now: now,
            onRequestAccept: { acceptedInstanceID = $0.instanceID },
            onSubmitPhotoEvidence: { submittedPhotoInstanceID = $0 }
        )
        _ = activeView.body
        activeView.onSubmitPhotoEvidence?("sq-independent-1")
        XCTAssertEqual(submittedPhotoInstanceID, "sq-independent-1")

        let evidenceState = try presentation.submitPhotoEvidence(for: "sq-independent-1")
        XCTAssertEqual(evidenceState, .submittedAwaitingReview)

        let awaitingCards = presentation.discoverableCards(now: now)
        let updatedCard = try XCTUnwrap(awaitingCards.first(where: { $0.instanceID == "sq-independent-1" }))
        XCTAssertEqual(updatedCard.evidenceState, .submittedAwaitingReview)
        // W14.4: submitting photo evidence never auto-completes the attempt without server readback.
        XCTAssertFalse(updatedCard.isCompletedByAuthority)
        _ = MerchantSideQuestHostSectionView(presentation: presentation, now: now).body

        // Authoritative .completed readback marks isCompletedByAuthority == true.
        presentation.applyEvidenceReadback(for: "sq-independent-1", state: .accepted)
        try presentation.applyAttemptReadback(
            instanceID: "sq-independent-1",
            attemptNo: 1,
            status: .completed,
            revision: 2
        )
        let completedCard = try XCTUnwrap(
            presentation.discoverableCards(now: now).first(where: { $0.instanceID == "sq-independent-1" })
        )
        XCTAssertTrue(completedCard.isCompletedByAuthority)
        XCTAssertNil(acceptedInstanceID)
        _ = MerchantSideQuestHostSectionView(presentation: presentation, now: now).body
    }

    func testMerchantSideQuestHostSectionViewRendersUnknownOutcomeReadbackLockAndSurvivedAttempts() throws {
        let storePlace = try MapSourceKey(type: .store, id: "store-303")
        let spawn = try SideQuestSpawnInstance(
            instanceID: "sq-lock-1",
            definitionID: "def-lock",
            definitionVersion: 1,
            place: storePlace,
            themeReleaseID: nil,
            visibleFrom: now.addingTimeInterval(-300),
            visibleUntil: now.addingTimeInterval(900),
            status: .open,
            remainingCapacity: 3,
            title: "Unknown Accept Lock Quest"
        )

        var presentation = MerchantSideQuestHostPresentation(instances: [spawn])
        let requestID = UUID()
        let request = try presentation.requestAcceptForContract(spawn, now: now, requestID: requestID)
        presentation.finishAccept(request, attempt: nil)

        XCTAssertTrue(presentation.isLockedByUnknownOutcome)
        XCTAssertEqual(presentation.unknownPendingRequest, request)
        let lockedCard = try XCTUnwrap(presentation.discoverableCards(now: now).first)
        XCTAssertTrue(lockedCard.isLockedByUnknownAccept)
        _ = MerchantSideQuestHostSectionView(presentation: presentation, now: now).body

        // Authoritative readback resolves the unknown lock into an accepted attempt.
        try presentation.applyAttemptReadback(
            instanceID: "sq-lock-1",
            attemptNo: 1,
            status: .accepted,
            revision: 1
        )
        XCTAssertFalse(presentation.isLockedByUnknownOutcome)
        XCTAssertNil(presentation.unknownPendingRequest)

        // W14.3: Even when the spawn instance disappears from the viewport feed, the accepted attempt survives.
        presentation.replaceSpawnInstances([])
        XCTAssertTrue(presentation.discoverableCards(now: now).isEmpty)
        let attempts = presentation.attemptPresentations(now: now)
        XCTAssertEqual(attempts.count, 1)
        XCTAssertEqual(attempts[0].instanceID, "sq-lock-1")
        XCTAssertTrue(attempts[0].survivedInstanceExpiryOrRemoval)
        _ = MerchantSideQuestHostSectionView(presentation: presentation, now: now).body
    }
}
