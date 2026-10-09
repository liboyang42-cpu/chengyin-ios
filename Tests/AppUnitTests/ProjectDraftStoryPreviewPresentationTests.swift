import XCTest
@testable import Questify

@MainActor final class ProjectDraftStoryPreviewPresentationTests: XCTestCase {
    private final class Owner { var session: ProjectEditSession? = try? .init(accountID:7,epoch:1,storageNamespace:"story-preview") }
    private func setup(scope:ProjectEditScope = .full) async throws -> (ProjectDraftStoryPreviewController,Owner,ProjectEditMemoryStorage) {
        let owner=Owner(),storage=ProjectEditMemoryStorage(); var draft=ProjectEditSyntheticFixtures.draft(product:.city)
        draft.chapters[0].blocks=[.init(kind:.text,content:"Unsaved first")]
        var second=ProjectEditChapter();second.name="Second";second.blocks=[.init(kind:.voice,content:"Unsaved second")];draft.chapters.append(second)
        let initial=ProjectEditSnapshot(topicID:scope == .whitelist ? 101:nil,scope:scope,draft:draft)
        let model=ProjectEditModel(coordinator:.init(initial:initial,service:ProjectEditSyntheticService(snapshot:initial),store:.init(storage:storage),currentSession:{owner.session}));await model.load()
        return (.init(model:model),owner,storage)
    }
    private func capture(_ controller:ProjectDraftStoryPreviewController) throws -> ProjectDraftStoryPreviewController.Capture {
        try XCTUnwrap(controller.capture(.init(draft:controller.model.draft)))
    }
    private func open(_ controller:ProjectDraftStoryPreviewController) throws -> ProjectDraftStoryPreviewController.Presentation {
        controller.open(try capture(controller));return try XCTUnwrap(controller.presentation)
    }
    func testPreviewUsesCurrentUnsavedDraftAndNeverMutatesStorageOrReview() async throws {
        let (controller,_,storage)=try await setup(),model=controller.model
        model.draft.chapters[0].blocks?[0].content="Latest unsaved text";model.review()
        let review=try XCTUnwrap(model.confirmation),bytes=ProjectEditPendingMaterials.exactData(model.draft),saved=storage.data
        let original=try open(controller);XCTAssertEqual(original.capture.projection.chapters[0].rows[0].text,"Latest unsaved text")
        XCTAssertTrue(controller.select(1,in:original));controller.close(original)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft),bytes);XCTAssertEqual(storage.data,saved);XCTAssertEqual(model.confirmation?.id,review.id)
    }
    func testPreviousNextAndChapterSelectionRespectBounds() async throws {
        let (controller,_,_)=try await setup();let original=try open(controller)
        XCTAssertFalse(controller.select(-1,in:original));XCTAssertEqual(controller.selectedChapter,0)
        XCTAssertTrue(controller.select(1,in:original));XCTAssertEqual(controller.selectedChapter,1)
        XCTAssertFalse(controller.select(2,in:original));XCTAssertEqual(controller.selectedChapter,1)
        XCTAssertTrue(controller.select(0,in:original))
    }
    func testCloseAndReopenStartAtFirstChapterAndOldCallbacksCannotCloseNew() async throws {
        let (controller,_,_)=try await setup();let original=try open(controller);_ = controller.select(1,in:original);controller.close(original)
        let next=try open(controller);XCTAssertEqual(controller.selectedChapter,0);controller.close(original)
        XCTAssertEqual(controller.presentation?.id,next.id);XCTAssertFalse(controller.select(1,in:original))
    }
    func testQueuedOpeningAfterDepartureIsRejected() async throws {
        let (controller,_,_)=try await setup();let old=try capture(controller);controller.retire();controller.open(old)
        XCTAssertNil(controller.presentation)
    }
    func testForeignControllerCannotUseCapturedPreview() async throws {
        let (controller,_,_)=try await setup();let (other,_,_)=try await setup();other.open(try capture(controller));XCTAssertNil(other.presentation)
    }
    func testWhitelistCannotCapture() async throws {
        let (controller,_,_)=try await setup(scope:.whitelist)
        XCTAssertNil(controller.capture(.init(draft:controller.model.draft)));XCTAssertNil(controller.presentation)
    }
    func testOwnerEpochLogoutAndLeaveRetireFacts() async throws {
        for action in ["owner","epoch","logout","leave"] {
            let (controller,owner,_)=try await setup();let original=try open(controller)
            switch action {
            case "owner":owner.session=try .init(accountID:8,epoch:1,storageNamespace:"story-preview")
            case "epoch":owner.session=try .init(accountID:7,epoch:2,storageNamespace:"story-preview")
            case "logout":owner.session=nil
            default:controller.model.leave()
            }
            XCTAssertFalse(controller.isCurrent(original));XCTAssertFalse(controller.select(1,in:original));controller.synchronize();XCTAssertNil(controller.presentation)
        }
    }
    func testDraftChangeAndSameByteABARejectOldProjection() async throws {
        for sameBytes in [false,true] {
            let (controller,_,_)=try await setup();let original=try open(controller)
            var next=controller.model.draft;if !sameBytes { next.chapters[0].blocks?[0].content="New version" };controller.model.draft=next
            XCTAssertFalse(controller.isCurrent(original));controller.synchronize();XCTAssertNil(controller.presentation)
        }
    }
    func testCanonicalEquivalentTextReplacementIsStale() async throws {
        let (controller,_,_)=try await setup();controller.model.draft.chapters[0].blocks?[0].content="e\u{301}";let original=try open(controller)
        controller.model.draft.chapters[0].blocks?[0].content="é";XCTAssertFalse(controller.isCurrent(original))
    }
    func testChapterReorderDeletionAndReplacementCannotRetargetOldSelection() async throws {
        for action in ["reorder","delete","replace"] {
            let (controller,_,_)=try await setup();let original=try open(controller);_ = controller.select(1,in:original)
            switch action {case "reorder":controller.model.draft.chapters.reverse();case "delete":controller.model.draft.chapters.removeLast();default:controller.model.draft.chapters[1]=ProjectEditChapter()}
            XCTAssertFalse(controller.select(0,in:original));controller.synchronize();XCTAssertNil(controller.presentation)
        }
    }
    func testUnsupportedBranchCannotOpenAnInventedRoute() async throws {
        let (controller,_,_)=try await setup();controller.model.draft.preserved["routeMode"] = .string("BRANCH_GRAPH")
        let projection=ProjectDraftStoryPreview(draft:controller.model.draft);XCTAssertEqual(projection.reason,.branchRoute);XCTAssertNil(controller.capture(projection))
    }
    func testEmptyDraftCanOpenAndCloseWithoutInventingContent() async throws {
        let (controller,_,_)=try await setup();controller.model.draft.chapters=[];let original=try open(controller)
        XCTAssertTrue(original.capture.projection.chapters.isEmpty);XCTAssertFalse(controller.select(0,in:original));controller.close(original)
    }
}
