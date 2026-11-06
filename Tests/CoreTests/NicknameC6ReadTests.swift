import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@MainActor private final class NickC6Wire:ProfileNicknameDispatching {
    var requests:[URLRequest]=[],body=NickC6Fixture.check(),status=200
    var before:(()->Void)?,after:(()->Void)?
    var skip=false,suspend=false,duplicate=false
    var mutate:((inout URLRequest)->Void)?
    var waiter:CheckedContinuation<(Data,Int),Error>?
    func send(_ r:URLRequest,authorization:ProfileNicknameReadAuthorization) async throws -> (Data,Int) {
        before?();var request=r;mutate?(&request);if !skip { try authorization.forward(request){requests.append(request)} };if duplicate { try authorization.forward(request){requests.append(request)} };after?()
        if suspend { suspend=false;return try await withCheckedThrowingContinuation {waiter=$0} }
        return (Data(body.utf8),status)
    }
}
@MainActor private final class NickC6Fixture {
    let context:RuntimeDependencyContext,approval:ProfileNicknameReadApproval,wire=NickC6Wire()
    var current:RuntimeDependencyContext?,session:ProfileEditSession?,selected:ProfileNicknameReadApproval?
    lazy var reader=ProfileNicknameAvailabilityReader(approval:approval,currentContext:{[unowned self] in current},currentSession:{[unowned self] in session},selected:{[unowned self] in selected},transport:wire)
    init() throws {
        context = .init(market:.china,baseURL:URL(string:"https://nick.example.test/native")!,role:"player",session:try .init(accountID:7,epoch:1,namespace:"nick-test",token:"synthetic-nick",role:"player"))
        current=context;session=try .init(accountID:7,epoch:1,token:"synthetic-nick",viewerRevision:3)
        approval=try .init(context:context,viewerRevision:3,expiresAt:Date().addingTimeInterval(600));selected=approval
    }
    static func check(_ name:String="城市玩家",available:Bool=true,error:String?=nil)->String {
        "{\"code\":200,\"data\":{\"nickname\":\"\(name)\",\"available\":\(available),\"errorCode\":\(error.map{"\""+$0+"\""} ?? "null")}}"
    }
    static func suggestion(_ name:String="城市玩家#0002",cursor:Int=2)->String {
        "{\"code\":200,\"data\":{\"nickname\":\"\(name)\",\"available\":true,\"cursor\":\(cursor)}}"
    }
}
@MainActor private final class NickC6FlowReader:ProfileNicknameAvailabilityReading {
    var identity:ProfileReadIdentity? = .init(accountID:7,epoch:1)
    var viewerRevision:UInt64?=3,sourceRevision:UUID?=UUID()
    var isConfigured=true
    var checkResult=ProfileNicknameCheck.taken,checks=0,suggestions=0
    var after:(()->Void)?
    func check(_ value:String) async throws -> ProfileNicknameCheck { checks+=1;after?();return checkResult }
    func suggest(_ base:String,cursor:Int?) async throws -> ProfileNicknameSuggestion {
        suggestions+=1;after?();let n=(cursor ?? 0)+1;return .init(nickname:base+"#000"+String(n),cursor:n)
    }
}
@MainActor final class NicknameC6ReadTests:XCTestCase {
    func testJavaTrimAndCodePointRulesDoNotRewriteWriterNormalization() {
        XCTAssertEqual(ProfileNicknameRules.normalize("\u{0000}\t 城市 \r\n"),"城市")
        XCTAssertEqual(ProfileNicknameRules.normalize("\u{00A0}城市\u{00A0}"),"\u{00A0}城市\u{00A0}")
        XCTAssertNotNil(ProfileNicknameRules.issue("\u{00A0}城市"));XCTAssertNil(ProfileNicknameRules.issue(String(repeating:"𐐀",count:24)))
        XCTAssertNotNil(ProfileNicknameRules.issue(String(repeating:"𐐀",count:25)));XCTAssertNotNil(ProfileNicknameRules.issue("e\u{301}a"))
    }
    func testCheckUsesOnlyOriginalReadPOSTAndExactNormalizedEcho() async throws {
        let f=try NickC6Fixture();let result=try await f.reader.check(" 城市玩家 ");XCTAssertEqual(result,.available)
        let r=try XCTUnwrap(f.wire.requests.first);XCTAssertEqual(r.httpMethod,"POST");XCTAssertEqual(r.url?.path,"/native/api/user/nickname/check");XCTAssertNil(r.url?.query);XCTAssertFalse(r.httpShouldHandleCookies)
        let body=String(decoding:try XCTUnwrap(r.httpBody),as:UTF8.self);XCTAssertTrue(body.contains("name=\"nickname\""));XCTAssertFalse(body.contains("member_id"));XCTAssertFalse(body.contains("requestId"))
    }
    func testTakenAndInvalidMachineCodesAreNotSuccess() async throws {
        let f=try NickC6Fixture();f.wire.body=NickC6Fixture.check(available:false,error:"NICKNAME_TAKEN");let a=try await f.reader.check("城市玩家");XCTAssertEqual(a,.taken)
        f.wire.body=NickC6Fixture.check(available:false,error:"NICKNAME_INVALID");let b=try await f.reader.check("城市玩家");XCTAssertEqual(b,.invalid)
    }
    func testWrongEchoDuplicateKeysAndContradictoryPayloadFailClosed() async throws {
        for body in [NickC6Fixture.check("别人的昵称"),NickC6Fixture.check(available:true,error:"NICKNAME_TAKEN"),#"{"code":200,"code":200,"data":null}"#,"{}",String(repeating:" ",count:65_537)] {
            let f=try NickC6Fixture();f.wire.body=body;do {_=try await f.reader.check("城市玩家");XCTFail()}catch{}
        }
    }
    func testSuggestPreservesProducerSuffixAndCursorWithoutReserving() async throws {
        let f=try NickC6Fixture();f.wire.body=NickC6Fixture.suggestion();let value=try await f.reader.suggest("城市玩家#0001",cursor:1)
        XCTAssertEqual(value.nickname,"城市玩家#0002");XCTAssertEqual(value.cursor,2);XCTAssertEqual(f.wire.requests.first?.url?.path,"/native/api/user/nickname/suggest")
    }
    func testSuggestionMustMatchBaseCursorAndBoundedOriginalSearch() async throws {
        for pair in [("另一昵称#0002",2),("城市玩家#0001",1),("城市玩家#00ZZ",129),("城市玩家#0002",3)] {
            let f=try NickC6Fixture();f.wire.body=NickC6Fixture.suggestion(pair.0,cursor:pair.1)
            do {_=try await f.reader.suggest("城市玩家",cursor:1);XCTFail()}catch{}
        }
    }
    func testOriginalSuffixWrapSkipsZeroAndAcceptsWithin128() async throws {
        let f=try NickC6Fixture();f.wire.body=NickC6Fixture.suggestion("城市玩家#0001",cursor:1)
        let v=try await f.reader.suggest("城市玩家",cursor:1_679_615);XCTAssertEqual(v.cursor,1)
    }
    func testExhaustedAndInvalidSuggestionAreOnlyRecognizedWithErrorEnvelope() async throws {
        for code in ["NICKNAME_INVALID","NICKNAME_SUFFIX_EXHAUSTED"] {
            let f=try NickC6Fixture();f.wire.body="{\"code\":400,\"errorCode\":\"\(code)\"}"
            do {_=try await f.reader.suggest("城市玩家",cursor:nil);XCTFail()}catch { XCTAssertEqual(error as? ProfileNicknameSuggestionFailure,code == "NICKNAME_INVALID" ? .invalid:.exhausted) }
        }
    }
    func testNilSourceAndWrongViewerPreventRequests() async throws {
        for withdraw in [true,false] {
            let f=try NickC6Fixture();if withdraw {f.selected=nil}else{f.session=try .init(accountID:7,epoch:1,token:"synthetic-nick",viewerRevision:4)}
            do {_=try await f.reader.check("城市玩家");XCTFail()}catch{};XCTAssertTrue(f.wire.requests.isEmpty)
        }
    }
    func testObservedContextMismatchPermanentlyRetiresReader() throws {
        let f=try NickC6Fixture();XCTAssertTrue(f.reader.isConfigured);f.current=nil;XCTAssertFalse(f.reader.isConfigured);f.current=f.context;XCTAssertFalse(f.reader.isConfigured)
    }
    func testLastForwardAndLateReturnRevocationNeverBecomeFacts() async throws {
        for before in [true,false] {
            let f=try NickC6Fixture();if before {f.wire.before={f.selected=nil}}else{f.wire.after={f.selected=nil}}
            do {_=try await f.reader.check("城市玩家");XCTFail()}catch{};XCTAssertEqual(f.wire.requests.count,before ? 0:1)
        }
    }
    func testUnforwardedResponseAndCancelledTaskCannotProduceAvailability() async throws {
        let f=try NickC6Fixture();f.wire.skip=true;do {_=try await f.reader.check("城市玩家");XCTFail()}catch{}
        f.wire.skip=false
        let task=Task{@MainActor in withUnsafeCurrentTask{$0?.cancel()};do{_=try await f.reader.check("城市玩家");XCTFail()}catch{}}
        await task.value;XCTAssertTrue(f.wire.requests.isEmpty)
    }
    func testCurrentDenialRetiresReadOnlyWhileStaleDenialCannotRevokeNewLease() async throws {
        let f=try NickC6Fixture();f.wire.status=403;do{_=try await f.reader.check("城市玩家");XCTFail()}catch{}
        XCTAssertTrue(f.approval.revoked);XCTAssertNotNil(f.session)
        let g=try NickC6Fixture(),new=try ProfileNicknameReadApproval(context:g.context,viewerRevision:3,expiresAt:Date().addingTimeInterval(600))
        g.wire.after={g.selected=new};g.wire.status=401;do{_=try await g.reader.check("城市玩家");XCTFail()}catch{}
        XCTAssertFalse(g.approval.revoked);XCTAssertFalse(new.revoked)
    }
    func testFlowTakenLoadsAtMostThreeServerCandidatesAndOnlyTapSelects() async throws {
        let r=NickC6FlowReader(),f=ProfileNicknameAvailabilityFlow(reader:r);f.activate();f.setInput("城市玩家");await f.check(debounce:false)
        XCTAssertEqual(r.suggestions,3);XCTAssertEqual(f.candidates.count,3);let action=try XCTUnwrap(f.actionID)
        XCTAssertNil(f.select("注入候选",action:action));XCTAssertEqual(f.select("城市玩家#0001",action:action),"城市玩家#0001");XCTAssertNil(f.select("城市玩家#0001",action:action))
    }
    func testStaleInputActionCannotRetryOrPickNewBatch() async throws {
        let r=NickC6FlowReader(),f=ProfileNicknameAvailabilityFlow(reader:r);f.activate();f.setInput("城市玩家");await f.check(debounce:false);let old=try XCTUnwrap(f.actionID)
        f.setInput("另一个名字");await f.retryCheck(action:old);XCTAssertEqual(r.checks,1);XCTAssertTrue(f.candidates.isEmpty);XCTAssertNil(f.select("城市玩家#0001",action:old));XCTAssertFalse(f.matchesInput("城市玩家"))
    }
    func testRevocationHidesEveryPriorStateAndCandidateImmediately() async {
        let r=NickC6FlowReader(),f=ProfileNicknameAvailabilityFlow(reader:r);f.activate();f.setInput("城市玩家");await f.check(debounce:false);r.isConfigured=false
        XCTAssertEqual(f.state,.unchecked);XCTAssertTrue(f.candidates.isEmpty);XCTAssertNil(f.actionID);XCTAssertNil(f.suggestionsMessage)
    }
    func testLeaveAndSourceReplacementRejectLateCheck() async {
        let r=NickC6FlowReader(),f=ProfileNicknameAvailabilityFlow(reader:r);f.activate();f.setInput("城市玩家");r.after={f.leave()};await f.check(debounce:false)
        XCTAssertEqual(f.state,.unchecked);XCTAssertEqual(r.suggestions,0)
        r.after={r.sourceRevision=UUID()};f.activate();f.setInput("城市玩家");await f.check(debounce:false);XCTAssertEqual(f.state,.unchecked)
    }
    func testUnchangedOriginalAndNilReaderDoNotStartRead() async {
        let r=NickC6FlowReader(),f=ProfileNicknameAvailabilityFlow(reader:r);f.activate();f.setInput("城市玩家",original:"城市玩家");await f.check(debounce:false);XCTAssertEqual(r.checks,0)
        let closed=ProfileNicknameAvailabilityFlow(reader:nil);closed.activate();closed.setInput("城市玩家");await closed.check(debounce:false);XCTAssertEqual(closed.state,.unchecked)
    }
    func testDelayedOldReplyCannotBecomeCurrentAfterRetirement() async throws {
        let f=try NickC6Fixture();f.wire.suspend=true
        let task=Task{@MainActor in do{_=try await f.reader.check("城市玩家");XCTFail()}catch{}}
        for _ in 0..<2000 {if f.wire.waiter != nil {break};await Task.yield()}
        guard let waiter=f.wire.waiter else{task.cancel();XCTFail();return}
        f.reader.retire();waiter.resume(returning:(Data(NickC6Fixture.check().utf8),200));await task.value;XCTAssertFalse(f.reader.isConfigured)
    }
    func testFinalForwardRejectsMutatedWriterQueryBodyCookiesOrHeader() async throws {
        let mutations:[(inout URLRequest)->Void]=[
            {$0.url=URL(string:"https://nick.example.test/native/api/user/update")},
            {$0.url=URL(string:"https://nick.example.test/native/api/user/nickname/check?member_id=7")},
            {$0.httpBody=Data("extra".utf8)},{$0.httpMethod="GET"},{$0.httpShouldHandleCookies=true},{$0.setValue("x",forHTTPHeaderField:"X-Extra")}
        ]
        for mutation in mutations {
            let f=try NickC6Fixture();f.wire.mutate=mutation
            do{_=try await f.reader.check("城市玩家");XCTFail()}catch{};XCTAssertTrue(f.wire.requests.isEmpty)
        }
    }
    func testReadAuthorizationIsSingleUseAndExpiredLeaseCannotBeCreated() async throws {
        let f=try NickC6Fixture();f.wire.duplicate=true
        do{_=try await f.reader.check("城市玩家");XCTFail()}catch{};XCTAssertEqual(f.wire.requests.count,1)
        XCTAssertThrowsError(try ProfileNicknameReadApproval(context:f.context,viewerRevision:3,expiresAt:Date().addingTimeInterval(-1)))
    }

}
