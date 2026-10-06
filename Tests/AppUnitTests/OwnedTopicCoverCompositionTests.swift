import XCTest
@testable import Questify

@MainActor final class OwnedTopicCoverCompositionTests: XCTestCase {
    private let base=URL(string:"https://example.com/native")!
    private final class Grant { var enabled=true; var operations:Set<OwnedTopicCoverOperation>=[.readCurrent,.readAsset,.upload,.select,.status]; var picker=false }
    private final class Vault:AppTokenStorage { var value:String?;func read()throws->String?{value};func write(_ token:String)throws{value=token};func clear()throws{value=nil} }
    @MainActor private final class Wire:HTTPTransport {
        var requests:[URLRequest]=[],role="player",hold=false
        var started:XCTestExpectation?,continuation:CheckedContinuation<(Data,Int),Error>?
        func send(_ request:URLRequest) async throws->(Data,Int) {
            requests.append(request)
            if request.url?.path.hasSuffix("/phone")==true{return(Data("{\"code\":200,\"token\":\"synthetic-7\",\"data\":{\"id\":7,\"role\":\"\(role)\"}}".utf8),200)}
            if request.url?.path.hasSuffix("/userInfo")==true{return(Data("{\"code\":200,\"appUser\":{\"userId\":7,\"role\":\"\(role)\"}}".utf8),200)}
            if hold {return try await withCheckedThrowingContinuation{continuation=$0;started?.fulfill()}}
            return(Data(#"{"code":200,"data":{"topicId":7901,"topicConfigVersion":1,"selectionVersion":0,"contentSlotId":51,"selectedAtConfigVersion":null,"selectionState":"NONE","assetAvailability":"NONE","display":null}}"#.utf8),200)
        }
        func finish401(){let old=continuation;continuation=nil;old?.resume(returning:(Data(),401))}
    }
    private func root(_ wire:Wire,_ grant:Grant,_ vault:Vault)throws->AppCompositionRoot {
        let suite="owned-cover-composition-"+UUID().uuidString,defaults=try XCTUnwrap(UserDefaults(suiteName:suite))
        addTeardownBlock{defaults.removePersistentDomain(forName:suite)}
        let deployment=try ReviewedAppDeployment(market:.china,baseURL:base.absoluteString,approvedBaseURLs:[.china:[base.absoluteString]],verifiedCapabilities:[.domesticChinaPhone],bundleIdentifier:"test.owned-cover",realm:"synthetic")
        return .init(deployment:.reviewed(deployment),storage:.init(defaults:defaults,tokenStore:{_ in vault}),makeTransport:{wire},ownedTopicCoverApproval:{context in
            guard grant.enabled else{return nil}
            return try? .init(baseURL:context.baseURL,namespace:context.session.namespace,accountID:context.session.accountID,operations:grant.operations,nativePicker:grant.picker)
        },makeOwnedTopicCoverTransport:{_ in wire})
    }
    private func login(_ session:AppSession)async{session.authChannels.cancel();await session.authChannels.loginWithPhone(phone:"10000000000",code:"123456");XCTAssertEqual(session.account?.id,7)}
    func testOrdinaryPersonalFactoryUsesExactProducerAndPickerIsIndependentlyOff()async throws {
        let wire=Wire(),grant=Grant(),session=try root(wire,grant,Vault()).makeSession();await login(session)
        let editor=session.projectEditor(product:.city),owner=try XCTUnwrap(editor.session),source=try XCTUnwrap(editor.ownedCoverSource)
        wire.requests=[];let current=try await source.current(topicID:7901,session:owner)
        XCTAssertEqual(current.contentSlotID,51);XCTAssertEqual(current.configVersion,1);XCTAssertNil(current.asset)
        XCTAssertEqual(wire.requests.count,1);XCTAssertEqual(wire.requests[0].url?.absoluteString,base.appendingPathComponent(OwnedTopicCoverClient.currentPath).absoluteString+"?topicId=7901")
        XCTAssertFalse(source.permitsNativePicker(session:owner));XCTAssertNotNil(editor.ownedCoverJournal)
        XCTAssertNil(editor.releaseReviewSource);XCTAssertNil(editor.releasePublicationSource)
    }
    func testMissingApprovalHasNoFactoryAndNoProducerDispatch()async throws {
        let wire=Wire(),grant=Grant();grant.enabled=false
        let session=try root(wire,grant,Vault()).makeSession();await login(session);wire.requests=[]
        XCTAssertNil(session.projectEditor(product:.city).ownedCoverSource);XCTAssertTrue(wire.requests.isEmpty)
    }
    func testConfigurationABAInvalidatesOldFactoryWithoutChangingPersistentOwner()async throws {
        let wire=Wire(),grant=Grant(),session=try root(wire,grant,Vault()).makeSession();await login(session)
        let old=session.projectEditor(product:.city),original=try XCTUnwrap(old.session),source=try XCTUnwrap(old.ownedCoverSource)
        session.withProjectEditConfigurationChange{grant.operations.remove(.upload)}
        session.withProjectEditConfigurationChange{grant.operations.insert(.upload)}
        let fresh=session.projectEditor(product:.city),owner=try XCTUnwrap(fresh.session),count=wire.requests.count
        XCTAssertEqual(owner.ownerKey,original.ownerKey);XCTAssertNotEqual(owner,original);XCTAssertFalse(source.isCurrent(session:owner))
        do{_=try await source.current(topicID:7901,session:owner);XCTFail()}catch{}
        XCTAssertEqual(wire.requests.count,count)
        _=try await XCTUnwrap(fresh.ownedCoverSource).current(topicID:7901,session:owner)
    }
    func testHeldActualCloneEmpty401AfterGrantABADoesNotExpireReturnedAccount()async throws {
        let wire=Wire(),grant=Grant(),vault=Vault(),session=try root(wire,grant,vault).makeSession();await login(session)
        let editor=session.projectEditor(product:.city),owner=try XCTUnwrap(editor.session),source=try XCTUnwrap(editor.ownedCoverSource)
        wire.hold=true;wire.started=expectation(description:"bounded underlying clone held")
        let task=Task{try await source.current(topicID:7901,session:owner)};await fulfillment(of:[try XCTUnwrap(wire.started)],timeout:3)
        session.withProjectEditConfigurationChange{grant.enabled=false;grant.enabled=true};wire.finish401()
        do{_=try await task.value;XCTFail()}catch{}
        XCTAssertEqual(session.account?.id,7);XCTAssertEqual(vault.value,"synthetic-7");XCTAssertFalse(source.isCurrent(session:owner))
    }
    func testRoleABAOldFactoryCannotBorrowFreshAuthorApproval()async throws {
        let wire=Wire(),grant=Grant(),session=try root(wire,grant,Vault()).makeSession();await login(session)
        let editor=session.projectEditor(product:.city),owner=try XCTUnwrap(editor.session),source=try XCTUnwrap(editor.ownedCoverSource)
        wire.role="merchant";await session.refreshOwnAccount();wire.role="player";await session.refreshOwnAccount()
        let count=wire.requests.count;XCTAssertFalse(source.isCurrent(session:owner))
        do{_=try await source.current(topicID:7901,session:owner);XCTFail()}catch{}
        XCTAssertEqual(wire.requests.count,count);XCTAssertNotNil(session.projectEditor(product:.city).ownedCoverSource)
    }
    func testOuterCloneRejectsAdjacentPathsDuplicateQueriesAndDifferentOwnerFields()async throws {
        let wire=Wire(),grant=Grant(),composition=try root(wire,grant,Vault()),fence=composition.transport()
        fence.current={.init(epoch:1,accountID:7,role:"player",token:"synthetic-7",viewerRevision:1)}
        fence.ownedTopicCoverConfigurationRevision={1};fence.ownedTopicCoverApproval={context in try? .init(baseURL:context.baseURL,namespace:context.session.namespace,accountID:7,operations:grant.operations)}
        let clone=fence.scopedForManualMap(ManualMapAreaSelection()).replacingUnderlying(wire)
        func get(_ suffix:String)->URLRequest{var r=URLRequest(url:URL(string:base.absoluteString+"/"+suffix)!);r.httpMethod="GET";r.setValue("synthetic-7",forHTTPHeaderField:"Authorization");return r}
        _=try await clone.send(get(OwnedTopicCoverClient.currentPath+"?topicId=7901"))
        for suffix in [OwnedTopicCoverClient.currentPath+"?topicId=7901&topicId=7901",OwnedTopicCoverClient.currentPath+"?topicId=07901",OwnedTopicCoverClient.currentPath+"?topicId=7901&owner=7","api/topic/cover/../player/content?topicId=7901"] {
            do{_=try await clone.send(get(suffix));XCTFail(suffix)}catch{}
        }
        var invalid=get(OwnedTopicCoverClient.selectPath);invalid.httpMethod="POST";invalid.setValue("application/json",forHTTPHeaderField:"Content-Type");invalid.httpBody=Data(#"{"topicId":7901,"ownerId":7}"#.utf8)
        do{_=try await clone.send(invalid);XCTFail()}catch{}
        XCTAssertEqual(wire.requests.count,1)
    }
    func testActualFactoryQueuedUploadAfterGrantABAHasPersistedIntentAndZeroDispatch()async throws {
        let wire=Wire(),grant=Grant();grant.picker=true
        let session=try root(wire,grant,Vault()).makeSession();await login(session)
        let editor=session.projectEditor(product:.city),owner=try XCTUnwrap(editor.session),source=try XCTUnwrap(editor.ownedCoverSource)
        let storage=ProjectEditMemoryStorage(),journal=OwnedTopicCoverJournal(storage:storage)
        let flow=OwnedTopicCoverAuthorFlow(session:owner,topicID:7901,source:source,journal:journal,parentCurrent:{true},mayChangeSelection:{true})
        await flow.load();let synthetic=try OwnedTopicCoverSynthetic(session:owner,currentSession:{owner});flow.setPicked(synthetic.picked)
        let claim=try XCTUnwrap(flow.claimUpload(try XCTUnwrap(flow.localReview))),before=storage.data,count=wire.requests.count
        let queued=Task{await flow.upload(claim)}
        session.withProjectEditConfigurationChange{grant.operations.remove(.upload);grant.operations.insert(.upload)}
        await queued.value;XCTAssertEqual(wire.requests.count,count);XCTAssertEqual(storage.data,before);XCTAssertEqual(flow.state,.closed)
        XCTAssertEqual(try journal.read(session:owner,topicID:7901).unresolvedUploadCount,1)
    }

}
