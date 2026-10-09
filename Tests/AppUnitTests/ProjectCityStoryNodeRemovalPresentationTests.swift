import XCTest
@testable import Questify

#if DEBUG
@MainActor final class ProjectCityStoryNodeRemovalPresentationTests:XCTestCase {
    private final class Owner { var session:ProjectEditSession?=try? .init(accountID:7,epoch:1,storageNamespace:"city-removal-tests") }
    private final class Clock { var now=0.0 }
    private final class Storage:ProjectEditDataStorage {
        var bytes:[String:Data]=[:],writes=0,failAt:Int?
        func read(_ key:String)throws->Data?{bytes[key]}
        func remove(_ key:String)throws{bytes[key]=nil}
        func write(_ data:Data,key:String)throws{writes+=1;if writes==failAt{throw ProjectEditError.persistenceUnavailable};bytes[key]=data}
    }
    private struct Context { let owner:Owner,clock:Clock,storage:Storage,editor:ProjectEditModel,controller:ProjectCityStoryNodeRemovalController,baseline:ProjectEditDraft }
    private func draft()->ProjectEditDraft {
        var d=ProjectEditSyntheticFixtures.draft(),c=d.chapters[0];c.id="chapter";var a=c.nodes[0];a.id="node-a";a.description=" é\n";var b=a;b.id="node-b";b.name="Second";c.nodes=[a,b]
        var t=ProjectEditBlock(kind:.text,content:"Keep text");t.id="text";var ba=ProjectEditBlock(kind:.node,nodeID:a.id);ba.id="a-block";var bb=ProjectEditBlock(kind:.node,nodeID:b.id);bb.id="b-block";c.blocks=[t,ba,bb];d.chapters=[c];return d
    }
    private func context(active:Bool=true,scope:ProjectEditScope = .full)async->Context {
        let d=draft(),owner=Owner(),clock=Clock(),storage=Storage()
        let editor=ProjectEditModel(coordinator:.init(initial:.init(scope:scope,draft:d),service:ProjectEditSyntheticService(),store:.init(storage:storage),currentSession:{owner.session}))
        await editor.load();editor.saveLocal();storage.writes=0
        let c=ProjectCityStoryNodeRemovalController(model:editor,chapterID:"chapter",now:{clock.now});c.setActive(active)
        return .init(owner:owner,clock:clock,storage:storage,editor:editor,controller:c,baseline:d)
    }
    private func open(_ c:Context,id:String="node-a")throws->ProjectCityStoryNodeRemovalController.Confirmation {
        c.controller.open(id,captured:c.controller.capture());return try XCTUnwrap(c.controller.confirmation)
    }
    func testInactiveAndRetiredRenderedIntentCannotRevive()async throws {
        let c=await context(active:false);XCTAssertNil(c.controller.capture());c.controller.setActive(true);let capture=try XCTUnwrap(c.controller.capture());c.controller.setActive(false);c.controller.setActive(true)
        c.controller.open("node-a",captured:capture);XCTAssertNil(c.controller.confirmation);XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.editor.draft),ProjectEditPendingMaterials.exactData(c.baseline))
    }
    func testCancelPreservesAllDraftBytesAndCreatesNoUndo()async throws {
        let c=await context(),value=try open(c);c.controller.close(value);XCTAssertNil(c.controller.confirmation);XCTAssertNil(c.controller.undo);XCTAssertEqual(c.storage.writes,0);XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.editor.draft),ProjectEditPendingMaterials.exactData(c.baseline))
    }
    func testExplicitConfirmAndFiveSecondUndoRestoreExactPositions()async throws {
        let c=await context(),value=try open(c);XCTAssertEqual(c.editor.draft.chapters[0].nodes.count,2);c.controller.confirm(value)
        let undo=try XCTUnwrap(c.controller.undo);XCTAssertEqual(c.editor.draft.chapters[0].nodes.map(\.id),["node-b"]);XCTAssertEqual(undo.deadline,5)
        c.clock.now=4.999;c.controller.restore(undo);XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.editor.draft),ProjectEditPendingMaterials.exactData(c.baseline));XCTAssertNil(c.controller.undo)
        c.controller.confirm(value);XCTAssertEqual(c.editor.draft.chapters[0].nodes.count,2)
    }
    func testDeadlineCannotExtendFromRenderingOrStaleTimer()async throws {
        let c=await context();c.controller.confirm(try open(c));let undo=try XCTUnwrap(c.controller.undo),after=ProjectEditPendingMaterials.exactData(c.editor.draft)
        c.clock.now=5;XCTAssertFalse(c.controller.canUndo(undo));c.controller.restore(undo);XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.editor.draft),after);XCTAssertNil(c.controller.undo)
    }
    func testConsecutiveDeleteRefreshesWindowAndCombinesSourceSnapshots()async throws {
        let c=await context();c.controller.confirm(try open(c));let old=try XCTUnwrap(c.controller.undo);c.clock.now=2;c.controller.confirm(try open(c,id:"node-b"));let combined=try XCTUnwrap(c.controller.undo)
        XCTAssertEqual(combined.deadline,7);XCTAssertTrue(c.editor.draft.chapters[0].nodes.isEmpty);c.controller.restore(old);XCTAssertTrue(c.editor.draft.chapters[0].nodes.isEmpty)
        c.clock.now=6.9;c.controller.restore(combined);XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.editor.draft),ProjectEditPendingMaterials.exactData(c.baseline))
    }
    func testSameByteABARejectsConfirmationAndUndo()async throws {
        for after in [false,true] {let c=await context(),value=try open(c);if after{c.controller.confirm(value)};let undo=c.controller.undo;let same=c.editor.draft;c.editor.draft=same
            c.controller.confirm(value);if let undo{c.controller.restore(undo)};XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.editor.draft),ProjectEditPendingMaterials.exactData(same));XCTAssertNil(c.controller.undo)}
    }
    func testCanonicalEquivalentPostimageEditCannotBeOverwritten()async throws {
        let c=await context();c.controller.confirm(try open(c));let undo=try XCTUnwrap(c.controller.undo);c.editor.draft.chapters[0].nodes[0].description=" e\u{301}\n";let changed=ProjectEditPendingMaterials.exactData(c.editor.draft)
        c.controller.restore(undo);XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.editor.draft),changed)
    }
    func testOwnerEpochBackgroundAndLeaveRetirePendingConfirmation()async throws {
        for mode in 0..<4 {let c=await context(),value=try open(c)
            switch mode{case 0:c.owner.session=nil;case 1:c.owner.session=try .init(accountID:7,epoch:2,storageNamespace:"city-removal-tests");case 2:c.controller.setActive(false);default:c.editor.leave()}
            c.controller.confirm(value);XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.editor.draft),ProjectEditPendingMaterials.exactData(c.baseline))}
    }
    func testBackgroundReturnCannotReuseOldUndo()async throws {
        let c=await context();c.controller.confirm(try open(c));let undo=try XCTUnwrap(c.controller.undo),after=ProjectEditPendingMaterials.exactData(c.editor.draft);c.controller.setActive(false);c.controller.setActive(true);c.controller.restore(undo)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.editor.draft),after);XCTAssertNil(c.controller.undo)
    }
    func testReplacementEditorWithSameIDsHasDifferentHostIdentity()async throws {
        let a=await context(),b=await context();let x=ProjectCityStoryNodeRemovalHostIdentity(owner:ObjectIdentifier(a.editor),chapter:Data("chapter".utf8)),y=ProjectCityStoryNodeRemovalHostIdentity(owner:ObjectIdentifier(b.editor),chapter:Data("chapter".utf8));XCTAssertNotEqual(x,y)
        let original=try open(a);b.controller.confirm(original);XCTAssertEqual(ProjectEditPendingMaterials.exactData(b.editor.draft),ProjectEditPendingMaterials.exactData(b.baseline))
    }
    func testEnvelopeOrPointerFailureIsUnconfirmedWithoutAdoptingDraft()async throws {
        for fail in [1,2] {let c=await context(),value=try open(c);c.storage.failAt=fail;c.controller.confirm(value)
            XCTAssertTrue(c.controller.saveUnconfirmed);XCTAssertNil(c.controller.undo);XCTAssertNil(c.controller.capture());XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.editor.draft),ProjectEditPendingMaterials.exactData(c.baseline))}
    }
    func testMixedOrMultipleSelectionsNeverPartiallyDelete()async throws {
        let c=await context(),capture=try XCTUnwrap(c.controller.capture());XCTAssertTrue(c.controller.interceptStory(offsets:IndexSet([0,1]),captured:capture));XCTAssertNil(c.controller.confirmation)
        c.controller.openNodes(offsets:IndexSet([0,1]),captured:capture);XCTAssertNil(c.controller.confirmation);XCTAssertEqual(c.storage.writes,0)
        XCTAssertFalse(c.controller.interceptStory(offsets:IndexSet(integer:0),captured:capture))
    }
    func testWhitelistAndReferencedNodesHaveNoDestructiveConfirmation()async throws {
        let c=await context(scope:.whitelist);XCTAssertNil(c.controller.capture())
        let linked=await context();linked.editor.draft.preserved["journeyRules"] = .string("{\"quest\":{\"nodeId\":1}}")
        linked.controller.open("node-a",captured:linked.controller.capture());XCTAssertNil(linked.controller.confirmation);XCTAssertTrue(linked.controller.blocked)
    }
    func testOldCancelCannotDismissAReplacementConfirmation()async throws {
        let c=await context(),old=try open(c);c.controller.close(old);let fresh=try open(c,id:"node-b");c.controller.close(old);XCTAssertEqual(c.controller.confirmation?.id,fresh.id)
    }
}
#endif
