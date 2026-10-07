import XCTest
@testable import QuestifyCore

@MainActor final class WorkshopCreatorPendingCoreTests: XCTestCase {
    static let targetId = "40000000-0000-4000-8000-000000000001", requestId = "50000000-0000-4000-8000-000000000001"
    static let revision = String(repeating: "b", count: 64), document = "Synthetic complete terms\nSecond line."
    static let now = Date(timeIntervalSince1970: 1791288000) // 2026-10-06T12:00:00Z
    static func data(_ object: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) }
    static func envelope(_ object: [String: Any]) throws -> Data { try data(["code": 200, "data": object]) }
    static func previewJSON() -> [String: Any] {
        let source = #"{"schema":"w18-member-text-v1","title":"Synthetic original","description":"原文","bindings":{}}"#
        return ["schema":"w18-creator-public-use-preview-v1", "sourceTemplateId":91, "templateHash":String(repeating:"a",count:64),
                "packageContentHash":WorkshopCreatorWire.sha(Data(source.utf8)), "packageSourceJson":source, "omittedPlanningMetadata":["players"],
                "disclosureVersion":WorkshopCreatorDisclosure.version,"disclosureHash":WorkshopCreatorDisclosure.hash,"disclosureText":WorkshopCreatorDisclosure.text,
                "state":"EXPLICIT_CREATOR_CONFIRMATION_REQUIRED","packageReviewed":false]
    }
    static func preview() throws -> WorkshopCreatorPreview { try WorkshopCreatorWire.decode(WorkshopCreatorPreview.self, data:data(previewJSON())) }
    static func command(document: String = WorkshopCreatorPendingCoreTests.document) throws -> WorkshopCreatorPendingCommand {
        try .init(preview:preview(),termsDocument:document,commercialUse:"ALLOWED",adaptation:"LOCAL_ADAPTATION",translation:"PROHIBITED",
                  allowedRegions:"CN,US",buyerKinds:"INDIVIDUAL,MERCHANT",themeLimit:3,merchantLimit:0,runLimit:-1,priceMinor:1499,currency:"CNY",
                  expiresAt:"2026-10-08T12:00:00.123456Z",requestId:requestId,now:now)
    }
    static func metadataJSON() throws -> [String: Any] {
        let c = try command()
        return ["schema":"w18-creator-pending-package-v1","targetId":targetId,"revision":revision,"sourceTemplateId":91,
                "templateHash":c.expectedTemplateHash,"packageContentHash":c.expectedPackageContentHash,"moduleId":"member-template:91",
                "versionId":"creator-package:\(targetId):\(revision)","offerVersion":"creator-offer:\(targetId):\(revision)","termsVersion":"creator-terms:\(targetId)",
                "termsDocumentHash":c.termsDocumentHash,"expiresAt":c.expiresAt,"createdAt":"2026-10-06T11:59:00.123456Z",
                "state":"UNREVIEWED_AUTHOR_PROPOSAL","packageReviewed":false,"listed":false,"licenseIssued":false,"copyrightOwnership":"RETAINED_BY_CREATOR"]
    }
    static func detailJSON() throws -> [String: Any] {
        var value = try metadataJSON(); let preview = previewJSON()
        value["termsDocument"] = document; value["packageSourceJson"] = preview["packageSourceJson"]
        for field in ["omittedPlanningMetadata","disclosureVersion","disclosureHash","disclosureText"] { value[field] = preview[field] }
        let terms: [String:Any] = ["useDuration":"PERPETUAL_PURCHASED_VERSION","termsVersion":"creator-terms:\(targetId)",
            "termsHash":"549d3ee07cc9cd1ffc0087517a12e2087d093dda4aa46cf51765fb11e71bd282","termsDocumentHash":WorkshopCreatorWire.sha(Data(document.utf8)),
            "termsDocumentReference":"creator-pending:\(requestId)","commercialUse":"ALLOWED","adaptation":"LOCAL_ADAPTATION","translation":"PROHIBITED",
            "updates":"EXACT_PURCHASED_VERSION","redistribution":"PROHIBITED","allowedRegions":["US","CN"],
            "themeLimit":["unlimited":false,"maximum":3],"merchantLimit":["unlimited":false,"maximum":0],"runLimit":["unlimited":true,"maximum":0]]
        value["proposedOffer"] = ["offerId":"creator-offer:\(requestId)","offerVersion":"creator-offer:\(targetId):\(revision)","moduleId":"member-template:91",
            "seller":["kind":"INDIVIDUAL","entityId":7],"buyerKinds":["INDIVIDUAL","MERCHANT"],"acquisition":"PAID","priceMinor":1499,"currency":"CNY","terms":terms] as [String:Any]
        return value
    }
    static func detail() throws -> WorkshopCreatorPendingDetail { try WorkshopCreatorPendingWire.decode(WorkshopCreatorPendingDetail.self,data:data(detailJSON())) }
    func testAuthorCommandHasExactTwentyOneFieldsAndUtf8Identity() throws {
        let c = try Self.command(), object = try XCTUnwrap(JSONSerialization.jsonObject(with:c.data()) as? [String:Any])
        XCTAssertEqual(object.count,21); XCTAssertEqual(try WorkshopCreatorPendingWire.decode(WorkshopCreatorPendingCommand.self,data:c.data()),c)
        XCTAssertNotEqual(try Self.command(document:"café"),try Self.command(document:"cafe\u{301}"))
        XCTAssertEqual(c.termsDocument,Self.document); XCTAssertEqual(c.requestId,Self.requestId)
    }
    func testAuthorCommandRejectsMissingUnknownNestedAndCoercedFields() throws {
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with:Self.command().data()) as? [String:Any])
        for key in original.keys { var value = original; value.removeValue(forKey:key); XCTAssertThrowsError(try WorkshopCreatorPendingWire.decode(WorkshopCreatorPendingCommand.self,data:Self.data(value))) }
        for (key,bad) in [("owner",7 as Any),("priceMinor",0),("currency","cny"),("allowedRegions","CN,CN"),("buyerKinds","INDIVIDUAL,INDIVIDUAL"),("themeLimit",-2),("termsDocument","\u{0085}"),("termsDocument",["nested":true]),("acquisition","FREE")] {
            var value = original; value[key] = bad; XCTAssertThrowsError(try WorkshopCreatorPendingWire.decode(WorkshopCreatorPendingCommand.self,data:Self.data(value)))
        }
        let text = String(decoding:try Self.command().data(),as:UTF8.self)
        for number in ["1499.0","1499e0","true","\"1499\""] {
            XCTAssertThrowsError(try WorkshopCreatorPendingWire.decode(WorkshopCreatorPendingCommand.self,data:Data(text.replacingOccurrences(of:"\"priceMinor\":1499",with:"\"priceMinor\":\(number)").utf8)))
        }
        XCTAssertThrowsError(try WorkshopCreatorPendingWire.decode(WorkshopCreatorPendingCommand.self,data:Data(("{\"requestId\":\"duplicate\","+text.dropFirst()).utf8)))
    }
    func testDocumentByteBoundAndRequestEncodedBound() throws {
        XCTAssertNoThrow(try Self.command(document:String(repeating:"中",count:21_845)))
        XCTAssertThrowsError(try Self.command(document:String(repeating:"中",count:21_846)))
        XCTAssertThrowsError(try Self.command(document:String(repeating:"\"",count:65_536)))
        XCTAssertThrowsError(try Self.command(document:"  \n\t"))
    }
    func testExactMicrosecondDatesAndInvalidCalendarDates() throws {
        let a = try XCTUnwrap(WorkshopCreatorPendingWire.instantMicros("2026-10-08T12:00:00.123456Z"))
        XCTAssertEqual(a,WorkshopCreatorPendingWire.instantMicros("2026-10-08T20:00:00.123456+08:00"))
        XCTAssertEqual(a+1,WorkshopCreatorPendingWire.instantMicros("2026-10-08T12:00:00.123457Z"))
        for invalid in ["2026-02-29T00:00:00Z","2026-10-06T24:00:00Z","2026-10-06T00:00:00.1234567Z","2026-10-06T00:00:00+18:01"] { XCTAssertNil(WorkshopCreatorPendingWire.date(invalid)) }
    }
    func testHistoricalMetadataRecoveryDoesNotCreateCurrentDescriptor() throws {
        let metadata = try WorkshopCreatorPendingWire.decode(WorkshopCreatorPendingMetadata.self,data:Self.data(Self.metadataJSON()))
        XCTAssertTrue(metadata.matches(command:try Self.command())); XCTAssertFalse(metadata.isUnexpired(now:.distantFuture))
        let detail = try Self.detail(); XCTAssertFalse(detail.matches(preview:try Self.preview(),now:.distantFuture))
        XCTAssertThrowsError(try detail.declarationTarget(preview:Self.preview(),now:.distantFuture))
    }
    func testStrictDetailHashOfferAndStableGeneratedTarget() throws {
        let detail = try Self.detail(), target = try detail.declarationTarget(preview:Self.preview(),now:Self.now)
        XCTAssertEqual(target.id,UUID(uuidString:Self.targetId)); XCTAssertEqual(target.versionId,"creator-package:\(Self.targetId):\(Self.revision)")
        XCTAssertEqual(target.offerVersion,"creator-offer:\(Self.targetId):\(Self.revision)"); XCTAssertEqual(target.termsDocument,Self.document)
        XCTAssertEqual(detail.proposedOffer.terms.termsHash,"549d3ee07cc9cd1ffc0087517a12e2087d093dda4aa46cf51765fb11e71bd282")
        XCTAssertTrue(detail.matches(preview:try Self.preview(),now:Self.now))
    }
    func testFreshSourceMismatchNeverCreatesTarget() throws {
        var changed = Self.previewJSON(); changed["templateHash"] = String(repeating:"c",count:64)
        let preview = try WorkshopCreatorWire.decode(WorkshopCreatorPreview.self,data:Self.data(changed)), detail = try Self.detail()
        XCTAssertFalse(detail.matches(preview:preview,now:Self.now))
        XCTAssertThrowsError(try detail.declarationTarget(preview:preview,now:Self.now))
    }
    func testUnknownFieldsConsentReferencesCorruptTermsAndFalseRightsAreRejected() throws {
        let baseline = try Self.detailJSON()
        for (key,bad) in [("termsDocument","changed" as Any),("packageSourceJson","{}"),("listed",true),("licenseIssued",true),("packageReviewed",true),("approval",true),("revision",String(repeating:"c",count:64)),("disclosureText","changed")] {
            var value=baseline;value[key]=bad;XCTAssertThrowsError(try WorkshopCreatorPendingWire.decode(WorkshopCreatorPendingDetail.self,data:Self.data(value)))
        }
        for field in ["publicThemeUseConsent","unexpected"] {
            var value=baseline,offer=try XCTUnwrap(value["proposedOffer"] as? [String:Any]),terms=try XCTUnwrap(offer["terms"] as? [String:Any])
            terms[field]=NSNull();offer["terms"]=terms;value["proposedOffer"]=offer
            XCTAssertThrowsError(try WorkshopCreatorPendingWire.decode(WorkshopCreatorPendingDetail.self,data:Self.data(value)))
        }
        var value=baseline,offer=try XCTUnwrap(value["proposedOffer"] as? [String:Any]),terms=try XCTUnwrap(offer["terms"] as? [String:Any])
        terms["commercialUse"]="PROHIBITED";offer["terms"]=terms;value["proposedOffer"]=offer
        XCTAssertThrowsError(try WorkshopCreatorPendingWire.decode(WorkshopCreatorPendingDetail.self,data:Self.data(value)))
    }
    func testPageBoundsDuplicatesCursorsAndFreshness() throws {
        let metadata=try Self.metadataJSON()
        func page(_ items:[[String:Any]],_ more:Bool=false,_ cursor:Any=NSNull())->[String:Any] {
            ["schema":"w18-creator-pending-package-list-v1","sourceTemplateId":91,"items":items,"hasMore":more,"nextCursor":cursor]
        }
        let value=try WorkshopCreatorPendingWire.decode(WorkshopCreatorPendingPage.self,data:Self.data(page([metadata])))
        XCTAssertTrue(value.matches(sourceTemplateId:91,afterTargetId:nil,now:Self.now));XCTAssertFalse(value.matches(sourceTemplateId:91,afterTargetId:Self.targetId,now:Self.now))
        XCTAssertFalse(value.matches(sourceTemplateId:91,afterTargetId:nil,now:.distantFuture))
        for invalid in [page([metadata,metadata]),page([metadata],true,Self.targetId),page([metadata],false,Self.targetId),page(Array(repeating:metadata,count:21))] {
            XCTAssertThrowsError(try WorkshopCreatorPendingWire.decode(WorkshopCreatorPendingPage.self,data:Self.data(invalid)))
        }
    }
    static func request(_ command:WorkshopCreatorPendingCommand,context:RuntimeDependencyContext)throws->URLRequest {
        var r=URLRequest(url:context.baseURL.appendingPathComponent(WorkshopCreatorPendingRequest.prefix+"author"));r.httpMethod="POST";r.httpBody=try command.data()
        r.setValue(context.session.token,forHTTPHeaderField:"Authorization");r.setValue("application/json; charset=utf-8",forHTTPHeaderField:"Content-Type")
        r.setValue(String(r.httpBody!.count),forHTTPHeaderField:"Content-Length");r.setValue("no-store",forHTTPHeaderField:"Cache-Control");r.setValue("no-cache",forHTTPHeaderField:"Pragma");r.cachePolicy = .reloadIgnoringLocalCacheData
        return r
    }
    @MainActor final class Wire: HTTPTransport, WorkshopCreatorPendingMutationTransport {
        let context:RuntimeDependencyContext
        var writes=0,reads=0,duplicateDenied=false,bodySwap=false,delay=false
        var suspended:CheckedContinuation<(Data,Int),Never>?
        init(_ context:RuntimeDependencyContext){self.context=context}
        func send(_ request:URLRequest)async throws->(Data,Int){
            guard WorkshopCreatorPendingRequest.accepts(request,baseURL:context.baseURL) != .author else {throw WorkshopCreatorConsentIssue.disabled}
            reads += 1
            if delay{return await withCheckedContinuation{suspended=$0}}
            if request.url?.lastPathComponent == "detail"{return(try WorkshopCreatorPendingCoreTests.envelope(WorkshopCreatorPendingCoreTests.detailJSON()),200)}
            return(try WorkshopCreatorPendingCoreTests.envelope(["schema":"w18-creator-pending-package-list-v1","sourceTemplateId":91,"items":[try WorkshopCreatorPendingCoreTests.metadataJSON()],"hasMore":false,"nextCursor":NSNull()]),200)
        }
        func sendWorkshopCreatorPendingAuthor(_ request:URLRequest,authorization:WorkshopCreatorPendingAuthorization)async throws->(Data,Int){
            var r=request;if bodySwap{r.httpBody=Data("{}".utf8)}
            try authorization.consume(r,context:context,revision:authorization.revision)
            do{try authorization.consume(r,context:context,revision:authorization.revision)}catch{duplicateDenied=true}
            writes += 1;return(try WorkshopCreatorPendingCoreTests.envelope(WorkshopCreatorPendingCoreTests.metadataJSON()),200)
        }
        func wait()async{for _ in 0..<1000{if suspended != nil{return};await Task.yield()};XCTFail("No suspended transport")}
        func resume401(){let old=suspended;suspended=nil;old?.resume(returning:(Data(),401))}
    }
    @MainActor final class Fixture {
        let context:RuntimeDependencyContext,wire:Wire
        var current:RuntimeDependencyContext?,author:WorkshopCreatorPendingAuthorApproval?,list:WorkshopCreatorPendingListApproval?,detail:WorkshopCreatorPendingDetailApproval?,unauthorized=0
        lazy var lease=ContentDraftSessionLease(context:context,current:{[weak self] in self?.current})
        lazy var service=WorkshopCreatorPendingService(api:try! APIConfiguration(baseURL:context.baseURL),transport:wire,lease:lease,
            author:author,list:list,detail:detail,currentAuthor:{[weak self] in self?.author},currentList:{[weak self] in self?.list},currentDetail:{[weak self] in self?.detail},
            now:{WorkshopCreatorPendingCoreTests.now},onUnauthorized:{[weak self] _ in self?.unauthorized += 1})
        init(grants:Bool=true)throws{
            context = .init(market:.china,baseURL:URL(string:"https://example.com/native")!,role:"player",session:try .init(accountID:7,epoch:1,namespace:"synthetic",token:"synthetic-secret",role:"player"))
            current=context;wire=Wire(context)
            if grants{author=try .init(context:context,expiresAt:.distantFuture);list=try .init(context:context,expiresAt:.distantFuture);detail=try .init(context:context,expiresAt:.distantFuture)}
        }
    }
    func testDefaultAbsentGrantsDispatchNothing()async throws{
        let f=try Fixture(grants:false),life=WorkshopCreatorConsentLifetime{true}
        do{_=try await f.service.author(.init(command:Self.command(),lifetime:life));XCTFail("Expected disabled")}catch{XCTAssertEqual(error as? WorkshopCreatorConsentIssue,.disabled)}
        do{_=try await f.service.list(sourceTemplateId:91,afterTargetId:nil,lifetime:life);XCTFail("Expected disabled")}catch{}
        do{_=try await f.service.detail(sourceTemplateId:91,targetId:Self.targetId,expectedRevision:Self.revision,lifetime:life);XCTFail("Expected disabled")}catch{}
        XCTAssertEqual(f.wire.writes,0);XCTAssertEqual(f.wire.reads,0)
    }
    func testAuthorHasOneUseConfirmationAndExactBodyAuthorization()async throws{
        let f=try Fixture(),life=WorkshopCreatorConsentLifetime{true},confirmation=try WorkshopCreatorPendingConfirmation(command:Self.command(),lifetime:life)
        _=try await f.service.author(confirmation);XCTAssertTrue(f.wire.duplicateDenied)
        do{_=try await f.service.author(confirmation);XCTFail("Expected spent confirmation")}catch{XCTAssertEqual(error as? WorkshopCreatorConsentIssue,.stale)}
        XCTAssertEqual(f.wire.writes,1)
        let other=try Fixture();other.wire.bodySwap=true
        do{_=try await other.service.author(.init(command:Self.command(),lifetime:life));XCTFail("Expected rejection")}catch{}
        XCTAssertEqual(other.wire.writes,0)
    }
    func testReadGrantsAreIndependentAndAuthorCannotUseGeneralSend()async throws{
        let f=try Fixture();f.author=nil;f.detail=nil;let life=WorkshopCreatorConsentLifetime{true}
        _=try await f.service.list(sourceTemplateId:91,afterTargetId:nil,lifetime:life)
        do{_=try await f.service.detail(sourceTemplateId:91,targetId:Self.targetId,expectedRevision:Self.revision,lifetime:life);XCTFail("Expected no detail grant")}catch{}
        do{_=try await f.wire.send(Self.request(Self.command(),context:f.context));XCTFail("Expected general author rejection")}catch{}
        XCTAssertEqual(f.wire.reads,1);XCTAssertEqual(f.wire.writes,0)
    }
    func testRevokedOrReplacedApprovalsAndClosedLifetimesPreventDispatch()async throws{
        for closed in [true,false]{let f=try Fixture(),life=WorkshopCreatorConsentLifetime{true};_=f.service
            if closed{life.revoke()}else{f.author=try .init(context:f.context,expiresAt:.distantFuture)}
            do{_=try await f.service.author(.init(command:Self.command(),lifetime:life));XCTFail("Expected stale action")}catch{}
            XCTAssertEqual(f.wire.writes,0)
        }
    }
    func testLate401OnlyExpiresCurrentLifetime()async throws{
        for closed in [false,true]{let f=try Fixture(),life=WorkshopCreatorConsentLifetime{true};f.wire.delay=true
            let task=Task{try? await f.service.list(sourceTemplateId:91,afterTargetId:nil,lifetime:life)};await f.wire.wait()
            if closed{life.revoke()};f.wire.resume401();_=await task.value;XCTAssertEqual(f.unauthorized,closed ? 0:1)
        }
    }
    func testRequestRejectsQueryStreamLengthAndStatusEndpoint()throws{
        let f=try Fixture(),original=try Self.request(Self.command(),context:f.context)
        XCTAssertEqual(WorkshopCreatorPendingRequest.accepts(original,baseURL:f.context.baseURL),.author)
        for choice in 0..<5{var r=original
            if choice==0{r.url=URL(string:original.url!.absoluteString+"?owner=7")}
            if choice==1{r.setValue("chunked",forHTTPHeaderField:"Transfer-Encoding")}
            if choice==2{r.setValue("2",forHTTPHeaderField:"Content-Length")}
            if choice==3{r.httpMethod="GET"}
            if choice==4{r.url=f.context.baseURL.appendingPathComponent(WorkshopCreatorPendingRequest.prefix+"status")}
            XCTAssertNil(WorkshopCreatorPendingRequest.accepts(r,baseURL:f.context.baseURL))
        }
    }
}
