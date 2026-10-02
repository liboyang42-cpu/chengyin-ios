import XCTest
@testable import QuestifyCore

@MainActor private final class TeamSessionBox {
    var value: TeamSession?
    init(_ value: TeamSession?) { self.value = value }
}
@MainActor final class TeamCoordinatorTests: XCTestCase {
    private func setup(_ scenario: TeamSyntheticService.Scenario = .content) throws -> (TeamCoordinator, TeamSyntheticService, TeamMemoryJournal, TeamSessionBox) {
        let service = try TeamSyntheticService(scenario: scenario), journal = TeamMemoryJournal(), box = TeamSessionBox(try TeamSyntheticFixtures.session())
        return (TeamCoordinator(service: service, journal: journal, currentSession: { box.value }), service, journal, box)
    }
    private func reviewLeave(_ coordinator: TeamCoordinator) async throws -> TeamReview {
        await coordinator.loadDetail(.id(4101)); coordinator.prepare(.leave(teamID: 4101)); return try XCTUnwrap(coordinator.review)
    }
    func testCancelAndReopenDiscardEarlierReviewIdentity() async throws {
        let (c, service, _, _) = try setup(); let first = try await reviewLeave(c)
        c.cancelReview(); c.prepare(.leave(teamID: 4101)); let second = try XCTUnwrap(c.review)
        XCTAssertNotEqual(first.id, second.id); await c.confirm(first); XCTAssertTrue(service.submissions.isEmpty)
        await c.confirm(second); XCTAssertEqual(service.submissions.count, 1); XCTAssertEqual(c.writeState, .simulated)
    }
    func testDoubleConfirmSubmitsAtMostOnce() async throws {
        let (c, service, _, _) = try setup(); let review = try await reviewLeave(c)
        service.beforeRead = { await Task.yield() }
        let first = Task { await c.confirm(review) }, second = Task { await c.confirm(review) }
        await first.value; await second.value; XCTAssertEqual(service.submissions.count, 1)
    }
    func testSignOutImmediatelyClearsPrivateDataAndReview() async throws {
        let (c, _, _, box) = try setup(); _ = try await reviewLeave(c); box.value = nil; c.synchronizeSession()
        XCTAssertNil(c.detail); XCTAssertNil(c.review); XCTAssertTrue(c.teams.isEmpty); XCTAssertFalse(c.authenticated)
    }
    func testSameAccountNewEpochInvalidatesReview() async throws {
        let (c, service, _, box) = try setup(); let review = try await reviewLeave(c)
        box.value = try TeamSyntheticFixtures.session(epoch: 2); await c.confirm(review)
        XCTAssertTrue(service.submissions.isEmpty); XCTAssertNil(c.review); XCTAssertNil(c.detail)
    }
    func testRoleChangeDuringPreflightPreventsDispatch() async throws {
        let (c, service, _, box) = try setup(); let review = try await reviewLeave(c)
        service.beforeRead = { box.value = try? TeamSyntheticFixtures.session(epoch: 1, role: "merchant") }
        await c.confirm(review); XCTAssertTrue(service.submissions.isEmpty)
    }
    func testSnapshotChangeDuringPreflightPreventsDispatch() async throws {
        let (c, service, _, _) = try setup(); let review = try await reviewLeave(c)
        service.currentDetail = try JSONDecoder().decode(TeamDetail.self, from: Data(TeamSyntheticFixtures.detailJSON.replacingOccurrences(of: "\"status\":0", with: "\"status\":2").utf8))
        await c.confirm(review); XCTAssertTrue(service.submissions.isEmpty); XCTAssertEqual(c.messageKey, "team.changed")
    }
    func testListCompletionAfterAccountSwitchIsDiscarded() async throws {
        let (c, service, _, box) = try setup()
        service.beforeRead = { box.value = try? TeamSyntheticFixtures.session(epoch: 2, accountID: 903) }
        await c.loadTeams(); XCTAssertTrue(c.teams.isEmpty)
    }
    func testDetailCompletionAfterDismissalIsDiscarded() async throws {
        let (c, service, _, _) = try setup(); service.beforeRead = { c.leaveScreen() }
        await c.loadDetail(.id(4101)); XCTAssertNil(c.detail)
    }
    func testReadPersistenceFailureBlocksReview() async throws {
        let (c, service, journal, _) = try setup(); journal.failReads = true
        await c.loadDetail(.id(4101)); c.prepare(.leave(teamID: 4101))
        XCTAssertNil(c.review); XCTAssertEqual(c.writeState, .blocked); XCTAssertTrue(service.submissions.isEmpty)
    }
    func testJournalWriteFailurePreventsSubmission() async throws {
        let (c, service, journal, _) = try setup(); let review = try await reviewLeave(c); journal.failWrites = true
        await c.confirm(review); XCTAssertTrue(service.submissions.isEmpty); XCTAssertNil(c.pending); XCTAssertEqual(c.writeState, .blocked)
    }
    func testUnknownOutcomeSurvivesRefreshAndCannotReplay() async throws {
        let (c, service, journal, _) = try setup(.unknownOutcome); let review = try await reviewLeave(c)
        await c.confirm(review); XCTAssertEqual(c.writeState, .unknown); XCTAssertEqual(journal.records.count, 1)
        await c.loadDetail(.id(4101)); c.prepare(.leave(teamID: 4101)); await c.confirm(review)
        XCTAssertNil(c.review); XCTAssertEqual(service.submissions.count, 1); XCTAssertNotNil(c.pending)
    }
    func testUnknownOutcomeSurvivesNewCoordinatorAndSameAccountReauthentication() async throws {
        let (c, service, journal, box) = try setup(.unknownOutcome); let review = try await reviewLeave(c); await c.confirm(review)
        box.value = try TeamSyntheticFixtures.session(epoch: 2)
        let restored = TeamCoordinator(service: service, journal: journal, currentSession: { box.value })
        await restored.loadDetail(.id(4101)); XCTAssertNotNil(restored.pending); XCTAssertEqual(restored.writeState, .unknown)
        restored.prepare(.leave(teamID: 4101)); XCTAssertNil(restored.review)
    }
    func testUnknownOutcomeIsAccountAndRegionScoped() async throws {
        let (c, service, journal, box) = try setup(.unknownOutcome); let review = try await reviewLeave(c); await c.confirm(review)
        box.value = try TeamSyntheticFixtures.session(epoch: 2, region: "US")
        let other = TeamCoordinator(service: service, journal: journal, currentSession: { box.value })
        await other.loadDetail(.id(4101)); XCTAssertNil(other.pending); XCTAssertEqual(journal.records.count, 1)
    }
    func testDismissalDuringSubmissionLeavesDurableUnknownLock() async throws {
        let (c, service, journal, box) = try setup(); let review = try await reviewLeave(c)
        service.beforeSubmit = { c.leaveScreen() }; await c.confirm(review)
        XCTAssertEqual(c.writeState, .unknown); XCTAssertEqual(journal.records.count, 1)
        let restored = TeamCoordinator(service: service, journal: journal, currentSession: { box.value })
        await restored.loadDetail(.id(4101)); XCTAssertNotNil(restored.pending)
        await restored.checkOutcome(); XCTAssertNil(restored.pending); XCTAssertEqual(restored.writeState, .simulated)
    }
    func testAccountChangeDuringSubmissionCannotShowSuccessToAnotherAccount() async throws {
        let (c, service, journal, box) = try setup(); let review = try await reviewLeave(c)
        service.beforeSubmit = { box.value = try? TeamSyntheticFixtures.session(epoch: 2, accountID: 903) }
        await c.confirm(review); c.synchronizeSession()
        XCTAssertNil(c.completedTeamID); XCTAssertNil(c.detail); XCTAssertEqual(journal.records.count, 1)
    }
    func testWrongOperationReceiptCannotClearUnknownLock() async throws {
        let (c, service, _, _) = try setup(.unknownOutcome); let review = try await reviewLeave(c); await c.confirm(review)
        service.outcomes[review.id] = .simulated(operationID: UUID(), teamID: 4101)
        await c.checkOutcome(); XCTAssertNotNil(c.pending); XCTAssertEqual(c.writeState, .unknown)
    }
    func testWrongTeamReceiptCannotClearUnknownLock() async throws {
        let (c, service, _, _) = try setup(.unknownOutcome); let review = try await reviewLeave(c); await c.confirm(review)
        service.outcomes[review.id] = .simulated(operationID: review.id, teamID: 999)
        await c.checkOutcome(); XCTAssertNotNil(c.pending); XCTAssertEqual(c.writeState, .unknown)
    }
    func testCorrelatedTerminalReceiptUnlocksWithoutResubmitting() async throws {
        let (c, service, journal, _) = try setup(.unknownOutcome); let review = try await reviewLeave(c); await c.confirm(review)
        service.outcomes[review.id] = .simulated(operationID: review.id, teamID: 4101)
        await c.checkOutcome(); XCTAssertNil(c.pending); XCTAssertTrue(journal.records.isEmpty); XCTAssertEqual(service.submissions.count, 1)
    }
    func testExplicitRejectionAndNotSentClearOnlyTheirPendingIntent() async throws {
        for scenario in [TeamSyntheticService.Scenario.rejected, .notSent] {
            let (c, _, journal, _) = try setup(scenario); let review = try await reviewLeave(c); await c.confirm(review)
            XCTAssertNil(c.pending); XCTAssertTrue(journal.records.isEmpty)
            XCTAssertEqual(c.writeState, scenario == .rejected ? .rejected : .notSent)
        }
    }
    func testGuestCannotReadPrepareOrCreate() async throws {
        let (c, service, _, box) = try setup(); box.value = nil
        await c.loadTeams(); await c.loadCreation(ownerID: 5101)
        c.prepare(.create(context: TeamSyntheticFixtures.creation, size: 2, inviteOnly: false))
        XCTAssertNil(c.review); XCTAssertNil(c.creation); XCTAssertTrue(service.submissions.isEmpty)
    }
    func testCreationRequiresLoadedMatchingCurrentAccountContext() async throws {
        let (c, service, _, _) = try setup()
        c.prepare(.create(context: TeamSyntheticFixtures.creation, size: 2, inviteOnly: false)); XCTAssertNil(c.review)
        await c.loadCreation(ownerID: 5101)
        c.prepare(.create(context: TeamSyntheticFixtures.creation, size: 2, inviteOnly: true))
        let review = try XCTUnwrap(c.review); await c.confirm(review)
        XCTAssertEqual(service.submissions.count, 1); XCTAssertEqual(c.completedTeamID, 4101)
    }
    func testInviteJoinIsReviewedAndRevalidatedAgainstSameInvite() async throws {
        let (c, service, _, _) = try setup(.invitation)
        await c.loadDetail(.invitation("SYNTHETIC-TEAM"))
        c.prepare(.join(teamID: 4101, inviteCode: "DIFFERENT")); XCTAssertNil(c.review)
        c.prepare(.join(teamID: 4101, inviteCode: "SYNTHETIC-TEAM")); let review = try XCTUnwrap(c.review)
        await c.confirm(review); XCTAssertEqual(service.submissions.count, 1)
    }
    func testPaddedInvitationRouteAndActionUseSameCanonicalCodeThroughPreflight() async throws {
        for actionCode in ["SYNTHETIC-TEAM", "  SYNTHETIC-TEAM  "] {
            let (c, service, _, _) = try setup(.invitation)
            var reads = 0; service.beforeRead = { reads += 1 }
            await c.loadDetail(.invitation("  SYNTHETIC-TEAM  "))
            XCTAssertEqual(c.detail?.team.id, 4101)
            c.prepare(.join(teamID: 4101, inviteCode: actionCode))
            let review = try XCTUnwrap(c.review)
            XCTAssertEqual(review.action.lookup, .invitation("SYNTHETIC-TEAM"))
            await c.confirm(review)
            XCTAssertEqual(reads, 2); XCTAssertEqual(service.submissions.count, 1)
            XCTAssertEqual(c.writeState, .simulated)
        }
    }
    func testPaddedInvitationDoesNotAliasDifferentOrDifferentlyCasedCodes() async throws {
        let (c, service, _, _) = try setup(.invitation)
        await c.loadDetail(.invitation(" SYNTHETIC-TEAM "))
        for code in [" DIFFERENT ", " synthetic-team "] {
            c.prepare(.join(teamID: 4101, inviteCode: code))
            XCTAssertNil(c.review); XCTAssertEqual(c.messageKey, "team.changed")
        }
        XCTAssertTrue(service.submissions.isEmpty)
        XCTAssertNotEqual(TeamLookup.invitation(" CODE ").normalized, TeamLookup.invitation(" code ").normalized)
    }
    func testInvitationNormalizationPreservesEmptyAndControlCharacterRejection() async throws {
        let (c, service, _, _) = try setup(.invitation)
        var reads = 0; service.beforeRead = { reads += 1 }
        for code in ["", "   ", "SYNTHETIC-TEAM\n", "SYNTHETIC\u{0}-TEAM"] {
            XCTAssertNil(TeamLookup.invitation(code).normalized)
            await c.loadDetail(.invitation(code))
            XCTAssertNil(c.detail); XCTAssertEqual(c.messageKey, "team.invalidLink")
            c.prepare(.join(teamID: 4101, inviteCode: code)); XCTAssertNil(c.review)
        }
        XCTAssertEqual(reads, 0); XCTAssertTrue(service.submissions.isEmpty)
    }
    func testDefaultsJournalRestoresWithANewInstanceAndDoesNotClearDifferentIntent() throws {
        let suite = "team-tests-" + UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let journal = TeamDefaultsJournal(defaults: defaults), record = TeamPendingRecord(operationID: UUID(), ownerKey: "CN-901", targetKey: "team-4101")
        try journal.write(record); let restored = TeamDefaultsJournal(defaults: defaults)
        XCTAssertEqual(try restored.pending(ownerKey: "CN-901", targetKey: "team-4101"), record)
        XCTAssertThrowsError(try restored.clear(.init(operationID: UUID(), ownerKey: record.ownerKey, targetKey: record.targetKey)))
        XCTAssertEqual(try restored.pending(ownerKey: "CN-901", targetKey: "team-4101"), record)
        defaults.set("corrupt record", forKey: "questify.team.pending.v1.CN-901.team-4101")
        XCTAssertThrowsError(try restored.pending(ownerKey: "CN-901", targetKey: "team-4101"))
    }
}
