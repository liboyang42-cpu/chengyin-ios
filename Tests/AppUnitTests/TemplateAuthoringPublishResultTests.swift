import XCTest
@testable import Questify

/// Memory-only transport and controllable clock. No socket, credential, upload or real content write.
@MainActor final class TemplateAuthoringPublishResultAppTests: XCTestCase {
    private final class Owner { var session: TemplateAuthoringSession? = try? .init(accountID:36,namespace:"result-app",epoch:1,authorizationRevision:"creator") }
    private final class Wire: TemplateAuthoringTransport {
        var authority: TemplateAuthoringAuthority = .injectedHTTP
        var raw = #"{"code":200,"data":360}"#, calls = 0
        func send(_ request: TemplateAuthoringRequest) async throws -> (Data,Int) { calls += 1; return (Data(raw.utf8),200) }
    }
    private final class Storage: TemplateAuthoringStorage {
        var values: [String:Data] = [:], writes = 0, removes = 0
        func read(_ key: String) throws -> Data? { values[key] }
        func write(_ data: Data,key: String) throws { values[key] = data; writes += 1 }
        func remove(_ key: String) throws { values.removeValue(forKey:key); removes += 1 }
    }
    @MainActor private final class Clock {
        struct Job { let deadline: Int; let action: @MainActor () -> Void; var cancelled = false; var fired = false }
        var now = 0, jobs: [Job] = []
        func schedule(_ delay: Int, _ action: @escaping @MainActor () -> Void) -> () -> Void {
            let index = jobs.count; jobs.append(.init(deadline:now + delay,action:action))
            return { self.jobs[index].cancelled = true }
        }
        func advance(_ milliseconds: Int) {
            now += milliseconds
            for index in jobs.indices where !jobs[index].cancelled && !jobs[index].fired && jobs[index].deadline <= now {
                jobs[index].fired = true; jobs[index].action()
            }
        }
        func forceOldTick(_ index: Int) { jobs[index].action() }
    }
    private struct Context {
        let owner: Owner, wire: Wire, storage: Storage, clock: Clock, model: TemplateAuthoringModel, flow: TemplateAuthoringPublishFlowController
    }
    private func setup(admit: Bool = true, seed: TemplateAuthoringDraft? = nil) -> Context {
        let owner = Owner(), wire = Wire(), storage = Storage(), clock = Clock()
        let visit = DiscoveryTemplateAdoptionOwner {
            let coordinator = TemplateAuthoringCoordinator(adapter:.init(transport:wire),store:.init(storage:storage),currentSession:{ owner.session })
            coordinator.open(seed: seed); return coordinator
        }
        let model = TemplateAuthoringModel(coordinator:visit.coordinator); model.load()
        if seed == nil { model.draft = TemplateAuthoringSyntheticFixtures.draft() }
        model.changed()
        let flow = TemplateAuthoringPublishFlowController(coordinator:model.coordinator,schedule:clock.schedule); flow.activate()
        let c = Context(owner:owner,wire:wire,storage:storage,clock:clock,model:model,flow:flow)
        if admit { observe(c) }; return c
    }
    private func observe(_ c: Context, eligible: Bool = true) { c.flow.accept(TemplateAuthoringPublishResultObservation.capture(model:c.model,eligible:eligible)) }
    private func save(_ c: Context, intent: TemplateAuthoringIntent = .publish) async throws {
        c.model.prepare(intent); let review = try XCTUnwrap(c.model.review); observe(c)
        await c.model.confirm(review); observe(c)
    }
    func testFreshPublishDisplaysActualReceiptThenRoutesAtExactlyTwoSeconds() async throws {
        let c = setup(); try await save(c); let panel = try XCTUnwrap(c.flow.presentation)
        XCTAssertEqual(panel.signal.result.memberTemplateID.rawValue,360); XCTAssertFalse(c.flow.showingLibrary)
        c.clock.advance(1999); XCTAssertNotNil(c.flow.presentation); XCTAssertFalse(c.flow.showingLibrary)
        c.clock.advance(1); XCTAssertNil(c.flow.presentation); XCTAssertTrue(c.flow.showingLibrary); XCTAssertEqual(c.wire.calls,1)
    }
    func testExplicitCloseAndRetainedTickCannotNavigateTwiceOrMutateJournal() async throws {
        let c = setup(); try await save(c); let panel = try XCTUnwrap(c.flow.presentation), values = c.storage.values, draft = c.model.draft
        let writes = c.storage.writes, close = c.flow.closeAction(panel); close(); close(); c.clock.forceOldTick(0)
        XCTAssertTrue(c.flow.showingLibrary); XCTAssertNil(c.flow.presentation); XCTAssertEqual(c.storage.values,values)
        XCTAssertEqual(c.storage.writes,writes); XCTAssertEqual(c.storage.removes,0); XCTAssertEqual(c.model.draft,draft); XCTAssertEqual(c.wire.calls,1)
    }
    func testRepeatedPreferenceDoesNotRestartResultDeadline() async throws {
        let c = setup(); try await save(c); c.clock.advance(1000); observe(c); XCTAssertEqual(c.clock.jobs.count,1)
        c.clock.advance(1000); XCTAssertTrue(c.flow.showingLibrary)
    }
    func testOwnerChangeBeforeCloseOrTickNeverRoutes() async throws {
        let c = setup(); try await save(c); let close = c.flow.closeAction(try XCTUnwrap(c.flow.presentation)), values = c.storage.values
        c.owner.session = try .init(accountID:37,namespace:"result-app",epoch:2,authorizationRevision:"creator")
        close(); c.clock.forceOldTick(0); XCTAssertFalse(c.flow.showingLibrary); XCTAssertEqual(c.storage.values,values); XCTAssertEqual(c.wire.calls,1)
    }
    func testBackgroundSuspendsOldTickAndForegroundStartsFreshTwoSeconds() async throws {
        let c = setup(); try await save(c); let old = c.flow.closeAction(try XCTUnwrap(c.flow.presentation)); c.clock.advance(500)
        c.flow.suspend(); c.clock.forceOldTick(0); old(); XCTAssertFalse(c.flow.showingLibrary); XCTAssertNil(c.flow.presentation)
        c.flow.activate(); XCTAssertNotNil(c.flow.presentation); XCTAssertEqual(c.clock.jobs.count,2)
        c.clock.forceOldTick(0); old(); XCTAssertFalse(c.flow.showingLibrary); c.clock.advance(1999); XCTAssertFalse(c.flow.showingLibrary)
        c.clock.advance(1); XCTAssertTrue(c.flow.showingLibrary)
    }
    func testDisappearAndReentryDoNotTreatOldReceiptAsNewPublish() async throws {
        let c = setup(); try await save(c); let old = c.flow.closeAction(try XCTUnwrap(c.flow.presentation)); c.flow.retire(); c.model.leave()
        c.model.load(); c.flow.activate(); observe(c); old(); c.clock.forceOldTick(0)
        XCTAssertNil(c.flow.presentation); XCTAssertFalse(c.flow.showingLibrary); XCTAssertEqual(c.wire.calls,1); XCTAssertNotNil(c.model.coordinator.publishedReceipt)
    }
    func testRestoredTerminalJournalDoesNotAutomaticallyPresentOrResubmit() async throws {
        let c = setup(); try await save(c); c.flow.retire()
        let reopened = TemplateAuthoringModel(coordinator:.init(adapter:.init(transport:c.wire),store:.init(storage:c.storage),currentSession:{ c.owner.session })); reopened.load()
        let clock = Clock(), flow = TemplateAuthoringPublishFlowController(coordinator:reopened.coordinator,schedule:clock.schedule); flow.activate()
        flow.accept(TemplateAuthoringPublishResultObservation.capture(model:reopened,eligible:true))
        XCTAssertNil(flow.presentation); XCTAssertFalse(flow.showingLibrary); XCTAssertTrue(clock.jobs.isEmpty); XCTAssertEqual(c.wire.calls,1)
    }
    func testMissingIDSimulationUnknownAndDraftSaveHaveNoPublishPanel() async throws {
        for kind in ["missing","simulation","unknown","draft"] {
            let c = setup(); if kind == "missing" { c.wire.raw = #"{"code":200}"# }; if kind == "simulation" { c.wire.authority = .synthetic }; if kind == "unknown" { c.wire.raw = "unknown" }
            try await save(c,intent:kind == "draft" ? .saveDraft : .publish)
            XCTAssertNil(c.flow.presentation); XCTAssertFalse(c.flow.showingLibrary); XCTAssertTrue(c.clock.jobs.isEmpty); XCTAssertEqual(c.wire.calls,1)
        }
    }
    func testProjectNodeReturnEligibilityNeverEmitsResultSignal() async throws {
        let c = setup(); try await save(c)
        XCTAssertNil(TemplateAuthoringPublishResultObservation.capture(model:c.model,eligible:false))
        c.flow.accept(nil); XCTAssertNil(c.flow.presentation); c.clock.forceOldTick(0); XCTAssertFalse(c.flow.showingLibrary)
    }
    func testStaleBindingCannotDismissNewForegroundPanel() async throws {
        let c = setup(); try await save(c); let binding = c.flow.presentationBinding(), first = try XCTUnwrap(c.flow.presentation)
        c.flow.suspend(); c.flow.activate(); let second = try XCTUnwrap(c.flow.presentation); XCTAssertNotEqual(first.id,second.id)
        binding.wrappedValue = nil; c.flow.closeAction(first)(); XCTAssertEqual(c.flow.presentation?.id,second.id); XCTAssertFalse(c.flow.showingLibrary)
    }
    func testMetadataLeaveInvalidatesCloseBeforePreferencePropagation() async throws {
        let c = setup(); try await save(c); let close = c.flow.closeAction(try XCTUnwrap(c.flow.presentation)); c.model.leave()
        close(); c.clock.forceOldTick(0); XCTAssertFalse(c.flow.showingLibrary); XCTAssertEqual(c.wire.calls,1)
    }
    func testBusyAndDraftChangesRejectRetainedCloseImmediately() async throws {
        for busy in [true,false] {
            let c = setup(); try await save(c); let close = c.flow.closeAction(try XCTUnwrap(c.flow.presentation))
            if busy { c.model.busy = true } else { c.model.draft.title = "Different" }
            close(); c.clock.forceOldTick(0); XCTAssertFalse(c.flow.showingLibrary); XCTAssertEqual(c.wire.calls,1)
        }
    }
    func testPreactivationPreferenceCanAdmitAStillCurrentEditableVisit() async throws {
        let c = setup(admit:false); c.flow.retire(); observe(c); XCTAssertTrue(c.clock.jobs.isEmpty)
        c.flow.activate(); try await save(c); XCTAssertNotNil(c.flow.presentation)
    }
    func testOldEditableObservationCannotAdmitAnotherIdentityOrSession() async throws {
        let c = setup(admit:false), other = setup()
        let old = TemplateAuthoringPublishResultObservation.capture(model:other.model,eligible:true)
        c.flow.accept(old); try await save(c); XCTAssertNil(c.flow.presentation); XCTAssertFalse(c.flow.showingLibrary)
    }
    func testRouteCompletionIgnoresChildPreferenceRemovalAndRetainsLibrary() async throws {
        let c = setup(); try await save(c); c.flow.closeAction(try XCTUnwrap(c.flow.presentation))(); c.flow.accept(nil)
        c.flow.retire(); c.flow.activate(); XCTAssertTrue(c.flow.showingLibrary); XCTAssertNil(c.flow.presentation); XCTAssertEqual(c.wire.calls,1)
    }

    private func adoptedDraft() throws -> TemplateAuthoringDraft {
        let source = try JSONDecoder().decode(DiscoveryPlayTemplate.self, from: Data(#"{"id":742,"title":"Adopted public source","description":"Public description","players":"2-6","duration":10,"categoryId":4}"#.utf8))
        var draft = try TemplateAuthoringDraft.adopt(source)
        draft.rewardEnabled = false
        return draft
    }
    func testAdoptedSourceCompletesIntoOwnedReceiptWithoutReplacingSourceIdentity() async throws {
        let c = setup(seed: try adoptedDraft()), identity = c.model.coordinator.identity
        XCTAssertNil(c.model.draft.id); XCTAssertEqual(c.model.draft.originalTemplateID?.rawValue,742)
        try await save(c)
        let panel = try XCTUnwrap(c.flow.presentation)
        XCTAssertEqual(panel.signal.result.memberTemplateID.rawValue,360)
        XCTAssertEqual(c.model.coordinator.identity,identity)
        XCTAssertEqual(c.model.draft.originalTemplateID?.rawValue,742)
        XCTAssertEqual(try TemplateAuthoringContract.payload(c.model.draft)["originalTemplateId"],.number(742))
        c.flow.closeAction(panel)(); c.clock.forceOldTick(0)
        XCTAssertTrue(c.flow.showingLibrary); XCTAssertEqual(c.wire.calls,1)
    }
    func testAdoptedUnknownCannotShowSuccessResubmitOrLosePendingOnReopen() async throws {
        let c = setup(seed: try adoptedDraft()); c.wire.raw = "unknown"
        c.model.prepare(.publish); let review = try XCTUnwrap(c.model.review); observe(c)
        await c.model.confirm(review); observe(c)
        let pending = try XCTUnwrap(c.model.coordinator.pending), values = c.storage.values
        XCTAssertNil(c.flow.presentation); XCTAssertFalse(c.flow.showingLibrary)
        c.model.prepare(.publish); XCTAssertNil(c.model.review)
        await c.model.coordinator.confirm(review)
        c.flow.retire(); c.model.leave(); c.model.load(); c.flow.activate(); observe(c)
        XCTAssertEqual(c.model.coordinator.pending,pending); XCTAssertEqual(c.storage.values,values)
        XCTAssertNil(c.flow.presentation); XCTAssertFalse(c.flow.showingLibrary)
        XCTAssertTrue(c.clock.jobs.isEmpty); XCTAssertEqual(c.wire.calls,1)
    }
    func testAdoptionCancelledReviewAndRetainedConfirmDoNotNavigateOrWrite() async throws {
        let c = setup(seed: try adoptedDraft())
        c.model.prepare(.publish); let review = try XCTUnwrap(c.model.review)
        c.model.coordinator.cancelReview(); c.flow.retire(); c.model.leave()
        await c.model.coordinator.confirm(review)
        c.model.load(); c.flow.activate(); observe(c)
        XCTAssertEqual(c.wire.calls,0); XCTAssertNil(c.flow.presentation)
        XCTAssertFalse(c.flow.showingLibrary); XCTAssertTrue(c.clock.jobs.isEmpty)
        XCTAssertEqual(c.model.draft.originalTemplateID?.rawValue,742)
    }
    func testAdoptionSameAccountNewEpochOrPermissionCannotUseOldCompletion() async throws {
        for session in [
            try TemplateAuthoringSession(accountID:36,namespace:"result-app",epoch:2,authorizationRevision:"creator"),
            try TemplateAuthoringSession(accountID:36,namespace:"result-app",epoch:1,authorizationRevision:"revoked")
        ] {
            let c = setup(seed: try adoptedDraft()); try await save(c)
            let close = c.flow.closeAction(try XCTUnwrap(c.flow.presentation)), values = c.storage.values
            c.owner.session = session; close(); c.clock.forceOldTick(0)
            XCTAssertFalse(c.flow.showingLibrary); XCTAssertEqual(c.wire.calls,1); XCTAssertEqual(c.storage.values,values)
        }
    }
    func testAdoptedTerminalReopenDoesNotReplayCompletionOrOverwriteAttribution() async throws {
        let c = setup(seed: try adoptedDraft()); try await save(c)
        let oldClose = c.flow.closeAction(try XCTUnwrap(c.flow.presentation)), pending = c.model.coordinator.pending
        c.flow.retire(); c.model.leave(); c.model.load(); c.flow.activate(); observe(c)
        oldClose(); c.clock.forceOldTick(0)
        XCTAssertNil(c.flow.presentation); XCTAssertFalse(c.flow.showingLibrary)
        XCTAssertEqual(c.model.coordinator.pending,pending); XCTAssertEqual(c.wire.calls,1)
        XCTAssertEqual(c.model.draft.originalTemplateID?.rawValue,742)
    }
}
