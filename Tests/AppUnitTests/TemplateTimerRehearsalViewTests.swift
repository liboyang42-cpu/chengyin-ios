import XCTest
@testable import Questify

@MainActor final class TemplateTimerRehearsalViewTests: XCTestCase {
    private final class Clock { var now = 0.0 }
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
        // Intentionally fire cancelled jobs to prove generation fences, not just cancellation.
        func fire(_ index: Int) { jobs[index].tick() }
    }
    private func setup(_ kind: TemplateTimerRehearsal.Kind = .stopwatch, mode: TemplateTimerRehearsal.Mode = .sourceExample) throws -> (TemplateAuthoringModel, TemplateTimerRehearsalController, Clock, Scheduler, Owner) {
        let owner = Owner(try .init(accountID: 999, namespace: "timer-rehearsal", epoch: 1, authorizationRevision: "member"))
        let model = TemplateAuthoringModel(coordinator: .init(store: .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { owner.session }))
        model.load(); model.draft.title = "Keep original"; model.changed()
        let clock = Clock(), scheduler = Scheduler()
        let controller = TemplateTimerRehearsalController(model: model, kind: kind, mode: mode, clock: { clock.now }, scheduler: scheduler)
        controller.viewAppeared(sceneIsActive: true); return (model, controller, clock, scheduler, owner)
    }
    func testDelayedCountdownUsesClockAndLeavesDraftAndStorageExact() throws {
        let (model, controller, clock, scheduler, _) = try setup(.countdown), before = model.draft, stored = model.coordinator.draft
        controller.action(.start)(); clock.now = 90600; scheduler.fire(0)
        XCTAssertEqual(controller.visibleState?.phase, .finished); XCTAssertTrue(scheduler.jobs[0].cancelled)
        XCTAssertEqual(model.draft, before); XCTAssertEqual(model.coordinator.draft, stored); XCTAssertNil(model.review)
    }
    func testBothKindsUseSourceTickIntervals() throws {
        for (kind, interval) in [(TemplateTimerRehearsal.Kind.countdown, 1.0), (.stopwatch, 0.05)] {
            let (_, controller, _, scheduler, _) = try setup(kind); controller.action(.start)(); XCTAssertEqual(scheduler.jobs[0].interval, interval)
        }
    }
    func testQueuedOldTickCannotModifyResetAndNewRun() throws {
        let (_, controller, clock, scheduler, _) = try setup(); controller.action(.start)(); controller.action(.reset)()
        clock.now = 1000; controller.action(.start)(); clock.now = 90000; scheduler.fire(0)
        XCTAssertTrue(scheduler.jobs[0].cancelled); XCTAssertEqual(controller.visibleState?.phase, .running); XCTAssertEqual(controller.visibleState?.elapsedMs, 0)
    }
    func testPauseResumeCancelsOldTicksAndExcludesPausedTime() throws {
        let (_, controller, clock, scheduler, _) = try setup(); controller.action(.start)(); clock.now = 1500; controller.action(.pauseResume)()
        XCTAssertEqual(controller.visibleState?.phase, .paused); XCTAssertTrue(scheduler.jobs[0].cancelled)
        clock.now = 20000; scheduler.fire(0); XCTAssertEqual(controller.visibleState?.elapsedMs, 1500)
        controller.action(.pauseResume)(); clock.now = 21000; scheduler.fire(0); XCTAssertEqual(controller.visibleState?.elapsedMs, 1500)
        scheduler.fire(1); XCTAssertEqual(controller.visibleState?.elapsedMs, 2500)
    }
    func testStaleStartAndStopCallbacksCannotCrossPauseOrReset() throws {
        let (_, controller, clock, _, _) = try setup(), start = controller.action(.start); start()
        let stop = controller.action(.stop); clock.now = 1500; controller.action(.pauseResume)(); stop()
        XCTAssertEqual(controller.visibleState?.phase, .paused); controller.action(.reset)(); start(); XCTAssertEqual(controller.visibleState?.phase, .ready)
    }
    func testAutoFinishCancelsTickAndStaleTickCannotRestart() throws {
        let (_, controller, clock, scheduler, _) = try setup(.countdown); controller.action(.start)(); clock.now = 90000; scheduler.fire(0)
        XCTAssertEqual(controller.visibleState?.phase, .finished); clock.now = 180000; scheduler.fire(0); XCTAssertEqual(controller.visibleState?.phase, .finished)
        XCTAssertEqual(controller.visibleState?.elapsedMs, 90000)
    }
    func testConfigEditRetiresAndOldTickCannotTouchReloadedValues() throws {
        let (model, controller, clock, scheduler, _) = try setup(); controller.action(.start)()
        model.draft.advanced.set("stopwatch", "targetSeconds", .number(15)); XCTAssertNil(controller.visibleState); XCTAssertTrue(scheduler.jobs[0].cancelled)
        controller.reload(); clock.now = 90000; scheduler.fire(0); XCTAssertEqual(controller.visibleState?.targetSeconds, 15); XCTAssertEqual(controller.visibleState?.phase, .ready)
    }
    func testBackgroundRetirementAndForegroundReloadStartFresh() throws {
        let (_, controller, clock, scheduler, _) = try setup(); controller.action(.start)(); clock.now = 1200; scheduler.fire(0)
        controller.retire(); XCTAssertNil(controller.visibleState); XCTAssertTrue(scheduler.jobs[0].cancelled)
        clock.now = 50000; controller.reload(); scheduler.fire(0); XCTAssertEqual(controller.visibleState?.phase, .ready); XCTAssertFalse(controller.visibleState?.isMasked ?? true)
    }
    func testOwnerMismatchHidesStateAndCurrentTickCancelsItself() throws {
        let (_, controller, _, scheduler, owner) = try setup(); controller.action(.start)()
        owner.session = try .init(accountID: 1000, namespace: "timer-rehearsal", epoch: 2, authorizationRevision: "member")
        XCTAssertNil(controller.visibleState); XCTAssertFalse(controller.canReload); scheduler.fire(0); XCTAssertTrue(scheduler.jobs[0].cancelled)
    }
    func testBusyReviewLoadAndLeaveRetireScheduledWork() throws {
        for operation in ["busy", "review", "load", "leave", "changed"] {
            let (model, controller, _, scheduler, _) = try setup(); controller.action(.start)()
            switch operation { case "busy": model.busy = true; case "review": model.prepare(.saveDraft); case "load": model.load(); case "leave": model.leave(); default: model.changed() }
            XCTAssertNil(controller.visibleState, operation); XCTAssertTrue(scheduler.jobs[0].cancelled, operation)
        }
    }
    func testCloseCancelsAndOldCloseCannotDismissReloadedView() throws {
        let (_, controller, _, scheduler, _) = try setup(); controller.action(.start)(); var dismissals = 0
        let close = controller.closeAction { dismissals += 1 }; close(); XCTAssertEqual(dismissals, 1); XCTAssertTrue(scheduler.jobs[0].cancelled)
        controller.reload(); close(); XCTAssertEqual(dismissals, 1); XCTAssertNotNil(controller.visibleState)
    }
    func testDraftABACannotReviveOldStartOrOldTick() throws {
        let (model, controller, clock, scheduler, _) = try setup(), before = model.draft, start = controller.action(.start)
        start(); model.draft.title = "Changed"; model.draft = before; controller.reload(); start(); clock.now = 20000; scheduler.fire(0)
        XCTAssertEqual(controller.visibleState?.phase, .ready); XCTAssertEqual(controller.visibleState?.elapsedMs, 0)
    }
    func testInvalidCurrentConfigurationDoesNotInventSourceDoneText() throws {
        let (model, controller, _, scheduler, _) = try setup(.countdown, mode: .currentConfiguration), before = model.draft
        XCTAssertNil(controller.visibleState); controller.action(.start)(); XCTAssertTrue(scheduler.jobs.isEmpty); XCTAssertEqual(model.draft, before)
    }
    func testLocalStopwatchReadoutNeverPreparesOrWritesGameplay() throws {
        let (model, controller, clock, scheduler, _) = try setup(), before = model.draft, stored = model.coordinator.draft
        controller.action(.start)(); clock.now = 10000; controller.action(.stop)()
        XCTAssertEqual(controller.visibleState?.result?.matched, true); XCTAssertTrue(scheduler.jobs[0].cancelled)
        XCTAssertEqual(model.draft, before); XCTAssertEqual(model.coordinator.draft, stored); XCTAssertNil(model.review)
    }
    func testSampleModeDoesNotEnableOrCopyDemoIntoOriginal() throws {
        let (model, controller, _, _, _) = try setup(.countdown)
        XCTAssertEqual(controller.visibleState?.doneText, "时间到。"); XCTAssertEqual(model.draft.advanced.text("countdown", "doneText"), "")
        XCTAssertFalse(model.draft.advanced.enabled("countdown"))
    }
    func testTimeoutAndBackwardClockCancelCurrentAndQueuedTicks() throws {
        for time in [40001.0, -1.0] {
            let (_, controller, clock, scheduler, _) = try setup(); controller.action(.start)(); clock.now = time; scheduler.fire(0)
            XCTAssertEqual(controller.visibleState?.phase, .aborted); XCTAssertTrue(scheduler.jobs[0].cancelled)
            controller.action(.reset)(); scheduler.fire(0); XCTAssertEqual(controller.visibleState?.phase, .ready)
        }
    }
    func testHiddenForegroundCannotReloadOrRunOldActionAndClose() throws {
        let (model, controller, _, _, _) = try setup(), before = model.draft
        let oldAction = controller.action(.start); var dismissals = 0
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
        let (model, controller, _, _, _) = try setup(), before = model.draft, oldAction = controller.action(.start)
        controller.viewDisappeared(); controller.viewAppeared(sceneIsActive: false)
        controller.reload(); oldAction()
        XCTAssertTrue(controller.isVisible); XCTAssertFalse(controller.canReload); XCTAssertNil(controller.visibleState)
        controller.sceneChanged(isActive: true); oldAction()
        XCTAssertTrue(controller.canReload); XCTAssertNotNil(controller.visibleState); XCTAssertEqual(model.draft, before)
    }
    func testRepeatedVisibleAppearanceKeepsCurrentStateAndGeneration() throws {
        let (model, controller, clock, scheduler, _) = try setup()
        controller.action(.start)()
        let visible = controller.visibleState, draft = model.draft
        XCTAssertNotNil(visible)
        controller.viewAppeared(sceneIsActive: true); controller.sceneChanged(isActive: true)
        XCTAssertEqual(controller.visibleState, visible); XCTAssertEqual(model.draft, draft)
        XCTAssertEqual(scheduler.jobs.count, 1)
        controller.viewDisappeared(); XCTAssertTrue(scheduler.jobs[0].cancelled)
        controller.sceneChanged(isActive: true); scheduler.fire(0)
        XCTAssertNil(controller.visibleState); XCTAssertFalse(controller.canReload)
        controller.viewAppeared(sceneIsActive: true); controller.action(.start)()
        clock.now = 5000; scheduler.fire(0)
        XCTAssertEqual(controller.visibleState?.phase, .running); XCTAssertEqual(scheduler.jobs.count, 2)
    }

}
