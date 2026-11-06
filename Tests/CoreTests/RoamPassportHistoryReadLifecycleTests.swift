import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class RoamPassportHistoryReadLifecycleTests: XCTestCase {
    func testDefaultNilGrantNeverDispatchesAnyOriginalRead() async throws {
        let rig = try PassportReadRig(); rig.access = nil
        for route in [RoamPassportHistoryReadRoute.history(before:nil),.record(sessionID:"9"),.summary] {
            do { try await rig.read(route); XCTFail() } catch { XCTAssertEqual(error as? APIError,.notConfigured) }
        }
        XCTAssertTrue(rig.wire.requests.isEmpty)
    }
    func testThreeExactRoutesPreserveLongIDCursorAndSummary() async throws {
        let rig = try PassportReadRig()
        _ = try await rig.reader.summary(); _ = try await rig.reader.page(before:nil); _ = try await rig.reader.page(before:"9"); _ = try await rig.reader.record(sessionID:"8")
        XCTAssertEqual(rig.wire.requests.map { $0.url!.lastPathComponent },["summary","history","history","record"])
        XCTAssertEqual(rig.wire.requests[2].url?.query,"before=9&limit=30")
        XCTAssertEqual(rig.wire.requests[3].url?.query,"sessionId=8")
        XCTAssertTrue(rig.wire.requests.allSatisfy { $0.httpMethod == "GET" && $0.httpBody == nil })
    }
    func testRouteRejectsForeignHostExtraOwnerAliasEncodedIDAndWrites() throws {
        let rig = try PassportReadRig(), route = RoamPassportHistoryReadRoute.record(sessionID:"9")
        let valid = try route.request(baseURL:rig.base,token:"synthetic")
        XCTAssertEqual(RoamPassportHistoryReadRoute(request:valid,baseURL:rig.base),route)
        for url in ["https://other.test/native/api/roam/passport/record?sessionId=9", "https://passport.example/native/api/roam/passport/record?sessionId=%39", "https://passport.example/native/api/roam/passport/record?sessionId=9&owner=7", "https://passport.example/native/api/roam/passport/record?sessionId=09", "https://passport.example/native/api/roam/passport/summary?", "https://passport.example/native/api/roam/passport/history?limit=100", "https://passport.example/native/api/roam/passport/history?limit=30&before=9"] {
            var request = valid; request.url = URL(string:url); XCTAssertNil(RoamPassportHistoryReadRoute(request:request,baseURL:rig.base),url)
        }
        var post = valid; post.httpMethod = "POST"; XCTAssertNil(RoamPassportHistoryReadRoute(request:post,baseURL:rig.base))
        post = valid; post.httpBody = Data(); XCTAssertNil(RoamPassportHistoryReadRoute(request:post,baseURL:rig.base))
    }
    func testGrantCannotContainToolsStampOrPartialPassportPaths() throws {
        let rig = try PassportReadRig()
        for paths in [Set(["api/roam/passport/history"]), RoamPassportHistoryReadRoute.paths.union(["api/roam/stamp/list"]),Set(RoamPassportToolsService.paths)] {
            let approval = try OperationEndpointApproval(baseURL:rig.base,namespace:rig.context!.session.namespace,accountID:7,paths:paths)
            XCTAssertThrowsError(try RoamPassportHistoryReadAccess(context:rig.context!,approval:approval))
        }
    }
    func testHTTPStatusPrecedesSuccessfulOrDeniedEnvelope() async throws {
        let rig = try PassportReadRig()
        for status in [401,403,503] {
            rig.wire.status = status
            do { _ = try await rig.reader.page(before:nil); XCTFail() }
            catch { XCTAssertEqual(error as? APIError,status == 401 ? .unauthorized : .httpStatus(status)) }
        }
        XCTAssertEqual(rig.expired,1)
    }
    func testEnvelopeDenialMalformedAndExactRecordIdentityNeverBecomeEmptySuccess() async throws {
        let rig = try PassportReadRig()
        for (body,expectedError) in [(#"{"code":403}"#,APIError.businessCode(403)),(#"{"code":200,"data":{}}"#,.malformedResponse),(#"{"code":200,"data":{"sessionId":"2"}}"#,.malformedResponse)] {
            rig.wire.body = body
            do {_ = try await rig.reader.record(sessionID:"9"); XCTFail()}catch {XCTAssertEqual(error as? APIError,expectedError)}
        }
    }
    func testRevocationReplacementViewerAndAccountRejectHeldSuccessAnd401() async throws {
        for change in ["revoke","replace","remove","viewer","epoch","owner","token"] {
            for status in [200,401] {
                let rig = try PassportReadRig(); rig.wire.hold = true
                let task = Task { try await rig.reader.page(before:nil) }
                for _ in 0..<200 where rig.wire.pending == nil { await Task.yield() }
                _ = try XCTUnwrap(rig.wire.pending)
                switch change {
                case "revoke":rig.access?.revoke()
                case "replace":try rig.grant()
                case "remove":rig.access=nil
                case "viewer":rig.viewer += 1
                default: rig.context = try rig.contextValue(account:change == "owner" ? 8 : 7,epoch:change == "epoch" ? 2 : 1,token:change == "token" ? "changed" : "synthetic")
                }
                rig.wire.finish(status:status)
                do {_ = try await task.value; XCTFail(change)}catch {XCTAssertTrue(error is CancellationError,change)}
                XCTAssertEqual(rig.expired,0)
            }
        }
    }
    func testCancelledReadCannotPublishOrExpireOwner() async throws {
        let rig = try PassportReadRig(); rig.wire.hold=true
        let task=Task {try await rig.reader.page(before:nil)}
        for _ in 0..<200 where rig.wire.pending == nil {await Task.yield()}
        _ = try XCTUnwrap(rig.wire.pending)
        task.cancel();rig.wire.finish(status:401)
        do {_ = try await task.value;XCTFail()}catch {XCTAssertTrue(error is CancellationError)}
        XCTAssertEqual(rig.expired,0)
    }
    func testListOriginalCursorRetryAndIndependentSummaryFailure() async throws {
        let rig=try PassportReadRig(),model=RoamPassportHistoryCoordinator(reader:rig.reader);model.activate()
        rig.wire.summaryStatus=503;await model.read(model.intent(.refresh))
        XCTAssertEqual(model.items.map(\.sessionID),["9"]);XCTAssertNil(model.summary);XCTAssertNotNil(model.summaryError)
        rig.wire.status=503;await model.read(model.intent(.more));XCTAssertEqual(model.items.map(\.sessionID),["9"])
        rig.wire.status=200;await model.read(model.intent(.more));XCTAssertEqual(model.items.map(\.sessionID),["9","8"])
        XCTAssertEqual(rig.wire.requests.filter {$0.url?.lastPathComponent == "history"}.map {$0.url!.query!},["limit=30","before=9&limit=30","before=9&limit=30"])
        XCTAssertFalse(model.hasMore)
    }
    func testListDenialClearsPrivateRowsButTransientFailureRetainsOriginalCursor() async throws {
        let rig=try PassportReadRig(),model=RoamPassportHistoryCoordinator(reader:rig.reader);model.activate();await model.read(model.intent(.refresh))
        XCTAssertEqual(model.summary?.trips,100)
        rig.wire.status=403;await model.read(model.intent(.more))
        XCTAssertTrue(model.items.isEmpty);XCTAssertNil(model.summary);XCTAssertFalse(model.loaded)
        rig.wire.status=200;await model.read(model.intent(.refresh));XCTAssertEqual(model.items.map(\.sessionID),["9"])
    }
    func testQueuedIntentAfterSuspendOrRevocationNeverDispatches() async throws {
        let rig=try PassportReadRig(),model=RoamPassportHistoryCoordinator(reader:rig.reader);model.activate()
        let old=model.intent(.refresh);model.suspend();model.activate();await model.read(old)
        XCTAssertTrue(rig.wire.requests.isEmpty)
        let granted=model.intent(.refresh);rig.access?.revoke();await model.read(granted)
        XCTAssertFalse(model.isVisible);XCTAssertTrue(rig.wire.requests.isEmpty)
    }
    func testDetailReadsExactSessionAndOnlySameOwnerLocalSupplement() async throws {
        let rig=try PassportReadRig(),local=PassportLocalReader(identity:rig.reader.identity)
        local.rows=[try JSONDecoder().decode(RoamHistoryRecord.self,from:Data(#"{"ts":1700000000000,"serverSessionID":8,"photos":["not-read.jpg"],"track":[{"lat":30,"lng":120},{"lat":31,"lng":121}]}"#.utf8))]
        let model=RoamPassportRecordCoordinator(reader:rig.reader,sessionID:"8",localReader:local);model.activate();await model.read(model.intent())
        XCTAssertEqual(model.fact?.sessionID,"8");XCTAssertEqual(model.supplement?.photos.count,1);XCTAssertEqual(model.track.first?.lat,30)
        local.identity=nil;XCTAssertNil(model.supplement);XCTAssertEqual(model.track.first?.lat,31.2)
        XCTAssertEqual(local.reads,1);XCTAssertEqual(rig.wire.requests.count,1)
    }
    func testDetailLocalFailureOrDifferentSessionNeverBlocksServerFactOrAddsPhotos() async throws {
        let rig=try PassportReadRig(),local=PassportLocalReader(identity:rig.reader.identity);local.failure=APIError.notConfigured
        let model=RoamPassportRecordCoordinator(reader:rig.reader,sessionID:"8",localReader:local);model.activate();await model.read(model.intent())
        XCTAssertNotNil(model.fact);XCTAssertNil(model.supplement);XCTAssertEqual(model.track.count,2)
        local.failure=nil
        local.rows=[try JSONDecoder().decode(RoamHistoryRecord.self,from:Data(#"{"ts":1700000000000,"serverSessionID":99,"photos":["different-session.jpg"]}"#.utf8))]
        await model.read(model.intent());XCTAssertNil(model.supplement)
        rig.wire.status=404;await model.read(model.intent());XCTAssertNil(model.fact);XCTAssertTrue(model.track.isEmpty);XCTAssertTrue(model.isMissing)
    }
    func testHeldListAndDetailDisappearCannotRepopulateOrReadLocalStorage() async throws {
        let rig=try PassportReadRig(),local=PassportLocalReader(identity:rig.reader.identity)
        let detail=RoamPassportRecordCoordinator(reader:rig.reader,sessionID:"8",localReader:local);detail.activate();rig.wire.hold=true
        let task=Task {await detail.read(detail.intent())}
        for _ in 0..<200 where rig.wire.pending == nil {await Task.yield()}
        _ = try XCTUnwrap(rig.wire.pending)
        detail.suspend();rig.wire.finish(status:200);await task.value
        XCTAssertNil(detail.fact);XCTAssertEqual(local.reads,0)
        let list=RoamPassportHistoryCoordinator(reader:rig.reader);list.activate()
        let listTask=Task {await list.read(list.intent(.refresh))}
        for _ in 0..<200 where rig.wire.pending == nil {await Task.yield()}
        _ = try XCTUnwrap(rig.wire.pending)
        list.suspend();rig.wire.finish(status:200);await listTask.value
        XCTAssertTrue(list.items.isEmpty);XCTAssertNil(list.summary)
        XCTAssertEqual(rig.wire.requests.count,2,"Suspended summary never continues into history")
    }
}

@MainActor private final class PassportReadRig {
    let base=URL(string:"https://passport.example/native")!
    var context:RuntimeDependencyContext?,access:RoamPassportHistoryReadAccess?,viewer:UInt64=1,expired=0
    let wire=PassportMemoryWire()
    lazy var reader=RoamPassportHistoryReader(service:.init(configuration:try! APIConfiguration(baseURL:base),transport:wire),current:{[weak self] in self?.context},viewerRevision:{[weak self] in self?.viewer ?? 0},access:{[weak self] _ in self?.access},onUnauthorized:{[weak self] _ in self?.expired += 1})
    init()throws {context=try contextValue();try grant()}
    func contextValue(account:Int=7,epoch:UInt64=1,token:String="synthetic")throws->RuntimeDependencyContext {
        .init(market:.china,baseURL:base,role:"player",session:try .init(accountID:account,epoch:epoch,namespace:"passport",token:token))
    }
    func grant()throws {let c=try XCTUnwrap(context);access=try .init(context:c,approval:.init(baseURL:base,namespace:c.session.namespace,accountID:c.session.accountID,paths:RoamPassportHistoryReadRoute.paths))}
    func read(_ route:RoamPassportHistoryReadRoute)async throws {
        switch route {case .summary:_ = try await reader.summary();case .history(let cursor):_ = try await reader.page(before:cursor);case .record(let id):_ = try await reader.record(sessionID:id)}
    }
}
@MainActor private final class PassportMemoryWire:HTTPTransport {
    var requests:[URLRequest]=[],status=200,summaryStatus=200,body:String?,hold=false
    var pending:CheckedContinuation<(Data,Int),Error>?
    private var heldBody=Data()
    func finish(status:Int){let p=pending;pending=nil;p?.resume(returning:(heldBody,status))}
    func send(_ request:URLRequest)async throws->(Data,Int) {
        requests.append(request)
        let path=request.url!.lastPathComponent,query=URLComponents(url:request.url!,resolvingAgainstBaseURL:false)?.queryItems ?? []
        let id=path == "record" ? query.first?.value ?? "8" : (query.contains {$0.name == "before"} ? "8":"9")
        let row:[String:Any]=["sessionId":id,"distanceM":1000,"shops":0,"startedAt":1700000000000,"finishedAt":1700003600000,"track":[[31.2,121.4],[31.3,121.5]]]
        let data:[String:Any]
        if path == "summary" {data=["trips":100,"shops":0]}
        else if path == "record" {data=row}
        else {data=["items":[row],"hasMore":id == "9","nextBefore":id == "9" ? ("9" as Any) : NSNull()]}
        let bytes=try body.map {Data($0.utf8)} ?? JSONSerialization.data(withJSONObject:["code":200,"data":data])
        if hold {heldBody=bytes;return try await withCheckedThrowingContinuation {pending=$0}}
        return(bytes,path == "summary" ? summaryStatus:status)
    }
}
@MainActor private final class PassportLocalReader:RoamExperienceReading {
    var identity:RoamExperienceIdentity?,isConfigured=false,isOfflineExample=false,rows:[RoamHistoryRecord]=[],reads=0,failure:Error?
    init(identity:RoamExperienceIdentity?){self.identity=identity}
    func history()throws->[RoamHistoryRecord]{reads += 1;if let failure {throw failure};return rows}
    func sessionFact(_ query:RoamRecoveryQuery)async throws->RoamSessionFact{throw APIError.notConfigured}
    func tilePage(afterID:Int,limit:Int)async throws->RoamTileMemoryPage{throw APIError.notConfigured}
    func album(page:Int,pageSize:Int)async throws->RoamAlbumPage{throw APIError.notConfigured}
    func shopBadge()async throws->RoamShopBadge?{throw APIError.notConfigured}
}
