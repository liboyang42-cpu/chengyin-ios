import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class NativeChannelWelcomeProducerShapeTests:XCTestCase {
    private func context()throws->RuntimeDependencyContext {
        .init(market:.china,baseURL:URL(string:"https://welcome-fixture.example.test/")!,role:"player",session:try PlayExperienceSession(accountID:17,epoch:3,namespace:"welcome-fixture",token:"not-live"))
    }
    private func scope()throws->NativeChannelManagementScope {try .init(guildKind:1,guildID:.init("42"))}
    private func flow(_ wire:WelcomeShapeWire,current:@escaping()->Bool={true},unauthorized:@escaping()->Void={})throws->NativeChannelWelcomeFlow {
        let c=try context();let approval=try NativeChannelWelcomeApproval(endpoint:.init(baseURL:c.baseURL,namespace:c.session.namespace,accountID:17,paths:[NativeChannelWelcomeApproval.path]),expiresAt:Date().addingTimeInterval(600))
        return try .init(scope:scope(),context:c,approval:approval,transport:wire,current:current,unauthorized:unauthorized)
    }
    private func snapshot(_ value:[String:Any])throws->NativeChannelWelcomeSnapshot {
        try JSONDecoder().decode(NativeChannelWelcomeSnapshot.self,from:JSONSerialization.data(withJSONObject:value))
    }
    func testOriginalProducerAllowsZeroVersionAndEmptyTitleTogether()throws {
        let value=try snapshot(WelcomeShapeWire().payload)
        XCTAssertEqual(value.version,0);XCTAssertEqual(value.title,"");XCTAssertTrue(value.validate(context:try context(),scope:try scope()))
    }
    func testZeroVersionWithTitleAndPositiveVersionWithoutTitleAreIndependentlyValid()throws {
        for (version,title) in [(Int64(0),"Original title"),(Int64(1),"") ,(Int64(1),"Original title")] {
            var raw=WelcomeShapeWire().payload;raw["version"]=version;raw["title"]=title
            XCTAssertTrue(try snapshot(raw).validate(context:context(),scope:scope()))
        }
    }
    func testOriginalNormalReadCanOfferOnlyReturnedSignpostAndEntry()async throws {
        let wire=WelcomeShapeWire(),f=try flow(wire);await f.activate()
        XCTAssertEqual(f.snapshot?.version,0);XCTAssertEqual(f.snapshot?.title,"");XCTAssertNil(f.issue)
        XCTAssertTrue(f.permits(try .init("77")));XCTAssertTrue(f.permits(try .init("78")));XCTAssertFalse(f.permits(try .init("79")))
        XCTAssertEqual(wire.requests.count,1);let request=try XCTUnwrap(wire.requests.first)
        XCTAssertEqual(request.url?.path,"/api/welcome-screen/get");XCTAssertEqual(request.httpMethod,"POST")
        let fields=try XCTUnwrap(try JSONSerialization.jsonObject(with:XCTUnwrap(request.httpBody)) as? [String:Any])
        XCTAssertEqual(Set(fields.keys),["guild_kind","guild_id"]);XCTAssertEqual(fields["guild_id"] as? String,"42")
    }
    func testNegativeVersionAndMissingVersionRemainRejected()throws {
        var raw=WelcomeShapeWire().payload;raw["version"] = -1
        XCTAssertFalse(try snapshot(raw).validate(context:context(),scope:scope()))
        raw.removeValue(forKey:"version");XCTAssertThrowsError(try snapshot(raw))
    }
    func testMissingOrNonStringTitleIsNotInventedAsEmptyTitle()throws {
        var raw=WelcomeShapeWire().payload;raw.removeValue(forKey:"title");XCTAssertThrowsError(try snapshot(raw))
        raw["title"]=NSNull();XCTAssertThrowsError(try snapshot(raw));raw["title"]=12;XCTAssertThrowsError(try snapshot(raw))
    }
    func testActorScopeAndMaximumTextBoundsRemainRequired()throws {
        for (key,value) in [("viewer_id","18" as Any),("guild_id","43" as Any),("guild_kind",3 as Any),("title",String(repeating:"a",count:101) as Any),("description",String(repeating:"a",count:2001) as Any)] {
            var raw=WelcomeShapeWire().payload;raw[key]=value
            XCTAssertFalse(try snapshot(raw).validate(context:context(),scope:scope()))
        }
    }
    func testFiveDistinctSignpostsRemainMaximumAndEmptyLabelIsRejected()throws {
        var raw=WelcomeShapeWire().payload
        raw["signposts"]=(1...5).map{["channel_id":String(100+$0),"label":"Original","emoji":""]}
        XCTAssertTrue(try snapshot(raw).validate(context:context(),scope:scope()))
        raw["signposts"]=(1...6).map{["channel_id":String(100+$0),"label":"Original","emoji":""]}
        XCTAssertFalse(try snapshot(raw).validate(context:context(),scope:scope()))
        raw["signposts"]=[["channel_id":"78","label":"","emoji":""]]
        XCTAssertFalse(try snapshot(raw).validate(context:context(),scope:scope()))
        raw["signposts"]=[["channel_id":"78","label":"A","emoji":""],["channel_id":"78","label":"B","emoji":""]]
        XCTAssertFalse(try snapshot(raw).validate(context:context(),scope:scope()))
    }
    func testNotConfiguredAndScreeningPendingNeverGrantEntryOrBecomeJoinFailure()async throws {
        for error in ["WELCOME_SCREEN_NOT_CONFIGURED","SCREENING_PENDING"] {
            let wire=WelcomeShapeWire();wire.errorCode=error;let f=try flow(wire);await f.activate()
            XCTAssertNil(f.snapshot);XCTAssertNotNil(f.issue);XCTAssertFalse(f.permits(try .init("77")));XCTAssertEqual(wire.requests.count,1)
        }
    }
    func testRefreshClearsOldSignpostsAndAcceptsCurrentServerTargetsOnly()async throws {
        let wire=WelcomeShapeWire(),f=try flow(wire);await f.activate();XCTAssertTrue(f.permits(try .init("78")))
        wire.payload["entry_channel_id"]="81";wire.payload["signposts"]=[["channel_id":"82","label":"New current","emoji":""]]
        await f.refresh();XCTAssertFalse(f.permits(try .init("78")));XCTAssertFalse(f.permits(try .init("77")))
        XCTAssertTrue(f.permits(try .init("81")));XCTAssertTrue(f.permits(try .init("82")))
    }
    func testOriginalReturnCreatesFreshReaderWithoutUsingOldSnapshotAsAuthority()async throws {
        let wire=WelcomeShapeWire(),first=try flow(wire);await first.activate();first.deactivate()
        XCTAssertNil(first.snapshot);XCTAssertFalse(first.permits(try .init("77")))
        wire.payload["entry_channel_id"]="81";let returned=try flow(wire);await returned.activate()
        XCTAssertFalse(returned.permits(try .init("77")));XCTAssertTrue(returned.permits(try .init("81")));XCTAssertEqual(wire.requests.count,2)
    }
    func testDelayedOldVisitAndRevokedAccountNeverAcceptContent()async throws {
        let wire=WelcomeShapeWire();wire.hold=true;var allowed=true;let f=try flow(wire,current:{allowed})
        let task=Task{await f.activate()};await wire.waitForHeld();f.deactivate();allowed=false;wire.release();await task.value
        XCTAssertNil(f.snapshot);XCTAssertFalse(f.permits(try .init("77")))
        await f.activate();allowed=true;await f.activate();XCTAssertFalse(f.isCurrent);XCTAssertEqual(wire.requests.count,1)
    }
    func testUnauthorizedAndUnknownReadCannotRetainPreviouslyVisibleTargets()async throws {
        for status in [401,503] {
            let wire=WelcomeShapeWire();var unauthorized=false;let f=try flow(wire,unauthorized:{unauthorized=true});await f.activate()
            wire.status=status;await f.refresh();XCTAssertNil(f.snapshot);XCTAssertFalse(f.permits(try .init("77")))
            XCTAssertEqual(unauthorized,status==401)
        }
    }
}
@MainActor private final class WelcomeShapeWire:HTTPTransport {
    var payload:[String:Any] = ["viewer_id":"17","guild_id":"42","guild_kind":1,"entry_channel_id":"77","version":0,"title":"","description":"Original description","signposts":[["channel_id":"78","label":"Original guide","emoji":""]]]
    var requests:[URLRequest]=[],errorCode:String?,status=200,hold=false
    private var held:CheckedContinuation<(Data,Int),Error>?,waiter:CheckedContinuation<Void,Never>?
    func waitForHeld()async {if held != nil{return};await withCheckedContinuation{waiter=$0}}
    func release(){let old=held;held=nil;old?.resume(returning:try! response())}
    private func response()throws->(Data,Int) {
        var envelope:[String:Any]=["code":status,"data":payload]
        if let errorCode {envelope["code"]=409;envelope["errorCode"]=errorCode}
        return (try JSONSerialization.data(withJSONObject:envelope),errorCode == nil ? status:409)
    }
    func send(_ request:URLRequest)async throws->(Data,Int) {
        requests.append(request);XCTAssertEqual(request.url?.path,"/api/welcome-screen/get")
        if hold {return try await withCheckedThrowingContinuation{held=$0;waiter?.resume();waiter=nil}}
        return try response()
    }
}
