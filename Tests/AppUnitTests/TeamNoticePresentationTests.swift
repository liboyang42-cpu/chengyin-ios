import XCTest
@testable import Questify

@MainActor final class TeamNoticePresentationTests: XCTestCase {
    func testNoticeSnapshotsReflectCompletedSimulation() async throws {
        let environment = try TeamFixtureEnvironment(scenario: .content)
        let coordinator = environment.makeCoordinator()
        let initial = TeamNotice(coordinator: coordinator)
        await coordinator.loadDetail(.id(4101))
        coordinator.prepare(.leave(teamID: 4101))
        await coordinator.confirm(try XCTUnwrap(coordinator.review))
        XCTAssertEqual(coordinator.writeState, .simulated)
        let completed = TeamNotice(coordinator: coordinator)
        XCTAssertNil(initial.messageKey)
        XCTAssertEqual(completed.messageKey, "team.simulated")
        XCTAssertFalse(completed.hasPending)
    }

    func testUnknownNoticeStaysDistinctFromSimulation() async throws {
        let environment = try TeamFixtureEnvironment(scenario: .unknownOutcome)
        let coordinator = environment.makeCoordinator()
        await coordinator.loadDetail(.id(4101))
        coordinator.prepare(.leave(teamID: 4101))
        await coordinator.confirm(try XCTUnwrap(coordinator.review))
        let notice = TeamNotice(coordinator: coordinator)
        XCTAssertEqual(notice.messageKey, "team.unknown")
        XCTAssertTrue(notice.hasPending)
        XCTAssertEqual(environment.service.submissions.count, 1)
    }

    func testInvalidLinkAndSignOutProduceFreshNoticeValues() async throws {
        let environment = try TeamFixtureEnvironment(scenario: .content)
        let coordinator = environment.makeCoordinator()
        let initial = TeamNotice(coordinator: coordinator)
        await coordinator.loadDetail(.invitation(""))
        XCTAssertNil(initial.messageKey)
        XCTAssertEqual(TeamNotice(coordinator: coordinator).messageKey, "team.invalidLink")
        environment.becomeGuest()
        await coordinator.loadDetail(.id(4101))
        XCTAssertEqual(TeamNotice(coordinator: coordinator).messageKey, "team.signIn")
        XCTAssertNil(coordinator.detail)
    }
}

/// The real screen wrapper and coordinator, with suspended in-process reads only.
/// These tests cover the same run/leave/run sequence used by the retained views.
@MainActor final class TeamScreenLifecycleTests: XCTestCase {
    @MainActor private final class Gate {
        let entered: XCTestExpectation
        private var continuation: CheckedContinuation<Void, Never>?
        init(_ entered: XCTestExpectation) { self.entered = entered }
        func pause() async {
            await withCheckedContinuation { continuation = $0; entered.fulfill() }
        }
        func finish() { let saved = continuation; continuation = nil; saved?.resume() }
    }
    private func gate(_ name: String) -> Gate { Gate(expectation(description: name)) }
    private func changedDetail() throws -> TeamDetail {
        try JSONDecoder().decode(TeamDetail.self, from: Data(TeamSyntheticFixtures.detailJSON
            .replacingOccurrences(of: "Synthetic harbor companions", with: "Synthetic refreshed team")
            .replacingOccurrences(of: "\"status\":0", with: "\"status\":2").utf8))
    }

    func testReturnStartsFreshListBeforeOldReadEndsInEitherCompletionOrder() async throws {
        for cached in [false, true] {
            for oldFinishesFirst in [false, true] {
                let environment = try TeamFixtureEnvironment(scenario: .content)
                let coordinator = environment.makeCoordinator(), model = TeamScreenModel(coordinator)
                let oldDetail = environment.service.currentDetail, fresh = try changedDetail()
                if cached { await model.run { await coordinator.loadTeams() } }
                let oldGate = gate("departing list"), newGate = gate("returning list")
                environment.service.beforeRead = { await oldGate.pause() }
                let old = Task { await model.run { await coordinator.loadTeams() } }
                await fulfillment(of: [oldGate.entered], timeout: 2)
                model.leave()
                XCTAssertFalse(model.running); XCTAssertFalse(coordinator.loading)
                environment.service.beforeRead = { await newGate.pause() }
                let current = Task { await model.run { await coordinator.loadTeams() } }
                await fulfillment(of: [newGate.entered], timeout: 2)
                XCTAssertTrue(model.running); XCTAssertTrue(model.actionLocked)
                if oldFinishesFirst {
                    oldGate.finish(); await old.value
                    XCTAssertTrue(model.running); XCTAssertTrue(coordinator.loading)
                    XCTAssertEqual(coordinator.teams, cached ? [oldDetail.team] : [])
                }
                environment.service.currentDetail = fresh
                newGate.finish(); await current.value
                XCTAssertFalse(model.running); XCTAssertFalse(coordinator.loading)
                XCTAssertEqual(coordinator.teams, [fresh.team]); XCTAssertNil(coordinator.messageKey)
                if !oldFinishesFirst {
                    environment.service.currentDetail = oldDetail
                    oldGate.finish(); await old.value
                    XCTAssertEqual(coordinator.teams, [fresh.team]); XCTAssertFalse(model.running)
                }
                XCTAssertTrue(environment.service.submissions.isEmpty)
            }
        }
    }

    func testOldFailureCannotClearReturningReadOrPublishAnError() async throws {
        let environment = try TeamFixtureEnvironment(scenario: .retry)
        let coordinator = environment.makeCoordinator(), model = TeamScreenModel(coordinator)
        let oldGate = gate("old failing read"), newGate = gate("fresh read")
        environment.service.beforeRead = { await oldGate.pause() }
        let old = Task { await model.run { await coordinator.loadTeams() } }
        await fulfillment(of: [oldGate.entered], timeout: 2)
        model.leave()
        environment.service.beforeRead = { await newGate.pause() }
        let current = Task { await model.run { await coordinator.loadTeams() } }
        await fulfillment(of: [newGate.entered], timeout: 2)
        oldGate.finish(); await old.value // The fixture's first completed read fails.
        XCTAssertTrue(model.running); XCTAssertTrue(coordinator.loading)
        XCTAssertNil(coordinator.messageKey)
        newGate.finish(); await current.value
        XCTAssertFalse(model.running); XCTAssertEqual(coordinator.teams.count, 1)
        XCTAssertNil(coordinator.messageKey)
    }

    func testCurrentFailureStaysVisibleAfterOldSuccessAndExplicitRetryRecovers() async throws {
        let environment = try TeamFixtureEnvironment(scenario: .retry)
        let coordinator = environment.makeCoordinator(), model = TeamScreenModel(coordinator)
        let oldGate = gate("old successful read"), newGate = gate("current failing read")
        environment.service.beforeRead = { await oldGate.pause() }
        let old = Task { await model.run { await coordinator.loadTeams() } }
        await fulfillment(of: [oldGate.entered], timeout: 2)
        model.leave()
        environment.service.beforeRead = { await newGate.pause() }
        let current = Task { await model.run { await coordinator.loadTeams() } }
        await fulfillment(of: [newGate.entered], timeout: 2)
        newGate.finish(); await current.value
        XCTAssertFalse(model.running); XCTAssertEqual(coordinator.messageKey, "team.loadFailed")
        oldGate.finish(); await old.value
        XCTAssertTrue(coordinator.teams.isEmpty); XCTAssertEqual(coordinator.messageKey, "team.loadFailed")
        environment.service.beforeRead = nil
        await model.run { await coordinator.loadTeams() }
        XCTAssertEqual(coordinator.teams.count, 1); XCTAssertNil(coordinator.messageKey)
        XCTAssertFalse(model.running); XCTAssertTrue(environment.service.submissions.isEmpty)
    }

    func testDetailReadOnlyContinuationAndCreationUseTheSameReturnGuard() async throws {
        for route in ["detail", "readOnly", "creation"] {
            let environment = try TeamFixtureEnvironment(scenario: .content)
            let coordinator = environment.makeCoordinator(), model = TeamScreenModel(coordinator)
            let oldGate = gate("old \(route)"), newGate = gate("new \(route)")
            let read: () async -> Void = {
                if route == "creation" { await coordinator.loadCreation(ownerID: 5101) }
                else if route == "readOnly" { await coordinator.loadPostJoinDetail(teamID: 4101) }
                else { await coordinator.loadDetail(.id(4101), requireMembership: true) }
            }
            environment.service.beforeRead = { await oldGate.pause() }
            let old = Task { await model.run(read) }
            await fulfillment(of: [oldGate.entered], timeout: 2)
            model.leave()
            environment.service.beforeRead = { await newGate.pause() }
            let current = Task { await model.run(read) }
            await fulfillment(of: [newGate.entered], timeout: 2)
            oldGate.finish(); await old.value
            XCTAssertTrue(model.running); XCTAssertTrue(model.actionLocked)
            XCTAssertNil(coordinator.detail); XCTAssertNil(coordinator.creation)
            newGate.finish(); await current.value
            XCTAssertFalse(model.running)
            if route == "creation" { XCTAssertEqual(coordinator.creation, TeamSyntheticFixtures.creation) }
            else { XCTAssertEqual(coordinator.detail?.team.id, 4101) }
            if route == "readOnly" {
                model.prepare(.leave(teamID: 4101)); XCTAssertNil(coordinator.review)
            }
            XCTAssertTrue(environment.service.submissions.isEmpty)
        }
    }

    func testTwoRapidReturnsKeepTheNewestRunLockedUntilItsOwnCompletion() async throws {
        let environment = try TeamFixtureEnvironment(scenario: .content)
        let coordinator = environment.makeCoordinator(), model = TeamScreenModel(coordinator)
        let firstGate = gate("first"), secondGate = gate("second"), thirdGate = gate("third")
        environment.service.beforeRead = { await firstGate.pause() }
        let first = Task { await model.run { await coordinator.loadTeams() } }
        await fulfillment(of: [firstGate.entered], timeout: 2); model.leave()
        environment.service.beforeRead = { await secondGate.pause() }
        let second = Task { await model.run { await coordinator.loadTeams() } }
        await fulfillment(of: [secondGate.entered], timeout: 2); model.leave()
        environment.service.beforeRead = { await thirdGate.pause() }
        let third = Task { await model.run { await coordinator.loadTeams() } }
        await fulfillment(of: [thirdGate.entered], timeout: 2)
        secondGate.finish(); await second.value
        firstGate.finish(); await first.value
        XCTAssertTrue(model.running); XCTAssertTrue(coordinator.loading); XCTAssertTrue(coordinator.teams.isEmpty)
        thirdGate.finish(); await third.value
        XCTAssertFalse(model.running); XCTAssertEqual(coordinator.teams.count, 1)
    }

    func testDuplicateRunIsSuppressedOnlyWithinTheCurrentPresentation() async throws {
        let environment = try TeamFixtureEnvironment(scenario: .content)
        let coordinator = environment.makeCoordinator(), model = TeamScreenModel(coordinator)
        let paused = gate("current read")
        environment.service.beforeRead = { await paused.pause() }
        let task = Task { await model.run { await coordinator.loadTeams() } }
        await fulfillment(of: [paused.entered], timeout: 2)
        var duplicateCalls = 0
        await model.run { duplicateCalls += 1 }
        XCTAssertEqual(duplicateCalls, 0); XCTAssertTrue(model.running)
        paused.finish(); await task.value
        await model.run { duplicateCalls += 1 }
        XCTAssertEqual(duplicateCalls, 1); XCTAssertFalse(model.running)
    }

    func testCanceledCallerCannotStartANewRunAfterLeaving() async throws {
        let environment = try TeamFixtureEnvironment(scenario: .content)
        let model = TeamScreenModel(environment.makeCoordinator()), paused = gate("canceled caller")
        var calls = 0
        let task = Task {
            await paused.pause()
            await model.run { calls += 1 }
        }
        await fulfillment(of: [paused.entered], timeout: 2)
        task.cancel(); model.leave(); paused.finish(); await task.value
        XCTAssertEqual(calls, 0); XCTAssertFalse(model.running)
        await model.run { calls += 1 }
        XCTAssertEqual(calls, 1)
    }

    func testQueuedGesturePermitCannotStartAfterLeaveOrUnlockTheReturningRead() async throws {
        let environment = try TeamFixtureEnvironment(scenario: .content)
        let coordinator = environment.makeCoordinator(), model = TeamScreenModel(coordinator)
        let permit = model.captureRun(), queuedGate = gate("queued refresh"), currentGate = gate("return read")
        var queuedCalls = 0
        let queued = Task {
            await queuedGate.pause() // Simulate a gesture Task that has not entered run.
            return await model.run(permit: permit) { queuedCalls += 1; await coordinator.loadTeams() }
        }
        await fulfillment(of: [queuedGate.entered], timeout: 2)
        model.leave()
        environment.service.beforeRead = { await currentGate.pause() }
        let current = Task { await model.run { await coordinator.loadTeams() } }
        await fulfillment(of: [currentGate.entered], timeout: 2)
        queuedGate.finish(); let admitted = await queued.value
        XCTAssertFalse(admitted); XCTAssertEqual(queuedCalls, 0)
        XCTAssertTrue(model.running); XCTAssertTrue(coordinator.loading)
        currentGate.finish(); let completed = await current.value
        XCTAssertTrue(completed); XCTAssertFalse(model.running); XCTAssertEqual(coordinator.teams.count, 1)
        // The retired permit also stays invalid after the new run is finished.
        let late = await model.run(permit: permit) { queuedCalls += 1 }
        XCTAssertFalse(late); XCTAssertEqual(queuedCalls, 0)
    }

    func testQueuedConfirmationCannotConsumeOrDismissTheReturningReview() async throws {
        let environment = try TeamFixtureEnvironment(scenario: .content)
        let coordinator = environment.makeCoordinator(), model = TeamScreenModel(coordinator)
        await model.run { await coordinator.loadDetail(.id(4101)) }
        model.prepare(.leave(teamID: 4101))
        let oldReview = try XCTUnwrap(coordinator.review), oldPermit = model.captureRun()
        model.leave()
        await model.run { await coordinator.loadDetail(.id(4101)) }
        model.prepare(.leave(teamID: 4101)); let freshReview = try XCTUnwrap(coordinator.review)
        let shouldDismiss = await model.run(permit: oldPermit) { await coordinator.confirm(oldReview) }
        XCTAssertFalse(shouldDismiss); XCTAssertEqual(coordinator.review, freshReview)
        XCTAssertTrue(environment.service.submissions.isEmpty); XCTAssertTrue(environment.journal.records.isEmpty)
    }

    func testQueuedOutcomeCheckCannotClearUnknownButNewExplicitCheckCan() async throws {
        let environment = try TeamFixtureEnvironment(scenario: .unknownOutcome)
        let coordinator = environment.makeCoordinator(), model = TeamScreenModel(coordinator)
        await model.run { await coordinator.loadDetail(.id(4101)) }
        model.prepare(.leave(teamID: 4101)); let review = try XCTUnwrap(coordinator.review)
        await model.run { await coordinator.confirm(review) }
        let originalPending = try XCTUnwrap(coordinator.pending), oldPermit = model.captureRun()
        environment.service.outcomes[review.id] = .simulated(operationID: review.id, teamID: 4101)
        model.leave()
        await model.run { await coordinator.loadDetail(.id(4101)) }
        let oldCheck = await model.run(permit: oldPermit) { await coordinator.checkOutcome() }
        XCTAssertFalse(oldCheck); XCTAssertEqual(coordinator.pending, originalPending)
        XCTAssertEqual(environment.journal.records.count, 1)
        let currentCheck = await model.run(permit: model.captureRun()) { await coordinator.checkOutcome() }
        XCTAssertTrue(currentCheck); XCTAssertNil(coordinator.pending); XCTAssertTrue(environment.journal.records.isEmpty)
        XCTAssertEqual(environment.service.submissions, [review.id])
    }

    func testAccountChangeOnReturnStillDiscardsTheOldRead() async throws {
        let environment = try TeamFixtureEnvironment(scenario: .content)
        let coordinator = environment.makeCoordinator(), model = TeamScreenModel(coordinator)
        let oldDetail = environment.service.currentDetail, fresh = try changedDetail()
        let paused = gate("previous account read")
        environment.service.beforeRead = { await paused.pause() }
        let old = Task { await model.run { await coordinator.loadTeams() } }
        await fulfillment(of: [paused.entered], timeout: 2)
        model.leave(); environment.switchAccount()
        environment.service.beforeRead = nil; environment.service.currentDetail = fresh
        await model.run { await coordinator.loadTeams() }
        XCTAssertEqual(coordinator.teams, [fresh.team])
        environment.service.currentDetail = oldDetail; paused.finish(); await old.value
        XCTAssertEqual(coordinator.teams, [fresh.team]); XCTAssertFalse(model.running)
    }

    func testLeavingDuringPreflightAllowsFreshReadWithoutSubmittingOldReview() async throws {
        let environment = try TeamFixtureEnvironment(scenario: .content)
        let coordinator = environment.makeCoordinator(), model = TeamScreenModel(coordinator)
        await model.run { await coordinator.loadDetail(.id(4101)) }
        model.prepare(.leave(teamID: 4101)); let review = try XCTUnwrap(coordinator.review)
        let paused = gate("write preflight")
        environment.service.beforeRead = { await paused.pause() }
        let old = Task { await model.run { await coordinator.confirm(review) } }
        await fulfillment(of: [paused.entered], timeout: 2)
        model.leave(); environment.service.beforeRead = nil
        await model.run { await coordinator.loadDetail(.id(4101)) }
        XCTAssertEqual(coordinator.detail?.team.id, 4101)
        paused.finish(); await old.value
        XCTAssertNil(coordinator.review); XCTAssertTrue(environment.service.submissions.isEmpty)
        XCTAssertTrue(environment.journal.records.isEmpty); XCTAssertFalse(model.running)
    }

    func testLeavingAfterDispatchKeepsUnknownLockWhileReturnReadCompletes() async throws {
        let environment = try TeamFixtureEnvironment(scenario: .content)
        let coordinator = environment.makeCoordinator(), model = TeamScreenModel(coordinator)
        await model.run { await coordinator.loadDetail(.id(4101)) }
        model.prepare(.leave(teamID: 4101)); let review = try XCTUnwrap(coordinator.review)
        let paused = gate("dispatched write")
        environment.service.beforeSubmit = { await paused.pause() }
        let old = Task { await model.run { await coordinator.confirm(review) } }
        await fulfillment(of: [paused.entered], timeout: 2)
        let originalPending = coordinator.pending
        XCTAssertNotNil(originalPending)
        model.leave()
        XCTAssertEqual(coordinator.writeState, .unknown); XCTAssertFalse(model.running)
        await model.run { await coordinator.loadDetail(.id(4101)) }
        XCTAssertEqual(coordinator.pending, originalPending); XCTAssertTrue(model.actionLocked)
        paused.finish(); await old.value
        XCTAssertEqual(coordinator.pending, originalPending); XCTAssertEqual(coordinator.writeState, .unknown)
        XCTAssertEqual(environment.journal.records.count, 1); XCTAssertEqual(environment.service.submissions, [review.id])
        model.prepare(.leave(teamID: 4101)); XCTAssertNil(coordinator.review)
        await model.run { await coordinator.confirm(review) }
        XCTAssertEqual(environment.service.submissions, [review.id]); XCTAssertTrue(model.actionLocked)
    }
}
