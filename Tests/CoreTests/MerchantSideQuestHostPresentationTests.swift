import XCTest
@testable import QuestifyCore

final class MerchantSideQuestHostPresentationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 3_000_000)

    private func makeInstance(
        id: String = "sq-1",
        placeType: MapSourceType = .store,
        placeID: String = "store-77",
        theme: String? = nil,
        fromOffset: TimeInterval = -60,
        untilOffset: TimeInterval = 3600,
        status: SideQuestSpawnInstance.Status = .open,
        capacity: Int? = 3,
        title: String = "Merchant coffee tasting"
    ) throws -> SideQuestSpawnInstance {
        try SideQuestSpawnInstance(
            instanceID: id,
            definitionID: "def-\(id)",
            definitionVersion: 1,
            place: try MapSourceKey(type: placeType, id: placeID),
            themeReleaseID: theme,
            visibleFrom: now.addingTimeInterval(fromOffset),
            visibleUntil: now.addingTimeInterval(untilOffset),
            status: status,
            remainingCapacity: capacity,
            title: title
        )
    }

    func testDiscoverabilityWindowStatusCapacityAndOptionalThemeReleasePresentation() throws {
        let openThemeFree = try makeInstance(id: "sq-open", theme: nil, status: .open, capacity: 2)
        let themedFull = try makeInstance(id: "sq-full", placeType: .roamPOI, placeID: "poi-9", theme: "rel-2026", status: .open, capacity: 0)
        let paused = try makeInstance(id: "sq-paused", status: .paused, capacity: 4)
        let closed = try makeInstance(id: "sq-closed", status: .closed, capacity: 4)
        let future = try makeInstance(id: "sq-future", fromOffset: 120, untilOffset: 3600)
        let expired = try makeInstance(id: "sq-expired", fromOffset: -7200, untilOffset: -1)

        let host = MerchantSideQuestHostPresentation(
            instances: [openThemeFree, themedFull, paused, closed, future, expired]
        )

        let cards = host.discoverableCards(now: now)
        XCTAssertEqual(cards.map(\.instanceID), ["sq-open", "sq-full", "sq-paused"])

        let first = try XCTUnwrap(cards.first { $0.instanceID == "sq-open" })
        XCTAssertNil(first.themeReleaseID)
        XCTAssertTrue(first.isIndependentOfTheme)
        XCTAssertTrue(first.offersServerAccept)
        XCTAssertEqual(first.markerState, .interactive)
        XCTAssertFalse(first.canTriggerClientAccept, "SideQuestFeature.acceptEnabled is false by default")

        let second = try XCTUnwrap(cards.first { $0.instanceID == "sq-full" })
        XCTAssertEqual(second.themeReleaseID, "rel-2026")
        XCTAssertFalse(second.isIndependentOfTheme)
        XCTAssertFalse(second.offersServerAccept)
        XCTAssertEqual(second.markerState, .unavailable)

        let third = try XCTUnwrap(cards.first { $0.instanceID == "sq-paused" })
        XCTAssertFalse(third.offersServerAccept)
        XCTAssertEqual(third.markerState, .unavailable)
    }

    func testDefaultAcceptFeatureDisabledBlocksPublicAcceptAndDisablesClientTrigger() throws {
        let quest = try makeInstance()
        var host = MerchantSideQuestHostPresentation(instances: [quest])
        XCTAssertFalse(host.isAcceptFeatureEnabled)
        XCTAssertThrowsError(try host.requestAccept(for: quest, now: now)) { error in
            XCTAssertEqual(error as? SideQuestFailure, .featureDisabled)
        }
    }

    func testUnknownAcceptOutcomeLocksHostPresentationUntilReadbackOrNotAcceptedConfirmation() throws {
        let quest = try makeInstance()
        var host = MerchantSideQuestHostPresentation(instances: [quest])
        let fixedUUID = UUID()

        let request = try host.requestAcceptForContract(quest, now: now, requestID: fixedUUID)
        XCTAssertEqual(request.attemptNo, 1)

        // Finishing with nil attempt enters unknown outcome lock.
        host.finishAccept(request, attempt: nil)
        XCTAssertTrue(host.isLockedByUnknownOutcome)
        XCTAssertEqual(host.unknownPendingRequest, request)
        XCTAssertEqual(host.discoverableCards(now: now).first?.isLockedByUnknownAccept, true)

        // Retrying while unknown returns the exact same request (no blind duplicate attempt number).
        let retried = try host.requestAcceptForContract(quest, now: now, requestID: UUID())
        XCTAssertEqual(retried, request)

        // Confirming not accepted returns pending state to .sending(request), then readback clears lock.
        host.confirmNotAccepted(instanceID: quest.instanceID)
        XCTAssertFalse(host.isLockedByUnknownOutcome)
        host.finishAccept(request, attempt: nil)
        XCTAssertTrue(host.isLockedByUnknownOutcome)

        try host.applyAttemptReadback(instanceID: quest.instanceID, attemptNo: 1, status: .accepted, revision: 1)
        XCTAssertFalse(host.isLockedByUnknownOutcome)
        XCTAssertNil(host.unknownPendingRequest)
        XCTAssertEqual(host.discoverableCards(now: now).first?.attempt?.status, .accepted)
    }

    func testAcceptedAttemptSurvivesInstanceExpiryAndVanishingFromSpawnFeed() throws {
        let quest = try makeInstance(id: "sq-survive", fromOffset: -60, untilOffset: 60)
        var host = MerchantSideQuestHostPresentation(instances: [quest])

        let request = try host.requestAcceptForContract(quest, now: now)
        host.finishAccept(request, attempt: .init(instanceID: "sq-survive", attemptNo: 1, status: .accepted, revision: 1))

        // Before expiry: card is discoverable and attempt has not outlived the instance yet.
        XCTAssertEqual(host.discoverableCards(now: now).count, 1)
        XCTAssertEqual(host.attemptPresentations(now: now).first?.survivedInstanceExpiryOrRemoval, false)

        // After visibleUntil window passes: spawn card is hidden, but accepted attempt survives in attemptBook.
        let afterExpiry = now.addingTimeInterval(300)
        XCTAssertTrue(host.discoverableCards(now: afterExpiry).isEmpty)
        let retainedAfterExpiry = try XCTUnwrap(host.attemptPresentations(now: afterExpiry).first)
        XCTAssertEqual(retainedAfterExpiry.instanceID, "sq-survive")
        XCTAssertEqual(retainedAfterExpiry.status, .accepted)
        XCTAssertTrue(retainedAfterExpiry.survivedInstanceExpiryOrRemoval)

        // Even if server feed drops the spawn instance completely, the attempt still survives and can advance.
        host.replaceSpawnInstances([])
        try host.applyAttemptReadback(instanceID: "sq-survive", attemptNo: 1, status: .active, revision: 2)
        let retainedAfterRemoval = try XCTUnwrap(host.attemptPresentations(now: afterExpiry).first)
        XCTAssertEqual(retainedAfterRemoval.status, .active)
        XCTAssertTrue(retainedAfterRemoval.survivedInstanceExpiryOrRemoval)
    }

    func testPhotoEvidenceSubmissionEntersAwaitingReviewAndNeverAutoCompletesAttempt() throws {
        let quest = try makeInstance(id: "sq-photo")
        var host = MerchantSideQuestHostPresentation(instances: [quest])

        // Cannot submit photo evidence before an active attempt exists.
        XCTAssertThrowsError(try host.submitPhotoEvidence(for: "sq-photo")) { error in
            XCTAssertEqual(error as? SideQuestFailure, .illegalTransition)
        }

        let request = try host.requestAcceptForContract(quest, now: now)
        host.finishAccept(request, attempt: .init(instanceID: "sq-photo", attemptNo: 1, status: .accepted, revision: 1))

        // Accepted (not yet active) still rejects photo evidence submission.
        XCTAssertThrowsError(try host.submitPhotoEvidence(for: "sq-photo")) { error in
            XCTAssertEqual(error as? SideQuestFailure, .illegalTransition)
        }

        // Move to active via server readback, then submit photo evidence.
        try host.applyAttemptReadback(instanceID: "sq-photo", attemptNo: 1, status: .active, revision: 2)
        let evidenceState = try host.submitPhotoEvidence(for: "sq-photo")
        XCTAssertEqual(evidenceState, .submittedAwaitingReview)

        let cardAfterSubmit = try XCTUnwrap(host.discoverableCards(now: now).first)
        XCTAssertEqual(cardAfterSubmit.evidenceState, .submittedAwaitingReview)
        XCTAssertEqual(cardAfterSubmit.attempt?.status, .active, "Submitting photo evidence must never auto-complete the attempt")
        XCTAssertFalse(cardAfterSubmit.isCompletedByAuthority)

        // Only an authoritative server readback marks the attempt completed.
        host.applyEvidenceReadback(for: "sq-photo", state: .accepted)
        try host.applyAttemptReadback(instanceID: "sq-photo", attemptNo: 1, status: .completed, revision: 3)
        let cardAfterAuthority = try XCTUnwrap(host.discoverableCards(now: now).first)
        XCTAssertEqual(cardAfterAuthority.evidenceState, .accepted)
        XCTAssertTrue(cardAfterAuthority.isCompletedByAuthority)
    }

    func testAttemptLifecycleReadbackRejectsIllegalJumpAndIgnoresStaleRevision() throws {
        let quest = try makeInstance(id: "sq-lifecycle")
        var host = MerchantSideQuestHostPresentation(instances: [quest])
        let request = try host.requestAcceptForContract(quest, now: now)
        host.finishAccept(request, attempt: .init(instanceID: "sq-lifecycle", attemptNo: 1, status: .accepted, revision: 1))

        // ACCEPTED -> COMPLETED directly is illegal (must pass through ACTIVE).
        XCTAssertThrowsError(
            try host.applyAttemptReadback(instanceID: "sq-lifecycle", attemptNo: 1, status: .completed, revision: 2)
        ) { error in
            XCTAssertEqual(error as? SideQuestFailure, .illegalTransition)
        }

        // ACCEPTED -> ACTIVE is legal; stale revision is ignored.
        try host.applyAttemptReadback(instanceID: "sq-lifecycle", attemptNo: 1, status: .active, revision: 2)
        try host.applyAttemptReadback(instanceID: "sq-lifecycle", attemptNo: 1, status: .accepted, revision: 1)
        XCTAssertEqual(host.attemptBook.attempts["sq-lifecycle"]?.status, .active)
    }
}
