import XCTest
@testable import QuestifyCore

@MainActor final class WorkshopPaidInstallTests: XCTestCase {
    private static let target: [String: Any] = ["targetDraftId":91,"targetRevision":1,"businessType":"TOPIC","targetPayloadHash":String(repeating:"c",count:64),"mode":"UNRESOLVED","destinationKind":"W18_PRIVATE_COMPONENT_ONLY"]
    private static func data(_ value: [String:Any]) throws -> Data { try JSONSerialization.data(withJSONObject:value, options:.sortedKeys) }
    private static func envelope(_ value: [String:Any]) throws -> Data { try data(["code":200,"data":value]) }
    private static func item() throws -> WorkshopPurchasedItem { try WorkshopPurchasedTestData.decode(WorkshopPurchasedTestData.item) }
    private static func decodedTarget() throws -> WorkshopPaidInstallTarget { try WorkshopPaidInstallWire.decode(WorkshopPaidInstallTarget.self,data:data(target)) }
    private static func command() throws -> WorkshopPaidInstallCommand { try .init(item:item(),target:decodedTarget(),region:"synthetic-region",commercialUse:false,requestID:UUID(uuidString:"00000000-0000-4000-8000-000000000001")!) }
    private static func outcome(_ command:WorkshopPaidInstallCommand,state:String="INSTALLED_PRIVATE_DRAFT") throws -> [String:Any] {
        if state=="NOT_FOUND" {return ["schema":"w18-paid-install-outcome-v1","requestId":command.requestId,"state":state]}
        var value=try JSONSerialization.jsonObject(with:command.wireData()) as! [String:Any]
        value["schema"]="w18-paid-install-outcome-v1";value["state"]=state;value["mode"]="UNRESOLVED";value["holdDeadline"]="2026-10-05T00:05:00Z"
        value["ownedDraftId"]=state=="INSTALLED_PRIVATE_DRAFT" ? 101 as Any:NSNull();value["installedAt"]=state=="INSTALLED_PRIVATE_DRAFT" ? "2026-10-05T00:00:01Z" as Any:NSNull()
        value["professionalTemplateStatus"]="MATERIALIZATION_REQUIRED";value["published"]=false;value["executable"]=false;return value
    }
    @MainActor private final class Memory:TemplateAuthoringStorage {
        var values:[String:Data]=[:];var failWrite=false
        func read(_ key:String)throws->Data?{values[key]}
        func write(_ data:Data,key:String)throws{if failWrite{throw WorkshopPaidInstallIssue.storageUnavailable};values[key]=data}
        func remove(_ key:String)throws{values.removeValue(forKey:key)}
    }
    @MainActor private final class Wire:HTTPTransport,WorkshopPaidInstallMutationTransport {
        let context:RuntimeDependencyContext
        var requests:[URLRequest]=[],writes=0,delayNext=false,commitThenThrow=false
        var committed:WorkshopPaidInstallCommand?
        var suspended:CheckedContinuation<(Data,Int),Never>?
        init(_ context:RuntimeDependencyContext){self.context=context}
        func wait()async{for _ in 0..<1000{if suspended != nil{return};await Task.yield()};XCTFail("Expected suspended synthetic transport")}
        func resume(_ value:(Data,Int)){let old=suspended;suspended=nil;old?.resume(returning:value)}
        func send(_ request:URLRequest)async throws->(Data,Int){
            requests.append(request)
            if delayNext{delayNext=false;return await withCheckedContinuation{suspended=$0}}
            switch request.url!.lastPathComponent{
            case "targets":return(try WorkshopPaidInstallTests.envelope(["schema":"w18-paid-install-targets-v1","scope":"OWNER_DRAFT_METADATA_ONLY","licenseId":"w18-paid-11","checkedAt":"2026-10-05T00:00:00Z","items":[WorkshopPaidInstallTests.target],"hasMore":false,"nextBeforeDraftId":NSNull()]),200)
            case "history":return(try WorkshopPaidInstallTests.envelope(["schema":"w18-paid-install-history-v1","scope":"OWNER_COMMAND_RECEIPTS_ONLY","licenseId":"w18-paid-11","checkedAt":"2026-10-05T00:00:00Z","items":committed.map{[try! WorkshopPaidInstallTests.outcome($0)]} ?? [],"hasMore":false,"nextBeforeCommandKey":NSNull()]),200)
            case "status":let body=try JSONSerialization.jsonObject(with:request.httpBody!) as! [String:Any];if let committed{return(try WorkshopPaidInstallTests.envelope(WorkshopPaidInstallTests.outcome(committed)),200)};return(try WorkshopPaidInstallTests.envelope(["schema":"w18-paid-install-outcome-v1","requestId":body["requestId"]!,"state":"NOT_FOUND"]),200)
            default:throw WorkshopPaidInstallIssue.disabled
            }
        }
        func sendWorkshopPaidInstall(_ request:URLRequest,authorization:WorkshopPaidInstallDispatchAuthorization)async throws->(Data,Int){
            try authorization.consume(request,context:context,revision:authorization.approvalRevision);writes += 1;requests.append(request)
            let command=try WorkshopPaidInstallWire.decode(WorkshopPaidInstallCommand.self,data:request.httpBody!)
            committed=command
            if delayNext{delayNext=false;return await withCheckedContinuation{suspended=$0}}
            if commitThenThrow{throw WorkshopPaidInstallIssue.unavailable}
            return(try WorkshopPaidInstallTests.envelope(WorkshopPaidInstallTests.outcome(command)),200)
        }
    }
    @MainActor private final class Fixture {
        let context:RuntimeDependencyContext,wire:Wire,memory:Memory,item:WorkshopPurchasedItem
        var current:RuntimeDependencyContext?,approval:WorkshopPaidInstallApproval?,unauthorized=0
        lazy var lease=ContentDraftSessionLease(context:context,current:{[weak self] in self?.current})
        lazy var store=try! WorkshopPaidInstallPendingStore(storage:memory,context:context,licenseId:item.licenseId)
        lazy var service=WorkshopPaidInstallService(api:try! APIConfiguration(baseURL:context.baseURL),transport:wire,lease:lease,approval:approval,currentApproval:{[weak self] in self?.approval},onUnauthorized:{[weak self] _ in self?.unauthorized += 1})
        lazy var controller=WorkshopPaidInstallController(item:item,service:service,lease:lease,store:store)
        init(memory:Memory?=nil,approved:Bool=true)throws{
            context = .init(market:.china,baseURL:URL(string:"https://example.com/native")!,role:"player",session:try .init(accountID:7,epoch:1,namespace:"synthetic",token:"synthetic-secret-token"))
            current=context;self.memory=memory ?? Memory();wire=Wire(context);item=try WorkshopPaidInstallTests.item()
            approval=approved ? try WorkshopPaidInstallApproval(context:context,expiresAt:.distantFuture):nil
        }
        func load(_ appearance:WorkshopPaidInstallAppearance)async throws{await (try XCTUnwrap(controller.appear(appearance)))()}
        func review(_ appearance:WorkshopPaidInstallAppearance)throws->WorkshopPaidInstallCommand{
            controller.select(try XCTUnwrap(controller.targets.first),appearance:appearance);controller.chooseRegion("synthetic-region",appearance:appearance);controller.review(appearance:appearance);return try XCTUnwrap(controller.confirmation)
        }
    }
    func testCommandRequiresExplicitRegionAndCommercialPermissionAndKeepsExactCAS()throws{
        let c=try Self.command();XCTAssertEqual(c.targetDraftId,91);XCTAssertEqual(c.targetRevision,1);XCTAssertEqual(c.businessType,"TOPIC")
        XCTAssertThrowsError(try WorkshopPaidInstallCommand(item:Self.item(),target:Self.decodedTarget(),region:"other",commercialUse:false))
        XCTAssertThrowsError(try WorkshopPaidInstallCommand(item:Self.item(),target:Self.decodedTarget(),region:"synthetic-region",commercialUse:true))
        let data=try c.wireData();XCTAssertEqual(try WorkshopPaidInstallWire.decode(WorkshopPaidInstallCommand.self,data:data),c)
        var extra=try JSONSerialization.jsonObject(with:data) as! [String:Any];extra["ownerId"]=7;XCTAssertThrowsError(try WorkshopPaidInstallWire.decode(WorkshopPaidInstallCommand.self,data:Self.data(extra)))
    }
    func testModeTemplatePublicationAndExtraSourceFieldsFailClosed()throws{
        for (key,value) in [("mode","CITY"),("destinationKind","PROFESSIONAL_TEMPLATE"),("sourceJSON","private answer")]{var object=Self.target;object[key]=value;XCTAssertThrowsError(try WorkshopPaidInstallWire.decode(WorkshopPaidInstallTarget.self,data:Self.data(object)))}
        var result=try Self.outcome(Self.command());result["published"]=true;XCTAssertThrowsError(try WorkshopPaidInstallWire.decode(WorkshopPaidInstallOutcome.self,data:Self.data(result)))
        result=try Self.outcome(Self.command());result["professionalTemplateStatus"]="READY";XCTAssertThrowsError(try WorkshopPaidInstallWire.decode(WorkshopPaidInstallOutcome.self,data:Self.data(result)))
    }
    func testOutcomeRequiresExactRequestAndPurchasedSourceTuple()throws{
        let c=try Self.command(),result=try WorkshopPaidInstallWire.decode(WorkshopPaidInstallOutcome.self,data:Self.data(Self.outcome(c)))
        XCTAssertTrue(result.matches(c));XCTAssertTrue(result.state.terminal)
        var changed=try Self.outcome(c);changed["contentHash"]=String(repeating:"d",count:64);XCTAssertFalse(try WorkshopPaidInstallWire.decode(WorkshopPaidInstallOutcome.self,data:Self.data(changed)).matches(c))
        changed=try Self.outcome(c,state:"RESERVED");changed["ownedDraftId"]=1;XCTAssertThrowsError(try WorkshopPaidInstallWire.decode(WorkshopPaidInstallOutcome.self,data:Self.data(changed)))
    }
    func testBoundedDuplicateDeepAndUnknownJsonAreRejected()throws{
        let c=try Self.command(),text=String(data:try c.wireData(),encoding:.utf8)!
        let duplicate=text.replacingOccurrences(of:"{",with:"{\"schema\":\"duplicate\",",options:[],range:text.startIndex..<text.index(after:text.startIndex))
        XCTAssertThrowsError(try WorkshopPaidInstallWire.decode(WorkshopPaidInstallCommand.self,data:Data(duplicate.utf8)))
        XCTAssertThrowsError(try WorkshopPaidInstallWire.decode(WorkshopPaidInstallCommand.self,data:Data((String(repeating:"[",count:1000)+"0"+String(repeating:"]",count:1000)).utf8)))
        XCTAssertThrowsError(try WorkshopPaidInstallWire.decode(WorkshopPaidInstallCommand.self,data:Data(repeating:0,count:4097),maximum:4096))
    }
    func testSaveReadbackPrecedesDispatchAndConfirmedInstallClearsOnlyMatchingPending()async throws{
        let f=try Fixture(),a=WorkshopPaidInstallAppearance();try await f.load(a);let c=try f.review(a),offered=try XCTUnwrap(f.controller.offerSubmit(a,command:c))
        XCTAssertEqual(try f.store.load()?.id,c.id);XCTAssertEqual(f.wire.writes,0)
        await offered();XCTAssertEqual(f.wire.writes,1);XCTAssertEqual(f.controller.phase,.installed);XCTAssertNil(try f.store.load());XCTAssertEqual(f.controller.outcome?.ownedDraftId,101)
    }
    func testStorageFailurePreventsAllMutationDispatch()async throws{
        let f=try Fixture(),a=WorkshopPaidInstallAppearance();try await f.load(a);let c=try f.review(a);f.memory.failWrite=true
        XCTAssertNil(f.controller.offerSubmit(a,command:c));XCTAssertEqual(f.wire.writes,0);XCTAssertEqual(f.controller.issue,.storageUnavailable)
    }
    func testUnknownCommitIsRecoveredWithoutNewUuidOrSecondDispatch()async throws{
        let f=try Fixture(),a=WorkshopPaidInstallAppearance();try await f.load(a);let c=try f.review(a);f.wire.commitThenThrow=true
        await (try XCTUnwrap(f.controller.offerSubmit(a,command:c)))();XCTAssertEqual(f.controller.pending?.id,c.id);XCTAssertEqual(f.controller.issue,.outcomeUnknown)
        await (try XCTUnwrap(f.controller.offerStatus(a)))();XCTAssertEqual(f.controller.phase,.installed);XCTAssertNil(try f.store.load());XCTAssertEqual(f.wire.writes,1)
    }
    func testQueuedSubmitAfterBackCannotDispatchAndReopenKeepsOriginalUuid()async throws{
        let f=try Fixture(),a=WorkshopPaidInstallAppearance();try await f.load(a);let c=try f.review(a),offered=try XCTUnwrap(f.controller.offerSubmit(a,command:c))
        f.controller.close(a);await offered();XCTAssertEqual(f.wire.writes,0);XCTAssertEqual(try f.store.load()?.id,c.id)
        let fresh=WorkshopPaidInstallAppearance();try await f.load(fresh);XCTAssertEqual(f.controller.pending?.id,c.id);XCTAssertEqual(f.controller.outcome?.state,.notFound)
        f.controller.review(appearance:fresh);XCTAssertNil(f.controller.confirmation)
        f.controller.reviewRecovery(appearance:fresh);XCTAssertEqual(f.controller.confirmation?.id,c.id)
    }
    func testOldAppearDisappearAndQueuedReadCannotAffectReplacementPresentation()async throws{
        let f=try Fixture(),old=WorkshopPaidInstallAppearance();let queued=try XCTUnwrap(f.controller.appear(old));f.controller.close(old)
        let fresh=WorkshopPaidInstallAppearance();try await f.load(fresh);let before=f.wire.requests.count
        f.controller.close(old);XCTAssertNil(f.controller.appear(old));await queued();XCTAssertEqual(f.wire.requests.count,before);XCTAssertEqual(f.controller.phase,.ready)
    }
    func testDoubleConfirmAndRepeatedOfferedClosureWriteOnce()async throws{
        let f=try Fixture(),a=WorkshopPaidInstallAppearance();try await f.load(a);let c=try f.review(a),one=try XCTUnwrap(f.controller.offerSubmit(a,command:c))
        XCTAssertNil(f.controller.offerSubmit(a,command:c));await one();await one();XCTAssertEqual(f.wire.writes,1)
    }
    func testCancelConfirmationHasNoPendingRecordOrWrite()async throws{
        let f=try Fixture(),a=WorkshopPaidInstallAppearance();try await f.load(a);let c=try f.review(a);f.controller.cancelReview(appearance:a)
        XCTAssertNil(f.controller.offerSubmit(a,command:c));XCTAssertNil(try f.store.load());XCTAssertEqual(f.wire.writes,0)
    }
    func testCurrent401CallsExpiryButOldClosedRead401DoesNot()async throws{
        for closed in [false,true]{let f=try Fixture(),a=WorkshopPaidInstallAppearance();f.wire.delayNext=true;let action=try XCTUnwrap(f.controller.appear(a));let task=Task{await action()};await f.wire.wait()
            if closed{f.controller.close(a);try await f.load(WorkshopPaidInstallAppearance())}
            f.wire.resume((Data(),401));await task.value;XCTAssertEqual(f.unauthorized,closed ? 0:1)
        }
    }
    func testClosedWrite401CannotExpireCurrentSessionOrEraseRecovery()async throws{
        let f=try Fixture(),a=WorkshopPaidInstallAppearance();try await f.load(a);let c=try f.review(a);f.wire.delayNext=true;let action=try XCTUnwrap(f.controller.offerSubmit(a,command:c)),task=Task{await action()};await f.wire.wait()
        f.controller.close(a);f.wire.resume((Data(),401));await task.value;XCTAssertEqual(f.unauthorized,0);XCTAssertEqual(try f.store.load()?.id,c.id)
    }
    func testDefaultMissingApprovalPerformsZeroRequests()async throws{
        let f=try Fixture(approved:false),a=WorkshopPaidInstallAppearance();try await f.load(a);XCTAssertTrue(f.wire.requests.isEmpty);XCTAssertEqual(f.controller.issue,.disabled)
    }
    func testOwnerRoleTokenAndRealmReplacementInvalidateQueuedActions()async throws{
        let f=try Fixture(),a=WorkshopPaidInstallAppearance();let action=try XCTUnwrap(f.controller.appear(a));f.current=nil;await action();XCTAssertTrue(f.wire.requests.isEmpty);XCTAssertEqual(f.controller.phase,.invalidated)
    }
    func testFreshClientFindsLocallySavedUnknownUuidAcrossEpochWithoutSavingCredential()throws{
        let f=try Fixture(),command=try Self.command();try f.store.save(command)
        let context=RuntimeDependencyContext(market:.china,baseURL:f.context.baseURL,role:"merchant",session:try .init(accountID:7,epoch:9,namespace:"synthetic",token:"new-token"))
        let fresh=try WorkshopPaidInstallPendingStore(storage:f.memory,context:context,licenseId:command.licenseId);XCTAssertEqual(try fresh.load()?.id,command.id)
        XCTAssertFalse(f.memory.values.values.contains{String(data:$0,encoding:.utf8)?.contains("synthetic-secret-token")==true})
        let other=RuntimeDependencyContext(market:.china,baseURL:f.context.baseURL,role:"player",session:try .init(accountID:8,epoch:1,namespace:"synthetic",token:"other"))
        XCTAssertNil(try WorkshopPaidInstallPendingStore(storage:f.memory,context:other,licenseId:command.licenseId).load())
    }
    func testCorruptPendingAndDifferentUuidAreNeverSilentlyOverwritten()throws{
        let f=try Fixture(),c=try Self.command();try f.store.save(c);let original=f.memory.values
        let other=try WorkshopPaidInstallCommand(item:Self.item(),target:Self.decodedTarget(),region:"synthetic-region",commercialUse:false)
        XCTAssertThrowsError(try f.store.save(other));XCTAssertEqual(f.memory.values,original)
        let key=try XCTUnwrap(f.memory.values.keys.first);f.memory.values[key]=Data("{\"format\":null}".utf8);let corrupt=f.memory.values
        XCTAssertThrowsError(try f.store.load());XCTAssertThrowsError(try f.store.save(c));XCTAssertEqual(f.memory.values,corrupt)
    }
    func testCanonicalReadAndSubmitRequestShapesRejectForeignFieldsAndGeneralizedPaths()throws{
        let f=try Fixture(),body=try WorkshopPaidInstallRequest.readBody(.targets,licenseId:"w18-paid-11")
        var request=URLRequest(url:f.context.baseURL.appendingPathComponent("api/workshop/purchased/install/targets"));request.httpMethod="POST";request.httpBody=body;request.setValue(String(body.count),forHTTPHeaderField:"Content-Length");request.setValue("application/json; charset=utf-8",forHTTPHeaderField:"Content-Type");request.setValue("no-store",forHTTPHeaderField:"Cache-Control");request.setValue("no-cache",forHTTPHeaderField:"Pragma");request.cachePolicy = .reloadIgnoringLocalCacheData
        XCTAssertEqual(WorkshopPaidInstallRequest.accepts(request,baseURL:f.context.baseURL),.targets)
        request.httpBody=Data("{\"licenseId\":\"w18-paid-11\",\"owner\":7}".utf8);request.setValue(String(request.httpBody!.count),forHTTPHeaderField:"Content-Length");XCTAssertNil(WorkshopPaidInstallRequest.accepts(request,baseURL:f.context.baseURL))
    }
}
