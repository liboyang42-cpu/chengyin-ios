import XCTest
@testable import QuestifyCore

@MainActor final class OwnedTopicCoverAuthorFlowTests: XCTestCase {
    private final class Scope { var active = true; var writable = true }
    @MainActor private final class Source: OwnedTopicCoverServing {
        let session: ProjectEditSession
        var currentValue: OwnedTopicCoverCurrent
        let asset: OwnedTopicCoverAsset
        var reads = 0, uploads = 0, selections = 0, statuses = 0, images = 0
        var unknownUpload = false, unknownSelection = false, failCurrent = false, failImage = false, unauthorizedImage = false
        var beforeReceipt: (() -> Void)?
        var active = true
        var commands: [OwnedTopicCoverSelectionCommand] = []
        init(session: ProjectEditSession) throws {
            self.session = session
            asset = try OwnedTopicCoverAsset.decode(.object(["kind":.string("OWNED_TOPIC_COVER_V1"),"policyVersion":.string("OWNED_TOPIC_COVER_V1"),"id":.string("11111111-1111-4111-8111-111111111111"),"assetId":.string("11111111-1111-4111-8111-111111111111"),"sourceVersion":.string("22222222-2222-4222-8222-222222222222"),"contentHash":.string(String(repeating:"a",count:64)),"owner":.number(7),"ownerMemberId":.number(7)]),owner:7)
            currentValue = .init(topicID:101,configVersion:4,selectionVersion:0,contentSlotID:51,selectedAtConfigVersion:nil,selection:.none,availability:.none,asset:nil)
        }
        func isCurrent(session:ProjectEditSession)->Bool { active && self.session == session }
        func permits(_ operation:OwnedTopicCoverOperation,session:ProjectEditSession)->Bool { isCurrent(session:session) }
        func permitsNativePicker(session:ProjectEditSession)->Bool { isCurrent(session:session) }
        func current(topicID:Int,session:ProjectEditSession) async throws->OwnedTopicCoverCurrent { reads += 1;if failCurrent { throw OwnedTopicCoverFailure.unavailable };return currentValue }
        func upload(_ selection:RetainedSelectedImage,session:ProjectEditSession) async throws->OwnedTopicCoverAsset {
            uploads += 1; if unknownUpload { throw OwnedTopicCoverFailure.outcomeUnknown }; beforeReceipt?();return asset
        }
        func receipt(_ command:OwnedTopicCoverSelectionCommand)->OwnedTopicCoverSelectionReceipt {
            .init(topicID:command.topicID,configVersion:command.expectedConfigVersion+1,selectionVersion:command.expectedSelectionVersion+1,contentSlotID:command.expectedContentSlotID,asset:command.asset)
        }
        func select(_ command:OwnedTopicCoverSelectionCommand,session:ProjectEditSession) async throws->OwnedTopicCoverSelectionReceipt {
            selections += 1;commands.append(command)
            if unknownSelection { throw OwnedTopicCoverFailure.outcomeUnknown };beforeReceipt?();return receipt(command)
        }
        func status(_ command:OwnedTopicCoverSelectionCommand,session:ProjectEditSession) async throws->OwnedTopicCoverSelectionReceipt { statuses += 1;commands.append(command);return receipt(command) }
        func content(_ asset:OwnedTopicCoverAsset,session:ProjectEditSession) async throws->Data { images += 1;if unauthorizedImage { throw APIError.unauthorized };if failImage { throw OwnedTopicCoverFailure.unavailable };return Data([1,2,3]) }
    }
    private struct Context {
        let session:ProjectEditSession, scope:Scope, storage:ProjectEditMemoryStorage, journal:OwnedTopicCoverJournal, source:Source, flow:OwnedTopicCoverAuthorFlow
    }
    private func context() throws -> Context {
        let session=try ProjectEditSession(accountID:7,epoch:1,storageNamespace:"cover-flow"),scope=Scope(),storage=ProjectEditMemoryStorage()
        let journal=OwnedTopicCoverJournal(storage:storage),source=try Source(session:session)
        let flow=OwnedTopicCoverAuthorFlow(session:session,topicID:101,source:source,journal:journal,parentCurrent:{scope.active},mayChangeSelection:{scope.writable})
        return .init(session:session,scope:scope,storage:storage,journal:journal,source:source,flow:flow)
    }
    private func image(_ byte:UInt8=1) throws -> RetainedSelectedImage { try .init(jpeg:Data([255,216,255,byte]),width:1,height:1) }
    private func uploaded(_ c:Context) async throws {
        await c.flow.load();c.flow.setPicked(try image());let review=try XCTUnwrap(c.flow.localReview),claim=try XCTUnwrap(c.flow.claimUpload(review));await c.flow.upload(claim)
        XCTAssertEqual(c.flow.uploadedAsset,c.source.asset)
    }
    private func reopened(_ c:Context)->OwnedTopicCoverAuthorFlow {
        .init(session:c.session,topicID:101,source:c.source,journal:c.journal,parentCurrent:{c.scope.active},mayChangeSelection:{c.scope.writable})
    }
    func testPickAndCancelAreLocalAndStaleReviewCannotUploadNewSelection() async throws {
        let c=try context();await c.flow.load();c.flow.setPicked(try image());let old=try XCTUnwrap(c.flow.localReview)
        c.flow.setPicked(try image(2));let current=try XCTUnwrap(c.flow.localReview)
        XCTAssertNil(c.flow.claimUpload(old));c.flow.cancelPicked(old);XCTAssertEqual(c.flow.localReview?.id,current.id)
        c.flow.cancelPicked(current);XCTAssertNil(c.flow.localReview);XCTAssertTrue(c.storage.data.isEmpty);XCTAssertEqual(c.source.uploads,0)
    }
    func testPickingLeaseRejectsQueuedUploadAndOldPickerCompletion() async throws {
        let c=try context();await c.flow.load();c.flow.setPicked(try image());let old=try XCTUnwrap(c.flow.localReview)
        let picker=try XCTUnwrap(c.flow.beginPicking());XCTAssertNil(c.flow.claimUpload(old));XCTAssertNil(c.flow.beginPicking())
        c.flow.finishPicking(try image(2),original:UUID());XCTAssertEqual(c.flow.localReview?.id,old.id)
        c.flow.finishPicking(try image(3),original:picker);XCTAssertNotEqual(c.flow.localReview?.id,old.id);XCTAssertEqual(c.source.uploads,0)
    }
    func testIntentWrittenBeforeDispatchAndCloseAfterClaimNeverUploads() async throws {
        let c=try context();await c.flow.load();c.flow.setPicked(try image());let claim=try XCTUnwrap(c.flow.claimUpload(try XCTUnwrap(c.flow.localReview)))
        XCTAssertEqual(try c.journal.read(session:c.session,topicID:101).uploads.count,1);XCTAssertEqual(c.source.uploads,0)
        c.flow.close();await c.flow.upload(claim);XCTAssertEqual(c.source.uploads,0)
        XCTAssertEqual(try c.journal.read(session:c.session,topicID:101).unresolvedUploadCount,1)
    }
    func testLocalWriteFailureBeforeUploadHasZeroNetworkAndRetainsLocalImage() async throws {
        let c=try context();await c.flow.load();c.flow.setPicked(try image());let review=try XCTUnwrap(c.flow.localReview)
        c.storage.failWrites=true;XCTAssertNil(c.flow.claimUpload(review));XCTAssertEqual(c.flow.localReview?.id,review.id);XCTAssertEqual(c.source.uploads,0)
    }
    func testUnknownUploadSurvivesReopenWithoutAutomaticRetryOrInventedAsset() async throws {
        let c=try context();c.source.unknownUpload=true;await c.flow.load();c.flow.setPicked(try image())
        let claim=try XCTUnwrap(c.flow.claimUpload(try XCTUnwrap(c.flow.localReview)));await c.flow.upload(claim);XCTAssertEqual(c.flow.state,.uploadUnconfirmed);c.flow.close()
        let next=reopened(c);await next.load();XCTAssertNil(next.uploadedAsset);XCTAssertEqual(next.snapshot?.unresolvedUploadCount,1);XCTAssertEqual(c.source.uploads,1)
        next.setPicked(try image(2));XCTAssertEqual(c.source.uploads,1)
    }
    func testReturnedUploadReceiptSurvivesSheetCloseAfterLocalFailureAndRetriesOnlyPersistence() async throws {
        let c=try context();c.source.beforeReceipt={c.storage.failWrites=true};try await uploaded(c)
        XCTAssertEqual(c.flow.state,.uploadReceiptUnstored);XCTAssertFalse(c.flow.canPick);c.flow.close();c.storage.failWrites=false;c.source.beforeReceipt=nil
        let next=reopened(c);await next.load();XCTAssertEqual(next.state,.uploadReceiptUnstored);XCTAssertEqual(next.uploadedAsset,c.source.asset)
        next.persistUploadReceipt();XCTAssertEqual(next.state,.uploaded);XCTAssertEqual(c.source.uploads,1)
        XCTAssertEqual(try c.journal.read(session:c.session,topicID:101).uploads.last?.asset,c.source.asset)
    }
    func testCannotSelectBeforeExplicitCheckedImageReadAndCancelNeverWrites() async throws {
        let c=try context();try await uploaded(c);XCTAssertNil(c.flow.reviewSelection(c.source.asset))
        await c.flow.readImage(c.source.asset);let original=try XCTUnwrap(c.flow.reviewSelection(c.source.asset));c.flow.cancelSelection(original)
        XCTAssertNil(c.flow.selectionReview);XCTAssertTrue(try c.journal.read(session:c.session,topicID:101).selections.isEmpty);XCTAssertEqual(c.source.selections,0)
    }
    func testUnknownSelectionRestoresOnlyOriginalCASRequestAndBlocksReplacement() async throws {
        let c=try context();try await uploaded(c);await c.flow.readImage(c.source.asset)
        let review=try XCTUnwrap(c.flow.reviewSelection(c.source.asset)),claim=try XCTUnwrap(c.flow.claimSelection(review));c.source.unknownSelection=true
        await c.flow.select(claim);XCTAssertEqual(c.flow.state,.selectionUnconfirmed);c.flow.close()
        c.source.currentValue = .init(topicID:101,configVersion:99,selectionVersion:18,contentSlotID:72,selectedAtConfigVersion:nil,selection:.stale,availability:.unavailable,asset:nil)
        let next=reopened(c);await next.load();XCTAssertFalse(next.canPick);XCTAssertTrue(next.hasUnknownSelection)
        let snapshot=try XCTUnwrap(next.snapshot);await next.checkSelection(snapshot)
        guard case .selected(let receipt)=next.state else{return XCTFail()}
        XCTAssertEqual(receipt.configVersion,5);XCTAssertEqual(c.source.commands[0],c.source.commands[1]);XCTAssertEqual(c.source.selections,1);XCTAssertEqual(c.source.statuses,1)
    }
    func testSelectionReceiptWriteFailureSurvivesReopenWithoutAnotherServerWrite() async throws {
        let c=try context();try await uploaded(c);await c.flow.readImage(c.source.asset)
        let claim=try XCTUnwrap(c.flow.claimSelection(try XCTUnwrap(c.flow.reviewSelection(c.source.asset))))
        c.source.beforeReceipt={c.storage.failWrites=true};await c.flow.select(claim);XCTAssertEqual(c.flow.state,.selectionReceiptUnstored);c.flow.close()
        c.storage.failWrites=false;c.source.beforeReceipt=nil;let next=reopened(c);await next.load();XCTAssertEqual(next.state,.selectionReceiptUnstored)
        next.persistSelectionReceipt();guard case .selected=next.state else{return XCTFail()}
        XCTAssertEqual(c.source.selections,1);XCTAssertEqual(c.source.statuses,0)
    }
    func testChangedParentAfterClaimCannotUseQueuedSelectionOrEraseIntent() async throws {
        let c=try context();try await uploaded(c);await c.flow.readImage(c.source.asset)
        let claim=try XCTUnwrap(c.flow.claimSelection(try XCTUnwrap(c.flow.reviewSelection(c.source.asset))));let saved=c.storage.data
        c.scope.active=false;await c.flow.select(claim);XCTAssertEqual(c.source.selections,0);XCTAssertEqual(c.storage.data,saved);XCTAssertEqual(c.flow.state,.closed)
    }
    func testReceivedReceiptCacheIsScopedToOwnerAndDoesNotContainPickedBytes() async throws {
        let c=try context();c.source.beforeReceipt={c.storage.failWrites=true};try await uploaded(c)
        let other=try ProjectEditSession(accountID:8,epoch:2,storageNamespace:c.session.storageNamespace)
        XCTAssertNil(c.journal.receivedUpload(session:other,topicID:101));XCTAssertNotNil(c.journal.receivedUpload(session:c.session,topicID:101))
        for data in c.storage.data.values { XCTAssertNil(data.range(of:try image().jpeg));XCTAssertFalse(String(decoding:data,as:UTF8.self).contains("token")) }
    }
    func testReceivedReceiptCanRecoverLocallyWhenCurrentNetworkReadIsUnavailable() async throws {
        let c=try context();c.source.beforeReceipt={c.storage.failWrites=true};try await uploaded(c);c.flow.close()
        c.storage.failWrites=false;c.source.beforeReceipt=nil;c.source.failCurrent=true;let reads=c.source.reads
        let next=reopened(c);await next.load();XCTAssertEqual(next.state,.uploadReceiptUnstored);XCTAssertEqual(c.source.reads,reads)
        next.persistUploadReceipt();XCTAssertEqual(next.state,.uploaded);XCTAssertEqual(c.source.uploads,1)
    }

    func testUploadReceiptStillSavesLocallyAfterImageFailureChangesVisibleState() async throws {
        let c=try context();c.source.beforeReceipt={c.storage.failWrites=true};try await uploaded(c)
        c.source.failImage=true;await c.flow.readImage(c.source.asset)
        XCTAssertEqual(c.flow.state,.failed(.unavailable));XCTAssertTrue(c.flow.canPersistUploadReceipt);XCTAssertTrue(c.flow.hasUnstoredUploadReceipt);XCTAssertFalse(c.flow.hasUnstoredSelectionReceipt)
        XCTAssertFalse(c.flow.canReadCurrentDetails);XCTAssertFalse(c.flow.canPick)
        c.source.unauthorizedImage=true;await c.flow.readImage(c.source.asset)
        XCTAssertEqual(c.flow.state,.unauthorized);XCTAssertTrue(c.flow.hasUnstoredUploadReceipt);XCTAssertTrue(c.flow.canPersistUploadReceipt)
        let snapshot=try XCTUnwrap(c.flow.snapshot);await c.flow.checkSelection(snapshot);await c.flow.retrySelection(snapshot)
        XCTAssertEqual(c.source.uploads,1);XCTAssertEqual(c.source.selections,0);XCTAssertEqual(c.source.statuses,0)
        c.storage.failWrites=false;c.flow.persistUploadReceipt()
        XCTAssertFalse(c.flow.hasUnstoredReceipt);XCTAssertEqual(c.flow.state,.uploaded)
        XCTAssertEqual(try c.journal.read(session:c.session,topicID:101).uploads.last?.asset,c.source.asset);XCTAssertEqual(c.source.uploads,1)
    }
    func testKnownSelectionReceiptCannotReturnToNetworkRecoveryAfterImageFailure() async throws {
        let c=try context();try await uploaded(c);await c.flow.readImage(c.source.asset)
        let review=try XCTUnwrap(c.flow.reviewSelection(c.source.asset)),claim=try XCTUnwrap(c.flow.claimSelection(review))
        c.source.beforeReceipt={c.storage.failWrites=true};await c.flow.select(claim)
        XCTAssertTrue(c.flow.hasUnstoredSelectionReceipt);c.source.failImage=true;await c.flow.readImage(c.source.asset)
        XCTAssertEqual(c.flow.state,.failed(.unavailable));XCTAssertTrue(c.flow.canPersistSelectionReceipt);XCTAssertTrue(c.flow.hasUnstoredSelectionReceipt)
        c.source.unauthorizedImage=true;await c.flow.readImage(c.source.asset)
        XCTAssertEqual(c.flow.state,.unauthorized);XCTAssertTrue(c.flow.hasUnstoredSelectionReceipt);XCTAssertTrue(c.flow.canPersistSelectionReceipt)
        let original=try XCTUnwrap(c.flow.snapshot);await c.flow.checkSelection(original);await c.flow.retrySelection(original)
        XCTAssertEqual(c.source.selections,1);XCTAssertEqual(c.source.statuses,0);XCTAssertNil(c.flow.claimSelection(review))
        c.storage.failWrites=false;c.flow.persistSelectionReceipt()
        guard case .selected(let receipt)=c.flow.state else{return XCTFail()}
        XCTAssertFalse(c.flow.hasUnstoredReceipt);XCTAssertEqual(receipt.asset,c.source.asset)
        XCTAssertEqual(try c.journal.read(session:c.session,topicID:101).currentSelection?.receipt,receipt)
        XCTAssertEqual(c.source.selections,1);XCTAssertEqual(c.source.statuses,0)
    }

}
