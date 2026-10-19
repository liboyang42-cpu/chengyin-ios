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
        var scripted:[String:[(Data,Int)]]=[:]
        var committed:WorkshopPaidInstallCommand?
        var suspended:CheckedContinuation<(Data,Int),Never>?
        init(_ context:RuntimeDependencyContext){self.context=context}
        func wait()async{for _ in 0..<1000{if suspended != nil{return};await Task.yield()};XCTFail("Expected suspended synthetic transport")}
        func resume(_ value:(Data,Int)){let old=suspended;suspended=nil;old?.resume(returning:value)}
        func send(_ request:URLRequest)async throws->(Data,Int){
            requests.append(request)
            if delayNext{delayNext=false;return await withCheckedContinuation{suspended=$0}}
            let route=request.url!.lastPathComponent
            if var responses=scripted[route], !responses.isEmpty {
                let response=responses.removeFirst();scripted[route]=responses;return response
            }
            switch route{
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
    private static let historyCursor = String(repeating: "a", count: 64)
    private static func receipt(_ index: Int) throws -> [String: Any] {
        let requestID = UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index))!
        let command = try WorkshopPaidInstallCommand(item: item(), target: decodedTarget(), region: "synthetic-region", commercialUse: false, requestID: requestID)
        return try outcome(command)
    }
    private static func historyPage(_ ids: [Int], cursor: String? = nil) throws -> (Data, Int) {
        (try envelope(["schema":"w18-paid-install-history-v1", "scope":"OWNER_COMMAND_RECEIPTS_ONLY",
                      "licenseId":"w18-paid-11", "checkedAt":"2026-10-05T00:00:00Z",
                      "items":try ids.map { try receipt($0) }, "hasMore":cursor != nil,
                      "nextBeforeCommandKey":cursor as Any? ?? NSNull()]), 200)
    }
    private static func targetPage(_ ids: [Int], cursor: Int? = nil) throws -> (Data, Int) {
        let rows = ids.map { id -> [String: Any] in var row = target; row["targetDraftId"] = id; return row }
        return (try envelope(["schema":"w18-paid-install-targets-v1", "scope":"OWNER_DRAFT_METADATA_ONLY",
                              "licenseId":"w18-paid-11", "checkedAt":"2026-10-05T00:00:00Z",
                              "items":rows, "hasMore":cursor != nil,
                              "nextBeforeDraftId":cursor as Any? ?? NSNull()]), 200)
    }
    func testHistoryContinuationKeepsPriorResultsAndNeverReloadsTargets() async throws {
        let f = try Fixture(), a = WorkshopPaidInstallAppearance()
        f.wire.scripted["history"] = [try Self.historyPage(Array(1...50), cursor: Self.historyCursor), try Self.historyPage([50, 51])]
        try await f.load(a)
        let earlier = try XCTUnwrap(f.controller.history.first), targets = f.controller.targets
        let start = f.wire.requests.count
        let action = try XCTUnwrap(f.controller.offerLoad(a, beforeHistory: Self.historyCursor))
        XCTAssertTrue(f.controller.loadingPage); XCTAssertEqual(f.controller.history.count, 50)
        await action()
        XCTAssertEqual(f.wire.requests.count, start + 1)
        XCTAssertEqual(f.wire.requests.last?.url?.lastPathComponent, "history")
        XCTAssertEqual(f.controller.history.count, 51); XCTAssertEqual(f.controller.targets, targets)
        XCTAssertNil(f.controller.nextHistoryCursor); XCTAssertFalse(f.controller.loadingPage)
        XCTAssertNotNil(f.controller.installedTextReference(earlier, appearance: a))
        XCTAssertEqual(f.wire.writes, 0)
    }
    func testTargetContinuationKeepsHistoryAndChosenTarget() async throws {
        let f = try Fixture(), a = WorkshopPaidInstallAppearance()
        f.wire.scripted["history"] = [try Self.historyPage([1])]
        f.wire.scripted["targets"] = [try Self.targetPage(Array((51...100).reversed()), cursor: 51), try Self.targetPage([50, 49])]
        try await f.load(a)
        let first = try XCTUnwrap(f.controller.targets.first), receipts = f.controller.history
        f.controller.select(first, appearance: a); f.controller.chooseRegion("synthetic-region", appearance: a)
        let start = f.wire.requests.count
        await (try XCTUnwrap(f.controller.offerLoad(a, beforeTarget: 51)))()
        XCTAssertEqual(f.wire.requests.count, start + 1); XCTAssertEqual(f.controller.targets.count, 52)
        XCTAssertEqual(f.controller.history, receipts); XCTAssertEqual(f.controller.target, first)
        XCTAssertEqual(f.controller.region, "synthetic-region"); XCTAssertNil(f.controller.nextTargetCursor)
        XCTAssertEqual(f.wire.writes, 0)
    }
    func testFailedContinuationPreservesResultsAndRetriesSameCursor() async throws {
        let f = try Fixture(), a = WorkshopPaidInstallAppearance()
        f.wire.scripted["history"] = [try Self.historyPage(Array(1...50), cursor: Self.historyCursor), (Data(), 500), try Self.historyPage([51])]
        try await f.load(a); let before = f.controller.history
        await (try XCTUnwrap(f.controller.offerLoad(a, beforeHistory: Self.historyCursor)))()
        XCTAssertEqual(f.controller.history, before); XCTAssertEqual(f.controller.nextHistoryCursor, Self.historyCursor)
        XCTAssertNotNil(f.controller.pageIssue); XCTAssertEqual(f.controller.phase, .ready)
        XCTAssertNotNil(f.controller.installedTextReference(before[0], appearance: a))
        await (try XCTUnwrap(f.controller.offerLoad(a, beforeHistory: Self.historyCursor)))()
        XCTAssertEqual(f.controller.history.count, 51); XCTAssertNil(f.controller.pageIssue)
        let reads = f.wire.requests.filter { $0.url?.lastPathComponent == "history" }
        XCTAssertEqual(reads[1].httpBody, reads[2].httpBody); XCTAssertEqual(f.wire.writes, 0)
    }
    func testRepeatedCursorCannotReplaceEarlierResults() async throws {
        let f = try Fixture(), a = WorkshopPaidInstallAppearance()
        f.wire.scripted["history"] = [try Self.historyPage(Array(1...50), cursor: Self.historyCursor), try Self.historyPage(Array(51...100), cursor: Self.historyCursor)]
        try await f.load(a); let before = f.controller.history
        await (try XCTUnwrap(f.controller.offerLoad(a, beforeHistory: Self.historyCursor)))()
        XCTAssertEqual(f.controller.history, before); XCTAssertEqual(f.controller.pageIssue, .malformed)
        XCTAssertEqual(f.controller.nextHistoryCursor, Self.historyCursor)
        XCTAssertNil(f.controller.offerLoad(a, beforeTarget: 99, beforeHistory: Self.historyCursor))
        XCTAssertNil(f.controller.offerLoad(a, beforeHistory: String(repeating:"b", count:64)))
    }
    func testLatePageCannotClearReplacementBusyOrPublishOldResults() async throws {
        let f = try Fixture(), old = WorkshopPaidInstallAppearance()
        f.wire.scripted["history"] = [try Self.historyPage(Array(1...50), cursor: Self.historyCursor)]
        try await f.load(old); f.wire.delayNext = true
        let task = Task { await (try! XCTUnwrap(f.controller.offerLoad(old, beforeHistory: Self.historyCursor)))() }
        await f.wire.wait(); f.controller.close(old)
        let fresh = WorkshopPaidInstallAppearance(), queued = try XCTUnwrap(f.controller.appear(fresh))
        f.wire.resume(try Self.historyPage([51])); await task.value
        XCTAssertEqual(f.controller.phase, .loading); XCTAssertTrue(f.controller.history.isEmpty)
        await queued(); XCTAssertEqual(f.controller.phase, .ready); XCTAssertEqual(f.wire.writes, 0)
    }
    func testUnauthorizedContinuationClearsProtectedReceipts() async throws {
        let f = try Fixture(), a = WorkshopPaidInstallAppearance()
        f.wire.scripted["history"] = [try Self.historyPage(Array(1...50), cursor: Self.historyCursor), (Data(), 401)]
        try await f.load(a); let old = try XCTUnwrap(f.controller.history.first)
        await (try XCTUnwrap(f.controller.offerLoad(a, beforeHistory: Self.historyCursor)))()
        XCTAssertEqual(f.controller.phase, .invalidated); XCTAssertTrue(f.controller.history.isEmpty)
        XCTAssertNil(f.controller.installedTextReference(old, appearance: a)); XCTAssertEqual(f.wire.writes, 0)
    }

    func testPendingStatusCannotReplaceOwnedPaginationAndRemainsAvailableAfterPage() async throws {
        let f = try Fixture(), a = WorkshopPaidInstallAppearance()
        try f.store.save(Self.command())
        f.wire.scripted["history"] = [try Self.historyPage(Array(1...50), cursor: Self.historyCursor), try Self.historyPage([51])]
        try await f.load(a)
        let page = try XCTUnwrap(f.controller.offerLoad(a, beforeHistory: Self.historyCursor))
        XCTAssertNil(f.controller.offerStatus(a)); XCTAssertTrue(f.controller.loadingPage)
        await page(); XCTAssertFalse(f.controller.loadingPage)
        let status = try XCTUnwrap(f.controller.offerStatus(a))
        XCTAssertEqual(f.controller.phase, .loading)
        await status(); XCTAssertEqual(f.controller.phase, .ready); XCTAssertFalse(f.controller.loadingPage)
        XCTAssertEqual(f.wire.writes, 0)
    }
    func testInitialTargetFailureCanBeExplicitlyReloadedWithoutInstallation() async throws {
        let f = try Fixture(), a = WorkshopPaidInstallAppearance()
        f.wire.scripted["history"] = [try Self.historyPage([1]), try Self.historyPage([1])]
        f.wire.scripted["targets"] = [(Data(), 500), try Self.targetPage([91])]
        try await f.load(a)
        XCTAssertEqual(f.controller.phase, .ready); XCTAssertNotNil(f.controller.targetIssue)
        XCTAssertEqual(f.controller.history.count, 1)
        await (try XCTUnwrap(f.controller.offerLoad(a)))()
        XCTAssertNil(f.controller.targetIssue); XCTAssertEqual(f.controller.targets.count, 1)
        XCTAssertEqual(f.wire.writes, 0)
    }
    func testCursorCycleRejectsSecondContinuationWithoutErasingEarlierPages() async throws {
        let f = try Fixture(), a = WorkshopPaidInstallAppearance(), second = String(repeating: "9", count: 64)
        f.wire.scripted["history"] = [try Self.historyPage(Array(1...50), cursor: Self.historyCursor),
                                    try Self.historyPage(Array(51...100), cursor: second),
                                    try Self.historyPage(Array(101...150), cursor: Self.historyCursor)]
        try await f.load(a)
        await (try XCTUnwrap(f.controller.offerLoad(a, beforeHistory: Self.historyCursor)))()
        await (try XCTUnwrap(f.controller.offerLoad(a, beforeHistory: second)))()
        XCTAssertEqual(f.controller.history.count, 100); XCTAssertEqual(f.controller.nextHistoryCursor, second)
        XCTAssertEqual(f.controller.pageIssue, .malformed); XCTAssertFalse(f.controller.loadingPage)
    }
    func testInitialTargetUnauthorizedClearsAlreadyReadHistory() async throws {
        let f = try Fixture(), a = WorkshopPaidInstallAppearance()
        f.wire.scripted["history"] = [try Self.historyPage([1])]
        f.wire.scripted["targets"] = [(Data(), 401)]
        try await f.load(a)
        XCTAssertEqual(f.controller.phase, .invalidated); XCTAssertTrue(f.controller.history.isEmpty)
        XCTAssertTrue(f.controller.targets.isEmpty); XCTAssertEqual(f.wire.writes, 0)
    }
    func testRefreshUnauthorizedClearsPreviouslyReadResults() async throws {
        let f = try Fixture(), a = WorkshopPaidInstallAppearance()
        f.wire.scripted["history"] = [try Self.historyPage([1]), (Data(), 401)]
        try await f.load(a); XCTAssertEqual(f.controller.history.count, 1)
        await (try XCTUnwrap(f.controller.offerLoad(a)))()
        XCTAssertEqual(f.controller.phase, .invalidated); XCTAssertTrue(f.controller.history.isEmpty)
        XCTAssertTrue(f.controller.targets.isEmpty)
    }

    func testConflictingReceiptPageIsRejectedAtomically() async throws {
        let f = try Fixture(), a = WorkshopPaidInstallAppearance()
        var changed = try Self.receipt(1); changed["ownedDraftId"] = 102
        let response = try Self.envelope(["schema":"w18-paid-install-history-v1", "scope":"OWNER_COMMAND_RECEIPTS_ONLY",
                                         "licenseId":"w18-paid-11", "checkedAt":"2026-10-05T00:00:00Z",
                                         "items":[try Self.receipt(51), changed], "hasMore":false, "nextBeforeCommandKey":NSNull()])
        f.wire.scripted["history"] = [try Self.historyPage(Array(1...50), cursor: Self.historyCursor), (response, 200)]
        try await f.load(a); let before = f.controller.history
        await (try XCTUnwrap(f.controller.offerLoad(a, beforeHistory: Self.historyCursor)))()
        XCTAssertEqual(f.controller.history, before); XCTAssertEqual(f.controller.pageIssue, .malformed)
        XCTAssertEqual(f.controller.nextHistoryCursor, Self.historyCursor)
    }
    func testTargetPageFailureKeepsSelectionAndRetriesWithoutReloadingReceipts() async throws {
        let f = try Fixture(), a = WorkshopPaidInstallAppearance()
        f.wire.scripted["targets"] = [try Self.targetPage(Array((51...100).reversed()), cursor: 51), (Data(), 500), try Self.targetPage([50])]
        try await f.load(a); let chosen = try XCTUnwrap(f.controller.targets.first)
        f.controller.select(chosen, appearance: a)
        await (try XCTUnwrap(f.controller.offerLoad(a, beforeTarget: 51)))()
        XCTAssertEqual(f.controller.targets.count, 50); XCTAssertEqual(f.controller.target, chosen)
        XCTAssertEqual(f.controller.nextTargetCursor, 51); XCTAssertNotNil(f.controller.pageIssue)
        await (try XCTUnwrap(f.controller.offerLoad(a, beforeTarget: 51)))()
        XCTAssertEqual(f.controller.targets.count, 51); XCTAssertNil(f.controller.pageIssue)
        XCTAssertEqual(f.wire.requests.filter { $0.url?.lastPathComponent == "history" }.count, 1)
        XCTAssertEqual(f.wire.writes, 0)
    }

    func testEmptyTerminalPagesRetainEarlierResultsAndEndPagination() async throws {
        let f = try Fixture(), a = WorkshopPaidInstallAppearance()
        f.wire.scripted["history"] = [try Self.historyPage(Array(1...50), cursor: Self.historyCursor), try Self.historyPage([])]
        f.wire.scripted["targets"] = [try Self.targetPage(Array((51...100).reversed()), cursor: 51), try Self.targetPage([])]
        try await f.load(a); let history = f.controller.history, targets = f.controller.targets
        await (try XCTUnwrap(f.controller.offerLoad(a, beforeHistory: Self.historyCursor)))()
        await (try XCTUnwrap(f.controller.offerLoad(a, beforeTarget: 51)))()
        XCTAssertEqual(f.controller.history, history); XCTAssertEqual(f.controller.targets, targets)
        XCTAssertNil(f.controller.nextHistoryCursor); XCTAssertNil(f.controller.nextTargetCursor)
        XCTAssertNil(f.controller.pageIssue); XCTAssertEqual(f.controller.phase, .ready)
    }
    func testOnlyOneCollectionPageIsOfferedAtATime() async throws {
        let f = try Fixture(), a = WorkshopPaidInstallAppearance()
        f.wire.scripted["history"] = [try Self.historyPage(Array(1...50), cursor: Self.historyCursor), try Self.historyPage([51])]
        f.wire.scripted["targets"] = [try Self.targetPage(Array((51...100).reversed()), cursor: 51), try Self.targetPage([50])]
        try await f.load(a)
        let history = try XCTUnwrap(f.controller.offerLoad(a, beforeHistory: Self.historyCursor))
        XCTAssertNil(f.controller.offerLoad(a, beforeTarget: 51))
        await history()
        await (try XCTUnwrap(f.controller.offerLoad(a, beforeTarget: 51)))()
        XCTAssertEqual(f.controller.history.count, 51); XCTAssertEqual(f.controller.targets.count, 51)
        XCTAssertFalse(f.controller.loadingPage); XCTAssertEqual(f.wire.writes, 0)
    }

}

