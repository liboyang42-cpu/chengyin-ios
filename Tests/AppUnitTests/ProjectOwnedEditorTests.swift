import XCTest
@testable import Questify

@MainActor final class ProjectOwnedEditorTests: XCTestCase {
    private func setup(_ flags: [String] = []) async throws -> (ProjectOwnedContentFixture, ProjectEditRemoteTarget, ProjectEditModel) {
        let context = ProjectOwnedContentFixture(arguments: flags)
        let rows = try await context.reader.projects(query: .init())
        let target = try XCTUnwrap(ProjectEditRemoteTarget(project: XCTUnwrap(rows.rows.first), readerScope: context.reader.scope))
        let model = ProjectEditModel(coordinator: try XCTUnwrap(context.editor(target)))
        await model.load(); return (context, target, model)
    }
    func testNormalAppSessionRemoteFactoryRejectsGuestWithoutSendingRequests() throws {
        let wire = ProjectOwnedContentFixture.Wire(Data())
        let session = AppSession(runtimeDependencies: .init(transport: wire))
        let row = try JSONDecoder().decode(CreatorContentProject.self, from: Data(#"{"id":71,"bizType":"topic","ownerType":"member"}"#.utf8))
        let target = try XCTUnwrap(ProjectEditRemoteTarget(project: row, readerScope: session.creatorContentReader.scope))
        XCTAssertNil(session.projectEditor(target: target)); XCTAssertEqual(wire.requests, 0)
    }
    func testOwnedListFactoryReusesSameTargetAndFreshServerModeWinsPlaceholder() async throws {
        let (context, target, model) = try await setup()
        XCTAssertTrue(context.editor(target) === model.coordinator); XCTAssertEqual(model.draft.product, .freeExplore)
        XCTAssertEqual(model.draft.baseRevision, "fixture-r2"); XCTAssertTrue(model.canEdit); XCTAssertFalse(model.coordinator.canSubmit)
        model.review(); let captured = try XCTUnwrap(model.confirmation)
        XCTAssertEqual(captured.payload["productType"], .number(2)); XCTAssertEqual(captured.payload["id"], .number(71))
        await model.submit(captured); XCTAssertEqual(context.wire.requests, 1)
    }
    func testBackReopenRequiresExplicitRestoreAndPreservesEditedBytes() async throws {
        let (context, target, model) = try await setup()
        model.draft.name = "  Edited e\u{301}\t"; model.saveLocal(); model.leave()
        let reopened = ProjectEditModel(coordinator: try XCTUnwrap(context.editor(target))); await reopened.load()
        XCTAssertTrue(reopened.canRestore); XCTAssertFalse(reopened.canEdit)
        XCTAssertEqual(reopened.draft.name, "Owned fixture route"); reopened.restore()
        XCTAssertEqual(Array(reopened.draft.name.utf8), Array("  Edited e\u{301}\t".utf8)); XCTAssertTrue(reopened.canEdit)
        XCTAssertEqual(context.wire.requests, 2)
    }
    func testChangedServerVersionKeepsLocalConflictAndCannotOverwriteOrPrepare() async throws {
        let (context, target, model) = try await setup()
        model.draft.name = "Local unsent edit"; model.saveLocal(); model.leave(); let saved = context.storage.data
        context.wire.data = try ProjectEditRemoteFixtures.detail(product: .freeExplore, revision: "fixture-r3")
        let reopened = ProjectEditModel(coordinator: try XCTUnwrap(context.editor(target))); await reopened.load()
        XCTAssertEqual(reopened.restoreKey, "projectEdit.revisionConflict"); XCTAssertFalse(reopened.canRestore); XCTAssertFalse(reopened.canEdit)
        reopened.review(); XCTAssertNil(reopened.confirmation); reopened.saveLocal(); XCTAssertEqual(context.storage.data, saved)
    }
    func testForbiddenEditReadNeverMountsEditableSnapshotAndDoesNotCreateLocalData() async throws {
        let (context, _, model) = try await setup(["--project-owned-denied"])
        XCTAssertNil(model.coordinator.snapshot); XCTAssertEqual(model.coordinator.state, .blocked)
        XCTAssertFalse(model.canEdit); XCTAssertTrue(context.storage.data.isEmpty)
        model.review(); XCTAssertNil(model.confirmation); XCTAssertEqual(context.wire.requests, 1)
    }
    func testAccountChangeClosesOldScopeAndOldReviewDoesNotReachTransport() async throws {
        let (context, target, model) = try await setup(); model.review(); let old = try XCTUnwrap(model.confirmation)
        context.signOut(); XCTAssertNil(context.editor(target)); await model.submit(old); await model.load(force: true)
        XCTAssertFalse(model.canEdit); XCTAssertNil(model.confirmation); XCTAssertEqual(context.wire.requests, 1)
    }
    func testOldNavigationBindingAndScopeRetirementCannotCloseNewSelection() async throws {
        let context = ProjectOwnedContentFixture(arguments: []), navigation = ProjectOwnedContentNavigation()
        let page = try await context.reader.projects(query: .init()), row = try XCTUnwrap(page.rows.first)
        let empty = navigation.presentation(nil), scope = context.reader.scope
        navigation.open(row, scope: scope, reader: context.reader); let old = try XCTUnwrap(navigation.selection)
        let oldDismissal = navigation.presentation(old)
        navigation.open(row, scope: scope, reader: context.reader); let current = try XCTUnwrap(navigation.selection)
        empty.wrappedValue = nil; oldDismissal.wrappedValue = nil; navigation.close(old)
        navigation.retire(scope: UUID()); XCTAssertEqual(navigation.selection?.id, current.id)
        navigation.presentation(current).wrappedValue = nil; XCTAssertNil(navigation.selection)
    }
    func testRetainedOldModelLeaveCancelAndQueuedConfirmationCannotTouchNewHost() async throws {
        let (context, target, old) = try await setup(); old.review(); let captured = try XCTUnwrap(old.confirmation)
        let queued = { await old.submit(captured) }
        let current = ProjectEditModel(coordinator: try XCTUnwrap(context.editor(target))); await current.load()
        current.restore(); current.review(); let replacement = try XCTUnwrap(current.confirmation)
        let requests = context.wire.requests, saved = context.storage.data
        old.leave(); old.cancelReview(); old.restore(); old.discard(); await old.load(force: true); await queued()
        XCTAssertEqual(current.confirmation?.id, replacement.id); XCTAssertEqual(current.coordinator.confirmation?.id, replacement.id)
        XCTAssertTrue(current.reviewIsCurrent(replacement)); XCTAssertEqual(context.storage.data, saved); XCTAssertEqual(context.wire.requests, requests)
    }
    func testLeaveBeforeFirstLoadCannotClaimOrInvalidateAnAlreadyVisibleEditor() async throws {
        let (context, target, current) = try await setup(); current.review(); let review = try XCTUnwrap(current.confirmation)
        let neverAppeared = ProjectEditModel(coordinator: try XCTUnwrap(context.editor(target)))
        neverAppeared.leave(); await neverAppeared.load(); neverAppeared.cancelReview()
        XCTAssertFalse(neverAppeared.ownsVisit); XCTAssertEqual(current.coordinator.confirmation?.id, review.id)
        XCTAssertEqual(context.wire.requests, 1)
    }
    func testFirstLoadLeaveBeforeRedrawCancelsItsOwnReadWithoutMountingSnapshot() async throws {
        let context = ProjectOwnedContentFixture(arguments: [])
        let page = try await context.reader.projects(query: .init())
        let target = try XCTUnwrap(ProjectEditRemoteTarget(project: XCTUnwrap(page.rows.first), readerScope: context.reader.scope))
        let model = ProjectEditModel(coordinator: try XCTUnwrap(context.editor(target)))
        context.wire.beforeReply = { model.leave() }
        await model.load(); XCTAssertFalse(model.canEdit); XCTAssertNil(model.coordinator.snapshot)
        XCTAssertNil(model.confirmation); XCTAssertTrue(context.storage.data.isEmpty)
    }
    func testClaimedReviewClearedBeforeQueuedTaskCannotSubmit() async throws {
        let (context, _, model) = try await setup(); model.review(); let captured = try XCTUnwrap(model.confirmation)
        let queued = { await model.submit(captured) }; model.cancelReview(captured)
        await queued(); XCTAssertNil(model.coordinator.confirmation); XCTAssertEqual(context.wire.requests, 1)
    }
    func testModePickerAndCopyBindOriginalPresentationEvenBeforeFirstRedraw() async throws {
        let (context, _, model) = try await setup(), controller = ProjectEditModeReviewController(model: model)
        let notYetPresented = controller.binding(nil); controller.open()
        let first = try XCTUnwrap(controller.picker), presentation = try XCTUnwrap(controller.presentation)
        notYetPresented.wrappedValue = nil; XCTAssertEqual(controller.presentation?.id, presentation.id)
        controller.select(.city, from: first); let old = try XCTUnwrap(controller.copy)
        controller.open(); let next = try XCTUnwrap(controller.picker)
        controller.select(.city, from: first); controller.cancel(old); controller.binding(presentation).wrappedValue = nil
        XCTAssertEqual(controller.picker?.id, next.id)
        controller.select(.city, from: next); let current = try XCTUnwrap(controller.copy)
        XCTAssertNil(try controller.perform(old)); let copied = try XCTUnwrap(controller.perform(current))
        XCTAssertNil(try controller.perform(current)); await copied.load()
        XCTAssertEqual(copied.snapshot?.draft.product, .city); XCTAssertNil(copied.snapshot?.topicID)
        XCTAssertNil(copied.snapshot?.draft.chapters.first?.nodes.first?.localMetadata["id"])
        XCTAssertEqual(model.draft.product, .freeExplore); XCTAssertEqual(context.wire.requests, 1)
    }
    func testModeCopyDismissalBeforeQueuedConfirmAndRawEditBothPreventPersistence() async throws {
        for rawEdit in [false, true] {
            let (context, _, model) = try await setup(), controller = ProjectEditModeReviewController(model: model)
            controller.open(); controller.select(.city, from: try XCTUnwrap(controller.picker))
            let copy = try XCTUnwrap(controller.copy), before = context.storage.data
            let queued = { try controller.perform(copy) }
            if rawEdit { model.draft.chapters[0].nodes[0].description = "  Raw é\n" }
            else { controller.binding(try XCTUnwrap(controller.presentation)).wrappedValue = nil }
            XCTAssertNil(try queued()); XCTAssertEqual(context.storage.data, before)
        }
    }
    func testModeCopyFromOldEditorHostCannotSaveAfterReplacement() async throws {
        let (context, target, old) = try await setup(), controller = ProjectEditModeReviewController(model: old)
        controller.open(); controller.select(.city, from: try XCTUnwrap(controller.picker)); let copy = try XCTUnwrap(controller.copy)
        let current = ProjectEditModel(coordinator: try XCTUnwrap(context.editor(target))); await current.load()
        let before = context.storage.data
        XCTAssertNil(try controller.perform(copy)); XCTAssertEqual(context.storage.data, before); XCTAssertTrue(current.canEdit)
    }
    func testCityStoryReadbackUsesServerNodeBindingsAndExactPreparedOrder() async throws {
        let (context, _, model) = try await setup(["--project-owned-city"])
        defer { withExtendedLifetime(context) {} }
        XCTAssertEqual(model.draft.product, .city); XCTAssertTrue(model.draft.chapters[0].hasRealStory)
        XCTAssertEqual(model.draft.chapters[0].blocks?.last?.nodeID, model.draft.chapters[0].nodes[0].id)
        model.review(); let review = try XCTUnwrap(model.confirmation)
        XCTAssertEqual(ProjectEditPreparedNodes(payload: review.payload).chapters?.first?.nodes?.first?.value(.templateId).text, "73")
        model.cancelReview(review); XCTAssertNil(model.confirmation)
    }
}
