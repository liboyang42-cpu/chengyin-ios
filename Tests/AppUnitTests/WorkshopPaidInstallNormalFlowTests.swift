import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class WorkshopPaidInstallNormalFlowTests: XCTestCase {
    private static func item()throws->WorkshopPurchasedItem{try JSONDecoder().decode(WorkshopPurchasedItem.self,from:JSONSerialization.data(withJSONObject:WorkshopPurchasedAppFixture.item))}
    private static let target:[String:Any]=["targetDraftId":91,"targetRevision":1,"businessType":"TOPIC","targetPayloadHash":String(repeating:"c",count:64),"mode":"UNRESOLVED","destinationKind":"W18_PRIVATE_COMPONENT_ONLY"]
    @MainActor private final class Vault:AppTokenStorage{var token:String?;func read()throws->String?{token};func write(_ value:String)throws{token=value};func clear()throws{token=nil}}
    @MainActor private final class Wire:HTTPTransport{
        var role="player",requests:[URLRequest]=[],delayNext=false
        var suspended:CheckedContinuation<(Data,Int),Never>?
        var command:WorkshopPaidInstallCommand?
        var installs:[URLRequest]{requests.filter{$0.url?.path.contains("/purchased/install/")==true}}
        var writes:[URLRequest]{installs.filter{$0.url?.lastPathComponent=="submit"}}
        func wait()async{for _ in 0..<1000{if suspended != nil{return};await Task.yield()};XCTFail("Expected suspended real service transport")}
        func resume(_ value:(Data,Int)){let old=suspended;suspended=nil;old?.resume(returning:value)}
        func send(_ request:URLRequest)async throws->(Data,Int){
            requests.append(request)
            if request.url?.path.contains("/purchased/install/")==true{
                if delayNext{delayNext=false;return await withCheckedContinuation{suspended=$0}}
                let value:[String:Any]
                switch request.url!.lastPathComponent{
                case "history":value=["schema":"w18-paid-install-history-v1","scope":"OWNER_COMMAND_RECEIPTS_ONLY","licenseId":"w18-paid-11","checkedAt":"2026-10-05T00:00:00Z","items":[],"hasMore":false,"nextBeforeCommandKey":NSNull()]
                case "targets":value=["schema":"w18-paid-install-targets-v1","scope":"OWNER_DRAFT_METADATA_ONLY","licenseId":"w18-paid-11","checkedAt":"2026-10-05T00:00:00Z","items":[WorkshopPaidInstallNormalFlowTests.target],"hasMore":false,"nextBeforeDraftId":NSNull()]
                case "submit":
                    let q=try WorkshopPaidInstallWire.decode(WorkshopPaidInstallCommand.self,data:request.httpBody!);command=q
                    var body=try JSONSerialization.jsonObject(with:q.wireData()) as! [String:Any];body["schema"]="w18-paid-install-outcome-v1";body["state"]="INSTALLED_PRIVATE_DRAFT";body["mode"]="UNRESOLVED";body["holdDeadline"]="2026-10-05T00:05:00Z";body["ownedDraftId"]=101;body["installedAt"]="2026-10-05T00:00:01Z";body["professionalTemplateStatus"]="MATERIALIZATION_REQUIRED";body["published"]=false;body["executable"]=false;value=body
                case "status":let body=try JSONSerialization.jsonObject(with:request.httpBody!) as! [String:Any];value=["schema":"w18-paid-install-outcome-v1","state":"NOT_FOUND","requestId":body["requestId"]!]
                default:throw APIError.invalidRequest
                }
                return(try WorkshopPurchasedAppFixture.envelope(value),200)
            }
            if request.url?.path.contains("/workshop/purchased/")==true{return(try WorkshopPurchasedAppFixture.envelope(request.url?.lastPathComponent=="list" ? WorkshopPurchasedAppFixture.page():WorkshopPurchasedAppFixture.detail()),200)}
            let value:String
            switch request.url?.lastPathComponent{
            case "phone":value="{\"code\":200,\"token\":\"synthetic-7\",\"data\":{\"id\":7,\"role\":\"\(role)\"}}"
            case "userInfo":value="{\"code\":200,\"appUser\":{\"userId\":7,\"role\":\"\(role)\"}}"
            case "logout":value=#"{"code":200}"#
            default:throw APIError.invalidRequest
            }
            return(Data(value.utf8),200)
        }
    }
    @MainActor private final class Harness{
        let wire=Wire(),vault=Vault(),base=URL(string:"https://example.com/native")!,suite="paid-install-tests-"+UUID().uuidString
        let deployment:ReviewedAppDeployment
        var session:AppSession!,approval:WorkshopPaidInstallApproval?,readApproval:WorkshopPurchasedReadApproval?,seen=0
        init()throws{
            deployment=try .init(market:.china,baseURL:base.absoluteString,approvedBaseURLs:[.china:[base.absoluteString]],verifiedCapabilities:[.domesticChinaPhone],bundleIdentifier:"test.workshop.install",realm:"synthetic-"+UUID().uuidString.lowercased())
            session=AppCompositionRoot(deployment:.reviewed(deployment),storage:.init(defaults:UserDefaults(suiteName:suite)!,tokenStore:{[vault] _ in vault}),makeTransport:{[wire] in wire},workshopPaidInstallApproval:{[weak self] context in
                guard let self,let expected=try? self.context() else{return nil};self.seen += 1;XCTAssertEqual(context,expected);guard context==expected else{return nil};return self.approval
            },workshopPurchasedReadApproval:{[weak self] context in guard let self,let grant=self.readApproval,grant.matches(context) else{return nil};return grant}).makeSession()
        }
        func context()throws->RuntimeDependencyContext{.init(market:.china,baseURL:base,role:wire.role,session:try .init(accountID:7,epoch:session.sessionRevision,namespace:deployment.storageScope.service,token:"synthetic-7"))}
        func login()async{await session.authChannels.loginWithPhone(phone:"10000000000",code:"123456")}
        func approve()throws{let grant=try WorkshopPaidInstallApproval(context:context(),expiresAt:.distantFuture);session.withWorkshopReadConfigurationChange{approval=grant}}
        func clean(){UserDefaults(suiteName:suite)?.removePersistentDomain(forName:suite)}
        func controller()throws->WorkshopPaidInstallController{try XCTUnwrap(session.makeWorkshopPaidInstallController(item:WorkshopPaidInstallNormalFlowTests.item()))}
    }
    func testNormalAccountDefaultAndMetadataApprovalCannotConstructInstallController()async throws{
        let h=try Harness();defer{h.clean()};XCTAssertNil(h.session.makeWorkshopPaidInstallController(item:try Self.item()));await h.login()
        h.readApproval=try .init(context:h.context(),expiresAt:.distantFuture);XCTAssertNotNil(h.session.workshopPurchasedBrowser);XCTAssertNil(h.session.makeWorkshopPaidInstallController(item:try Self.item()));XCTAssertTrue(h.wire.installs.isEmpty)
    }
    func testNormalSignedInPlayerMerchantAndClubUseExactFullContextAndSameController()async throws{
        for role in ["player","merchant","club"]{let h=try Harness();defer{h.clean()};h.wire.role=role;await h.login();try h.approve()
            let c=try h.controller();XCTAssertTrue(c === h.session.makeWorkshopPaidInstallController(item:try Self.item()));let a=WorkshopPaidInstallAppearance();await (try XCTUnwrap(c.appear(a)))()
            XCTAssertEqual(c.phase,.ready);XCTAssertEqual(c.targets.count,1);XCTAssertEqual(h.wire.installs.count,2);XCTAssertGreaterThanOrEqual(h.seen,5)
            XCTAssertTrue(h.wire.installs.allSatisfy{$0.value(forHTTPHeaderField:"Authorization")=="synthetic-7"});XCTAssertTrue(h.wire.writes.isEmpty)
        }
    }
    func testNormalControllerConfirmationReachesDedicatedTransportAndOnePrivateReceipt()async throws{
        let h=try Harness();defer{h.clean()};await h.login();try h.approve();let c=try h.controller(),a=WorkshopPaidInstallAppearance();await (try XCTUnwrap(c.appear(a)))()
        c.select(try XCTUnwrap(c.targets.first),appearance:a);c.chooseRegion("synthetic-region",appearance:a);c.review(appearance:a);let q=try XCTUnwrap(c.confirmation)
        let action=try XCTUnwrap(c.offerSubmit(a,command:q));XCTAssertTrue(h.wire.writes.isEmpty);await action()
        XCTAssertEqual(h.wire.writes.count,1);XCTAssertEqual(c.phase,.installed);XCTAssertEqual(c.outcome?.ownedDraftId,101);XCTAssertNil(c.pending)
    }
    func testNormalConfigurationABAInvalidatesBeforeChangeAndLate401DoesNotLogout()async throws{
        let h=try Harness();defer{h.clean()};await h.login();try h.approve();let c=try h.controller(),old=h.approval,a=WorkshopPaidInstallAppearance();h.wire.delayNext=true
        let action=try XCTUnwrap(c.appear(a)),task=Task{await action()};await h.wire.wait()
        h.session.withWorkshopReadConfigurationChange{XCTAssertEqual(c.phase,.invalidated);h.approval=nil;XCTAssertNil(h.session.makeWorkshopPaidInstallController(item:try! Self.item()))}
        h.session.withWorkshopReadConfigurationChange{h.approval=old};let replacement=try h.controller();XCTAssertFalse(c === replacement)
        h.wire.resume((Data(),401));await task.value;XCTAssertTrue(h.session.isSignedIn);XCTAssertEqual(replacement.phase,.idle)
    }
    func testNormalRoleABAAndRootReplacementRevokeQueuedReadBeforeDispatch()async throws{
        let h=try Harness();defer{h.clean()};await h.login();try h.approve();let c=try h.controller(),a=WorkshopPaidInstallAppearance(),action=try XCTUnwrap(c.appear(a))
        h.wire.role="merchant";await h.session.refreshOwnAccount();h.wire.role="player";await h.session.refreshOwnAccount();await action()
        XCTAssertEqual(c.phase,.invalidated);XCTAssertTrue(h.wire.installs.isEmpty);let fresh=try h.controller();h.session.setWorkshopOwnedPresentationActive(false);XCTAssertEqual(fresh.phase,.invalidated)
        XCTAssertNil(h.session.makeWorkshopPaidInstallController(item:try Self.item()));h.session.setWorkshopOwnedPresentationActive(true);XCTAssertFalse(fresh === h.session.makeWorkshopPaidInstallController(item:try Self.item()))
    }
    func testRealHostedInstallModalDismissAndReopenRetiresOldViewCallbacks()async throws{
        let h=try Harness();defer{h.clean()};await h.login();try h.approve();let c=try h.controller(),old=WorkshopPaidInstallAppearance()
        let window=UIWindow(frame:UIScreen.main.bounds),presenter=UIViewController();window.rootViewController=presenter;window.makeKeyAndVisible();defer{window.isHidden=true}
        let host=UIHostingController(rootView:WorkshopPaidInstallView(controller:c,appearance:old,onClose:{}));presenter.present(host,animated:false)
        for _ in 0..<1000{if c.phase == .ready{break};await Task.yield()};XCTAssertEqual(c.phase,.ready)
        presenter.dismiss(animated:false);for _ in 0..<1000{if c.phase == .idle{break};await Task.yield()};XCTAssertEqual(c.phase,.idle)
        let fresh=WorkshopPaidInstallAppearance();await (try XCTUnwrap(c.appear(fresh)))();c.close(old);XCTAssertNil(c.appear(old));XCTAssertEqual(c.phase,.ready)
    }
    func testNormalTransportNeverAcceptsSubmitThroughGeneralSendEvenWithInstallApproval()async throws{
        let h=try Harness();defer{h.clean()};await h.login();let ctx=try h.context(),grant=try WorkshopPaidInstallApproval(context:ctx,expiresAt:.distantFuture),transport=CompositionHTTPTransport(deployment:h.deployment,underlying:h.wire,workshopPaidInstallApproval:{actual in XCTAssertEqual(actual,ctx);return actual==ctx ? grant:nil})
        transport.current={.init(epoch:ctx.session.epoch,accountID:7,role:"player",token:"synthetic-7")}
        let target=try WorkshopPaidInstallWire.decode(WorkshopPaidInstallTarget.self,data:JSONSerialization.data(withJSONObject:Self.target)),command=try WorkshopPaidInstallCommand(item:Self.item(),target:target,region:"synthetic-region",commercialUse:false)
        let request=try mutationRequest(command,context:ctx);do{_=try await transport.send(request);XCTFail("General send accepted installation")}catch{}
        XCTAssertTrue(h.wire.installs.isEmpty)
        let lifetime=WorkshopPaidInstallLifetime{true},authorization=WorkshopPaidInstallDispatchAuthorization(context:ctx,revision:grant.revision,body:try command.wireData(),lifetime:lifetime,checkCurrent:{})
        _=try await transport.sendWorkshopPaidInstall(request,authorization:authorization);XCTAssertEqual(h.wire.writes.count,1)
        do{_=try await transport.sendWorkshopPaidInstall(request,authorization:authorization);XCTFail("Dispatch token reused")}catch{};XCTAssertEqual(h.wire.writes.count,1)
    }
    func testTransportClonePreservesInstallSelectorAndLifetimeClosesBeforeForward()async throws{
        let h=try Harness();defer{h.clean()};await h.login();let ctx=try h.context(),grant=try WorkshopPaidInstallApproval(context:ctx,expiresAt:.distantFuture),transport=CompositionHTTPTransport(deployment:h.deployment,underlying:h.wire,workshopPaidInstallApproval:{actual in actual==ctx ? grant:nil})
        transport.current={.init(epoch:ctx.session.epoch,accountID:7,role:"player",token:"synthetic-7")};let lifetime=WorkshopPaidInstallLifetime{true}
        transport.workshopPaidInstallBeforeForward={lifetime.revoke()};let clone=transport.replacingUnderlying(h.wire)
        let target=try WorkshopPaidInstallWire.decode(WorkshopPaidInstallTarget.self,data:JSONSerialization.data(withJSONObject:Self.target)),command=try WorkshopPaidInstallCommand(item:Self.item(),target:target,region:"synthetic-region",commercialUse:false)
        let authorization=WorkshopPaidInstallDispatchAuthorization(context:ctx,revision:grant.revision,body:try command.wireData(),lifetime:lifetime,checkCurrent:{})
        do{_=try await clone.sendWorkshopPaidInstall(mutationRequest(command,context:ctx),authorization:authorization);XCTFail("Expired action forwarded")}catch{};XCTAssertTrue(h.wire.installs.isEmpty)
    }
    private func mutationRequest(_ command:WorkshopPaidInstallCommand,context:RuntimeDependencyContext)throws->URLRequest{
        var r=URLRequest(url:context.baseURL.appendingPathComponent("api/workshop/purchased/install/submit"));r.httpMethod="POST";r.httpBody=try command.wireData();r.setValue("synthetic-7",forHTTPHeaderField:"Authorization");r.setValue(String(r.httpBody!.count),forHTTPHeaderField:"Content-Length");r.setValue("application/json; charset=utf-8",forHTTPHeaderField:"Content-Type");r.setValue("no-store",forHTTPHeaderField:"Cache-Control");r.setValue("no-cache",forHTTPHeaderField:"Pragma");r.cachePolicy = .reloadIgnoringLocalCacheData;return r
    }
}
