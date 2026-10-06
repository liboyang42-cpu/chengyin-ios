import XCTest
@testable import Questify

@MainActor final class OwnedTopicCoverPresentationTests:XCTestCase {
    private final class Owner{var session:ProjectEditSession?=try? .init(accountID:7,epoch:1,storageNamespace:"owned-cover-host")}
    private struct Context{let owner:Owner,storage:ProjectEditMemoryStorage,source:OwnedTopicCoverSynthetic,editor:ProjectEditModel,controller:OwnedTopicCoverAuthorPresentation}
    private func context(failFirstUploadReceipt:Bool=false)async throws->Context{
        let owner=Owner(),storage=ProjectEditMemoryStorage(),session=try XCTUnwrap(owner.session)
        var failReceipt=failFirstUploadReceipt
        let source=try OwnedTopicCoverSynthetic(session:session,beforeReceipt:{if failReceipt{failReceipt=false;storage.failWrites=true}},currentSession:{owner.session})
        let coordinator=ProjectEditCoordinator(initial:.init(draft:ProjectEditSyntheticFixtures.draft()),service:ProjectEditSyntheticService(scenario:.bundlePending),store:.init(storage:storage),ownedCoverSource:source,ownedCoverJournal:.init(storage:storage),currentSession:{owner.session})
        let editor=ProjectEditModel(coordinator:coordinator);await editor.load();editor.review();await editor.submit(try XCTUnwrap(editor.confirmation))
        XCTAssertNotNil(editor.submissionEvidence?.bundleAcknowledgment)
        return .init(owner:owner,storage:storage,source:source,editor:editor,controller:.init(model:editor))
    }
    private func opened(_ c:Context)throws->OwnedTopicCoverAuthorPresentation.Presentation{
        c.controller.open(try XCTUnwrap(c.controller.capture()));return try XCTUnwrap(c.controller.presentation)
    }
    private func uploaded(_ c:Context,_ model:OwnedTopicCoverAuthorModel)async throws{
        await model.load();await model.choose();model.upload(try XCTUnwrap(model.flow.localReview))
        for _ in 0..<100 where model.flow.uploadedAsset==nil{await Task.yield()}
        XCTAssertEqual(model.flow.uploadedAsset,c.source.asset);await model.read(c.source.asset)
        XCTAssertNotNil(model.image);XCTAssertEqual(model.renderedAsset,c.source.asset)
    }
    func testOldSheetDismissalCannotCloseReplacementPresentation()async throws{
        let c=try await context(),old=try opened(c),oldBinding=c.controller.binding(old)
        c.controller.close(old);let current=try opened(c)
        oldBinding.wrappedValue=nil;c.controller.close(old)
        XCTAssertEqual(c.controller.presentation?.id,current.id);XCTAssertNil(oldBinding.wrappedValue)
        XCTAssertEqual(old.flow.state,.closed);XCTAssertTrue(current.flow.isCurrent)
    }
    func testModelUploadClaimIsSynchronousAndClosingBeforeQueuedTaskSendsNothing()async throws{
        let c=try await context(),original=try opened(c),picker=OwnedTopicCoverSynthetic.Picker(c.source.picked)
        let model=OwnedTopicCoverAuthorModel(original:original,picker:picker,selected:{_ in XCTFail()})
        await model.load();await model.choose();let review=try XCTUnwrap(model.flow.localReview)
        model.upload(review);XCTAssertEqual(try original.opening.journal.read(session:original.opening.session,topicID:7901).uploads.count,1)
        model.close();for _ in 0..<40{await Task.yield()}
        XCTAssertEqual(c.source.uploadCount,0);XCTAssertTrue(picker.cancelled);XCTAssertNil(model.flow.localReview)
    }
    func testCapturedSelectionCancelCannotAffectNewConfirmationAndCloseKeepsOriginalIntent()async throws{
        let c=try await context(),original=try opened(c)
        let model=OwnedTopicCoverAuthorModel(original:original,picker:OwnedTopicCoverSynthetic.Picker(c.source.picked),selected:{_ in XCTFail()})
        try await uploaded(c,model);model.review(c.source.asset);let old=try XCTUnwrap(model.flow.selectionReview),binding=model.binding(model.flow.selectionReview)
        model.cancel(old);model.review(c.source.asset);let current=try XCTUnwrap(model.flow.selectionReview)
        binding.wrappedValue=nil;model.cancel(old);model.confirm(old)
        XCTAssertEqual(model.flow.selectionReview?.id,current.id);XCTAssertEqual(c.source.selectCount,0)
        model.confirm(current);let journal=try original.opening.journal.read(session:original.opening.session,topicID:7901)
        XCTAssertEqual(journal.currentSelection?.command,current.command)
        model.close();for _ in 0..<40{await Task.yield()};XCTAssertEqual(c.source.selectCount,0)
        XCTAssertEqual(try original.opening.journal.read(session:original.opening.session,topicID:7901),journal)
    }
    func testActualViewMethodsRenderVerifiedImageAndKeepSelectionReceiptSeparateFromV2Acknowledgment()async throws{
        let c=try await context(),original=try opened(c),oldPending=try XCTUnwrap(c.editor.coordinator.pending),oldIncarnation=c.editor.editorIncarnation
        let model=OwnedTopicCoverAuthorModel(original:original,picker:OwnedTopicCoverSynthetic.Picker(c.source.picked),selected:{c.controller.acceptedSelection($0)})
        try await uploaded(c,model);model.review(c.source.asset);model.confirm(try XCTUnwrap(model.flow.selectionReview))
        for _ in 0..<100 where c.controller.presentation != nil{await Task.yield()}
        XCTAssertEqual(c.source.uploadCount,1);XCTAssertEqual(c.source.imageCount,1);XCTAssertEqual(c.source.selectCount,1)
        XCTAssertEqual(c.editor.coverSelectionNotice?.asset,c.source.asset);XCTAssertEqual(c.editor.coverSelectionNotice?.configVersion,2)
        XCTAssertTrue(ProjectEditLocalStore.exactPending(try XCTUnwrap(c.editor.coordinator.pending),oldPending))
        XCTAssertNotEqual(c.editor.editorIncarnation,oldIncarnation);XCTAssertNil(c.controller.presentation)
    }
    func testAccountChangeRejectsAlreadyRenderedOldConfirmWithoutMutatingNewOwner()async throws{
        let c=try await context(),original=try opened(c)
        let model=OwnedTopicCoverAuthorModel(original:original,picker:OwnedTopicCoverSynthetic.Picker(c.source.picked),selected:{_ in XCTFail()})
        try await uploaded(c,model);model.review(c.source.asset);let review=try XCTUnwrap(model.flow.selectionReview),before=c.storage.data
        c.owner.session=try .init(accountID:8,epoch:2,storageNamespace:original.opening.session.storageNamespace)
        model.confirm(review);for _ in 0..<20{await Task.yield()}
        XCTAssertEqual(c.source.selectCount,0);XCTAssertEqual(c.storage.data,before);XCTAssertNil(c.editor.coverSelectionNotice)
    }
    @MainActor private final class HeldPicker:OwnedTopicCoverSelecting{
        let started:XCTestExpectation;var continuation:CheckedContinuation<RetainedSelectedImage?,Error>?,cancellations=0
        init(_ started:XCTestExpectation){self.started=started}
        func select()async throws->RetainedSelectedImage?{try await withCheckedThrowingContinuation{continuation=$0;started.fulfill()}}
        func cancel(){cancellations+=1}
        func finish(_ image:RetainedSelectedImage){let old=continuation;continuation=nil;old?.resume(returning:image)}
    }
    func testClosingActualPickerOwnerRejectsLateSelectedImageAndCannotUpload()async throws{
        let c=try await context(),original=try opened(c),began=expectation(description:"picker entered")
        let picker=HeldPicker(began),model=OwnedTopicCoverAuthorModel(original:original,picker:picker,selected:{_ in XCTFail()})
        await model.load();let task=Task{await model.choose()};await fulfillment(of:[began],timeout:3)
        model.close();picker.finish(c.source.picked);await task.value
        XCTAssertEqual(model.flow.state,.closed);XCTAssertNil(model.flow.localReview);XCTAssertEqual(picker.cancellations,1);XCTAssertEqual(c.source.uploadCount,0)
    }
    func testOldImagePanelCloseCannotRetireNewExactReferenceRead()async throws{
        let c=try await context(),session=try XCTUnwrap(c.owner.session),controller=OwnedTopicCoverImagePresentation()
        controller.open(asset:c.source.asset,session:session,source:c.source,parentCurrent:{true});let old=try XCTUnwrap(controller.presentation),binding=controller.binding(controller.presentation)
        controller.close(old);controller.open(asset:c.source.asset,session:session,source:c.source,parentCurrent:{true});let current=try XCTUnwrap(controller.presentation)
        binding.wrappedValue=nil;controller.close(old);XCTAssertEqual(controller.presentation?.id,current.id)
        await current.flow.load();guard case .ready(let bytes)=current.flow.state else{return XCTFail()}
        XCTAssertEqual(bytes,c.source.picked.jpeg);XCTAssertEqual(old.flow.state,.closed)
    }
    func testReceiptFailureReopenRequiresExplicitCurrentReadBeforeSelectionCanContinue()async throws {
        let c=try await context(failFirstUploadReceipt:true),first=try opened(c)
        let initial=OwnedTopicCoverAuthorModel(original:first,picker:OwnedTopicCoverSynthetic.Picker(c.source.picked),selected:{_ in XCTFail()})
        await initial.load();await initial.choose();initial.upload(try XCTUnwrap(initial.flow.localReview))
        for _ in 0..<100 where initial.flow.state != .uploadReceiptUnstored{await Task.yield()}
        XCTAssertEqual(initial.flow.state,.uploadReceiptUnstored);XCTAssertEqual(c.source.uploadCount,1)
        initial.close();c.controller.close(first);c.storage.failWrites=false
        let second=try opened(c),reads=c.source.currentReadCount
        let recovered=OwnedTopicCoverAuthorModel(original:second,selected:{c.controller.acceptedSelection($0)})
        await recovered.load();XCTAssertEqual(recovered.flow.state,.uploadReceiptUnstored)
        XCTAssertNil(recovered.flow.current);XCTAssertEqual(c.source.currentReadCount,reads)
        // Reading exact asset bytes while its receipt awaits storage must not enable a no-op current-read button.
        await recovered.read(c.source.asset);XCTAssertNotNil(recovered.image)
        XCTAssertTrue(recovered.flow.hasUnstoredReceipt);XCTAssertFalse(recovered.flow.canReadCurrentDetails)
        await recovered.loadCurrentDetails();XCTAssertEqual(c.source.currentReadCount,reads)
        XCTAssertFalse(recovered.flow.canReviewSelection(c.source.asset))
        recovered.persistReceipt();XCTAssertEqual(recovered.flow.state,.uploaded);XCTAssertEqual(c.source.uploadCount,1)
        XCTAssertEqual(c.source.currentReadCount,reads);XCTAssertFalse(recovered.flow.hasUnstoredReceipt);XCTAssertTrue(recovered.flow.canReadCurrentDetails)
        XCTAssertFalse(recovered.flow.canReviewSelection(c.source.asset));recovered.review(c.source.asset)
        XCTAssertNil(recovered.flow.selectionReview);XCTAssertEqual(c.source.selectCount,0)
        // The actual 'Read current cover details' action now obtains the missing server CAS.
        await recovered.loadCurrentDetails();XCTAssertEqual(c.source.currentReadCount,reads+1)
        XCTAssertEqual(recovered.flow.current?.configVersion,1);XCTAssertEqual(recovered.flow.current?.contentSlotID,51)
        XCTAssertTrue(recovered.flow.canReviewSelection(c.source.asset));recovered.review(c.source.asset)
        let review=try XCTUnwrap(recovered.flow.selectionReview)
        XCTAssertEqual(review.command.expectedConfigVersion,1);XCTAssertEqual(review.command.expectedSelectionVersion,0);XCTAssertEqual(review.command.expectedContentSlotID,51)
        recovered.confirm(review);for _ in 0..<100 where c.controller.presentation != nil{await Task.yield()}
        XCTAssertEqual(c.source.uploadCount,1);XCTAssertEqual(c.source.imageCount,1);XCTAssertEqual(c.source.selectCount,1)
        XCTAssertEqual(c.editor.coverSelectionNotice?.configVersion,2);XCTAssertNil(c.controller.presentation)
    }

    func testImageFailureKeepsActualModelKnownSelectionInLocalReceiptRecovery()async throws {
        let c=try await context(),original=try opened(c)
        let model=OwnedTopicCoverAuthorModel(original:original,picker:OwnedTopicCoverSynthetic.Picker(c.source.picked),selected:{c.controller.acceptedSelection($0)})
        try await uploaded(c,model);model.review(c.source.asset);c.source.beforeNextReceipt{c.storage.failWrites=true}
        model.confirm(try XCTUnwrap(model.flow.selectionReview))
        for _ in 0..<100 where !model.flow.hasUnstoredSelectionReceipt{await Task.yield()}
        XCTAssertTrue(model.flow.hasUnstoredSelectionReceipt);let snapshot=try XCTUnwrap(model.flow.snapshot)
        c.source.simulateImageReadFailure();await model.read(c.source.asset)
        XCTAssertNil(model.image);XCTAssertTrue(model.flow.hasUnstoredSelectionReceipt);XCTAssertTrue(model.flow.canPersistSelectionReceipt)
        guard case .failed=model.flow.state else{return XCTFail()}
        model.check(snapshot);model.retry(snapshot);for _ in 0..<30{await Task.yield()}
        XCTAssertEqual(c.source.selectCount,1);XCTAssertEqual(c.source.statusCount,0)
        c.storage.failWrites=false;model.persistSelectionReceipt()
        XCTAssertEqual(c.editor.coverSelectionNotice?.asset,c.source.asset);XCTAssertNil(c.controller.presentation)
        XCTAssertEqual(c.source.uploadCount,1);XCTAssertEqual(c.source.selectCount,1);XCTAssertEqual(c.source.statusCount,0)
    }

}
