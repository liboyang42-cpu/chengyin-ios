import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class WorkshopCreatorConsentNormalFlowTests: XCTestCase {
    private static func envelope(_ value:[String:Any])throws->Data{try JSONSerialization.data(withJSONObject:["code":200,"data":value],options:.sortedKeys)}
    private static func preview()throws->[String:Any]{
        let text=#"{"schema":"w18-member-text-v1","title":"Synthetic original","merchantGuide":"Original guide","bindings":{}}"#
        return ["schema":"w18-creator-public-use-preview-v1","sourceTemplateId":91,"templateHash":String(repeating:"a",count:64),"packageContentHash":WorkshopCreatorWire.sha(Data(text.utf8)),"packageSourceJson":text,"omittedPlanningMetadata":[],"disclosureVersion":WorkshopCreatorDisclosure.version,"disclosureHash":WorkshopCreatorDisclosure.hash,"disclosureText":WorkshopCreatorDisclosure.text,"state":"EXPLICIT_CREATOR_CONFIRMATION_REQUIRED","packageReviewed":false]
    }
    private static func receipt(_ c:WorkshopCreatorDeclarationCommand)->[String:Any]{
        ["schema":"w18-creator-public-use-declaration-receipt-v1","state":"CREATOR_DECLARED_PENDING_PACKAGE_REVIEW","sourceTemplateId":c.sourceTemplateId,"templateHash":c.expectedTemplateHash,"offerVersion":c.offerVersion,"termsVersion":c.termsVersion,"declaredAt":"2026-10-06T00:00:00Z","disclosureVersion":WorkshopCreatorDisclosure.version,"disclosureHash":WorkshopCreatorDisclosure.hash,"packageReviewed":false,"listed":false,"licenseIssued":false,"consentReference":["scope":"BUYER_OWN_PUBLISHED_THEMES","consentId":"00000000-0000-4000-8000-000000000001","creatorMemberId":7,"moduleId":c.moduleId,"versionId":c.versionId,"contentHash":c.expectedPackageContentHash,"termsDocumentHash":c.termsDocumentHash,"recordHash":String(repeating:"b",count:64)]]
    }
    @MainActor private final class Vault:AppTokenStorage{var token:String?;func read()throws->String?{token};func write(_ value:String)throws{token=value};func clear()throws{token=nil}}
    @MainActor private final class Wire:HTTPTransport{
        var role="player",requests:[URLRequest]=[],delay=false
        var committed:WorkshopCreatorDeclarationCommand?,suspended:CheckedContinuation<(Data,Int),Never>?
        var creatorRequests:[URLRequest]{requests.filter{$0.url?.path.contains("/creator/public-theme-use/")==true}}
        var writes:[URLRequest]{creatorRequests.filter{$0.url?.lastPathComponent=="declare"}}
        func wait()async{for _ in 0..<1000{if suspended != nil{return};await Task.yield()};XCTFail("Expected suspended transport")}
        func resume401(){let old=suspended;suspended=nil;old?.resume(returning:(Data(),401))}
        func send(_ request:URLRequest)async throws->(Data,Int){
            requests.append(request)
            if request.url?.path.contains("/creator/public-theme-use/")==true{
                if delay{delay=false;return await withCheckedContinuation{suspended=$0}}
                switch request.url!.lastPathComponent{
                case "preview":return(try WorkshopCreatorConsentNormalFlowTests.envelope(WorkshopCreatorConsentNormalFlowTests.preview()),200)
                case "declare":let c=try WorkshopCreatorWire.decode(WorkshopCreatorDeclarationCommand.self,data:request.httpBody!);committed=c;return(try WorkshopCreatorConsentNormalFlowTests.envelope(WorkshopCreatorConsentNormalFlowTests.receipt(c)),200)
                case "status":if let committed{return(try WorkshopCreatorConsentNormalFlowTests.envelope(WorkshopCreatorConsentNormalFlowTests.receipt(committed)),200)}
                    let q=try JSONSerialization.jsonObject(with:request.httpBody!) as! [String:Any];return(try WorkshopCreatorConsentNormalFlowTests.envelope(["schema":"w18-creator-public-use-declaration-status-v1","state":"NOT_FOUND","requestId":q["requestId"]!]),200)
                default:throw APIError.invalidRequest
                }
            }
            switch request.url?.lastPathComponent{
            case "phone":return(Data("{\"code\":200,\"token\":\"synthetic-7\",\"data\":{\"id\":7,\"role\":\"\(role)\"}}".utf8),200)
            case "userInfo":return(Data("{\"code\":200,\"appUser\":{\"userId\":7,\"role\":\"\(role)\"}}".utf8),200)
            default:throw APIError.invalidRequest
            }
        }
    }
    @MainActor private final class Harness{
        let wire=Wire(),vault=Vault(),base=URL(string:"https://example.com/native")!,suite="creator-consent-"+UUID().uuidString
        let deployment:ReviewedAppDeployment
        var session:AppSession!,read:WorkshopCreatorConsentReadApproval?,write:WorkshopCreatorConsentWriteApproval?,targets:[WorkshopCreatorDeclarationTarget]=[],seen=0
        init()throws{
            deployment=try .init(market:.china,baseURL:base.absoluteString,approvedBaseURLs:[.china:[base.absoluteString]],verifiedCapabilities:[.domesticChinaPhone],bundleIdentifier:"test.creator.declaration",realm:"synthetic-"+UUID().uuidString.lowercased())
            session=AppCompositionRoot(deployment:.reviewed(deployment),storage:.init(defaults:UserDefaults(suiteName:suite)!,tokenStore:{[vault] _ in vault}),makeTransport:{[wire] in wire},
                workshopCreatorDeclarationTargets:{[weak self] actual,source in guard let self,let expected=try? self.context() else{return []};XCTAssertEqual(actual,expected);XCTAssertEqual(source,91);return actual==expected ? self.targets:[]},
                workshopCreatorConsentReadApproval:{[weak self] actual in guard let self,let expected=try? self.context() else{return nil};self.seen += 1;XCTAssertEqual(actual,expected);return actual==expected ? self.read:nil},
                workshopCreatorConsentWriteApproval:{[weak self] actual in guard let self,let expected=try? self.context() else{return nil};XCTAssertEqual(actual,expected);return actual==expected ? self.write:nil}).makeSession()
        }
        func context()throws->RuntimeDependencyContext{.init(market:.china,baseURL:base,role:wire.role,session:try .init(accountID:7,epoch:session.sessionRevision,namespace:deployment.storageScope.service,token:"synthetic-7",role:wire.role))}
        func login()async{await session.authChannels.loginWithPhone(phone:"10000000000",code:"123456")}
        func approve(writing:Bool=true,target:Bool=true)throws{
            let c=try context(),r=try WorkshopCreatorConsentReadApproval(context:c,expiresAt:.distantFuture)
            let w=writing ? try WorkshopCreatorConsentWriteApproval(context:c,expiresAt:.distantFuture):nil
            let t=try WorkshopCreatorDeclarationTarget(sourceTemplateId:91,moduleId:"synthetic-package",versionId:"v1",offerVersion:"offer-v1",termsVersion:"terms-v1",termsDocument:"Full synthetic terms",termsDocumentHash:WorkshopCreatorWire.sha(Data("Full synthetic terms".utf8)),expiresAt:.distantFuture)
            session.withWorkshopCreatorConsentConfigurationChange{read=r;write=w;targets=target ? [t]:[]}
        }
        func controller()throws->WorkshopCreatorConsentController{try XCTUnwrap(session.makeWorkshopCreatorConsentController(sourceTemplateId:91))}
        func clean(){UserDefaults(suiteName:suite)?.removePersistentDomain(forName:suite)}
    }
    func testDefaultNormalLoginDoesNotGrantPreviewOrDeclaration()async throws{
        let h=try Harness();defer{h.clean()};await h.login();XCTAssertNil(h.session.makeWorkshopCreatorConsentController(sourceTemplateId:91));XCTAssertTrue(h.wire.creatorRequests.isEmpty)
    }
    func testPlayerMerchantClubSelectorsReceiveConsistentFullContextAndRetainController()async throws{
        for role in ["player","merchant","club"]{let h=try Harness();defer{h.clean()};h.wire.role=role;await h.login();try h.approve()
            let c=try h.controller(),a=WorkshopCreatorConsentAppearance();XCTAssertTrue(c === h.session.makeWorkshopCreatorConsentController(sourceTemplateId:91))
            await (try XCTUnwrap(c.appear(a)))();XCTAssertEqual(c.phase,.reviewing);XCTAssertEqual(c.targets.count,1);XCTAssertGreaterThan(h.seen,3);XCTAssertTrue(h.wire.writes.isEmpty)
        }
    }
    func testNormalPreviewExplicitThreeConfirmationsAndRecordedReceipt()async throws{
        let h=try Harness();defer{h.clean()};await h.login();try h.approve();let c=try h.controller(),a=WorkshopCreatorConsentAppearance();await (try XCTUnwrap(c.appear(a)))()
        c.select(try XCTUnwrap(c.targets.first),appearance:a);for i in 0..<3{c.acknowledge(i,value:true,appearance:a)}
        let action=try XCTUnwrap(c.offerConfirm(a));XCTAssertTrue(h.wire.writes.isEmpty);await action();XCTAssertEqual(c.phase,.recorded);XCTAssertEqual(h.wire.writes.count,1)
        c.close(a);let fresh=WorkshopCreatorConsentAppearance();await (try XCTUnwrap(c.appear(fresh)))();XCTAssertEqual(c.phase,.recorded);XCTAssertEqual(h.wire.writes.count,1)
    }
    func testReadGrantAndMissingTargetCannotDeclare()async throws{
        let h=try Harness();defer{h.clean()};await h.login();try h.approve(writing:false,target:false);let c=try h.controller(),a=WorkshopCreatorConsentAppearance();await (try XCTUnwrap(c.appear(a)))()
        XCTAssertNotNil(c.preview);XCTAssertTrue(c.targets.isEmpty);XCTAssertNil(c.offerConfirm(a));XCTAssertTrue(h.wire.writes.isEmpty)
    }
    func testConfigurationABARevokesBeforeCallbackAndFencesLate401()async throws{
        let h=try Harness();defer{h.clean()};await h.login();try h.approve();let c=try h.controller(),a=WorkshopCreatorConsentAppearance(),old=h.read;h.wire.delay=true
        let action=try XCTUnwrap(c.appear(a)),task=Task{await action()};await h.wire.wait()
        h.session.withWorkshopCreatorConsentConfigurationChange{XCTAssertEqual(c.phase,.invalidated);h.read=nil;XCTAssertNil(h.session.makeWorkshopCreatorConsentController(sourceTemplateId:91))}
        h.session.withWorkshopCreatorConsentConfigurationChange{h.read=old};let replacement=try h.controller();h.wire.resume401();await task.value
        XCTAssertTrue(h.session.isSignedIn);XCTAssertFalse(c === replacement);XCTAssertEqual(replacement.phase,.idle)
    }
    func testNormalRoleABARejectsQueuedOldAction()async throws{
        let h=try Harness();defer{h.clean()};await h.login();try h.approve();let c=try h.controller(),a=WorkshopCreatorConsentAppearance(),action=try XCTUnwrap(c.appear(a))
        h.wire.role="merchant";await h.session.refreshOwnAccount();h.wire.role="player";await h.session.refreshOwnAccount();await action()
        XCTAssertEqual(c.phase,.invalidated);XCTAssertTrue(h.wire.creatorRequests.isEmpty)
    }
    func testGeneralTransportRejectsDeclarationButPreservesPreviewOnClone()async throws{
        let h=try Harness();defer{h.clean()};await h.login();let ctx=try h.context(),r=try WorkshopCreatorConsentReadApproval(context:ctx,expiresAt:.distantFuture),w=try WorkshopCreatorConsentWriteApproval(context:ctx,expiresAt:.distantFuture)
        let t=CompositionHTTPTransport(deployment:h.deployment,underlying:h.wire,workshopCreatorConsentReadApproval:{$0==ctx ? r:nil},workshopCreatorConsentWriteApproval:{$0==ctx ? w:nil})
        t.current={.init(epoch:ctx.session.epoch,accountID:7,role:ctx.role,token:ctx.session.token)};let clone=t.replacingUnderlying(h.wire)
        let p=try WorkshopCreatorWire.decode(WorkshopCreatorPreview.self,data:JSONSerialization.data(withJSONObject:Self.preview()))
        try h.approve();let command=try WorkshopCreatorDeclarationCommand(preview:p,target:h.targets[0])
        var request=URLRequest(url:h.base.appendingPathComponent("api/workshop/creator/public-theme-use/declare"));request.httpMethod="POST";request.httpBody=try command.data();request.setValue(ctx.session.token,forHTTPHeaderField:"Authorization");request.setValue("application/json; charset=utf-8",forHTTPHeaderField:"Content-Type");request.setValue(String(request.httpBody!.count),forHTTPHeaderField:"Content-Length");request.setValue("no-store",forHTTPHeaderField:"Cache-Control");request.setValue("no-cache",forHTTPHeaderField:"Pragma");request.cachePolicy = .reloadIgnoringLocalCacheData
        do{_=try await clone.send(request);XCTFail("Ordinary send allowed declaration")}catch{};XCTAssertTrue(h.wire.writes.isEmpty)
        request.url=h.base.appendingPathComponent("api/workshop/creator/public-theme-use/preview");request.httpBody=try WorkshopCreatorConsentRequest.previewBody(91);request.setValue(String(request.httpBody!.count),forHTTPHeaderField:"Content-Length")
        _=try await clone.send(request);XCTAssertEqual(h.wire.creatorRequests.count,1)
    }
    func testHostedNavigationBackAndFreshRowSelectionRetiresOldPresentation()async throws{
        let h=try Harness();defer{h.clean()};await h.login();try h.approve();let c=try h.controller(),selection=WorkshopCreatorConsentSelection(source:MemberPlayTemplateID(rawValue:91)!)
        let root=WorkshopHostedLifecycleRoot(),navigation=UINavigationController(rootViewController:root),window=UIWindow(frame:UIScreen.main.bounds)
        window.rootViewController=navigation;window.makeKeyAndVisible();defer{window.isHidden=true}
        let host=WorkshopHostedLifecycleHost(rootView:WorkshopCreatorConsentView(controller:c,appearance:selection.appearance));navigation.pushViewController(host,animated:false)
        try await waitUntil{c.phase == .reviewing};
        WorkshopHostedLifecycleProbe.record(.consentInitial, root: root, host: host, navigation: navigation, idle: c.phase == .idle, loading: c.phase == .loading, reviewing: c.phase == .reviewing, editing: false)
        XCTAssertEqual(c.phase,.reviewing)
        navigation.popViewController(animated:false);try await waitUntil{c.phase == .idle};XCTAssertEqual(c.phase,.idle)
        let fresh=WorkshopCreatorConsentSelection(source:selection.source);XCTAssertNotEqual(fresh,selection)
        await (try XCTUnwrap(c.appear(fresh.appearance)))();c.close(selection.appearance);XCTAssertNil(c.appear(selection.appearance));XCTAssertEqual(c.phase,.reviewing)
    }
    private func waitUntil(_ condition:()->Bool)async throws{
        let deadline=Date().addingTimeInterval(5)
        while !condition(),Date()<deadline{try await Task.sleep(nanoseconds:10_000_000)}
        XCTAssertTrue(condition(),"Bounded hosted navigation condition did not arrive")
    }
}

#if DEBUG
import SwiftUI
import UIKit

@MainActor final class WorkshopHostedLifecycleRoot: UIViewController {
    private(set) var observedAppearance = false
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        observedAppearance = true
    }
}

@MainActor final class WorkshopHostedLifecycleHost<Content: View>: UIHostingController<Content> {
    private(set) var observedAppearance = false
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        observedAppearance = true
    }
}

@MainActor enum WorkshopHostedLifecycleProbe {
    enum Stage: String { case consentInitial, pendingInitialBack, pendingInitialReview }
    static func record<Content: View>(_ stage: Stage, root: WorkshopHostedLifecycleRoot,
                                      host: WorkshopHostedLifecycleHost<Content>, navigation: UINavigationController,
                                      idle: Bool, loading: Bool, reviewing: Bool, editing: Bool) {
        // One fixed checkpoint per sealed test. No controller IDs, content or errors.
        print("WORKSHOP_CREATOR_HOST stage=\(stage.rawValue) rootWindow=\(root.viewIfLoaded?.window != nil) hostWindow=\(host.viewIfLoaded?.window != nil) rootAppeared=\(root.observedAppearance) hostAppeared=\(host.observedAppearance) topMatches=\(navigation.topViewController === host) idle=\(idle) loading=\(loading) reviewing=\(reviewing) editing=\(editing)")
    }
}
#endif
