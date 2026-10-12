import XCTest
import Combine
@testable import Questify

@MainActor private final class IntroExampleReader: DiscoveryReading {
    var isConfigured = true
    var discoveryPresentationIdentity = "intro-a"
    let changes = PassthroughSubject<Void,Never>()
    var discoveryPresentationChanges: AnyPublisher<Void,Never> { changes.eraseToAnyPublisher() }
    var home: DiscoveryTemplateHome?
    var error: Error = APIError.httpStatus(503)
    var held = false
    var reads = 0, otherReads = 0
    private var pending: [Int:CheckedContinuation<DiscoveryTemplateHome,Error>] = [:]
    func discoveryTemplateHome() async throws -> DiscoveryTemplateHome {
        reads += 1
        if held { let index = reads; return try await withCheckedThrowingContinuation { pending[index] = $0 } }
        if let home { return home }; throw error
    }
    func waitForRead(_ count: Int) async {
        for _ in 0..<200 where pending[count] == nil { await Task.yield() }; XCTAssertNotNil(pending[count])
    }
    func finish(_ index: Int,_ result: DiscoveryTemplateHome) { pending.removeValue(forKey:index)?.resume(returning:result) }
    func fail(_ index: Int) { pending.removeValue(forKey:index)?.resume(throwing:error) }
    func discoveryBanners() async throws -> [DiscoveryBanner] { otherReads += 1; return [] }
    func discoveryCategories(type: Int?) async throws -> [DiscoveryCategory] { otherReads += 1; return [] }
    func discoveryPlayTemplates(keyword: String,packType: DiscoveryPackType?) async throws -> [DiscoveryPlayTemplate] { otherReads += 1; return [] }
    func discoveryTopicTemplates() async throws -> [DiscoveryTopicTemplate] { otherReads += 1; return [] }
    func discoveryTopicTemplateDetail(id: Int) async throws -> PublicTopicTemplateDetail { otherReads += 1; throw APIError.notConfigured }
    func discoveryPlayTemplate(id: Int) async throws -> DiscoveryPlayTemplate { otherReads += 1; throw APIError.notConfigured }
}

@MainActor final class TemplateIntroExperienceTests: XCTestCase {
    private final class Owner { var session: TemplateAuthoringSession? = try? .init(accountID:37,namespace:"intro",epoch:1,authorizationRevision:"creator") }
    private struct Context { let owner: Owner, model: TemplateAuthoringModel, memory: TemplateAuthoringMemoryStorage, reader: IntroExampleReader, controller: TemplateAuthoringIntroController }
    private func setup(noReader: Bool = false) -> Context {
        let owner = Owner(), memory = TemplateAuthoringMemoryStorage(), reader = IntroExampleReader()
        let model = TemplateAuthoringModel(coordinator:.init(store:.init(storage:memory),currentSession:{ owner.session })); model.load()
        let c = TemplateAuthoringIntroController(model:model,reader:noReader ? nil : reader); c.activate()
        return .init(owner:owner,model:model,memory:memory,reader:reader,controller:c)
    }
    private func home(_ ids: [Int], pool: String = "recommendList") throws -> DiscoveryTemplateHome {
        try JSONDecoder().decode(DiscoveryTemplateHome.self,from:JSONSerialization.data(withJSONObject:[pool:ids.map { ["id":$0,"title":"Example \($0)"] }]))
    }
    private func load(_ c: Context) async { await c.controller.load(c.controller.permit())?.value }
    func testRealLoadedRowsUseOnlyExistingHomeReadAndNeverAlterDraft() async throws {
        let c = setup(); c.reader.home = try home([7,2,9,4]); let draft = c.model.draft, stored = c.memory.values
        await load(c); XCTAssertEqual(c.controller.visibleExamples?.rows.map(\.id),[7,2,9]); XCTAssertEqual(c.controller.visiblePhase,.ready)
        XCTAssertEqual(c.reader.reads,1); XCTAssertEqual(c.reader.otherReads,0); XCTAssertEqual(c.model.draft,draft); XCTAssertEqual(c.memory.values,stored)
    }
    func testInitialFailureRetrySuccessIsComplete() async throws {
        let c = setup(); await load(c); XCTAssertEqual(c.controller.visiblePhase,.failed); XCTAssertNil(c.controller.visibleExamples)
        c.reader.home = try home([8]); await load(c); XCTAssertEqual(c.controller.visibleExamples?.rows.map(\.id),[8]); XCTAssertEqual(c.reader.reads,2)
    }
    func testRefreshFailureRetainsExactExistingCards() async throws {
        let c = setup(); c.reader.home = try home([8,8,9]); await load(c); let old = c.controller.visibleExamples
        c.reader.home = nil; await load(c); XCTAssertEqual(c.controller.visibleExamples,old); XCTAssertEqual(c.controller.visiblePhase,.ready)
    }
    func testSuccessfulEmptyRefreshClearsOldCardsWithoutFakeFallback() async throws {
        let c = setup(); c.reader.home = try home([8]); await load(c); c.reader.home = try home([]); await load(c)
        XCTAssertEqual(c.controller.visiblePhase,.empty); XCTAssertEqual(c.controller.visibleExamples?.rows.count,0)
    }
    func testDuplicateRequestsAreSuppressedWhileHeld() async throws {
        let c = setup(); c.reader.held = true; let first = try XCTUnwrap(c.controller.load(c.controller.permit())); await c.reader.waitForRead(1)
        XCTAssertNil(c.controller.load(c.controller.permit())); XCTAssertEqual(c.reader.reads,1)
        c.reader.finish(1,try home([1])); await first.value; XCTAssertEqual(c.controller.visiblePhase,.ready)
    }
    func testBeginAndSkipShareOneShotExitAndKeepLocalDraft() async throws {
        for noReader in [true,false] {
            let c = setup(noReader:noReader); let before = c.model.draft, store = c.memory.values; var advances = 0
            let begin = c.controller.continueAction { advances += 1 }, skip = c.controller.continueAction { advances += 1 }
            begin(); skip(); begin(); XCTAssertEqual(advances,1); XCTAssertEqual(c.model.draft,before); XCTAssertEqual(c.memory.values,store)
        }
    }
    func testUnconfiguredFailedAndEmptyDataDoNotBlockCreation() async throws {
        for kind in ["unconfigured","failed","empty","unencodable"] {
            let c = setup(); if kind == "unconfigured" { c.reader.isConfigured = false; c.controller.activate() }; if kind == "empty" { c.reader.home = try home([]) }
            if kind == "unencodable" { c.model.draft.advanced.set("timer","durationSeconds",.number(.nan)); c.model.changed(); c.controller.activate() }
            await load(c); XCTAssertTrue(c.controller.canContinue); var advances = 0; c.controller.continueAction { advances += 1 }(); XCTAssertEqual(advances,1)
            if kind == "unconfigured" { XCTAssertEqual(c.reader.reads,0) }
            if kind == "unencodable" { XCTAssertTrue(c.model.draft.advanced.value["timer"]?.object?["durationSeconds"]?.number?.isNaN == true) }
        }
    }
    func testContinueDuringLoadCancelsAndRejectsLateResult() async throws {
        let c = setup(); c.reader.held = true; let task = try XCTUnwrap(c.controller.load(c.controller.permit())); await c.reader.waitForRead(1)
        var advances = 0; c.controller.continueAction { advances += 1 }(); c.reader.finish(1,try home([9])); await task.value
        XCTAssertEqual(advances,1); XCTAssertNil(c.controller.visibleExamples); XCTAssertEqual(c.reader.reads,1)
    }
    func testRetiredOwnerReadCannotReplaceNewVisitCards() async throws {
        let c = setup(); c.reader.held = true; let old = try XCTUnwrap(c.controller.load(c.controller.permit())); await c.reader.waitForRead(1)
        c.controller.retire(); c.controller.activate(); let next = try XCTUnwrap(c.controller.load(c.controller.permit())); await c.reader.waitForRead(2)
        c.reader.finish(2,try home([2])); await next.value; c.reader.finish(1,try home([1])); await old.value
        XCTAssertEqual(c.controller.visibleExamples?.rows.map(\.id),[2]); XCTAssertEqual(c.controller.visiblePhase,.ready)
    }
    func testHeldFailureAfterRetireCannotReplaceNewSuccess() async throws {
        let c = setup(); c.reader.held = true; let old = try XCTUnwrap(c.controller.load(c.controller.permit())); await c.reader.waitForRead(1)
        c.controller.retire(); c.controller.activate(); let next = try XCTUnwrap(c.controller.load(c.controller.permit())); await c.reader.waitForRead(2)
        c.reader.finish(2,try home([2])); await next.value; c.reader.fail(1); await old.value
        XCTAssertEqual(c.controller.visiblePhase,.ready); XCTAssertEqual(c.controller.visibleExamples?.rows.map(\.id),[2])
    }
    func testOwnerChangeRejectsReadAndOldContinueWithoutWrites() async throws {
        let c = setup(); c.reader.held = true; let task = try XCTUnwrap(c.controller.load(c.controller.permit())); await c.reader.waitForRead(1)
        var advances = 0; let advance = c.controller.continueAction { advances += 1 }, stored = c.memory.values
        c.owner.session = try .init(accountID:38,namespace:"intro",epoch:2,authorizationRevision:"creator"); advance(); c.reader.finish(1,try home([1])); await task.value
        XCTAssertEqual(advances,0); XCTAssertNil(c.controller.visibleExamples); XCTAssertEqual(c.memory.values,stored)
    }
    func testReaderIdentityRevocationHidesOldCardsAndRejectsOldRetry() async throws {
        let c = setup(); c.reader.home = try home([8]); await load(c); let permit = c.controller.permit(); c.reader.discoveryPresentationIdentity = "intro-b"
        XCTAssertNil(c.controller.visibleExamples); XCTAssertNil(c.controller.load(permit)); XCTAssertEqual(c.reader.reads,1)
        c.controller.activate(); await load(c); XCTAssertEqual(c.reader.reads,2)
    }
    func testReaderPublicationABAAndBackgroundRetireAllOldPermits() async throws {
        let c = setup(); let old = c.controller.permit(); var advances = 0; let action = c.controller.continueAction { advances += 1 }
        c.controller.retire(); c.reader.discoveryPresentationIdentity = "intro-b"; c.reader.discoveryPresentationIdentity = "intro-a"; c.controller.activate()
        XCTAssertNil(c.controller.load(old)); action(); XCTAssertEqual(advances,0); c.controller.continueAction { advances += 1 }(); XCTAssertEqual(advances,1)
    }
    func testDraftABAImmediatelyRetiresPriorCreationAction() throws {
        let c = setup(); let original = c.model.draft; var advances = 0; let old = c.controller.continueAction { advances += 1 }
        c.model.draft.title = "temporary"; c.model.draft = original; old(); XCTAssertEqual(advances,0); XCTAssertFalse(c.controller.canContinue)
    }
    func testBusyReviewAndRestoreLockNeverAllowCreationAction() throws {
        let c = setup(); c.model.busy = true; c.controller.activate(); XCTAssertFalse(c.controller.canContinue)
        c.model.busy = false; c.model.draft = TemplateAuthoringSyntheticFixtures.draft(); c.model.changed(); c.model.prepare(.saveDraft); c.controller.activate()
        XCTAssertFalse(c.controller.canContinue); var advances = 0; c.controller.continueAction { advances += 1 }(); XCTAssertEqual(advances,0)
        let saved = setup(); saved.model.draft.title = "Restorable"; saved.model.changed(); saved.model.save()
        let reopened = TemplateAuthoringModel(coordinator:.init(store:.init(storage:saved.memory),currentSession:{ saved.owner.session })); reopened.load()
        let restored = TemplateAuthoringIntroController(model:reopened,reader:saved.reader); restored.activate(); XCTAssertFalse(restored.canContinue)
    }
    func testEmptyReaderDoesNotStartNetworkRequest() async throws {
        let c = setup(noReader:true); await load(c); XCTAssertEqual(c.controller.visiblePhase,.unavailable); XCTAssertEqual(c.reader.reads,0); XCTAssertTrue(c.controller.canContinue)
    }
}
