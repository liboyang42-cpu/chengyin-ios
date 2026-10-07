import XCTest
@testable import QuestifyCore

@MainActor final class WorkshopCreatorConsentTests: XCTestCase {
    static func data(_ value: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: value, options: .sortedKeys) }
    static func envelope(_ value: [String: Any]) throws -> Data { try data(["code": 200, "data": value]) }
    static func previewJSON() throws -> [String: Any] {
        let content = #"{"schema":"w18-member-text-v1","title":"Synthetic original","description":"原文","merchantGuide":"逐字保留\n第二行","questionName":"Question","questionAnswer":"Answer","bindings":{}}"#
        return ["schema":"w18-creator-public-use-preview-v1", "sourceTemplateId":91, "templateHash":String(repeating:"a",count:64), "packageContentHash":WorkshopCreatorWire.sha(Data(content.utf8)), "packageSourceJson":content, "omittedPlanningMetadata":["categoryId","players"], "disclosureVersion":WorkshopCreatorDisclosure.version, "disclosureHash":WorkshopCreatorDisclosure.hash, "disclosureText":WorkshopCreatorDisclosure.text, "state":"EXPLICIT_CREATOR_CONFIRMATION_REQUIRED", "packageReviewed":false]
    }
    static func preview() throws -> WorkshopCreatorPreview { try WorkshopCreatorWire.decode(WorkshopCreatorPreview.self,data:data(previewJSON())) }
    static func target() throws -> WorkshopCreatorDeclarationTarget { try .init(sourceTemplateId:91,moduleId:"synthetic-package",versionId:"v1",offerVersion:"offer-v1",termsVersion:"terms-v1",termsDocument:"Synthetic complete terms",termsDocumentHash:WorkshopCreatorWire.sha(Data("Synthetic complete terms".utf8)),expiresAt:.distantFuture) }
    static func receipt(_ c: WorkshopCreatorDeclarationCommand) -> [String: Any] {
        ["schema":"w18-creator-public-use-declaration-receipt-v1", "state":"CREATOR_DECLARED_PENDING_PACKAGE_REVIEW", "sourceTemplateId":c.sourceTemplateId, "templateHash":c.expectedTemplateHash, "offerVersion":c.offerVersion, "termsVersion":c.termsVersion, "declaredAt":"2026-10-06T12:00:00.123456Z", "disclosureVersion":WorkshopCreatorDisclosure.version, "disclosureHash":WorkshopCreatorDisclosure.hash, "packageReviewed":false, "listed":false, "licenseIssued":false, "consentReference":["scope":"BUYER_OWN_PUBLISHED_THEMES","consentId":"00000000-0000-4000-8000-000000000001","creatorMemberId":7,"moduleId":c.moduleId,"versionId":c.versionId,"contentHash":c.expectedPackageContentHash,"termsDocumentHash":c.termsDocumentHash,"recordHash":String(repeating:"b",count:64)]]
    }
    @MainActor final class Memory: TemplateAuthoringStorage {
        var values:[String:Data]=[:], fail=false
        func read(_ key:String)throws->Data?{values[key]}
        func write(_ data:Data,key:String)throws{if fail{throw WorkshopCreatorConsentIssue.storage};values[key]=data}
        func remove(_ key:String)throws{values.removeValue(forKey:key)}
    }
    @MainActor final class Wire: HTTPTransport, WorkshopCreatorConsentMutationTransport {
        let context:RuntimeDependencyContext
        var requests:[URLRequest]=[],writes=0,delay=false,commitThenThrow=false
        var committed:WorkshopCreatorDeclarationCommand?
        var suspended:CheckedContinuation<(Data,Int),Never>?
        init(_ context:RuntimeDependencyContext){self.context=context}
        func wait()async{for _ in 0..<1000{if suspended != nil{return};await Task.yield()};XCTFail("Transport did not suspend")}
        func resume401(){let old=suspended;suspended=nil;old?.resume(returning:(Data(),401))}
        func send(_ request:URLRequest)async throws->(Data,Int){
            requests.append(request)
            if delay{delay=false;return await withCheckedContinuation{suspended=$0}}
            if request.url?.lastPathComponent == "preview"{return(try WorkshopCreatorConsentTests.envelope(WorkshopCreatorConsentTests.previewJSON()),200)}
            let body=try JSONSerialization.jsonObject(with:request.httpBody!) as! [String:Any]
            if let committed{return(try WorkshopCreatorConsentTests.envelope(WorkshopCreatorConsentTests.receipt(committed)),200)}
            return(try WorkshopCreatorConsentTests.envelope(["schema":"w18-creator-public-use-declaration-status-v1","state":"NOT_FOUND","requestId":body["requestId"]!]),200)
        }
        func sendWorkshopCreatorConsent(_ request:URLRequest,authorization:WorkshopCreatorConsentDispatchAuthorization)async throws->(Data,Int){
            try authorization.consume(request,context:context,revision:authorization.revision)
            writes += 1;requests.append(request);let command=try WorkshopCreatorWire.decode(WorkshopCreatorDeclarationCommand.self,data:request.httpBody!);committed=command
            if delay{delay=false;return await withCheckedContinuation{suspended=$0}}
            if commitThenThrow{throw WorkshopCreatorConsentIssue.unavailable}
            return(try WorkshopCreatorConsentTests.envelope(WorkshopCreatorConsentTests.receipt(command)),200)
        }
    }
    @MainActor final class Fixture {
        let context:RuntimeDependencyContext,wire:Wire,memory:Memory
        var current:RuntimeDependencyContext?,read:WorkshopCreatorConsentReadApproval?,write:WorkshopCreatorConsentWriteApproval?,choices:[WorkshopCreatorDeclarationTarget],unauthorized=0
        lazy var lease=ContentDraftSessionLease(context:context,current:{[weak self] in self?.current})
        lazy var store=try! WorkshopCreatorConsentPendingStore(storage:memory,context:context,sourceTemplateId:91)
        lazy var service=WorkshopCreatorConsentService(api:try! APIConfiguration(baseURL:context.baseURL),transport:wire,lease:lease,read:read,write:write,currentRead:{[weak self] in self?.read},currentWrite:{[weak self] in self?.write},onUnauthorized:{[weak self] _ in self?.unauthorized += 1})
        lazy var controller=WorkshopCreatorConsentController(sourceTemplateId:91,service:service,lease:lease,store:store,targets:{[weak self] in self?.choices ?? []},canWrite:{[weak self] in self?.write != nil})
        init(reading:Bool=true,writing:Bool=true,memory:Memory?=nil)throws{
            context = .init(market:.china,baseURL:URL(string:"https://example.com/native")!,role:"player",session:try .init(accountID:7,epoch:1,namespace:"synthetic",token:"synthetic-secret",role:"player"))
            current=context;wire=Wire(context);self.memory=memory ?? Memory();choices=[try WorkshopCreatorConsentTests.target()]
            read=reading ? try .init(context:context,expiresAt:.distantFuture):nil;write=writing ? try .init(context:context,expiresAt:.distantFuture):nil
        }
        func load(_ a:WorkshopCreatorConsentAppearance)async throws{await (try XCTUnwrap(controller.appear(a)))()}
        func consent(_ a:WorkshopCreatorConsentAppearance)throws{controller.select(try XCTUnwrap(controller.targets.first),appearance:a);for i in 0..<3{controller.acknowledge(i,value:true,appearance:a)}}
    }
    func testExactOriginalAndOmittedFieldsArePreserved()throws{
        let p=try Self.preview();XCTAssertEqual(p.textFields["merchantGuide"],"逐字保留\n第二行");XCTAssertEqual(p.omittedPlanningMetadata,["categoryId","players"])
        XCTAssertEqual(WorkshopCreatorWire.sha(Data(p.packageSourceJson.utf8)),p.packageContentHash)
    }
    func testAlteredDisclosureSourceHashUnknownFieldAndDuplicateFailClosed()throws{
        for (key,value) in [("disclosureText","expanded rights"),("packageContentHash",String(repeating:"f",count:64)),("arbitrary","extra")]{var p=try Self.previewJSON();p[key]=value;XCTAssertThrowsError(try WorkshopCreatorWire.decode(WorkshopCreatorPreview.self,data:Self.data(p)))}
        let data=try Self.data(Self.previewJSON()),text=String(decoding:data,as:UTF8.self)
        XCTAssertThrowsError(try WorkshopCreatorWire.decode(WorkshopCreatorPreview.self,data:Data(("{\"schema\":\"duplicate\","+text.dropFirst()).utf8)))
        XCTAssertThrowsError(try WorkshopCreatorWire.decode(WorkshopCreatorPreview.self,data:Data((String(repeating:"[",count:1000)+"0"+String(repeating:"]",count:1000)).utf8)))
        XCTAssertThrowsError(try WorkshopCreatorWire.decode(WorkshopCreatorPreview.self,data:Data(repeating:0,count:1_048_577)))
    }
    func testTargetRequiresFullTermsAndExactHash()throws{
        XCTAssertThrowsError(try WorkshopCreatorDeclarationTarget(sourceTemplateId:91,moduleId:"m",versionId:"v",offerVersion:"o",termsVersion:"t",termsDocument:"actual terms",termsDocumentHash:String(repeating:"a",count:64),expiresAt:.distantFuture))
    }
    func testPublishedOrIssuedReceiptAndWrongOwnerNeverSucceed()throws{
        let c=try WorkshopCreatorDeclarationCommand(preview:Self.preview(),target:Self.target())
        for key in ["packageReviewed","listed","licenseIssued"]{var r=Self.receipt(c);r[key]=true;XCTAssertThrowsError(try WorkshopCreatorWire.decode(WorkshopCreatorDeclarationReceipt.self,data:Self.data(r)))}
        let receipt=try WorkshopCreatorWire.decode(WorkshopCreatorDeclarationReceipt.self,data:Self.data(Self.receipt(c)))
        XCTAssertTrue(receipt.matches(c,owner:7));XCTAssertFalse(receipt.matches(c,owner:8))
    }
    func testMissingReadApprovalPerformsZeroRequests()async throws{
        let f=try Fixture(reading:false),a=WorkshopCreatorConsentAppearance();try await f.load(a);XCTAssertTrue(f.wire.requests.isEmpty);XCTAssertEqual(f.controller.issue,.disabled)
    }
    func testMissingTargetOrWriteApprovalAllowsOnlyPreview()async throws{
        for noTarget in [true,false]{let f=try Fixture(writing:noTarget),a=WorkshopCreatorConsentAppearance();if noTarget{f.choices=[]};try await f.load(a)
            XCTAssertNotNil(f.controller.preview);if !noTarget{try f.consent(a)};XCTAssertFalse(f.controller.canConfirm);XCTAssertNil(f.controller.offerConfirm(a));XCTAssertEqual(f.wire.writes,0)
        }
    }
    func testThreeUncheckedAcknowledgmentsAndSaveBeforeWrite()async throws{
        let f=try Fixture(),a=WorkshopCreatorConsentAppearance();try await f.load(a);f.controller.select(try XCTUnwrap(f.controller.targets.first),appearance:a)
        XCTAssertTrue(f.controller.acknowledgments.isEmpty)
        for i in 0..<2{f.controller.acknowledge(i,value:true,appearance:a)};XCTAssertNil(f.controller.offerConfirm(a))
        f.controller.acknowledge(2,value:true,appearance:a);let action=try XCTUnwrap(f.controller.offerConfirm(a))
        XCTAssertNotNil(try f.store.load());XCTAssertEqual(f.wire.writes,0);XCTAssertNil(f.controller.offerConfirm(a));await action();await action()
        XCTAssertEqual(f.wire.writes,1);XCTAssertEqual(f.controller.phase,.recorded);XCTAssertNotNil(try f.store.load())
    }
    func testStorageFailureAndCancelBeforeConfirmationProduceNoWrite()async throws{
        let f=try Fixture(),a=WorkshopCreatorConsentAppearance();try await f.load(a);try f.consent(a);f.memory.fail=true
        XCTAssertNil(f.controller.offerConfirm(a));XCTAssertEqual(f.controller.issue,.storage);XCTAssertEqual(f.wire.writes,0)
        f.controller.close(a);XCTAssertNil(try f.store.load())
    }
    func testQueuedConfirmationAfterBackPreservesUuidWithoutDispatchAndReopenRequiresNewConsent()async throws{
        let f=try Fixture(),old=WorkshopCreatorConsentAppearance();try await f.load(old);try f.consent(old);let action=try XCTUnwrap(f.controller.offerConfirm(old)),id=try XCTUnwrap(f.store.load()?.requestId)
        f.controller.close(old);let fresh=WorkshopCreatorConsentAppearance();try await f.load(fresh);await action()
        XCTAssertEqual(f.wire.writes,0);XCTAssertEqual(f.controller.pending?.requestId,id);XCTAssertTrue(f.controller.acknowledgments.isEmpty);XCTAssertFalse(f.controller.canConfirm)
        f.controller.close(old);XCTAssertNil(f.controller.appear(old));XCTAssertEqual(f.controller.phase,.reviewing)
        try f.consent(fresh);await (try XCTUnwrap(f.controller.offerConfirm(fresh)))();XCTAssertEqual(f.wire.committed?.requestId,id)
    }
    func testQueuedReadAfterCloseCannotStartOrCancelNewPresentation()async throws{
        let f=try Fixture(),old=WorkshopCreatorConsentAppearance(),queued=try XCTUnwrap(f.controller.appear(old));f.controller.close(old)
        let fresh=WorkshopCreatorConsentAppearance();try await f.load(fresh);let before=f.wire.requests.count;await queued();XCTAssertEqual(f.wire.requests.count,before);XCTAssertEqual(f.controller.phase,.reviewing)
    }
    func testCurrent401ExpiresButClosedCancelledAndReplacedActionsDoNot()async throws{
        for change in 0..<4{let f=try Fixture(),a=WorkshopCreatorConsentAppearance();f.wire.delay=true;let action=try XCTUnwrap(f.controller.appear(a)),task=Task{await action()};await f.wire.wait()
            if change==1{f.controller.close(a)};if change==2{task.cancel()};if change==3{await (try XCTUnwrap(f.controller.offerLoad(a)))()}
            f.wire.resume401();await task.value;XCTAssertEqual(f.unauthorized,change==0 ? 1:0)
        }
    }
    func testUnknownCommittedResultIsReadBackWithoutSecondWrite()async throws{
        let f=try Fixture(),a=WorkshopCreatorConsentAppearance();try await f.load(a);try f.consent(a);f.wire.commitThenThrow=true
        await (try XCTUnwrap(f.controller.offerConfirm(a)))();let id=f.controller.pending?.requestId;XCTAssertEqual(f.controller.issue,.unknown)
        await (try XCTUnwrap(f.controller.offerLoad(a)))();XCTAssertEqual(f.controller.phase,.recorded);XCTAssertEqual(f.controller.pending?.requestId,id);XCTAssertEqual(f.wire.writes,1)
    }
    func testChangedTargetOrExpiredWriteBeforeQueuedDispatchDeniesWrite()async throws{
        for targetChanges in [true,false]{let f=try Fixture(),a=WorkshopCreatorConsentAppearance();try await f.load(a);try f.consent(a);let action=try XCTUnwrap(f.controller.offerConfirm(a))
            if targetChanges{f.choices=[]}else{f.write=try .init(context:f.context,expiresAt:.distantPast)};await action();XCTAssertEqual(f.wire.writes,0);XCTAssertNotNil(try f.store.load())
        }
    }
    func testCorruptJournalAndConflictingRequestAreNotOverwritten()throws{
        let f=try Fixture(),c=try WorkshopCreatorDeclarationCommand(preview:Self.preview(),target:Self.target());try f.store.retain(c);let bytes=f.memory.values
        XCTAssertThrowsError(try f.store.retain(WorkshopCreatorDeclarationCommand(preview:Self.preview(),target:Self.target())));XCTAssertEqual(f.memory.values,bytes)
        let key=try XCTUnwrap(f.memory.values.keys.first);f.memory.values[key]=Data("{}".utf8);XCTAssertThrowsError(try f.store.load());XCTAssertThrowsError(try f.store.retain(c));XCTAssertEqual(f.memory.values[key],Data("{}".utf8))
    }
    func testRecoveryScopeSurvivesEpochButIsolatesOtherOwnerAndNeverStoresBodyOrCredential()throws{
        let f=try Fixture(),c=try WorkshopCreatorDeclarationCommand(preview:Self.preview(),target:Self.target());try f.store.retain(c)
        let new=RuntimeDependencyContext(market:.china,baseURL:f.context.baseURL,role:"merchant",session:try .init(accountID:7,epoch:5,namespace:"synthetic",token:"new-secret",role:"merchant"))
        XCTAssertEqual(try WorkshopCreatorConsentPendingStore(storage:f.memory,context:new,sourceTemplateId:91).load()?.requestId,c.requestId)
        let other=RuntimeDependencyContext(market:.china,baseURL:f.context.baseURL,role:"player",session:try .init(accountID:8,epoch:1,namespace:"synthetic",token:"other",role:"player"))
        XCTAssertNil(try WorkshopCreatorConsentPendingStore(storage:f.memory,context:other,sourceTemplateId:91).load())
        for data in f.memory.values.values{let text=String(decoding:data,as:UTF8.self);XCTAssertFalse(text.contains("synthetic-secret"));XCTAssertFalse(text.contains("逐字保留"));XCTAssertFalse(text.contains("Synthetic complete terms"))}
    }
    func testExplicitNextReviewOnlyClearsConfirmedLocalRecord()async throws{
        let f=try Fixture(),a=WorkshopCreatorConsentAppearance();try await f.load(a);try f.consent(a);await (try XCTUnwrap(f.controller.offerConfirm(a)))()
        let action=try XCTUnwrap(f.controller.offerAnotherReview(a));XCTAssertNil(try f.store.load());await action();XCTAssertNil(f.controller.receipt);XCTAssertTrue(f.controller.acknowledgments.isEmpty);XCTAssertEqual(f.wire.writes,1)
    }
}
