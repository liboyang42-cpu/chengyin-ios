import XCTest
@testable import Questify

@MainActor final class TemplateReactionRehearsalViewTests: XCTestCase {
    private final class Clock { var now = 0.0; var unit = 0.0; var draws = 0 }
    private final class Owner {
        var session: TemplateAuthoringSession?
        init(_ value: TemplateAuthoringSession) { session = value }
    }
    private final class Scheduler: TemplateTimerRehearsalScheduler {
        struct Job { let interval: Double; let tick: @MainActor () -> Void; var cancelled = false }
        var jobs: [Job] = []
        func schedule(interval: TimeInterval, tick: @escaping @MainActor () -> Void) -> TemplateTimerCancellation {
            let index = jobs.count; jobs.append(.init(interval: interval, tick: tick))
            return { [weak self] in self?.jobs[index].cancelled = true }
        }
        // Fire cancelled jobs deliberately: cancellation alone is insufficient.
        func fire(_ index: Int) { jobs[index].tick() }
    }
    private func setup(mode: TemplateReactionRehearsal.Mode = .sourceExample) throws -> (TemplateAuthoringModel, TemplateReactionRehearsalController, Clock, Scheduler, Owner) {
        let owner = Owner(try .init(accountID: 999, namespace: "reaction-rehearsal", epoch: 1, authorizationRevision: "member"))
        let model = TemplateAuthoringModel(coordinator: .init(store: .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { owner.session }))
        model.load(); model.draft.title = "Keep original"; model.changed()
        let clock = Clock(), scheduler = Scheduler()
        let controller = TemplateReactionRehearsalController(model: model, mode: mode, clock: { clock.now }, delayUnit: { clock.draws += 1; return clock.unit }, scheduler: scheduler)
        controller.viewAppeared(sceneIsActive: true); return (model, controller, clock, scheduler, owner)
    }
    func testCurrentAndSampleModesDoNotWriteDraftOrStorage() throws {
        for mode in [TemplateReactionRehearsal.Mode.currentConfiguration, .sourceExample] {
            let (model, controller, clock, scheduler, _) = try setup(mode: mode), before = model.draft, stored = model.coordinator.draft
            controller.action(.tap)(); clock.now = 1400; scheduler.fire(0); clock.now = 1600; controller.action(.tap)(); controller.action(.reset)()
            XCTAssertEqual(model.draft, before); XCTAssertEqual(model.coordinator.draft, stored); XCTAssertNil(model.review)
        }
    }
    func testDelayInjectionUsesOneDrawPerArmAndReusesTimerScheduler() throws {
        let (_, controller, clock, scheduler, _) = try setup(); clock.unit = 1; controller.action(.tap)()
        XCTAssertEqual(scheduler.jobs[0].interval, 4.2); XCTAssertEqual(clock.draws, 1)
        clock.now = 4200; scheduler.fire(0); clock.now = 4500; controller.action(.tap)(); XCTAssertEqual(clock.draws, 1)
        controller.action(.tap)(); XCTAssertEqual(clock.draws, 2)
    }
    func testEarlyCallbackReschedulesRemainingAndOldJobCannotSignal() throws {
        let (_, controller, clock, scheduler, _) = try setup(); controller.action(.tap)(); clock.now = 1000; scheduler.fire(0)
        XCTAssertTrue(scheduler.jobs[0].cancelled); XCTAssertEqual(scheduler.jobs[1].interval, 0.4); XCTAssertEqual(controller.visibleState?.phase, .waiting)
        clock.now = 1400; scheduler.fire(0); XCTAssertEqual(controller.visibleState?.phase, .waiting)
        scheduler.fire(1); XCTAssertEqual(controller.visibleState?.phase, .signal); XCTAssertTrue(scheduler.jobs[1].cancelled)
    }
    func testLateCallbackMeasuresFromActualSignalAndDuplicateCannotReanchor() throws {
        let (_, controller, clock, scheduler, _) = try setup(); controller.action(.tap)(); clock.now = 10000; scheduler.fire(0)
        clock.now = 10120; scheduler.fire(0); controller.action(.tap)(); XCTAssertEqual(controller.visibleState?.times, [120])
    }
    func testEarlyTapCancelsWaitAndOldCallbackCannotAffectRetry() throws {
        let (_, controller, clock, scheduler, _) = try setup(); controller.action(.tap)(); clock.now = 100; controller.action(.tap)()
        XCTAssertEqual(controller.visibleState?.earlyReason, .beforeSignal); XCTAssertTrue(scheduler.jobs[0].cancelled)
        clock.now = 200; controller.action(.tap)(); clock.now = 5000; scheduler.fire(0); XCTAssertEqual(controller.visibleState?.phase, .waiting)
        scheduler.fire(1); XCTAssertEqual(controller.visibleState?.phase, .signal)
    }
    func testStaleWaitingTapCannotBecomeAcceptedSignalTap() throws {
        let (_, controller, clock, scheduler, _) = try setup(); controller.action(.tap)(); let oldTap = controller.action(.tap)
        clock.now = 1400; scheduler.fire(0); clock.now = 1600; oldTap(); XCTAssertTrue(controller.visibleState?.times.isEmpty == true)
        controller.action(.tap)(); XCTAssertEqual(controller.visibleState?.times, [200])
    }
    func testTooFastRetriesKeepValidRoundHistory() throws {
        let (_, controller, clock, scheduler, _) = try setup(); controller.action(.tap)(); clock.now = 1400; scheduler.fire(0); clock.now = 1700; controller.action(.tap)()
        controller.action(.tap)(); clock.now = 3100; scheduler.fire(1); clock.now = 3219; controller.action(.tap)()
        XCTAssertEqual(controller.visibleState?.phase, .early); XCTAssertEqual(controller.visibleState?.times, [300]); XCTAssertEqual(controller.visibleState?.round, 2)
    }
    func testResetWhileWaitingFencesOldWaitAndOldTap() throws {
        let (_, controller, clock, scheduler, _) = try setup(); controller.action(.tap)(); let oldTap = controller.action(.tap)
        controller.action(.reset)(); controller.action(.tap)(); clock.now = 9000; scheduler.fire(0); oldTap()
        XCTAssertEqual(controller.visibleState?.phase, .waiting); XCTAssertTrue(controller.visibleState?.times.isEmpty == true)
        scheduler.fire(1); XCTAssertEqual(controller.visibleState?.phase, .signal)
    }
    func testResetWhileSignalClearsMeasurementsAndOldCallback() throws {
        let (_, controller, clock, scheduler, _) = try setup(); controller.action(.tap)(); clock.now = 1400; scheduler.fire(0)
        let oldTap = controller.action(.tap); controller.action(.reset)(); clock.now = 1700; oldTap(); scheduler.fire(0)
        XCTAssertEqual(controller.visibleState?.phase, .idle); XCTAssertTrue(controller.visibleState?.times.isEmpty == true)
    }
    func testDraftABARetiresAndOldCallbackCannotRetireFreshLease() throws {
        let (model, controller, clock, scheduler, _) = try setup(); let old = model.draft; controller.action(.tap)()
        model.draft.advanced.set("reaction", "kicker", .string("New title")); model.draft = old
        XCTAssertNil(controller.visibleState); controller.reload(); controller.action(.tap)(); clock.now = 5000; scheduler.fire(0)
        XCTAssertEqual(controller.visibleState?.phase, .waiting); scheduler.fire(1); XCTAssertEqual(controller.visibleState?.phase, .signal)
    }
    func testChangedConfigurationReloadsOnlyNewValues() throws {
        let (model, controller, _, _, _) = try setup(); model.draft.advanced.set("reaction", "rounds", .number(1)); model.draft.advanced.set("reaction", "goalMs", .number(500))
        XCTAssertNil(controller.visibleState); controller.reload(); XCTAssertEqual(controller.visibleState?.rounds, 1); XCTAssertEqual(controller.visibleState?.goalMs, 500)
    }
    func testOutOfSourceRangeDoesNotInventSampleFallback() throws {
        let (model, controller, _, _, _) = try setup(); model.draft.advanced.set("reaction", "goalMs", .number(3000)); controller.reload()
        XCTAssertNil(controller.visibleState); XCTAssertEqual(model.draft.advanced.text("reaction", "goalMs"), "3000")
    }
    func testRetireBackgroundAndReentryDiscardPartialRunAndQueuedWait() throws {
        let (_, controller, clock, scheduler, _) = try setup(); controller.action(.tap)(); clock.now = 1400; scheduler.fire(0); clock.now = 1700; controller.action(.tap)()
        controller.action(.tap)(); controller.retire(); XCTAssertNil(controller.visibleState); XCTAssertTrue(scheduler.jobs[1].cancelled)
        controller.reload(); controller.action(.tap)(); clock.now = 10000; scheduler.fire(1)
        XCTAssertEqual(controller.visibleState?.phase, .waiting); XCTAssertTrue(controller.visibleState?.times.isEmpty == true)
        scheduler.fire(2); XCTAssertEqual(controller.visibleState?.phase, .signal)
    }
    func testOwnerSwitchRejectsScheduledAndUserCallbacks() throws {
        let (_, controller, clock, scheduler, owner) = try setup(); controller.action(.tap)(); let tap = controller.action(.tap)
        owner.session = try .init(accountID: 1000, namespace: "reaction-rehearsal", epoch: 2, authorizationRevision: "member")
        clock.now = 2000; scheduler.fire(0); tap(); XCTAssertNil(controller.visibleState); XCTAssertTrue(scheduler.jobs[0].cancelled)
    }
    func testBusyAndMetadataChangesInvalidateLease() throws {
        let (model, controller, clock, scheduler, _) = try setup(); controller.action(.tap)(); model.busy = true
        clock.now = 2000; scheduler.fire(0); XCTAssertNil(controller.visibleState); model.busy = false; controller.reload()
        model.changed(); XCTAssertNil(controller.visibleState)
    }
    func testCloseCancelsPendingWaitAndCannotDismissFreshReentry() throws {
        let (_, controller, clock, scheduler, _) = try setup(); controller.action(.tap)(); var closes = 0
        let close = controller.closeAction { closes += 1 }; close(); XCTAssertEqual(closes, 1); XCTAssertNil(controller.visibleState)
        controller.reload(); controller.action(.tap)(); clock.now = 10000; close(); scheduler.fire(0)
        XCTAssertEqual(closes, 1); XCTAssertEqual(controller.visibleState?.phase, .waiting); XCTAssertTrue(scheduler.jobs[0].cancelled)
    }
    func testBackwardsCallbackAbortsAndCancelsWithoutAReading() throws {
        let (_, controller, clock, scheduler, _) = try setup(); clock.now = 100; controller.action(.tap)(); clock.now = 99; scheduler.fire(0)
        XCTAssertEqual(controller.visibleState?.phase, .aborted); XCTAssertTrue(scheduler.jobs[0].cancelled); XCTAssertTrue(controller.visibleState?.times.isEmpty == true)
    }
    func testInvalidDelayNeverSchedulesAndResetAllowsFreshAttempt() throws {
        let (_, controller, clock, scheduler, _) = try setup(); clock.unit = .nan; controller.action(.tap)()
        XCTAssertEqual(controller.visibleState?.phase, .aborted); XCTAssertTrue(scheduler.jobs.isEmpty)
        controller.action(.reset)(); clock.unit = 0; controller.action(.tap)(); XCTAssertEqual(scheduler.jobs.count, 1)
    }
    func testOneRoundDoneCannotScheduleAgainUntilExplicitReset() throws {
        let (model, controller, clock, scheduler, _) = try setup(); model.draft.advanced.set("reaction", "rounds", .number(1)); controller.reload()
        controller.action(.tap)(); clock.now = 1400; scheduler.fire(0); clock.now = 1720; controller.action(.tap)()
        XCTAssertEqual(controller.visibleState?.matched, true); controller.action(.tap)(); XCTAssertEqual(scheduler.jobs.count, 1)
        controller.action(.reset)(); controller.action(.tap)(); XCTAssertEqual(scheduler.jobs.count, 2)
    }
    func testOldResetCannotClearFreshAcceptedResult() throws {
        let (_, controller, clock, scheduler, _) = try setup(); let oldReset = controller.action(.reset)
        controller.action(.tap)(); clock.now = 1400; scheduler.fire(0); clock.now = 1600; controller.action(.tap)(); oldReset()
        XCTAssertEqual(controller.visibleState?.times, [200])
    }
    func testHiddenForegroundCannotReloadOrRunOldActionAndClose() throws {
        let (model, controller, _, _, _) = try setup(), before = model.draft
        let oldAction = controller.action(.tap); var dismissals = 0
        let oldClose = controller.closeAction { dismissals += 1 }
        controller.viewDisappeared(); controller.sceneChanged(isActive: false); controller.sceneChanged(isActive: true)
        controller.reload(); oldAction(); oldClose()
        XCTAssertFalse(controller.isVisible); XCTAssertFalse(controller.canReload); XCTAssertNil(controller.visibleState)
        XCTAssertEqual(model.draft, before); XCTAssertEqual(dismissals, 0)
        controller.viewAppeared(sceneIsActive: true); oldAction(); oldClose()
        XCTAssertTrue(controller.canReload); XCTAssertNotNil(controller.visibleState)
        XCTAssertEqual(model.draft, before); XCTAssertEqual(dismissals, 0)
    }
    func testInactiveAppearanceWaitsForForegroundAndRejectsOldAction() throws {
        let (model, controller, _, _, _) = try setup(), before = model.draft, oldAction = controller.action(.tap)
        controller.viewDisappeared(); controller.viewAppeared(sceneIsActive: false)
        controller.reload(); oldAction()
        XCTAssertTrue(controller.isVisible); XCTAssertFalse(controller.canReload); XCTAssertNil(controller.visibleState)
        controller.sceneChanged(isActive: true); oldAction()
        XCTAssertTrue(controller.canReload); XCTAssertNotNil(controller.visibleState); XCTAssertEqual(model.draft, before)
    }
    func testRepeatedVisibleAppearanceKeepsCurrentStateAndGeneration() throws {
        let (model, controller, clock, scheduler, _) = try setup()
        controller.action(.tap)()
        let visible = controller.visibleState, draft = model.draft
        XCTAssertNotNil(visible)
        controller.viewAppeared(sceneIsActive: true); controller.sceneChanged(isActive: true)
        XCTAssertEqual(controller.visibleState, visible); XCTAssertEqual(model.draft, draft)
        XCTAssertEqual(scheduler.jobs.count, 1)
        controller.viewDisappeared(); XCTAssertTrue(scheduler.jobs[0].cancelled)
        controller.sceneChanged(isActive: true); scheduler.fire(0)
        XCTAssertNil(controller.visibleState); XCTAssertFalse(controller.canReload)
        controller.viewAppeared(sceneIsActive: true); controller.action(.tap)()
        clock.now = 5000; scheduler.fire(0)
        XCTAssertEqual(controller.visibleState?.phase, .waiting); XCTAssertEqual(scheduler.jobs.count, 2)
    }

}
