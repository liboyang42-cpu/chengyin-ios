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
    func testSellingFrozenOwnedEntryDisplaysReadbackAndDisablesEditorActions() async throws {
        let (context, _, model) = try await setup()
        context.wire.data = try ProjectEditRemoteFixtures.detail(product: .city, scope: .sellingFrozen)
        await model.load(force: true)
        XCTAssertEqual(model.coordinator.state, .idle); XCTAssertTrue(model.coordinator.isReadOnly)
        XCTAssertNil(model.coordinator.messageKey)
        XCTAssertEqual(model.draft.name, "Owned fixture route"); XCTAssertEqual(model.draft.product, .city)
        XCTAssertEqual(model.draft.chapters[0].blocks?.last?.nodeID, model.draft.chapters[0].nodes[0].id)
        XCTAssertFalse(model.canEdit); XCTAssertFalse(model.fullEdit); XCTAssertFalse(model.canReview); XCTAssertFalse(model.canSaveLocal)
        let saved = context.storage.data
        model.review(); model.saveLocal(); model.restore(); model.discard(); model.leave()
        XCTAssertNil(model.confirmation); XCTAssertEqual(context.storage.data, saved); XCTAssertEqual(context.wire.requests, 2)
    }
    func testFrozenReopenKeepsPriorLocalDraftAndDoesNotRestoreOrDiscardIt() async throws {
        let (context, target, model) = try await setup()
        model.draft.name = "Local work before selling"; model.saveLocal(); model.leave()
        let saved = context.storage.data
        context.wire.data = try ProjectEditRemoteFixtures.detail(product: .freeExplore, scope: .sellingFrozen)
        let frozen = ProjectEditModel(coordinator: try XCTUnwrap(context.editor(target)))
        await frozen.load(); XCTAssertTrue(frozen.hasRestore); XCTAssertFalse(frozen.canRestore)
        XCTAssertFalse(frozen.canEdit); frozen.restore(); frozen.discard(); frozen.saveLocal()
        XCTAssertEqual(frozen.draft.name, "Owned fixture route"); XCTAssertEqual(context.storage.data, saved)
        frozen.leave(); context.wire.data = try ProjectEditRemoteFixtures.detail(product: .freeExplore)
        let editable = ProjectEditModel(coordinator: try XCTUnwrap(context.editor(target)))
        await editable.load(); XCTAssertTrue(editable.canRestore); editable.restore()
        XCTAssertEqual(editable.draft.name, "Local work before selling"); XCTAssertTrue(editable.canEdit)
    }
    func testAcknowledgedRefreshCanShowFrozenSnapshotWithoutConsumingCompletion() async throws {
        let (context, _, model) = try await setup(["--project-owned-completed"])
        let original = try XCTUnwrap(model.coordinator.pending), saved = context.storage.data
        context.wire.data = try ProjectEditRemoteFixtures.detail(product: .city, revision: "fixture-frozen-r3", scope: .sellingFrozen)
        await model.continueAcknowledged(try XCTUnwrap(model.coordinator.acknowledgedContinuation))
        XCTAssertTrue(model.coordinator.isReadOnly); XCTAssertEqual(model.coordinator.state, .acknowledged)
        XCTAssertEqual(model.draft.baseRevision, "fixture-frozen-r3"); XCTAssertEqual(model.draft.product, .city)
        XCTAssertFalse(model.canEdit); XCTAssertFalse(model.canReview); XCTAssertFalse(model.canSaveLocal)
        XCTAssertEqual(model.coordinator.pending?.operationID, original.operationID); XCTAssertEqual(context.storage.data, saved)
        context.wire.data = try ProjectEditRemoteFixtures.detail(product: .freeExplore, revision: "fixture-editable-r4")
        await model.continueAcknowledged(try XCTUnwrap(model.coordinator.acknowledgedContinuation))
        XCTAssertNil(model.coordinator.pending); XCTAssertTrue(model.canEdit); XCTAssertEqual(model.draft.baseRevision, "fixture-editable-r4")
    }
    func testFullAndWhitelistOwnedReadbackKeepExistingEditingDistinction() async throws {
        for scope in [ProjectEditScope.full, .whitelist] {
            let (context, _, model) = try await setup()
            context.wire.data = try ProjectEditRemoteFixtures.detail(product: .freeExplore, scope: scope)
            await model.load(force: true)
            XCTAssertFalse(model.coordinator.isReadOnly); XCTAssertTrue(model.canEdit); XCTAssertTrue(model.canSaveLocal)
            XCTAssertEqual(model.fullEdit, scope == .full)
            model.draft.name = "Allowed copy edit"; model.review()
            let review = try XCTUnwrap(model.confirmation)
            XCTAssertEqual(review.payload["name"], .string("Allowed copy edit"))
            XCTAssertEqual(review.payload["chapters"] != nil, scope == .full)
            model.cancelReview(); model.leave()
        }
    }
    private final class BundleOwner {
        var session: ProjectEditSession? = try? .init(accountID: 7, epoch: 1, storageNamespace: "frozen-bundle-readback")
    }
    private struct BundleContext {
        let owner: BundleOwner
        let storage: ProjectEditMemoryStorage
        let service: ProjectEditSyntheticService
        let editor: ProjectEditModel
        let cover: OwnedTopicCoverSynthetic
        let review: ApprovedTopicReviewSynthetic
        let publication: ApprovedTopicReleasePublicationSynthetic
    }
    private func bundleContext() async throws -> BundleContext {
        let owner = BundleOwner(), storage = ProjectEditMemoryStorage(), session = try XCTUnwrap(owner.session)
        var draft = ProjectEditSyntheticFixtures.draft(); draft.baseRevision = "owned-bundle-r1"; draft.publishToCreative = false
        let initial = ProjectEditSnapshot(topicID: 7901, draft: draft)
        let service = ProjectEditSyntheticService(scenario: .bundlePending, snapshot: initial)
        let cover = try OwnedTopicCoverSynthetic(session: session, currentSession: { owner.session })
        let review = try ApprovedTopicReviewSynthetic(session: session, currentSession: { owner.session })
        let reader = try ApprovedTopicReleaseSyntheticSource(session: session, currentSession: { owner.session })
        let publication = try ApprovedTopicReleasePublicationSynthetic(session: session, currentSession: { owner.session })
        let coordinator = ProjectEditCoordinator(initial: initial, service: service,
            store: .init(storage: storage), releasePreparationSource: reader, releasePublicationSource: publication,
            releasePublicationJournal: .init(storage: storage), releaseReviewSource: review, releaseReviewJournal: .init(storage: storage),
            ownedCoverSource: cover, ownedCoverJournal: .init(storage: storage), currentSession: { owner.session })
        let editor = ProjectEditModel(coordinator: coordinator)
        await editor.load(); editor.review(); await editor.submit(try XCTUnwrap(editor.confirmation))
        XCTAssertEqual(editor.submissionEvidence?.bundleAcknowledgment?.topicID, 7901)
        XCTAssertEqual(editor.submissionEvidence?.bundleAcknowledgment?.bundledTemplateIDs, [41])
        return .init(owner: owner, storage: storage, service: service, editor: editor, cover: cover, review: review, publication: publication)
    }
    private func freezeBundle(_ context: BundleContext) async throws {
        var draft = context.editor.draft; draft.baseRevision = "frozen-bundle-r2"
        context.service.snapshot = .init(topicID: 7901, scope: .sellingFrozen, draft: draft)
        // Keep the host incarnation unchanged to exercise live scope gates, rather than
        // accidentally relying only on the model's normal successful-read incarnation change.
        let result = await context.editor.coordinator.continueAcknowledged(try XCTUnwrap(context.editor.coordinator.acknowledgedContinuation))
        XCTAssertTrue(result); XCTAssertTrue(context.editor.coordinator.isReadOnly)
    }
    func testFrozenCityV2BundleKeepsReceiptAndReadbackWithoutMutationCapabilities() async throws {
        let context = try await bundleContext(), saved = context.storage.data
        let pending = try XCTUnwrap(context.editor.coordinator.pending)
        try await freezeBundle(context)
        XCTAssertNotNil(context.editor.submissionEvidence?.bundleAcknowledgment)
        let cover = OwnedTopicCoverAuthorPresentation(model: context.editor), opening = try XCTUnwrap(cover.capture())
        XCTAssertTrue(cover.isCurrent(opening)); XCTAssertFalse(cover.mayChange(opening))
        cover.open(opening); let flow = try XCTUnwrap(cover.presentation).flow
        await flow.load(); XCTAssertNotNil(flow.current); XCTAssertTrue(flow.canReadCurrentDetails)
        XCTAssertFalse(flow.canPick); XCTAssertNil(flow.beginPicking()); flow.setPicked(context.cover.picked)
        XCTAssertNil(flow.localReview); XCTAssertFalse(flow.canReviewSelection(context.cover.asset))
        let review = ApprovedTopicReviewPresentation(model: context.editor)
        XCTAssertNil(review.capture())
        let release = ApprovedReleaseAuthorPresentation(model: context.editor)
        release.open(try XCTUnwrap(release.capture())); let read = try XCTUnwrap(release.presentation)
        XCTAssertNil(read.publisher); await read.flow.load()
        guard case .ready = read.flow.state else { return XCTFail("Frozen snapshot reading must remain available") }
        XCTAssertEqual(context.cover.uploadCount, 0); XCTAssertEqual(context.cover.selectCount, 0)
        XCTAssertEqual(context.review.submitCount, 0); XCTAssertEqual(context.publication.publishCount, 0)
        XCTAssertTrue(ProjectEditLocalStore.exactPending(try XCTUnwrap(context.editor.coordinator.pending), pending))
        XCTAssertEqual(context.storage.data, saved)
    }
    func testFrozenBundleRejectsRetainedPickerAndUploadClaimWithoutErasingIntent() async throws {
        for claimed in [false, true] {
            let context = try await bundleContext(), controller = OwnedTopicCoverAuthorPresentation(model: context.editor)
            controller.open(try XCTUnwrap(controller.capture())); let original = try XCTUnwrap(controller.presentation), flow = original.flow
            await flow.load()
            if claimed {
                flow.setPicked(context.cover.picked)
                let claim = try XCTUnwrap(flow.claimUpload(XCTUnwrap(flow.localReview))), saved = context.storage.data
                try await freezeBundle(context); XCTAssertFalse(controller.mayChange(original.opening))
                await flow.upload(claim)
                XCTAssertEqual(context.storage.data, saved)
            } else {
                let picker = try XCTUnwrap(flow.beginPicking()), saved = context.storage.data
                try await freezeBundle(context); XCTAssertFalse(flow.canContinuePicking(picker))
                flow.finishPicking(context.cover.picked, original: picker)
                XCTAssertNil(flow.localReview); XCTAssertEqual(context.storage.data, saved)
            }
            XCTAssertEqual(context.cover.uploadCount, 0); XCTAssertEqual(context.cover.selectCount, 0)
            XCTAssertNotNil(context.editor.submissionEvidence?.bundleAcknowledgment)
        }
    }
    func testFrozenBundleRejectsCapturedReviewAndPublicationClaimsWithJournalsIntact() async throws {
        let reviewContext = try await bundleContext(), review = ApprovedTopicReviewPresentation(model: reviewContext.editor)
        review.open(try XCTUnwrap(review.capture())); let originalReview = try XCTUnwrap(review.presentation)
        await originalReview.flow.load()
        guard case .ready(let capture) = originalReview.flow.state else { return XCTFail() }
        let reviewConfirmation = try XCTUnwrap(originalReview.flow.review(capture))
        let reviewClaim = try XCTUnwrap(originalReview.flow.claim(reviewConfirmation)), reviewSaved = reviewContext.storage.data
        try await freezeBundle(reviewContext)
        XCTAssertFalse(review.isCurrent(originalReview.opening)); XCTAssertFalse(originalReview.flow.canRetryExact)
        await originalReview.flow.submit(reviewClaim)
        XCTAssertEqual(reviewContext.review.submitCount, 0); XCTAssertEqual(reviewContext.storage.data, reviewSaved)

        let releaseContext = try await bundleContext(), release = ApprovedReleaseAuthorPresentation(model: releaseContext.editor)
        release.open(try XCTUnwrap(release.capture())); let originalRelease = try XCTUnwrap(release.presentation)
        await originalRelease.flow.load()
        guard case .ready(let prepared) = originalRelease.flow.state else { return XCTFail() }
        let publisher = try XCTUnwrap(originalRelease.publisher), confirmation = try XCTUnwrap(publisher.review(prepared))
        let claim = try XCTUnwrap(publisher.claim(confirmation)), releaseSaved = releaseContext.storage.data
        try await freezeBundle(releaseContext)
        XCTAssertTrue(release.isCurrent(originalRelease.opening)); XCTAssertTrue(originalRelease.flow.isCurrent)
        XCTAssertFalse(publisher.canPublish); XCTAssertFalse(publisher.canRetryExact)
        await publisher.submit(claim)
        XCTAssertEqual(releaseContext.publication.publishCount, 0); XCTAssertEqual(releaseContext.storage.data, releaseSaved)
    }
    func testFrozenBundleRejectsCapturedCoverSelectionAndLateSelectionAcceptance() async throws {
        for selectedBeforeFreeze in [false, true] {
            let context = try await bundleContext(), controller = OwnedTopicCoverAuthorPresentation(model: context.editor)
            controller.open(try XCTUnwrap(controller.capture())); let original = try XCTUnwrap(controller.presentation), flow = original.flow
            await flow.load(); flow.setPicked(context.cover.picked)
            await flow.upload(try XCTUnwrap(flow.claimUpload(XCTUnwrap(flow.localReview))))
            await flow.readImage(context.cover.asset)
            let confirmation = try XCTUnwrap(flow.reviewSelection(context.cover.asset)), claim = try XCTUnwrap(flow.claimSelection(confirmation))
            if selectedBeforeFreeze { await flow.select(claim) }
            let saved = context.storage.data, selects = context.cover.selectCount
            try await freezeBundle(context)
            if selectedBeforeFreeze {
                controller.acceptedSelection(original)
                if case .selected(let receipt) = flow.state {
                    context.editor.recordCoverSelection(receipt, operationID: original.opening.pending.operationID)
                } else { XCTFail() }
                XCTAssertNil(context.editor.coverSelectionNotice)
            } else { await flow.select(claim) }
            XCTAssertEqual(context.cover.selectCount, selects); XCTAssertEqual(context.storage.data, saved)
            controller.close(original); controller.open(try XCTUnwrap(controller.capture()))
            let reopened = try XCTUnwrap(controller.presentation).flow
            await reopened.load(); XCTAssertTrue(reopened.canReadCurrentDetails); XCTAssertFalse(reopened.canPick)
            XCTAssertEqual(context.storage.data, saved)
        }
    }
}
