import XCTest
import UIKit
@testable import Questify

#if DEBUG
@MainActor final class ProjectNodeImageAuthorTests:XCTestCase {
    private final class Owner{var session:ProjectEditSession?=try? .init(accountID:7,epoch:1,storageNamespace:"node-photo-host")}
    private final class Storage:ProjectEditDataStorage{
        var values:[String:Data]=[:],failWrites=false,failMarkerOnce=false
        func read(_ key:String)throws->Data?{values[key]}
        func remove(_ key:String)throws{values[key]=nil}
        func write(_ bytes:Data,key:String)throws{
            if failWrites{throw ProjectEditError.persistenceUnavailable}
            if failMarkerOnce,key.hasPrefix("project-node-image.v1."),let raw=try? JSONDecoder().decode([String:ProjectEditJSON].self,from:bytes),
               raw["entries"]?.array?.contains(where:{$0.object?["applied"] == .bool(true)})==true{failMarkerOnce=false;throw ProjectEditError.persistenceUnavailable}
            values[key]=bytes
        }
    }
    private final class Source:ProjectNodeImageUploading{
        let owner:Owner
        let media=try! ProjectNodeImageMediaPolicy(maximumJPEGBytes:1024*1024,maximumDimension:400,maximumReferenceBytes:8192)
        var enabled=true,uploadCount=0,beforeForward:(()->Void)?
        init(_ owner:Owner){self.owner=owner}
        func isCurrent(context:ProjectNodeImageContext)->Bool{enabled && owner.session==context.session}
        func policy(context:ProjectNodeImageContext)->ProjectNodeImageMediaPolicy?{isCurrent(context:context) ? media:nil}
        func permitsPicker(context:ProjectNodeImageContext)->Bool{isCurrent(context:context)}
        func permitsReference(_ receipt:ProjectNodeUploadedImage,context:ProjectNodeImageContext)->Bool{isCurrent(context:context) && receipt.targetID==context.target.id && Data(receipt.ownerKey.utf8)==Data(context.target.ownerKey.utf8)}
        func upload(_ image:RetainedSelectedImage,attemptID:UUID,context:ProjectNodeImageContext,isCurrent:@escaping @MainActor()->Bool)async throws->ProjectNodeUploadedImage{
            beforeForward?();guard self.isCurrent(context:context),isCurrent(),media.permits(image),!Task.isCancelled else{throw ProjectNodeImageFailure.notSent};uploadCount+=1
            return try .restore(attemptID:attemptID,targetID:context.target.id,ownerKey:context.target.ownerKey,reference:"https://example.com/node/photo.jpg")
        }
    }
    private final class Picker:OwnedTopicCoverSelecting{
        let selected:RetainedSelectedImage?
        init(_ image:RetainedSelectedImage?){selected=image}
        func select()async throws->RetainedSelectedImage?{selected}
        func cancel(){}
    }
    private struct Context{let owner:Owner,storage:Storage,source:Source,editor:ProjectEditModel,presentation:ProjectNodeImagePresentation,baseline:ProjectEditDraft}
    private func selected(_ width:Int=40,_ height:Int=30)throws->RetainedSelectedImage{
        let format=UIGraphicsImageRendererFormat();format.scale=1;format.opaque=true
        let image=UIGraphicsImageRenderer(size:.init(width:width,height:height),format:format).image{c in UIColor.blue.setFill();c.fill(.init(x:0,y:0,width:width,height:height))}
        return try .init(jpeg:XCTUnwrap(image.jpegData(compressionQuality:0.8)),width:width,height:height)
    }
    private func makeEditor(_ draft:ProjectEditDraft,_ owner:Owner,_ storage:Storage,_ source:Source)->ProjectEditModel{
        .init(coordinator:.init(initial:.init(draft:draft),service:ProjectEditSyntheticService(),store:.init(storage:storage),nodeImageSource:source,nodeImageJournal:.init(storage:storage),currentSession:{owner.session}))
    }
    private func context(_ count:Int=1,active:Bool=true)async throws->Context{
        let owner=Owner(),storage=Storage(),source=Source(owner);var draft=ProjectEditSyntheticFixtures.draft()
        draft.chapters[0].nodes[0].imgUrl=Array(repeating:"https://example.com/old.jpg",count:count).joined(separator:",")
        let editor=makeEditor(draft,owner,storage,source);await editor.load();editor.saveLocal()
        let p=ProjectNodeImagePresentation(editor:editor,chapterID:draft.chapters[0].id,nodeID:draft.chapters[0].nodes[0].id);p.setActive(active)
        return .init(owner:owner,storage:storage,source:source,editor:editor,presentation:p,baseline:draft)
    }
    private func open(_ c:Context)throws->ProjectNodeImagePresentation.Presentation{c.presentation.open(try XCTUnwrap(c.presentation.capture()));return try XCTUnwrap(c.presentation.presentation)}
    private func model(_ c:Context,_ p:ProjectNodeImagePresentation.Presentation)throws->ProjectNodeImageAuthorModel{.init(original:p,picker:Picker(try selected()),apply:c.presentation.apply)}
    private func select(_ m:ProjectNodeImageAuthorModel)async throws{m.load();await m.choose();let crop=try XCTUnwrap(m.crop.draft);m.confirmCrop(crop.id,0.5,0.5,1);XCTAssertNotNil(m.flow.review)}
    private func upload(_ m:ProjectNodeImageAuthorModel)async throws{try await select(m);m.upload(try XCTUnwrap(m.flow.review));for _ in 0..<100 where m.flow.busy{await Task.yield()};XCTAssertNotNil(m.flow.receipt)}
    func testReplacementEditorHasDistinctStateObjectHostIdentityDespiteSameNodeIDs()async throws{
        let c=try await context(),old=try open(c),replacement=makeEditor(c.editor.draft,c.owner,c.storage,c.source)
        await replacement.load();replacement.saveLocal()
        let chapter=Data(c.baseline.chapters[0].id.utf8),node=Data(c.baseline.chapters[0].nodes[0].id.utf8)
        let before=ProjectNodeImageHostIdentity(owner:ObjectIdentifier(c.editor),chapter:chapter,node:node)
        let after=ProjectNodeImageHostIdentity(owner:ObjectIdentifier(replacement),chapter:chapter,node:node)
        XCTAssertNotEqual(before,after)
        let fresh=ProjectNodeImagePresentation(editor:replacement,chapterID:c.baseline.chapters[0].id,nodeID:c.baseline.chapters[0].nodes[0].id);fresh.setActive(true)
        let opening=try XCTUnwrap(fresh.capture());XCTAssertEqual(opening.context.editorID,replacement.editorIncarnation)
        XCTAssertNotEqual(opening.context.editorID,old.opening.context.editorID);fresh.open(opening)
        c.presentation.close(old);XCTAssertNotNil(fresh.presentation);XCTAssertTrue(fresh.editor===replacement)
    }
    func testInactiveAndRetiredCaptureCannotOpenAfterReturning()async throws{
        let c=try await context(active:false);XCTAssertNil(c.presentation.capture());c.presentation.setActive(true);let old=try XCTUnwrap(c.presentation.capture());c.presentation.setActive(false);c.presentation.setActive(true);c.presentation.open(old);XCTAssertNil(c.presentation.presentation)
    }
    func testPickerCancelNeverUploadsOrChangesDraft()async throws{
        let c=try await context(),p=try open(c),before=ProjectEditPendingMaterials.exactData(c.editor.draft)
        let m=ProjectNodeImageAuthorModel(original:p,picker:Picker(nil),apply:c.presentation.apply);m.load();await m.choose();XCTAssertNil(m.crop.draft);XCTAssertNil(m.flow.review);XCTAssertEqual(c.source.uploadCount,0);XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.editor.draft),before)
    }
    func testCropCancelNeverStagesOrUploads()async throws{
        let c=try await context(),p=try open(c),m=try model(c,p);m.load();await m.choose();m.cancelCrop(try XCTUnwrap(m.crop.draft).id);XCTAssertNil(m.flow.review);XCTAssertNil(m.crop.draft);XCTAssertEqual(c.source.uploadCount,0)
    }
    func testFixed43RedrawIsExactForPortraitLandscapeAndZoom()throws{
        let policy=try ProjectNodeImageMediaPolicy(maximumJPEGBytes:1024*1024,maximumDimension:400,maximumReferenceBytes:8192)
        for dims in [(41,97),(97,41),(40,30)]{for zoom in [1.0,1.75,4.0]{let d=ProjectNodeImageCrop.Draft(source:try selected(dims.0,dims.1),policy:policy);let image=try ProjectNodeImageCrop.render(d,horizontal:0.7,vertical:0.2,zoom:zoom);XCTAssertEqual(image.width*3,image.height*4);XCTAssertTrue(policy.permits(image))}}
    }
    func testUploadThenExplicitAppendPreservesAllOtherDraftBytes()async throws{
        let c=try await context(),p=try open(c),m=try model(c,p),before=c.editor.draft;try await select(m);XCTAssertEqual(c.source.uploadCount,0)
        m.upload(try XCTUnwrap(m.flow.review));for _ in 0..<100 where m.flow.busy{await Task.yield()};let receipt=try XCTUnwrap(m.flow.receipt)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.editor.draft),ProjectEditPendingMaterials.exactData(before));m.apply()
        var expected=before;expected.chapters[0].nodes[0].imgUrl += ","+receipt.reference
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.editor.draft),ProjectEditPendingMaterials.exactData(expected));XCTAssertEqual(c.source.uploadCount,1);XCTAssertNil(c.presentation.presentation)
    }
    func testSameByteABARejectsQueuedUploadAndAppend()async throws{
        for afterUpload in [false,true]{let c=try await context(),p=try open(c),m=try model(c,p);if afterUpload{try await upload(m)}else{try await select(m)}
            let draft=c.editor.draft;c.editor.draft=draft;if let review=m.flow.review{m.upload(review)};m.apply();for _ in 0..<30{await Task.yield()}
            XCTAssertFalse(p.flow.isCurrent);XCTAssertEqual(c.source.uploadCount,afterUpload ? 1:0);XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.editor.draft),ProjectEditPendingMaterials.exactData(draft))}
    }
    func testBackgroundOwnerAndCapabilityRetirementBeforeQueuedDispatch()async throws{
        for mode in 0..<3{let c=try await context(),p=try open(c),m=try model(c,p);try await select(m);m.upload(try XCTUnwrap(m.flow.review))
            if mode==0{c.presentation.setActive(false)}else if mode==1{c.owner.session=nil}else{c.source.enabled=false};for _ in 0..<60{await Task.yield()};XCTAssertEqual(c.source.uploadCount,0);XCTAssertFalse(p.flow.isCurrent)}
    }
    func testFinalForwardClosureSeesDraftMutationWithoutManualRetirement()async throws{
        let c=try await context(),p=try open(c),m=try model(c,p);try await select(m);c.source.beforeForward={let same=c.editor.draft;c.editor.draft=same};m.upload(try XCTUnwrap(m.flow.review));for _ in 0..<100 where m.flow.busy{await Task.yield()};XCTAssertEqual(c.source.uploadCount,0)
    }
    func testLocalSaveFailureRetainsReceiptAndRetriesWithoutAnotherUpload()async throws{
        let c=try await context(),p=try open(c),m=try model(c,p);try await upload(m);let before=ProjectEditPendingMaterials.exactData(c.editor.draft);c.storage.failWrites=true;m.apply()
        XCTAssertEqual(p.flow.state,.localSaveFailed);XCTAssertNotNil(p.flow.receipt);XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.editor.draft),before);c.storage.failWrites=false;m.apply();XCTAssertEqual(c.source.uploadCount,1);XCTAssertNil(c.presentation.presentation)
    }
    func testNinthPhotoColdRecoveryCannotSelectOrDuplicateAppend()async throws{
        let c=try await context(8),p=try open(c),m=try model(c,p);try await upload(m);c.storage.failMarkerOnce=true;m.apply();XCTAssertEqual(p.flow.state,.localSaveFailed);let exact=ProjectEditPendingMaterials.exactData(c.editor.draft)
        c.presentation.close(p);c.editor.leave();let cold=makeEditor(c.baseline,c.owner,c.storage,c.source);await cold.load();cold.restore()
        let controller=ProjectNodeImagePresentation(editor:cold,chapterID:c.baseline.chapters[0].id,nodeID:c.baseline.chapters[0].nodes[0].id);controller.setActive(true)
        let opening=try XCTUnwrap(controller.capture());XCTAssertNotNil(opening.recoveryOnly);controller.open(opening);let recovered=try XCTUnwrap(controller.presentation);recovered.flow.load();XCTAssertFalse(recovered.flow.canPick);controller.apply(recovered)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(cold.draft),exact);XCTAssertEqual(c.source.uploadCount,1)
    }
    func testRetainedOldCancelCannotCloseReplacementPresentation()async throws{
        let c=try await context(),old=try open(c);c.presentation.close(old);let fresh=try open(c);c.presentation.close(old);XCTAssertEqual(c.presentation.presentation?.id,fresh.id)
    }
    func testCompositionRejectsOtherImagePurposeAndWrongEndpoint()throws{
        let policy=try ProjectNodeImageMediaPolicy(maximumJPEGBytes:1024,maximumDimension:400,maximumReferenceBytes:8192),base=URL(string:"https://example.com")!,id=UUID().uuidString,boundary="ProjectNodeImage-"+id
        var request=URLRequest(url:base.appendingPathComponent("api/common/uploadOSS"));request.httpMethod="POST";request.setValue("multipart/form-data; boundary="+boundary,forHTTPHeaderField:"Content-Type")
        var body=Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"bizType\"\r\n\r\nimage_4_3\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"node.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8);body.append(contentsOf:[255,216,255,1]);body.append(Data("\r\n--\(boundary)--\r\n".utf8));request.httpBody=body
        XCTAssertTrue(ProjectNodeImageCompositionRoute.accepts(request,baseURL:base,policy:policy));request.url=base.appendingPathComponent("api/common/other");XCTAssertFalse(ProjectNodeImageCompositionRoute.accepts(request,baseURL:base,policy:policy));request.url=base.appendingPathComponent("api/common/uploadOSS")
        request.httpBody=Data(String(decoding:body,as:UTF8.self).replacingOccurrences(of:"image_4_3",with:"image_free").utf8);XCTAssertFalse(ProjectNodeImageCompositionRoute.accepts(request,baseURL:base,policy:policy))
    }
}
#endif
