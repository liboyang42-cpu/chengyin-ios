import XCTest
@testable import Questify

@MainActor final class OwnedOrderCompositionTests:XCTestCase {
    private static let base="https://example.test/native"
    private func root(_ wire:Wire,_ grants:Grants,_ vault:Vault) throws ->AppCompositionRoot {
        let suite="orders-"+UUID().uuidString,defaults=try XCTUnwrap(UserDefaults(suiteName:suite))
        addTeardownBlock {defaults.removePersistentDomain(forName:suite)}
        let deployment=try ReviewedAppDeployment(market:.china,baseURL:Self.base,approvedBaseURLs:[.china:[Self.base]],verifiedCapabilities:[.domesticChinaPhone],bundleIdentifier:"test.orders",realm:"fixture")
        return AppCompositionRoot(deployment:.reviewed(deployment),storage:.init(defaults:defaults,tokenStore:{_ in vault}),makeTransport:{wire},ownedOrderReadApproval:{grants.approval($0)})
    }
    private func login(_ session:AppSession) async {
        session.authChannels.cancel();await session.authChannels.loginWithPhone(phone:"10000000000",code:"123456");XCTAssertNotNil(session.account)
    }
    private func read(_ detail:Bool,_ session:AppSession) async throws {
        if detail {_=try await session.ownedOrderReader.profileOrder(id:41)}else{_=try await session.ownedOrderReader.profileOrders()}
    }
    func testNormalAppSessionFreshDetailSeparateStatesAndNoMonetaryRoutes() async throws {
        let wire=Wire(),session=try root(wire,Grants(),Vault()).makeSession();await login(session);wire.requests=[]
        let rows=try await session.ownedOrderReader.profileOrders(),detail=try await session.ownedOrderReader.profileOrder(id:rows[0].id)
        XCTAssertEqual(rows[0].title,"List snapshot");XCTAssertEqual(detail.title,"Fresh detail")
        XCTAssertEqual(detail.memberID,7);XCTAssertEqual(detail.registrationStatus,2);XCTAssertEqual(detail.paymentStatus,0)
        XCTAssertEqual(detail.pointsReturned,0);XCTAssertEqual(detail.refundPayoutStatus,0)
        XCTAssertEqual(wire.requests.map{$0.url!.path},["/native/api/registration/list","/native/api/registration/info"])
        XCTAssertTrue(wire.requests.allSatisfy{OwnedOrderReadRoute(request:$0,baseURL:URL(string:Self.base)!) != nil})
    }
    func testGuestNoGrantAndUnrelatedProfileMethodsDispatchNothing() async throws {
        let wire=Wire(),grants=Grants(),session=try root(wire,grants,Vault()).makeSession()
        for detail in [false,true]{do{try await read(detail,session);XCTFail()}catch{XCTAssertEqual(error as? APIError,.unauthorized)}}
        XCTAssertTrue(wire.requests.isEmpty);await login(session);grants.revoke();wire.requests=[]
        for detail in [false,true]{do{try await read(detail,session);XCTFail()}catch{XCTAssertEqual(error as? APIError,.notConfigured)}}
        do{_=try await session.ownedOrderReader.profileParticipants();XCTFail()}catch{}
        do{_=try await session.ownedOrderReader.profileBadges();XCTFail()}catch{}
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testEmptyMixedOwnerMalformedAndBusinessErrorNeverBecomeSuccess() async throws {
        let wire=Wire(),session=try root(wire,Grants(),Vault()).makeSession();await login(session)
        for body in [#"{"rows":[{"id":41,"memberId":7},{"id":42,"memberId":8}],"total":2}"#,#"{"rows":[{"id":41,"memberId":7},{"id":41,"memberId":7}],"total":2}"#,#"{"rows":[{"id":41}],"total":1}"#,#"{"rows":[],"total":5}"#,"null"]{
            wire.override="{\"code\":200,\"data\":\(body)}"
            do{_=try await session.ownedOrderReader.profileOrders();XCTFail()}catch{XCTAssertEqual(error as? APIError,.malformedResponse)}
        }
        wire.override = #"{"code":200,"data":{"rows":[],"total":0}}"#
        let empty=try await session.ownedOrderReader.profileOrders();XCTAssertTrue(empty.isEmpty)
        for body in [#"{"id":42,"memberId":7}"#,#"{"id":41,"memberId":8}"#]{wire.override="{\"code\":200,\"data\":\(body)}";do{try await read(true,session);XCTFail()}catch{XCTAssertEqual(error as? APIError,.malformedResponse)}}
        for code in [403,500,503]{wire.override="{\"code\":\(code),\"msg\":\"Unavailable\"}";do{try await read(true,session);XCTFail()}catch{XCTAssertEqual((error as? ProfileReadFailure)?.code,code)}}
        XCTAssertEqual(session.account?.id,7)
    }
    func testCurrentHTTPAndEnvelope401ExpireOnlyTheCurrentSession() async throws {
        for detail in [false,true]{for http in [false,true]{
            let wire=Wire(),vault=Vault(),session=try root(wire,Grants(),vault).makeSession();await login(session)
            wire.override = #"{"code":401}"#;wire.status=http ? 401:200
            do{try await read(detail,session);XCTFail()}catch{XCTAssertEqual(error as? APIError,.unauthorized)}
            XCTAssertNil(session.account);XCTAssertNil(vault.value)
        }}
    }
    func testOwnerRoleSessionApprovalABAAndExpiryFenceLateSuccessOr401() async throws {
        for detail in [false,true]{for transition in ["owner","roleABA","sessionABA","revoke","reissue","expire"]{for code in [200,401]{
            let wire=Wire(),grants=Grants(),vault=Vault(),session=try root(wire,grants,vault).makeSession();await login(session)
            let before=session.ownedOrderReader.identity
            wire.pause=true;let started=expectation(description:"suspended order");wire.onPaused={started.fulfill()}
            let task=Task{try await self.read(detail,session)};await fulfillment(of:[started],timeout:2)
            switch transition {
            case "owner":await session.logout();wire.account=8;await login(session)
            case "roleABA":wire.role="merchant";await session.refreshOwnAccount();wire.role="player";await session.refreshOwnAccount()
            case "sessionABA":await session.logout();await login(session)
            case "revoke":grants.revoke()
            case "expire":let approval=try XCTUnwrap(grants.retained);approval.expireIfNeeded(now:approval.expiresAt)
            default:grants.retained?.revoke();grants.retained=nil;_=session.ownedOrderReader.identity
            }
            XCTAssertNotEqual(before,session.ownedOrderReader.identity)
            wire.finish(code:code)
            do{try await task.value;XCTFail(transition)}catch{XCTAssertTrue(error is CancellationError,"\(error)")}
            XCTAssertEqual(session.account?.id,wire.account);XCTAssertEqual(vault.value,"synthetic-\(wire.account)")
        }}}
    }
    func testActualTaskCancellationDismissSupersessionAndParentDoNotApplyLate401() async throws {
        for detail in [false,true]{for action in ["dismiss","replace","parent"]{for http in [false,true]{
            let wire=Wire(),vault=Vault(),session=try root(wire,Grants(),vault).makeSession();await login(session)
            let owner=ManualMapReadTaskOwner(),started=expectation(description:"owned load");wire.pause=true;wire.onPaused={started.fulfill()};var cancelled=false
            let task=Task{await owner.run{do{try await self.read(detail,session);XCTFail()}catch{cancelled=error is CancellationError}}}
            await fulfillment(of:[started],timeout:2)
            if action == "replace"{wire.pause=false;await owner.run{do{try await self.read(detail,session)}catch{XCTFail("\(error)")}}}
            else if action == "parent"{task.cancel()}else{owner.deactivate()}
            wire.finish(code:401,status:http ? 401:200);await task.value
            XCTAssertTrue(cancelled);XCTAssertEqual(session.account?.id,7);XCTAssertEqual(vault.value,"synthetic-7")
        }}}
    }
    func testRestoredAuthorityAndRevokedLoadedReaderCannotDispatchAgain() async throws {
        let wire=Wire(),grants=Grants(),vault=Vault();vault.value="synthetic-7"
        let session=try root(wire,grants,vault).makeSession();await session.bootstrap()
        XCTAssertEqual(wire.requests.first?.url?.lastPathComponent,"userInfo")
        _=try await session.ownedOrderReader.profileOrders();let old=session.ownedOrderReader.identity
        grants.retained?.revoke();XCTAssertFalse(session.ownedOrderReader.isConfigured);XCTAssertNotEqual(old,session.ownedOrderReader.identity)
        let count=wire.requests.count;do{try await read(true,session);XCTFail()}catch{}
        XCTAssertEqual(count,wire.requests.count)
    }
    func testClonePropagationExactShapesPartialIdentityAndAllOtherRoutesStayClosed() async throws {
        for mapFirst in [false,true]{
            let unused=Wire(),wire=Wire(),grants=Grants(),transport=try root(unused,grants,Vault()).transport()
            transport.current={.init(epoch:1,accountID:7,role:"player",token:"synthetic-7",viewerRevision:1)}
            let selection=ManualMapAreaSelection(),clone=mapFirst ? transport.scopedForManualMap(selection).replacingUnderlying(wire):transport.replacingUnderlying(wire).scopedForManualMap(selection)
            let exact=try form("api/registration/info",["id":"41"])
            _=try await clone.send(exact);_=try await clone.send(form("api/registration/list",["owner_type":"3"]))
            var invalid:[URLRequest]=[]
            for fields in [["owner_type":"1"],["owner_type":"3","memberId":"7"],["owner_type":"3","pageNum":"1"],["owner_type":"3","status":"0"]]{invalid.append(try form("api/registration/list",fields))}
            for path in ["api/registration/create","api/registration/pay","api/registration/pay/app","api/registration/cancel","api/registration/cancel-refund","api/activity/info","api/play/nodes","api/map/nearby","api/template/topic-template/info"]{invalid.append(try form(path,["id":"41"]))}
            var v=exact;v.setValue("old-token",forHTTPHeaderField:"Authorization");invalid.append(v)
            v=exact;v.httpMethod="GET";invalid.append(v)
            v=exact;v.httpBody=Data(#"{"id":41}"#.utf8);v.setValue("application/json",forHTTPHeaderField:"Content-Type");invalid.append(v)
            for request in invalid{do{_=try await clone.send(request);XCTFail()}catch{}}
            for identity in [CompositionHTTPTransport.SessionIdentity(epoch:1,accountID:nil,role:nil,token:nil),.init(epoch:1,accountID:7,role:nil,token:"synthetic-7"),.init(epoch:1,accountID:0,role:"player",token:"synthetic-7"),.init(epoch:1,accountID:7,role:"admin",token:"synthetic-7")]{transport.current={identity};do{_=try await clone.send(exact);XCTFail()}catch{}}
            XCTAssertEqual(wire.requests.count,2);XCTAssertTrue(unused.requests.isEmpty)
        }
    }
    private func form(_ path:String,_ fields:[String:String])throws->URLRequest{try AuthRequestBuilder.makeFormRequest(url:URL(string:Self.base+"/"+path)!,fields:fields,token:"synthetic-7")}
    @MainActor private final class Grants {
        var enabled=true;var retained:OwnedOrderReadApproval?
        func approval(_ context:RuntimeDependencyContext)->OwnedOrderReadApproval?{
            guard enabled else{return nil}
            if retained == nil || !ContentDraftContextFence.matches(retained?.context,context){retained?.revoke();retained=try? .init(context:context,expiresAt:Date().addingTimeInterval(600))}
            return retained
        }
        func revoke(){retained?.revoke();enabled=false}
    }
    private final class Vault:AppTokenStorage{var value:String?;func read()throws->String?{value};func write(_ token:String)throws{value=token};func clear()throws{value=nil}}
    private final class Wire:HTTPTransport {
        var requests:[URLRequest]=[],account=7,role="player",status=200,override:String?,pause=false,onPaused:(()->Void)?
        private var pending:CheckedContinuation<(Data,Int),Error>?,pendingJSON="{}"
        func finish(code:Int,status:Int=200){let saved=pending;pending=nil;saved?.resume(returning:(Data((code==200 ? pendingJSON:"{\"code\":\(code)}").utf8),status))}
        func send(_ request:URLRequest)async throws->(Data,Int){
            requests.append(request);let path=request.url!.path,json:String
            if path.hasSuffix("/phone"){json="{\"code\":200,\"token\":\"synthetic-\(account)\",\"data\":{\"id\":\(account),\"role\":\"\(role)\"}}"}
            else if path.hasSuffix("/userInfo"){json="{\"code\":200,\"appUser\":{\"userId\":\(account),\"role\":\"\(role)\"}}"}
            else if path.hasSuffix("/registration/list"){json=override ?? "{\"code\":200,\"data\":{\"rows\":[{\"id\":41,\"memberId\":\(account),\"cmsActivity\":{\"name\":\"List snapshot\"}}],\"total\":1}}"}
            else if path.hasSuffix("/registration/info"){json=override ?? "{\"code\":200,\"data\":{\"id\":41,\"memberId\":\(account),\"cmsActivity\":{\"name\":\"Fresh detail\"},\"registrationStatus\":2,\"paymentStatus\":0,\"payableAmount\":12.3456,\"pointsReturned\":0,\"refundApplication\":{\"payoutStatus\":0}}}"}
            else{json = #"{"code":200,"data":[]}"#}
            if path.contains("/registration/"),pause{pendingJSON=json;return try await withCheckedThrowingContinuation{pending=$0;onPaused?()}}
            return(Data(json.utf8),path.contains("/registration/") ? status:200)
        }
    }
}
