import XCTest
@testable import QuestifyCore

/// Deterministic in-memory transports only. These tests never contact a deployment.
@MainActor final class NearbyTeamWithdrawalRaceTests: XCTestCase {
    private let session = NearbyTeamSyntheticFixtures.session
    private let context = NearbyTeamSyntheticFixtures.context
    private let teamID = NearbyTeamID(502)

    private func make() -> (NearbyTeamCoordinator, NearbyWithdrawalReadFake, NearbyWithdrawalWriteFake) {
        let read = NearbyWithdrawalReadFake()
        let write = NearbyWithdrawalWriteFake()
        let service = NearbyTeamService(readTransport: read, liveReadGrant: true, writeAdapter: write)
        return (.init(service: service, session: session, locks: .init()), read, write)
    }
    private func withdraw(_ model: NearbyTeamCoordinator) async throws -> NearbyTeamReview {
        model.prepare(.withdraw(teamID))
        let review = try XCTUnwrap(model.review)
        await model.confirm(review)
        return review
    }
    private func status(_ model: NearbyTeamCoordinator) -> NearbyViewerStatus? {
        model.teams.first { $0.id == teamID }?.viewerStatus
    }
    private func team(_ status: String, expiry: String = "2099-10-02T02:00:00Z") -> String {
        """
        {"code":200,"data":[{"teamId":502,"viewerStatus":"\(status)","viewerHasTicket":true,"applyExpireTime":"\(expiry)"}]}
        """
    }
    private func application(_ status: String, expiry: String = "2099-10-02T02:00:00Z") -> String {
        """
        {"code":200,"data":[{"teamId":502,"applyStatus":"\(status)","applyExpireTime":"\(expiry)"}]}
        """
    }
    private func waitUntil(_ predicate: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<1_000 {
            if predicate() { return }
            await Task.yield()
        }
        XCTFail("Expected fake transport suspension was not reached", file: file, line: line)
        throw NearbyWithdrawalTestFailure.timedOut
    }

    func testAcknowledgedWithdrawSuppressesRepeatedPendingReadsAndActiveCount() async throws {
        let (model, read, write) = make()
        await model.loadNearby(context); await model.loadMine()
        _ = try await withdraw(model)
        XCTAssertEqual(status(model), NearbyViewerStatus.none)
        XCTAssertEqual(model.messageKey, "nearby.acknowledged")
        for _ in 0..<3 {
            await model.loadNearby(context); await model.loadMine()
            XCTAssertEqual(status(model), .unknown)
            XCTAssertNil(model.teams.first { $0.id == teamID }?.applyExpireTime)
            XCTAssertFalse(model.myApplications.contains { $0.id == teamID })
            XCTAssertEqual(NearbyTeamBridge.activeCount(NearbyTeamBridge.myRows(joined: [], applications: model.myApplications)), 0)
            XCTAssertEqual(model.myApplications.map(\.id), [.init(506)])
            XCTAssertEqual(model.messageKey, "nearby.stale")
            XCTAssertFalse(model.allowed(.withdraw(teamID)))
        }
        XCTAssertEqual(write.reviews.count, 1)
        XCTAssertEqual(read.requests.count, 8)
    }

    func testSimulatedWithdrawalUsesSameBarrierWithoutClaimingLiveAcknowledgment() async throws {
        let fake = NearbyTeamFakeTransport(steps: [
            .response(NearbyTeamSyntheticFixtures.response(NearbyTeamSyntheticFixtures.teams)),
            .response(NearbyTeamSyntheticFixtures.response("{\"code\":200}")),
            .response(NearbyTeamSyntheticFixtures.response(NearbyTeamSyntheticFixtures.teams))
        ])
        let model = NearbyTeamCoordinator(service: .init(fake: fake), session: session, locks: .init())
        await model.loadNearby(context); _ = try await withdraw(model)
        XCTAssertEqual(model.messageKey, "nearby.simulated")
        await model.loadNearby(context)
        XCTAssertEqual(status(model), .unknown)
        XCTAssertEqual(fake.requests.filter(\.mutation).count, 1)
    }

    func testMineOnlyWithdrawalSuppressesPendingWithoutNearbyTeamSnapshot() async throws {
        let (model, _, write) = make()
        await model.loadMine()
        let review = try await withdraw(model)
        XCTAssertNil(review.team); XCTAssertEqual(review.application?.id, teamID)
        await model.loadMine()
        XCTAssertFalse(model.myApplications.contains { $0.id == teamID })
        XCTAssertEqual(write.reviews.count, 1)
    }

    func testDifferentTeamAndNonPendingAuthorityRemainVisible() async throws {
        let (model, read, _) = make()
        await model.loadNearby(context); _ = try await withdraw(model)
        for value in ["JOINED", "LEADER", "REJECTED", "NONE", "UNKNOWN"] {
            read.nextJSON = team(value)
            await model.loadNearby(context)
            XCTAssertEqual(status(model), NearbyViewerStatus(rawValue: value))
            XCTAssertNotEqual(model.messageKey, "nearby.stale")
        }
        read.nextJSON = application("REJECTED")
        await model.loadMine()
        XCTAssertEqual(model.myApplications.map(\.status), [.rejected])
        await model.loadNearby(context)
        XCTAssertEqual(model.teams.first { $0.id == .init(503) }?.viewerStatus, .leader)
        XCTAssertEqual(model.teams.first { $0.id == .init(505) }?.viewerStatus, .joined)
        XCTAssertEqual(status(model), .unknown)
    }

    func testDifferentExpiryAloneCannotProveAnExternalNewApplication() async throws {
        let (model, read, _) = make()
        await model.loadNearby(context); _ = try await withdraw(model)
        read.nextJSON = team("PENDING", expiry: "2099-12-01T00:00:00Z")
        await model.loadNearby(context)
        XCTAssertEqual(status(model), .unknown)
        XCTAssertEqual(model.messageKey, "nearby.stale")
        read.nextJSON = application("PENDING", expiry: "2099-12-01T00:00:00Z")
        await model.loadMine()
        XCTAssertTrue(model.myApplications.isEmpty)
        XCTAssertEqual(model.messageKey, "nearby.stale")
    }

    func testExplicitNewApplyAcknowledgmentClearsOnlyMatchingBarrier() async throws {
        let (model, read, write) = make()
        read.nextJSON = team("PENDING")
        await model.loadNearby(context); _ = try await withdraw(model)
        XCTAssertTrue(model.allowed(.apply(teamID))) // No new replay restriction was added.
        model.prepare(.apply(teamID))
        let review = try XCTUnwrap(model.review)
        write.nextOutcome = .acknowledged(expiry: .text("2099-12-01T00:00:00Z"))
        await model.confirm(review)
        XCTAssertEqual(status(model), .pending)
        XCTAssertEqual(model.teams.first?.applyExpireTime, .text("2099-12-01T00:00:00Z"))
        read.nextJSON = team("PENDING", expiry: "2099-12-01T00:00:00Z")
        await model.loadNearby(context)
        read.nextJSON = application("PENDING", expiry: "2099-12-01T00:00:00Z")
        await model.loadMine()
        XCTAssertEqual(status(model), .pending)
        XCTAssertEqual(model.myApplications.map(\.id), [teamID])
        XCTAssertEqual(write.reviews.map(\.action), [.withdraw(teamID), .apply(teamID)])
        // Existing per-operation replay policy is retained; this patch does not invent
        // application IDs or erase durable HTTP dispatch records to enable another cycle.
        XCTAssertFalse(model.allowed(.apply(teamID)))
        XCTAssertFalse(model.allowed(.withdraw(teamID)))
    }

    func testKnownReplayBoundaryIsNotSilentlyRemovedForApplyWithdrawApplyCycle() async throws {
        let (model, read, write) = make()
        read.nextJSON = team("NONE")
        await model.loadNearby(context)
        model.prepare(.apply(teamID)); await model.confirm(try XCTUnwrap(model.review))
        XCTAssertTrue(model.allowed(.withdraw(teamID)))
        _ = try await withdraw(model)
        read.nextJSON = team("NONE"); await model.loadNearby(context)
        XCTAssertEqual(status(model), NearbyViewerStatus.none)
        XCTAssertFalse(model.allowed(.apply(teamID)))
        XCTAssertEqual(write.reviews.count, 2)
    }

    func testNewApplyDoesNotClearAnotherTeamsBarrier() async throws {
        let (model, read, write) = make()
        read.nextJSON = """
        {"code":200,"data":[
          {"teamId":501,"viewerStatus":"PENDING","viewerHasTicket":true},
          {"teamId":502,"viewerStatus":"PENDING","viewerHasTicket":true}
        ]}
        """
        await model.loadNearby(context)
        _ = try await withdraw(model)
        model.prepare(.withdraw(.init(501))); await model.confirm(try XCTUnwrap(model.review))
        model.prepare(.apply(teamID)); await model.confirm(try XCTUnwrap(model.review))
        read.nextJSON = """
        {"code":200,"data":[
          {"teamId":501,"viewerStatus":"PENDING","viewerHasTicket":true},
          {"teamId":502,"viewerStatus":"PENDING","viewerHasTicket":true}
        ]}
        """
        await model.loadNearby(context)
        XCTAssertEqual(model.teams.first { $0.id == .init(501) }?.viewerStatus, .unknown)
        XCTAssertEqual(status(model), .pending)
        XCTAssertEqual(write.reviews.count, 3)
    }

    func testRejectedOrUnsentNewApplyDoesNotClearWithdrawalBarrier() async throws {
        for outcome in [NearbyWriteResult.notSent, .rejected(errorCode: "APPLY_PENDING", message: "Still pending")] {
            let (model, read, write) = make()
            read.nextJSON = team("PENDING")
            await model.loadNearby(context); _ = try await withdraw(model)
            model.prepare(.apply(teamID)); let review = try XCTUnwrap(model.review)
            write.nextOutcome = outcome
            await model.confirm(review)
            await model.loadNearby(context); await model.loadMine()
            XCTAssertEqual(status(model), .unknown)
            XCTAssertFalse(model.myApplications.contains { $0.id == teamID })
        }
    }

    func testUnknownNewApplyKeepsLockAndWithdrawalBarrier() async throws {
        let (model, read, write) = make()
        read.nextJSON = team("PENDING")
        await model.loadNearby(context); _ = try await withdraw(model)
        model.prepare(.apply(teamID)); let review = try XCTUnwrap(model.review)
        write.nextOutcome = .unknown
        await model.confirm(review)
        await model.loadNearby(context); await model.loadMine()
        XCTAssertTrue(model.uncertain)
        XCTAssertEqual(status(model), .unknown)
        XCTAssertFalse(model.myApplications.contains { $0.id == teamID })
        XCTAssertFalse(model.allowed(.apply(teamID)))
    }

    func testUnsuccessfulWithdrawalNeverCreatesBarrier() async throws {
        for outcome in [NearbyWriteResult.notSent, .unknown, .rejected(errorCode: "DENIED", message: "No change")] {
            let (model, _, write) = make()
            await model.loadNearby(context); await model.loadMine()
            write.nextOutcome = outcome
            _ = try await withdraw(model)
            await model.loadNearby(context); await model.loadMine()
            XCTAssertEqual(status(model), .pending)
            XCTAssertTrue(model.myApplications.contains { $0.id == teamID && $0.status == .pending })
            XCTAssertEqual(model.uncertain, outcome == .unknown)
        }
    }

    func testCancelAndDuplicateConfirmNeverDispatchTwice() async throws {
        let (model, _, write) = make()
        await model.loadNearby(context)
        model.prepare(.withdraw(teamID)); let cancelled = try XCTUnwrap(model.review)
        model.cancelReview(); await model.confirm(cancelled)
        XCTAssertTrue(write.reviews.isEmpty)
        let settled = try await withdraw(model)
        await model.confirm(settled)
        await model.loadNearby(context)
        model.prepare(.withdraw(teamID))
        XCTAssertNil(model.review)
        XCTAssertEqual(write.reviews.count, 1)
    }

    func testConcurrentDuplicateConfirmDispatchesOneWithdrawal() async throws {
        let (model, _, write) = make()
        await model.loadNearby(context)
        model.prepare(.withdraw(teamID)); let review = try XCTUnwrap(model.review)
        write.suspendNext = true
        let first = Task { await model.confirm(review) }
        try await waitUntil { write.reviews.count == 1 }
        await model.confirm(review)
        XCTAssertEqual(write.reviews.count, 1)
        write.complete(.acknowledged(expiry: nil)); await first.value
        await model.loadNearby(context)
        XCTAssertEqual(status(model), .unknown)
        XCTAssertFalse(model.uncertain)
    }

    func testReadAlreadyInFlightBeforeNavigationAndWithdrawalIsDiscarded() async throws {
        let (model, read, _) = make()
        await model.loadNearby(context)
        read.suspendNext = true
        let oldRead = Task { await model.loadNearby(context) }
        try await waitUntil { read.requests.count == 2 }
        model.leave(); model.resume()
        _ = try await withdraw(model)
        read.complete(NearbyTeamSyntheticFixtures.teams); await oldRead.value
        XCTAssertEqual(status(model), NearbyViewerStatus.none)
        XCTAssertFalse(model.busy)
    }

    func testLateWithdrawalAckBeforeNewReadDoesNotClearItsBusyOrRestorePending() async throws {
        let (model, read, write) = make()
        await model.loadNearby(context)
        model.prepare(.withdraw(teamID)); let review = try XCTUnwrap(model.review)
        write.suspendNext = true
        let mutation = Task { await model.confirm(review) }
        try await waitUntil { write.reviews.count == 1 }
        model.leave(); model.resume()
        read.suspendNext = true
        let newerRead = Task { await model.loadNearby(context) }
        try await waitUntil { read.requests.count == 2 }
        write.complete(.acknowledged(expiry: nil)); await mutation.value
        XCTAssertTrue(model.busy)
        XCTAssertFalse(model.uncertain)
        read.complete(NearbyTeamSyntheticFixtures.teams); await newerRead.value
        XCTAssertFalse(model.busy)
        XCTAssertEqual(status(model), .unknown)
    }

    func testLateWithdrawalAckAfterNewMineReadRemovesOnlyPendingRow() async throws {
        let (model, _, write) = make()
        await model.loadNearby(context)
        model.prepare(.withdraw(teamID)); let review = try XCTUnwrap(model.review)
        write.suspendNext = true
        let mutation = Task { await model.confirm(review) }
        try await waitUntil { write.reviews.count == 1 }
        model.leave(); model.resume()
        await model.loadMine()
        XCTAssertTrue(model.myApplications.contains { $0.id == teamID })
        write.complete(.acknowledged(expiry: nil)); await mutation.value
        XCTAssertEqual(model.myApplications.map(\.id), [.init(506)])
        await model.loadMine()
        XCTAssertFalse(model.myApplications.contains { $0.id == teamID })
    }

    func testLateWithdrawalDoesNotMaskFreshNonPendingResult() async throws {
        let (model, read, write) = make()
        await model.loadNearby(context)
        model.prepare(.withdraw(teamID)); let review = try XCTUnwrap(model.review)
        write.suspendNext = true
        let mutation = Task { await model.confirm(review) }
        try await waitUntil { write.reviews.count == 1 }
        model.leave(); model.resume()
        read.nextJSON = team("JOINED"); await model.loadNearby(context)
        read.nextJSON = application("REJECTED"); await model.loadMine()
        write.complete(.acknowledged(expiry: nil)); await mutation.value
        XCTAssertEqual(status(model), .joined)
        XCTAssertEqual(model.myApplications.map(\.status), [.rejected])
    }

    func testLateNewApplyAcknowledgmentAfterNavigationSupersedesBarrier() async throws {
        let (model, read, write) = make()
        read.nextJSON = team("PENDING")
        await model.loadNearby(context); _ = try await withdraw(model)
        model.prepare(.apply(teamID)); let review = try XCTUnwrap(model.review)
        write.suspendNext = true
        let mutation = Task { await model.confirm(review) }
        try await waitUntil { write.reviews.count == 2 }
        model.leave(); model.resume()
        write.complete(.acknowledged(expiry: nil)); await mutation.value
        await model.loadNearby(context); await model.loadMine()
        XCTAssertEqual(status(model), .pending)
        XCTAssertTrue(model.myApplications.contains { $0.id == teamID })
    }

    func testLateApplyAckCannotDowngradeNewerJoinedOrLeaderRead() async throws {
        for value in ["JOINED", "LEADER", "REJECTED", "NONE"] {
            let (model, read, write) = make()
            read.nextJSON = team("PENDING")
            await model.loadNearby(context); _ = try await withdraw(model)
            model.prepare(.apply(teamID)); let review = try XCTUnwrap(model.review)
            write.suspendNext = true
            let mutation = Task { await model.confirm(review) }
            try await waitUntil { write.reviews.count == 2 }
            model.leave(); model.resume()
            read.nextJSON = team(value); await model.loadNearby(context)
            write.complete(.acknowledged(expiry: nil)); await mutation.value
            XCTAssertEqual(status(model), NearbyViewerStatus(rawValue: value))
            XCTAssertFalse(model.busy)
            // Clearing the old barrier still allows a later new application's readback.
            read.nextJSON = team("PENDING"); await model.loadNearby(context)
            XCTAssertEqual(status(model), .pending)
        }
    }

    func testBarrierSurvivesNavigationAndQueryContextChange() async throws {
        let (model, _, _) = make()
        await model.loadNearby(context); _ = try await withdraw(model)
        model.leave(); model.resume()
        await model.loadNearby(.init(latitude: 35, longitude: 120, radius: 1000))
        XCTAssertEqual(status(model), .unknown)
        await model.loadMine()
        XCTAssertFalse(model.myApplications.contains { $0.id == teamID })
    }

    func testIdentityAndEpochChangesDoNotInheritBarrier() async throws {
        let nextSessions = [
            NearbyTeamSession(accountID: 7002, epoch: 1, region: "US", namespace: session.namespace, role: "player"),
            NearbyTeamSession(accountID: session.accountID, epoch: 2, region: "US", namespace: session.namespace, role: "player"),
            NearbyTeamSession(accountID: session.accountID, epoch: 1, region: "CN", namespace: session.namespace, role: "player"),
            NearbyTeamSession(accountID: session.accountID, epoch: 1, region: "US", namespace: "other-deployment", role: "player")
        ]
        for next in nextSessions {
            let (model, _, _) = make()
            await model.loadNearby(context); _ = try await withdraw(model)
            model.bind(next)
            await model.loadNearby(context); await model.loadMine()
            XCTAssertEqual(status(model), .pending)
            XCTAssertTrue(model.myApplications.contains { $0.id == teamID })
        }
    }

    func testLateAckCannotImportBarrierAfterLogoutAndSameSessionRebind() async throws {
        let (model, _, write) = make()
        await model.loadNearby(context)
        model.prepare(.withdraw(teamID)); let review = try XCTUnwrap(model.review)
        write.suspendNext = true
        let mutation = Task { await model.confirm(review) }
        try await waitUntil { write.reviews.count == 1 }
        model.bind(nil); model.bind(session)
        await model.loadNearby(context); await model.loadMine()
        write.complete(.acknowledged(expiry: nil)); await mutation.value
        XCTAssertEqual(status(model), .pending)
        XCTAssertTrue(model.myApplications.contains { $0.id == teamID })
        await model.loadNearby(context)
        XCTAssertEqual(status(model), .pending)
    }

    func testCoordinatorRecreationDoesNotPretendToHaveServerWithdrawalAuthority() async throws {
        let (first, _, _) = make()
        await first.loadNearby(context); _ = try await withdraw(first)
        let (second, _, _) = make()
        await second.loadNearby(context); await second.loadMine()
        XCTAssertEqual(status(second), .pending)
        XCTAssertTrue(second.myApplications.contains { $0.id == teamID })
    }
}

private enum NearbyWithdrawalTestFailure: Error { case timedOut }

@MainActor private final class NearbyWithdrawalReadFake: NearbyTeamReadTransport {
    private(set) var requests: [NearbyTeamRequest] = []
    var nextJSON: String?
    var suspendNext = false
    private var continuation: CheckedContinuation<NearbyTeamResponse, Never>?
    func sendRead(_ request: NearbyTeamRequest, session: NearbyTeamSession) async throws -> NearbyTeamResponse {
        requests.append(request)
        if suspendNext {
            suspendNext = false
            return await withCheckedContinuation { continuation = $0 }
        }
        let fallback = request.path == "/api/team/my-applications" ? NearbyTeamSyntheticFixtures.applications : NearbyTeamSyntheticFixtures.teams
        let json = nextJSON ?? fallback; nextJSON = nil
        return NearbyTeamSyntheticFixtures.response(json)
    }
    func complete(_ json: String) {
        let pending = continuation; continuation = nil
        pending?.resume(returning: NearbyTeamSyntheticFixtures.response(json))
    }
}

@MainActor private final class NearbyWithdrawalWriteFake: NearbyTeamWriting {
    let configured = true
    private(set) var reviews: [NearbyTeamReview] = []
    var nextOutcome: NearbyWriteResult = .acknowledged(expiry: nil)
    var suspendNext = false
    private var continuation: CheckedContinuation<NearbyWriteResult, Never>?
    func submit(_ review: NearbyTeamReview) async -> NearbyWriteResult {
        reviews.append(review)
        if suspendNext {
            suspendNext = false
            return await withCheckedContinuation { continuation = $0 }
        }
        let outcome = nextOutcome; nextOutcome = .acknowledged(expiry: nil)
        return outcome
    }
    func complete(_ outcome: NearbyWriteResult) {
        let pending = continuation; continuation = nil
        pending?.resume(returning: outcome)
    }
}
