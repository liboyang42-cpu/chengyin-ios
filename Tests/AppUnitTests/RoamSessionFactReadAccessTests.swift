import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class RoamSessionFactReadAccessTests: XCTestCase {
    private let base=URL(string:"https://session-facts.example/native")!
    private func root(_ wire: Wire, _ grants: Grants? = nil) throws -> AppCompositionRoot {
        let suite="roam-session-fact-"+UUID().uuidString, vault=Vault()
        let defaults=try XCTUnwrap(UserDefaults(suiteName:suite));addTeardownBlock { defaults.removePersistentDomain(forName:suite) }
        let deployment=try ReviewedAppDeployment(market:.china,baseURL:base.absoluteString,
            approvedBaseURLs:[.china:[base.absoluteString]],verifiedCapabilities:[.domesticChinaPhone],
            bundleIdentifier:"test.roam.facts",realm:"synthetic")
        return .init(deployment:.reviewed(deployment),storage:.init(defaults:defaults,tokenStore:{_ in vault}),
            makeTransport:{wire},roamSessionFactReadAccess:{grants?.select($0)})
    }
    private func login(_ session: AppSession) async {
        session.authChannels.cancel();await session.authChannels.loginWithPhone(phone:"10000000000",code:"123456")
        XCTAssertNotNil(session.account)
    }
    private func request(_ id: Int = 17) -> URLRequest {
        var request=URLRequest(url:URL(string:base.absoluteString+"/api/roam/session?sessionId=\(id)")!)
        request.httpMethod="GET";request.setValue("application/json",forHTTPHeaderField:"Accept")
        request.setValue("synthetic-facts",forHTTPHeaderField:"Authorization");return request
    }
    private func settled() async { for _ in 0..<30 { await Task.yield() } }
    func testDefaultNilIsHonestUnavailableAndDoesNotDispatch() async throws {
        let wire=Wire(),session=try root(wire).makeSession();await login(session);wire.requests=[]
        let model=RoamRecoveryPresentation(reader:session.roamSessionFactReader)
        model.setVisible(true);model.sessionID="17";model.recoveryAction()();await settled()
        XCTAssertNotNil(model.reader.identity);XCTAssertFalse(model.reader.isConfigured)
        XCTAssertFalse(model.canRead);XCTAssertEqual(model.coordinator.phase,.idle);XCTAssertTrue(wire.requests.isEmpty)
    }
    func testExistingCoordinatorKeepsActiveNotFoundIncompleteAndFinishedDistinct() async throws {
        let wire=Wire(),session=try root(wire,Grants()).makeSession();await login(session);wire.requests=[]
        let coordinator=RoamRecoveryCoordinator(reader:session.roamSessionFactReader)
        let rows:[(String,RoamRecoveryPhase)]=[
            (#"{"state":"ACTIVE","sessionId":"17"}"#,.active),
            (#"{"state":"NOT_FOUND"}"#,.notFound),
            (#"{"state":"FINISHED","sessionId":"17","resultComplete":false,"result":{"totalXp":4}}"#,.incomplete),
            (#"{"state":"FINISHED","sessionId":17,"resultComplete":true,"result":{"totalXp":4}}"#,.incomplete),
            (#"{"state":"FINISHED","sessionId":"17","resultComplete":true,"result":{"tileXp":1,"poiXp":2,"totalXp":3,"newTiles":1,"newPois":1,"tilesEver":1,"sessionShops":0}}"#,.finished)]
        for (body,phase) in rows {
            wire.fact=body;await coordinator.recover(.sessionID(17));XCTAssertEqual(coordinator.phase,phase)
        }
        XCTAssertEqual(wire.ids,[17,17,17,17,17]);XCTAssertTrue(wire.requests.allSatisfy{$0.httpMethod=="GET"})
        XCTAssertEqual(coordinator.fact?.result?.totalXp,3)
    }
    func testReadFailureRetriesSameIDAndMalformedNeverBecomesNotFound() async throws {
        let wire=Wire(),session=try root(wire,Grants()).makeSession();await login(session)
        let c=RoamRecoveryCoordinator(reader:session.roamSessionFactReader)
        wire.status=503;await c.recover(.sessionID(17));XCTAssertEqual(c.phase,.failed)
        wire.status=200;wire.fact=#"{"state":"ACTIVE","sessionId":18}"#
        await c.recover(.sessionID(17));XCTAssertEqual(c.phase,.failed);XCTAssertNil(c.fact)
        wire.fact=#"{"state":"ACTIVE","sessionId":17}"#
        await c.recover(.sessionID(17));XCTAssertEqual(c.phase,.active);XCTAssertEqual(wire.ids,[17,17,17])
    }
    func testNoOtherOperationOrClientKeyCanBorrowThisReader() async throws {
        let wire=Wire(),session=try root(wire,Grants()).makeSession();await login(session);wire.requests=[]
        let reader=session.roamSessionFactReader
        XCTAssertThrowsError(try reader.history())
        do {_ = try await reader.album(page:1,pageSize:20);XCTFail()}catch {XCTAssertEqual(error as? APIError,.notConfigured)}
        do {_ = try await reader.tilePage(afterID:0,limit:1000);XCTFail()}catch {XCTAssertEqual(error as? APIError,.notConfigured)}
        do {_ = try await reader.shopBadge();XCTFail()}catch {XCTAssertEqual(error as? APIError,.notConfigured)}
        do {_ = try await reader.sessionFact(.clientSessionKey(String(repeating:"a",count:32)));XCTFail()}catch {XCTAssertEqual(error as? APIError,.notConfigured)}
        do {_ = try await reader.sessionFact(.sessionID(0));XCTFail()}catch {XCTAssertEqual(error as? APIError,.invalidRequest)}
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testNormalHubReceivesDedicatedReaderAndOldHostsRemainUnchanged() async throws {
        let wire=Wire(),session=try root(wire,Grants()).makeSession();await login(session)
        let original=RoamExperienceHubView(reader:session.roamExperienceReader)
        XCTAssertNil(original.sessionFactReader)
        let injected=RoamExperienceHubView(reader:session.roamExperienceReader,sessionFactReader:session.roamSessionFactReader)
        XCTAssertTrue(injected.sessionFactReader === session.roamSessionFactReader)
        XCTAssertTrue(injected.reader === session.roamExperienceReader)
        let browser=RoamBrowserView(reader:session.roamReader,experienceReader:session.roamExperienceReader,sessionFactReader:session.roamSessionFactReader)
        XCTAssertTrue(browser.sessionFactReader === session.roamSessionFactReader)
    }
    func testExplicitCurrentActionReadsOnceWithoutAutomaticReopenOrRetry() async throws {
        let wire=Wire(),session=try root(wire,Grants()).makeSession();await login(session);wire.requests=[]
        let model=RoamRecoveryPresentation(reader:session.roamSessionFactReader);model.sessionID="17"
        model.setVisible(true);await settled();XCTAssertTrue(wire.requests.isEmpty)
        let action=model.recoveryAction();action();action();await settled()
        XCTAssertEqual(wire.ids,[17]);XCTAssertEqual(model.coordinator.phase,.active);XCTAssertFalse(model.loading)
        model.setVisible(false);model.setVisible(true);await settled()
        XCTAssertEqual(model.coordinator.phase,.idle);XCTAssertEqual(wire.ids,[17])
        action();await settled();XCTAssertEqual(wire.ids,[17])
        model.recoveryAction()();await settled();XCTAssertEqual(wire.ids,[17,17])
    }
    func testOldInputOrInvisibleActionNeverAdoptsNewInputOrDispatches() async throws {
        let wire=Wire(),session=try root(wire,Grants()).makeSession();await login(session);wire.requests=[]
        let model=RoamRecoveryPresentation(reader:session.roamSessionFactReader);model.setVisible(true);model.sessionID="17"
        let old=model.recoveryAction();model.sessionID="18";old();await settled();XCTAssertTrue(wire.requests.isEmpty)
        let hidden=model.recoveryAction();model.setVisible(false);hidden();await settled();XCTAssertTrue(wire.requests.isEmpty)
        model.setVisible(true)
        for invalid in ["0","-1","01"," 17","17 ","999999999999999999999"] {
            model.sessionID=invalid;XCTAssertFalse(model.canRead);model.recoveryAction()()
        }
        await settled();XCTAssertTrue(wire.requests.isEmpty)
    }
    func testChangingInputOrHidingRetiresHeldResultAndCannotClearSuccessor() async throws {
        for leave in [false,true] {
            let wire=Wire(),session=try root(wire,Grants()).makeSession();await login(session)
            let model=RoamRecoveryPresentation(reader:session.roamSessionFactReader);model.setVisible(true);model.sessionID="17"
            wire.hold=true;let held=expectation(description:"held fact");wire.onHeld={held.fulfill()}
            model.recoveryAction()();await fulfillment(of:[held],timeout:2)
            if leave {model.setVisible(false);model.setVisible(true)} else {model.sessionID="18"}
            wire.hold=false;wire.fact=#"{"state":"NOT_FOUND"}"#;model.recoveryAction()();await settled()
            XCTAssertEqual(model.coordinator.phase,.notFound)
            wire.finish(status:200);await settled();XCTAssertEqual(model.coordinator.phase,.notFound)
            XCTAssertFalse(model.loading)
        }
    }
    func testRetiredApprovalActionCannotReadAndCurrentReplacementCan() async throws {
        let wire=Wire(),grants=Grants(),session=try root(wire,grants).makeSession();await login(session);wire.requests=[]
        let model=RoamRecoveryPresentation(reader:session.roamSessionFactReader);model.setVisible(true);model.sessionID="17"
        let action=model.recoveryAction();let previous=model.readScope;grants.retained?.revoke()
        action();await settled();XCTAssertTrue(wire.requests.isEmpty);XCTAssertNotEqual(model.readScope,previous)
        grants.retained=nil;action();await settled();XCTAssertTrue(wire.requests.isEmpty)
        model.recoveryAction()();await settled();XCTAssertEqual(wire.ids,[17])
    }
    func testScopeChangesWhenApprovalIsRevokedReplacedOrViewerChanges() async throws {
        let wire=Wire(),grants=Grants(),session=try root(wire,grants).makeSession();await login(session)
        let reader=session.roamSessionFactReader,first=reader.scope
        XCTAssertTrue(reader.isConfigured);grants.retained?.revoke()
        XCTAssertFalse(reader.isConfigured);XCTAssertNotEqual(reader.scope,first)
        grants.retained=nil;XCTAssertTrue(reader.isConfigured);XCTAssertNotEqual(reader.scope,first)
        let before=reader.scope;await session.logout();XCTAssertNotEqual(reader.scope,before);XCTAssertNil(reader.identity)
    }
    func testTransportClonesKeepIndependentApprovalAndRejectWrongRoutesTokenOrQuery() async throws {
        let wire=Wire(),transport=try root(wire,Grants()).transport()
        transport.current={.init(epoch:1,accountID:81,role:"player",token:"synthetic-facts",viewerRevision:1)}
        let clone=transport.replacingUnderlying(wire).scopedForManualMap(ManualMapAreaSelection())
        _ = try await clone.send(request())
        for path in ["api/roam/reveal","api/roam/tiles","api/roam/tiles/page","api/roam/stamp/list"] {
            var r=request();r.url=base.appendingPathComponent(path)
            do {_ = try await clone.send(r);XCTFail(path)}catch {}
        }
        var r=request();r.setValue("other-token",forHTTPHeaderField:"Authorization")
        do {_ = try await clone.send(r);XCTFail()}catch {}
        r=request();r.url=URL(string:r.url!.absoluteString+"&memberId=81")
        do {_ = try await clone.send(r);XCTFail()}catch {}
        XCTAssertEqual(wire.requests.count,1)
    }
    func testNoApprovalCannotBorrowManualScopeOrDispatch() async throws {
        let wire=Wire(),transport=try root(wire).transport()
        transport.current={.init(epoch:1,accountID:81,role:"player",token:"synthetic-facts",viewerRevision:1)}
        do {_ = try await transport.scopedForManualMap(ManualMapAreaSelection()).send(request());XCTFail()}catch {}
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testChangedIdentityOrIssuanceRejectsBothLateFactAnd401() async throws {
        for change in ["owner","epoch","token","viewer","role","revoke","replace","remove"] {
            for status in [200,401] {
                let wire=Wire(),grants=Grants(),transport=try root(wire,grants).transport()
                var identity=CompositionHTTPTransport.SessionIdentity(epoch:1,accountID:81,role:"player",token:"synthetic-facts",viewerRevision:1)
                transport.current={identity};wire.hold=true
                let held=expectation(description:"session fact held");wire.onHeld={held.fulfill()}
                let task=Task {try await transport.send(request())};await fulfillment(of:[held],timeout:2)
                let access=try XCTUnwrap(grants.retained)
                switch change {
                case "owner":identity = .init(epoch:2,accountID:82,role:"player",token:"synthetic-facts",viewerRevision:2)
                case "epoch":identity = .init(epoch:2,accountID:81,role:"player",token:"synthetic-facts",viewerRevision:1)
                case "token":identity = .init(epoch:1,accountID:81,role:"player",token:"other",viewerRevision:1)
                case "viewer":identity = .init(epoch:1,accountID:81,role:"player",token:"synthetic-facts",viewerRevision:2)
                case "role":identity = .init(epoch:1,accountID:81,role:"merchant",token:"synthetic-facts",viewerRevision:1)
                case "revoke":access.revoke()
                case "replace":grants.retained=try .init(context:access.context,approval:access.endpoints)
                default:grants.enabled=false
                }
                wire.finish(status:status)
                do {_ = try await task.value;XCTFail(change)}catch {XCTAssertTrue(error is CancellationError)}
            }
        }
    }
    func testLate401CannotExpireSuccessorButCurrent401DoesExpire() async throws {
        let wire=Wire(),grants=Grants(),session=try root(wire,grants).makeSession();await login(session)
        let reader=session.roamSessionFactReader;wire.hold=true
        let held=expectation(description:"old fact account");wire.onHeld={held.fulfill()}
        let task=Task {try await reader.sessionFact(.sessionID(17))};await fulfillment(of:[held],timeout:2)
        await session.logout();wire.hold=false;wire.account=82;grants.retained=nil;await login(session)
        wire.finish(status:401)
        do {_ = try await task.value;XCTFail()}catch {XCTAssertTrue(error is CancellationError)}
        XCTAssertEqual(session.account?.id,82)
        wire.status=401
        do {_ = try await reader.sessionFact(.sessionID(17));XCTFail()}catch {}
        XCTAssertNil(session.account)
    }
    func testHiddenOrRevokedBeforeTaskStartsHasZeroDispatch() async throws {
        for revoke in [false,true] {
            let wire=Wire(),grants=Grants(),session=try root(wire,grants).makeSession();await login(session);wire.requests=[]
            let model=RoamRecoveryPresentation(reader:session.roamSessionFactReader)
            model.setVisible(true);model.sessionID="17";model.recoveryAction()()
            if revoke {grants.retained?.revoke()} else {model.setVisible(false)}
            await settled();XCTAssertTrue(wire.requests.isEmpty);XCTAssertFalse(model.loading)
            XCTAssertEqual(model.coordinator.phase,.idle)
        }
    }
    func testNormalNavigationHostHasNoAutomaticRead() async throws {
        let wire=Wire(),session=try root(wire,Grants()).makeSession();await login(session);wire.requests=[]
        let host=UIHostingController(rootView:NavigationStack { RoamRecoveryView(reader:session.roamSessionFactReader) })
        let window=UIWindow(frame:CGRect(x:0,y:0,width:390,height:844));window.rootViewController=host;window.makeKeyAndVisible()
        host.loadViewIfNeeded();host.view.layoutIfNeeded();await settled()
        XCTAssertTrue(wire.requests.isEmpty)
        window.isHidden=true;window.rootViewController=nil
    }
    func testReaderRejectsServiceFromAnotherDeploymentBeforeDispatch() async throws {
        let wire=Wire(),grants=Grants()
        let context=RuntimeDependencyContext(market:.china,baseURL:base,role:"player",
            session:try .init(accountID:81,epoch:1,namespace:"synthetic",token:"synthetic-facts"))
        let service=RoamExperienceService(configuration:try APIConfiguration(baseURL:URL(string:"https://other.example/native")!),transport:wire)
        let reader=RoamSessionFactReader(service:service,current:{context},viewerRevision:{1},access:{grants.select($0)})
        XCTAssertFalse(reader.isConfigured)
        do {_ = try await reader.sessionFact(.sessionID(17));XCTFail()}catch {XCTAssertEqual(error as? APIError,.notConfigured)}
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testForegroundCannotPresentHiddenRecoveryOrReviveItsAction() async throws {
        let wire=Wire(),session=try root(wire,Grants()).makeSession();await login(session);wire.requests=[]
        let model=RoamRecoveryPresentation(reader:session.roamSessionFactReader)
        model.setVisible(true);model.sessionID="17";let old=model.recoveryAction()
        model.setVisible(false);model.setForeground(false);model.setForeground(true)
        XCTAssertFalse(model.visible);XCTAssertFalse(model.canRead)
        old();model.recoveryAction()();await settled();XCTAssertTrue(wire.requests.isEmpty)
        model.setVisible(true);old();await settled();XCTAssertTrue(wire.requests.isEmpty)
        model.recoveryAction()();await settled();XCTAssertEqual(wire.ids,[17]);XCTAssertEqual(model.coordinator.phase,.active)
    }
    func testBackgroundCancelsHeldFactAndReturningRequiresFreshExplicitRead() async throws {
        let wire=Wire(),session=try root(wire,Grants()).makeSession();await login(session)
        let model=RoamRecoveryPresentation(reader:session.roamSessionFactReader);model.setVisible(true);model.sessionID="17"
        wire.hold=true;let held=expectation(description:"foreground fact");wire.onHeld={held.fulfill()}
        model.recoveryAction()();await fulfillment(of:[held],timeout:2)
        model.setForeground(false);XCTAssertFalse(model.visible);XCTAssertFalse(model.loading);XCTAssertEqual(model.coordinator.phase,.idle)
        wire.hold=false;wire.finish(status:200);await settled();XCTAssertEqual(model.coordinator.phase,.idle)
        model.setForeground(true);await settled();XCTAssertTrue(model.visible);XCTAssertEqual(wire.ids,[17])
        XCTAssertEqual(model.coordinator.phase,.idle)
        model.recoveryAction()();await settled();XCTAssertEqual(wire.ids,[17,17]);XCTAssertEqual(model.coordinator.phase,.active)
    }
    @MainActor private final class Grants {
        var enabled=true;var retained:RoamSessionFactReadAccess?
        func select(_ context:RuntimeDependencyContext)->RoamSessionFactReadAccess? {
            guard enabled else{return nil}
            if retained==nil,let approval=try? OperationEndpointApproval(baseURL:context.baseURL,
                namespace:context.session.namespace,accountID:context.session.accountID,paths:[RoamSessionFactReadRoute.path]) {
                retained=try? .init(context:context,approval:approval)
            }
            return retained
        }
    }
    @MainActor private final class Vault:AppTokenStorage {
        var token:String?;func read()throws->String?{token};func write(_ value:String)throws{token=value};func clear()throws{token=nil}
    }
    @MainActor private final class Wire:HTTPTransport {
        var requests:[URLRequest]=[],ids:[Int]=[]
        var status=200,account=81;var hold=false,onHeld:(()->Void)?
        var fact=#"{"state":"ACTIVE","sessionId":"17"}"#
        var pending:CheckedContinuation<(Data,Int),Error>?
        func finish(status:Int){let value=pending;pending=nil;value?.resume(returning:(Data(#"{"code":200,"data":{"state":"ACTIVE","sessionId":"17"}}"#.utf8),status))}
        func send(_ request:URLRequest)async throws->(Data,Int){
            requests.append(request);let path=request.url!.lastPathComponent
            if path=="phone" {return(try JSONSerialization.data(withJSONObject:["code":200,"token":"synthetic-facts","data":["id":account,"role":"player"]]),200)}
            if path=="userInfo" {return(try JSONSerialization.data(withJSONObject:["code":200,"appUser":["userId":account,"role":"player"]]),200)}
            guard path=="session" else{return(Data(#"{"code":404}"#.utf8),404)}
            let id=Int(URLComponents(url:request.url!,resolvingAgainstBaseURL:false)!.queryItems!.first(where:{$0.name=="sessionId"})!.value!)!
            ids.append(id)
            if hold {return try await withCheckedThrowingContinuation {pending=$0;onHeld?()}}
            return(Data(("{\"code\":200,\"data\":"+fact+"}").utf8),status)
        }
    }
}
