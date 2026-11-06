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

@MainActor final class TemplateTimerOutcomeEditorTests: XCTestCase {
    private final class Owner {
        var session: TemplateAuthoringSession?
        init(_ session: TemplateAuthoringSession) { self.session = session }
    }
    private struct Fixture {
        let model: TemplateAuthoringModel
        let controller: TemplateTimerOutcomeController
        let storage: TemplateAuthoringMemoryStorage
        let store: TemplateAuthoringLocalStore
        let owner: Owner
    }
    private func fixture(appear: Bool = true) throws -> Fixture {
        let owner = Owner(try .init(accountID: 991, namespace: "timeout-editor", epoch: 1, authorizationRevision: "member"))
        let storage = TemplateAuthoringMemoryStorage(), store = TemplateAuthoringLocalStore(storage: storage)
        let model = TemplateAuthoringModel(coordinator: .init(store: store, currentSession: { owner.session }))
        model.load(); model.draft.title = "Local configuration"; model.changed()
        let controller = TemplateTimerOutcomeController(model: model)
        if appear { controller.viewAppeared(sceneIsActive: true) }
        return .init(model: model, controller: controller, storage: storage, store: store, owner: owner)
    }
    func testOpeningUsesCurrentDefaultsWithoutWritingOrReview() throws {
        let f = try fixture()
        XCTAssertEqual(f.controller.visibleDraft?.enabled, false)
        XCTAssertEqual(f.controller.visibleDraft?.seconds, "300")
        XCTAssertEqual(f.controller.visibleDraft?.outcome, "FAILED")
        XCTAssertTrue(f.controller.canSave); XCTAssertTrue(f.storage.values.isEmpty)
        XCTAssertNil(f.model.review); XCTAssertNil(f.model.coordinator.review)
        XCTAssertFalse(f.model.coordinator.canSubmit)
    }
    func testEnabledMustBeAnActualBoolean() {
        for malformed in [TemplateAuthoringJSON.string("false"), .string("true"), .number(0), .number(1), .null, .array([]), .object([:])] {
            var draft = TemplateAdvancedDraft(); draft.set("timer", "enabled", malformed)
            XCTAssertNil(TemplateTimerOutcomeDraft(draft))
        }
        var missing = TemplateAdvancedDraft()
        missing.value["timer"] = .object(["durationSeconds": .number(300), "timeoutResult": .string("FAILED")])
        XCTAssertNil(TemplateTimerOutcomeDraft(missing))
        for enabled in [true, false] {
            var draft = TemplateAdvancedDraft(); draft.set("timer", "enabled", .bool(enabled))
            XCTAssertEqual(TemplateTimerOutcomeDraft(draft)?.enabled, enabled)
        }
    }
    func testDurationBoundsAndMalformedTextAreRejectedWithoutCoercion() throws {
        var draft = try XCTUnwrap(TemplateTimerOutcomeDraft(.init()))
        for invalid in ["", " ", "9", "86401", "-1", "10.0", "1e2", "NaN", "Infinity", "+10", "１０", "99999999999999999999999999999999"] {
            draft.seconds = invalid
            XCTAssertNil(draft.duration, invalid); XCTAssertFalse(draft.isValid, invalid)
            XCTAssertNil(draft.applying(to: .init()), invalid)
        }
        for valid in ["10", "86400", " 300 "] {
            draft.seconds = valid; XCTAssertNotNil(draft.duration, valid); XCTAssertTrue(draft.isValid, valid)
        }
    }
    func testNonfiniteOrNonscalarDurationAndNonstringOutcomeStayUnavailable() {
        for malformed in [TemplateAuthoringJSON.number(.infinity), .number(.nan), .bool(true), .null, .array([]), .object([:])] {
            var draft = TemplateAdvancedDraft(); draft.set("timer", "durationSeconds", malformed)
            XCTAssertNil(TemplateTimerOutcomeDraft(draft))
        }
        for malformed in [TemplateAuthoringJSON.number(0), .bool(false), .null, .array([]), .object([:])] {
            var draft = TemplateAdvancedDraft(); draft.set("timer", "timeoutResult", malformed)
            XCTAssertNil(TemplateTimerOutcomeDraft(draft))
        }
    }
    func testUnknownOutcomeRequiresExplicitChoiceAndNeverChangesOnOpen() throws {
        let f = try fixture(appear: false)
        f.model.draft.advanced.set("timer", "timeoutResult", .string("CUSTOM")); f.model.changed()
        let original = f.model.draft
        f.controller.viewAppeared(sceneIsActive: true)
        XCTAssertEqual(f.controller.visibleDraft?.outcome, "CUSTOM"); XCTAssertFalse(f.controller.canSave)
        f.controller.saveAction()(); XCTAssertEqual(f.model.draft, original); XCTAssertTrue(f.storage.values.isEmpty)
        f.controller.outcomeBinding.wrappedValue = "EXPIRED"
        XCTAssertTrue(f.controller.canSave); XCTAssertEqual(f.model.draft, original)
        f.controller.saveAction()()
        XCTAssertEqual(f.model.draft.advanced.text("timer", "timeoutResult"), "EXPIRED")
        XCTAssertEqual(f.controller.statusKey, "templateAuthor.localSaved")
    }
    func testBothKnownOutcomesPersistThroughTheExistingLocalStore() throws {
        for outcome in TemplateTimerOutcome.allCases {
            let f = try fixture()
            f.controller.enabledBinding.wrappedValue = true
            f.controller.secondsBinding.wrappedValue = "75"
            f.controller.outcomeBinding.wrappedValue = outcome.rawValue
            f.controller.saveAction()()
            let session = try XCTUnwrap(f.owner.session)
            XCTAssertEqual(try f.store.active(session: session), f.model.coordinator.identity)
            guard case .ready(let saved) = f.store.load(session: session, identity: f.model.coordinator.identity) else {
                XCTFail("Expected the explicit local save to be readable"); continue
            }
            XCTAssertEqual(saved.draft, f.model.draft)
            XCTAssertTrue(saved.draft.advanced.enabled("timer"))
            XCTAssertEqual(saved.draft.advanced.value["timer"]?.object?["durationSeconds"], .number(75))
            XCTAssertEqual(saved.draft.advanced.text("timer", "timeoutResult"), outcome.rawValue)
            XCTAssertEqual(f.controller.statusKey, "templateAuthor.localSaved")
            XCTAssertNil(f.model.review); XCTAssertNil(f.model.coordinator.pending)
        }
    }
    func testSavePreservesEveryUnaddressedDraftAndTimerField() throws {
        let f = try fixture(appear: false)
        f.model.draft.description = "Keep this description"
        f.model.draft.advanced.set("timer", "extensionField", .array([.string("keep"), .number(9)]))
        f.model.draft.advanced.value["futureSection"] = .object(["enabled": .bool(true), "unknown": .null])
        f.model.changed(); let original = f.model.draft
        f.controller.viewAppeared(sceneIsActive: true)
        f.controller.enabledBinding.wrappedValue = true
        f.controller.secondsBinding.wrappedValue = "120"
        f.controller.outcomeBinding.wrappedValue = "EXPIRED"
        var expected = original
        expected.advanced.set("timer", "enabled", .bool(true))
        expected.advanced.set("timer", "durationSeconds", .number(120))
        expected.advanced.set("timer", "timeoutResult", .string("EXPIRED"))
        f.controller.saveAction()(); XCTAssertEqual(f.model.draft, expected)
        XCTAssertEqual(f.model.coordinator.draft, expected)
    }
    func testDisabledConfigurationRetainsItsDurationAndOutcome() throws {
        let f = try fixture()
        f.controller.secondsBinding.wrappedValue = "90"; f.controller.outcomeBinding.wrappedValue = "EXPIRED"
        f.controller.saveAction()()
        XCTAssertFalse(f.model.draft.advanced.enabled("timer"))
        XCTAssertEqual(f.model.draft.advanced.text("timer", "durationSeconds"), "90")
        XCTAssertEqual(f.model.draft.advanced.text("timer", "timeoutResult"), "EXPIRED")
    }
    func testNumericTextIsOnlyCanonicalizedByExplicitSave() throws {
        let f = try fixture(appear: false)
        f.model.draft.advanced.set("timer", "durationSeconds", .string(" 60 ")); f.model.changed()
        let original = f.model.draft
        f.controller.viewAppeared(sceneIsActive: true)
        XCTAssertEqual(f.controller.visibleDraft?.seconds, " 60 "); XCTAssertEqual(f.model.draft, original)
        f.controller.saveAction()()
        XCTAssertEqual(f.model.draft.advanced.value["timer"]?.object?["durationSeconds"], .number(60))
    }
    func testStorageFailureNeverClaimsSuccessOrOverwritesPreviousLocalSave() throws {
        let f = try fixture(); f.model.save(); f.controller.reload()
        let stored = f.storage.values
        f.storage.failWrites = true; f.controller.secondsBinding.wrappedValue = "180"
        f.controller.saveAction()()
        XCTAssertEqual(f.storage.values, stored)
        XCTAssertEqual(f.controller.statusKey, "templateAuthor.storageFailed")
        XCTAssertEqual(f.model.draft.advanced.text("timer", "durationSeconds"), "180")
        XCTAssertEqual(f.controller.visibleDraft?.seconds, "180")
        XCTAssertNil(f.model.review); XCTAssertNil(f.model.coordinator.pending)
    }
    func testCancelDiscardsOnlyUnappliedChangesAndConsumesDismissOnce() throws {
        let f = try fixture(), before = f.model.draft
        f.controller.enabledBinding.wrappedValue = true; f.controller.secondsBinding.wrappedValue = "100"
        var dismissals = 0; let cancel = f.controller.cancelAction { dismissals += 1 }
        cancel(); cancel()
        XCTAssertEqual(dismissals, 1); XCTAssertEqual(f.model.draft, before)
        XCTAssertTrue(f.storage.values.isEmpty); XCTAssertNil(f.controller.visibleDraft)
    }
    func testOldBindingsCannotReadOrWriteAReplacementVisibleEditor() throws {
        let f = try fixture()
        let enabled = f.controller.enabledBinding, seconds = f.controller.secondsBinding, outcome = f.controller.outcomeBinding
        f.controller.viewDisappeared(); f.controller.viewAppeared(sceneIsActive: true)
        f.controller.enabledBinding.wrappedValue = true; f.controller.secondsBinding.wrappedValue = "600"
        f.controller.outcomeBinding.wrappedValue = "EXPIRED"
        XCTAssertFalse(enabled.wrappedValue); XCTAssertEqual(seconds.wrappedValue, ""); XCTAssertEqual(outcome.wrappedValue, "")
        enabled.wrappedValue = false; seconds.wrappedValue = "10"; outcome.wrappedValue = "FAILED"
        XCTAssertEqual(f.controller.visibleDraft?.enabled, true)
        XCTAssertEqual(f.controller.visibleDraft?.seconds, "600"); XCTAssertEqual(f.controller.visibleDraft?.outcome, "EXPIRED")
    }
    func testOldSaveCancelAndReloadCannotActOnReplacementEditor() throws {
        let f = try fixture(), before = f.model.draft
        var dismissals = 0
        let save = f.controller.saveAction(), cancel = f.controller.cancelAction { dismissals += 1 }, reload = f.controller.reloadAction()
        f.controller.viewDisappeared(); f.controller.viewAppeared(sceneIsActive: true)
        f.controller.secondsBinding.wrappedValue = "500"
        save(); cancel(); reload()
        XCTAssertEqual(f.controller.visibleDraft?.seconds, "500"); XCTAssertEqual(dismissals, 0)
        XCTAssertEqual(f.model.draft, before); XCTAssertTrue(f.storage.values.isEmpty)
    }
    func testHiddenForegroundAndReloadCannotReviveOwner() throws {
        let f = try fixture(), oldSave = f.controller.saveAction()
        f.controller.viewDisappeared(); f.controller.sceneChanged(isActive: false); f.controller.sceneChanged(isActive: true)
        f.controller.reload(); oldSave()
        XCTAssertFalse(f.controller.isVisible); XCTAssertNil(f.controller.visibleDraft); XCTAssertFalse(f.controller.canSave)
        XCTAssertTrue(f.storage.values.isEmpty)
        f.controller.viewAppeared(sceneIsActive: true); XCTAssertNotNil(f.controller.visibleDraft)
    }
    func testInactiveAppearanceWaitsForVisibleForeground() throws {
        let f = try fixture(appear: false)
        f.controller.viewAppeared(sceneIsActive: false); f.controller.reload()
        XCTAssertNil(f.controller.visibleDraft); XCTAssertFalse(f.controller.canSave)
        f.controller.sceneChanged(isActive: true); XCTAssertNotNil(f.controller.visibleDraft)
        f.controller.secondsBinding.wrappedValue = "80"
        let old = f.controller.secondsBinding
        f.controller.sceneChanged(isActive: false); XCTAssertEqual(old.wrappedValue, "")
        f.controller.sceneChanged(isActive: true)
        XCTAssertEqual(f.controller.visibleDraft?.seconds, "300")
        old.wrappedValue = "90"; XCTAssertEqual(f.controller.visibleDraft?.seconds, "300")
    }
    func testRepeatedVisibleAppearancePreservesUnappliedEditsAndCurrentBinding() throws {
        let f = try fixture(), seconds = f.controller.secondsBinding
        seconds.wrappedValue = "45"
        f.controller.viewAppeared(sceneIsActive: true); f.controller.sceneChanged(isActive: true)
        XCTAssertEqual(seconds.wrappedValue, "45"); XCTAssertEqual(f.controller.visibleDraft?.seconds, "45")
        XCTAssertEqual(f.model.draft.advanced.text("timer", "durationSeconds"), "300")
    }
    func testOwnerChangeRejectsBindingsAndEveryOldCallbackBeforeModelPublishes() throws {
        let f = try fixture(), original = f.model.draft
        var dismissals = 0
        let binding = f.controller.secondsBinding, save = f.controller.saveAction()
        let cancel = f.controller.cancelAction { dismissals += 1 }, reload = f.controller.reloadAction()
        f.owner.session = try .init(accountID: 992, namespace: "timeout-editor", epoch: 2, authorizationRevision: "member")
        XCTAssertNil(f.controller.visibleDraft); XCTAssertEqual(binding.wrappedValue, "")
        binding.wrappedValue = "50"; save(); cancel(); reload()
        XCTAssertNil(f.controller.visibleDraft); XCTAssertEqual(f.model.draft, original)
        XCTAssertEqual(dismissals, 0); XCTAssertTrue(f.storage.values.isEmpty)
    }
    func testParentDraftABARevokesOldReadWriteAndSave() throws {
        let f = try fixture(), original = f.model.draft
        let binding = f.controller.outcomeBinding, save = f.controller.saveAction()
        f.model.draft.title = "Changed"; f.model.draft = original; f.controller.reload()
        XCTAssertEqual(binding.wrappedValue, ""); binding.wrappedValue = "EXPIRED"; save()
        XCTAssertEqual(f.controller.visibleDraft?.outcome, "FAILED")
        XCTAssertEqual(f.model.draft, original); XCTAssertTrue(f.storage.values.isEmpty)
    }
    func testBusyAndModelInvalidationRetireWithoutRevivingOnHiddenEvents() throws {
        for operation in ["busy", "load", "leave", "changed"] {
            let f = try fixture(), oldSave = f.controller.saveAction()
            switch operation {
            case "busy": f.model.busy = true
            case "load": f.model.load()
            case "leave": f.model.leave()
            default: f.model.changed()
            }
            XCTAssertNil(f.controller.visibleDraft, operation); oldSave()
            XCTAssertTrue(f.storage.values.isEmpty, operation)
            f.controller.viewDisappeared(); f.controller.sceneChanged(isActive: true)
            XCTAssertNil(f.controller.visibleDraft, operation)
        }
    }
    func testMalformedEnabledNeverReachesSaveAndCanBeCancelled() throws {
        let f = try fixture(appear: false)
        f.model.draft.advanced.set("timer", "enabled", .string("false")); f.model.changed()
        let original = f.model.draft
        f.controller.viewAppeared(sceneIsActive: true)
        XCTAssertNil(f.controller.visibleDraft); XCTAssertFalse(f.controller.canSave)
        f.controller.saveAction()(); XCTAssertEqual(f.model.draft, original); XCTAssertTrue(f.storage.values.isEmpty)
        var dismissals = 0; f.controller.cancelAction { dismissals += 1 }()
        XCTAssertEqual(dismissals, 1)
    }
    func testEnglishAndChineseDestinationTextAreExplicitAndNonempty() {
        for text in TemplateTimerOutcomeText.allCases {
            let english = text.value(Locale(identifier: "en_US")), chinese = text.value(Locale(identifier: "zh_CN"))
            XCTAssertFalse(english.isEmpty); XCTAssertFalse(chinese.isEmpty); XCTAssertNotEqual(english, chinese)
        }
        XCTAssertEqual(TemplateTimerOutcomeText.save.value(Locale(identifier: "en_US")), "Save to local draft")
        XCTAssertEqual(TemplateTimerOutcomeText.save.value(Locale(identifier: "zh_CN")), "保存到本地草稿")
    }
}
