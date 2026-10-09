import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class ProjectNodeImageTests:XCTestCase {
    private final class Wire:ProjectNodeImageDispatching {
        var isConfigured=true,failAfterForward=false
        var requests:[URLRequest]=[],reference="https://example.com/node/e%CC%81.jpg"
        var status=200,raw:Data?,beforeForward:(()->Void)?,afterForward:(()->Void)?
        var pause=false,started:XCTestExpectation?,continuation:CheckedContinuation<Void,Never>?
        func send(_ request:URLRequest,authorization:ProjectNodeImageDispatchAuthorization)async throws->(Data,Int){
            if pause{await withCheckedContinuation{continuation=$0;started?.fulfill()}}
            beforeForward?();try authorization.forward(request){requests.append(request)}
            afterForward?();if failAfterForward{throw URLError(.timedOut)}
            return (try raw ?? JSONEncoder().encode(["code":ProjectEditJSON.number(Decimal(status)),"url":.string(reference)]),status)
        }
        func resume(){let c=continuation;continuation=nil;c?.resume()}
    }
    @MainActor private final class Context {
        var session=try! ProjectEditSession(accountID:7,epoch:1,storageNamespace:"node-photo-tests")
        var draft=ProjectEditSyntheticFixtures.draft(),current=true,generation=0
        let identity=try! ProjectEditDraftIdentity(topicID:101),storage=ProjectEditMemoryStorage(),wire=Wire()
        var approval:ProjectNodeImageUploadApproval?
        lazy var journal=ProjectNodeImageJournal(storage:storage)
    }
    private func policy()throws->ProjectNodeImageMediaPolicy{try .init(maximumJPEGBytes:1024,maximumDimension:400,maximumReferenceBytes:8192)}
    private func target(_ c:Context)throws->ProjectNodeImageTarget{try .init(draft:c.draft,identity:c.identity,session:c.session,scope:.full,chapterID:c.draft.chapters[0].id,nodeID:c.draft.chapters[0].nodes[0].id)}
    private func capture(_ c:Context)throws->ProjectNodeImageContext{try .init(target:target(c),session:c.session,identity:c.identity,editorID:UUID(),presentationID:UUID(),draftRevision:c.generation)}
    private func image(_ width:Int=4,_ height:Int=3)throws->RetainedSelectedImage{try .init(jpeg:Data([255,216,255,1,2]),width:width,height:height)}
    private func source(_ c:Context,enabled:Bool=true,picker:Bool=true)throws->ProjectNodeImageUploadClient{
        let config=try APIConfiguration(baseURL:URL(string:"https://example.com")!)
        c.approval=enabled ? try .init(baseURL:config.baseURL,namespace:c.session.storageNamespace,accountID:7,approvedOrigins:["https://example.com"],policy:policy(),nativePicker:picker):nil
        return .init(configuration:config,approval:c.approval,transport:c.wire,credentials:{c.current ? try? .init(session:c.session,token:"synthetic-node-session"):nil},currentApproval:{c.approval})
    }
    private func flow(_ c:Context,_ source:ProjectNodeImageUploadClient)throws->ProjectNodeImageFlow{
        let ctx=try capture(c),revision=c.generation
        return .init(context:ctx,source:source,journal:c.journal,currentDraft:{c.draft},parentCurrent:{c.current && c.generation==revision})
    }
    private func upload(_ f:ProjectNodeImageFlow)async throws{f.load();f.stageCropped(try image());let claim=try XCTUnwrap(f.claimUpload(try XCTUnwrap(f.review)));await f.upload(claim)}
    func testDefaultOffIndependentPickerAndNarrowLocalPolicy()throws{
        let c=Context(),closed=try source(c,enabled:false),ctx=try capture(c);XCTAssertFalse(closed.isCurrent(context:ctx))
        let enabled=try source(c,picker:false);XCTAssertTrue(enabled.isCurrent(context:ctx));XCTAssertFalse(enabled.permitsPicker(context:ctx))
        XCTAssertThrowsError(try ProjectNodeImageMediaPolicy(maximumJPEGBytes:RetainedSelectedImage.maximumBytes+1,maximumDimension:400,maximumReferenceBytes:8192))
        XCTAssertFalse(try policy().permits(image(4,4)));XCTAssertTrue(try policy().permits(image()))
    }
    func testWrongNamespaceAccountBaseAndMissingCheckedTransportFailClosed()throws{
        let c=Context(),client=try source(c),ctx=try capture(c),config=try APIConfiguration(baseURL:URL(string:"https://example.com")!)
        c.session=try .init(accountID:8,epoch:2,storageNamespace:"other");XCTAssertFalse(client.isCurrent(context:ctx))
        let absent=ProjectNodeImageUploadClient(configuration:config,approval:c.approval,credentials:{nil},currentApproval:{c.approval});XCTAssertFalse(absent.isCurrent(context:ctx))
        XCTAssertFalse(try XCTUnwrap(c.approval).matches(configuration:try .init(baseURL:URL(string:"https://elsewhere.example")!),session:ctx.session))
    }
    func testActualClientUsesOnlyImage43AndBindsExactAttemptAndTarget()async throws{
        let c=Context(),client=try source(c),ctx=try capture(c),id=UUID();let receipt=try await client.upload(image(),attemptID:id,context:ctx,isCurrent:{true})
        XCTAssertEqual(receipt.attemptID,id);XCTAssertEqual(receipt.targetID,ctx.target.id);XCTAssertEqual(Data(receipt.reference.utf8),Data(c.wire.reference.utf8))
        let req=try XCTUnwrap(c.wire.requests.first);XCTAssertEqual(req.url?.path,"/api/common/uploadOSS");XCTAssertNil(req.url?.query);XCTAssertEqual(req.httpMethod,"POST")
        let body=String(decoding:try XCTUnwrap(req.httpBody),as:UTF8.self);XCTAssertTrue(body.contains("name=\"bizType\"\r\n\r\nimage_4_3"));XCTAssertFalse(body.contains("image_free"));XCTAssertEqual(c.wire.requests.count,1)
    }
    func testSquareOrWrongDimensionsNeverDispatch()async throws{
        let c=Context(),client=try source(c),ctx=try capture(c)
        for dims in [(4,4),(400,301),(404,303)]{do{_ = try await client.upload(image(dims.0,dims.1),attemptID:UUID(),context:ctx,isCurrent:{true});XCTFail()}catch{}}
        XCTAssertTrue(c.wire.requests.isEmpty)
    }
    func testFinalCheckedForwardRejectsOwnerDraftAndTransportLossAfterSuspension()async throws{
        for mode in 0..<3{
            let c=Context(),client=try source(c),ctx=try capture(c);var valid=true;c.wire.pause=true;c.wire.started=expectation(description:"paused before actual forward")
            let task=Task{try await client.upload(image(),attemptID:UUID(),context:ctx,isCurrent:{valid})};await fulfillment(of:[try XCTUnwrap(c.wire.started)],timeout:3)
            if mode==0{c.current=false}else if mode==1{valid=false}else{c.wire.isConfigured=false};c.wire.resume()
            do{_ = try await task.value;XCTFail()}catch{XCTAssertEqual(error as? ProjectNodeImageFailure,.notSent)};XCTAssertTrue(c.wire.requests.isEmpty)
        }
    }
    func testAuthorizationRejectsChangedBodyAndCannotForwardTwice()throws{
        var request=URLRequest(url:URL(string:"https://example.com/api/common/uploadOSS")!);request.httpMethod="POST";request.httpBody=Data([1,2])
        let authorization=ProjectNodeImageDispatchAuthorization(request:request,validity:{true});var starts=0,changed=request;changed.httpBody=Data([2,1])
        XCTAssertThrowsError(try authorization.forward(changed){starts+=1});XCTAssertFalse(authorization.didForward)
        try authorization.forward(request){starts+=1};XCTAssertEqual(starts,1)
        XCTAssertThrowsError(try authorization.forward(request){starts+=1});XCTAssertEqual(starts,1)
    }
    func testHTTPAndTypedAuthenticationLossNeverReturnsReceipt()async throws{
        let c=Context(),client=try source(c),ctx=try capture(c)
        for code in [401,403]{
            c.wire.status=code;c.wire.raw=nil
            do{_ = try await client.upload(image(),attemptID:UUID(),context:ctx,isCurrent:{true});XCTFail()}catch{XCTAssertEqual(error as? APIError,.unauthorized)}
            c.wire.status=200;c.wire.raw=Data("{\"code\":\(code),\"url\":\"https://example.com/a.jpg\"}".utf8)
            do{_ = try await client.upload(image(),attemptID:UUID(),context:ctx,isCurrent:{true});XCTFail()}catch{XCTAssertEqual(error as? APIError,.unauthorized)}
        }
    }
    func testReturnedUnapprovedOriginsDuplicateKeysAndControlsFailClosed()async throws{
        let c=Context(),client=try source(c),ctx=try capture(c)
        for value in ["https://other.example/a.jpg","file:///a.jpg","https://example.com/a.jpg\n","https://user@example.com/a.jpg"]{
            c.wire.reference=value;do{_ = try await client.upload(image(),attemptID:UUID(),context:ctx,isCurrent:{true});XCTFail(value)}catch{}
        }
        c.wire.raw=Data(#"{"code":200,"url":"https://example.com/a","url":"https://example.com/b"}"#.utf8)
        do{_ = try await client.upload(image(),attemptID:UUID(),context:ctx,isCurrent:{true});XCTFail()}catch{}
    }
    func testCommaURLRemainsRealUnappliedReceipt()async throws{
        let c=Context(),f=try flow(c,source(c));c.wire.reference="https://example.com/a,b.jpg";try await upload(f)
        XCTAssertNotNil(f.receipt);XCTAssertFalse(f.canPick);XCTAssertFalse(f.referenceFitsCSV);XCTAssertFalse(f.canApply);XCTAssertNil(f.draftForApply());XCTAssertNotNil(try c.journal.read(session:c.session,identity:c.identity).entries.first?.receipt)
    }
    func testLiteralCommaGraphemeAndDuplicatesAppendPreservesEveryPriorByte()async throws{
        let c=Context();c.draft.chapters[0].nodes[0].imgUrl="old,\u{301}same,\u{FE0F}same,old"
        let before=c.draft,f=try flow(c,source(c));try await upload(f);let next=try XCTUnwrap(f.draftForApply())
        var expected=before;expected.chapters[0].nodes[0].imgUrl += ","+c.wire.reference
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(next),ProjectEditPendingMaterials.exactData(expected));XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.draft),ProjectEditPendingMaterials.exactData(before))
    }
    func testEmptyCSVAppendsWithoutLeadingDelimiter()async throws{
        let c=Context();c.draft.chapters[0].nodes[0].imgUrl="";let f=try flow(c,source(c));try await upload(f)
        XCTAssertEqual(try XCTUnwrap(f.draftForApply()).chapters[0].nodes[0].imgUrl,c.wire.reference)
    }
    func testMalformedAndNineSlotCSVCannotCaptureNewUpload()throws{
        let c=Context()
        for raw in ["a,,b","a,"," a","[a]",String(repeating:"x,",count:8)+"x"]{c.draft.chapters[0].nodes[0].imgUrl=raw;XCTAssertThrowsError(try target(c),raw)}
    }
    func testCanonicalAmbiguityPendingAndWrongScopeRejectTargets()throws{
        let c=Context();let ci=c.draft.chapters[0].id,ni=c.draft.chapters[0].nodes[0].id
        XCTAssertThrowsError(try ProjectNodeImageTarget(draft:c.draft,identity:c.identity,session:c.session,scope:.whitelist,chapterID:ci,nodeID:ni))
        c.draft.pendingMaterials=[.init(node:c.draft.chapters[0].nodes[0])];XCTAssertThrowsError(try target(c));c.draft.pendingMaterials=nil
        var node=c.draft.chapters[0].nodes[0];node.id="é";c.draft.chapters[0].nodes=[node];node.id="e\u{301}";c.draft.chapters[0].nodes.append(node);XCTAssertThrowsError(try target(c))
    }
    func testUnchangedLookingABAAfterClaimDispatchesNothing()async throws{
        let c=Context(),f=try flow(c,source(c));f.load();f.stageCropped(try image());let claim=try XCTUnwrap(f.claimUpload(try XCTUnwrap(f.review)));c.generation+=1;await f.upload(claim)
        XCTAssertTrue(c.wire.requests.isEmpty);XCTAssertEqual(f.state,.closed);XCTAssertEqual(try c.journal.read(session:c.session,identity:c.identity).entries.count,1)
    }
    func testReviewCancelAndCloseNeverCreateCSVPlaceholder()throws{
        let c=Context(),f=try flow(c,source(c)),before=ProjectEditPendingMaterials.exactData(c.draft);f.load();f.stageCropped(try image());f.cancelReview(try XCTUnwrap(f.review));f.close()
        XCTAssertNil(f.review);XCTAssertTrue(c.wire.requests.isEmpty);XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.draft),before)
    }
    func testIntentFailurePreventsDispatchAndUnknownNeverRetries()async throws{
        let c=Context(),f=try flow(c,source(c));f.load();f.stageCropped(try image());c.storage.failWrites=true;XCTAssertNil(f.claimUpload(try XCTUnwrap(f.review)));XCTAssertTrue(c.wire.requests.isEmpty)
        c.storage.failWrites=false;c.wire.failAfterForward=true;try await upload(f);XCTAssertEqual(f.state,.unknown);XCTAssertFalse(f.canPick)
        let reopened=try flow(c,source(c));reopened.load();XCTAssertFalse(reopened.canPick);XCTAssertEqual(reopened.unresolvedUploadCount,1);XCTAssertEqual(c.wire.requests.count,1)
    }
    func testUnstoredReceiptSurvivesOnlyThisJournalInstanceWithoutAnotherUpload()async throws{
        let c=Context(),client=try source(c),f=try flow(c,client);c.wire.afterForward={c.storage.failWrites=true};try await upload(f);XCTAssertTrue(f.hasUnstoredReceipt);f.close()
        c.storage.failWrites=false;let reopened=try flow(c,client);reopened.load();XCTAssertTrue(reopened.hasUnstoredReceipt);reopened.persistReceipt();XCTAssertTrue(reopened.canApply);XCTAssertEqual(c.wire.requests.count,1)
        XCTAssertNotNil(try ProjectNodeImageJournal(storage:c.storage).read(session:c.session,identity:c.identity).entries.first?.receipt)
    }
    func testExactInverseRejectsMatchingLastURLWithDifferentOtherDraftBytes()async throws{
        let c=Context(),f=try flow(c,source(c));try await upload(f);let receipt=try XCTUnwrap(f.receipt);c.draft=try XCTUnwrap(f.draftForApply());XCTAssertTrue(f.alreadyApplied)
        c.draft.name += "changed";XCTAssertFalse(f.target.hasAppliedReference(receipt,in:c.draft,identity:c.identity,session:c.session))
    }
    func testNinthPhotoColdReceiptOnlyRecoveryDoesNotAppendAgain()async throws{
        let c=Context();c.draft.chapters[0].nodes[0].imgUrl=Array(repeating:"same",count:8).joined(separator:",");let client=try source(c),f=try flow(c,client);try await upload(f)
        c.draft=try XCTUnwrap(f.draftForApply());c.storage.failWrites=true;f.didSaveAppliedDraft();XCTAssertEqual(f.state,.localSaveFailed);f.close();c.storage.failWrites=false
        let journal=ProjectNodeImageJournal(storage:c.storage),entry=try XCTUnwrap(journal.read(session:c.session,identity:c.identity).entries.first),ctx=try ProjectNodeImageContext(target:entry.target,session:c.session,identity:c.identity,editorID:UUID(),presentationID:UUID(),draftRevision:1)
        let recovered=ProjectNodeImageFlow(context:ctx,source:client,journal:journal,recoveryOnly:entry,currentDraft:{c.draft},parentCurrent:{true});recovered.load();XCTAssertTrue(recovered.alreadyApplied);XCTAssertFalse(recovered.canPick)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(recovered.draftForApply()),ProjectEditPendingMaterials.exactData(c.draft));recovered.didSaveAppliedDraft();XCTAssertEqual(recovered.state,.applied);XCTAssertEqual(c.wire.requests.count,1)
    }
    func testJournalExactCASRejectsStaleSnapshotAndKeepsOriginalAttempt()throws{
        let c=Context(),old=try c.journal.read(session:c.session,identity:c.identity),t=try target(c),digest=ProjectNodeImageTarget.hash(Data([1]))
        _ = try c.journal.begin(target:t,digest:digest,expected:old,session:c.session,identity:c.identity)
        XCTAssertThrowsError(try c.journal.begin(target:t,digest:digest,expected:old,session:c.session,identity:c.identity));XCTAssertEqual(try c.journal.read(session:c.session,identity:c.identity).entries.count,1)
    }
}
