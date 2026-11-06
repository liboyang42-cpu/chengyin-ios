import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor private final class ReviewC6Wire: ProfileCurrentReviewDispatching {
    var requests: [URLRequest] = []
    var bytes = ReviewC6Fixture.response(), status = 200
    var before: (() -> Void)?, after: (() -> Void)?
    var failure: Error?
    var skipForward = false, suspendNext = false
    var waiter: CheckedContinuation<(Data, Int), Error>?
    func send(_ request: URLRequest, authorization: ProfileCurrentReviewAuthorization) async throws -> (Data, Int) {
        before?()
        if !skipForward { try authorization.forward(request) { requests.append(request) } }
        after?(); if let failure { throw failure }
        if suspendNext { suspendNext = false; return try await withCheckedThrowingContinuation { waiter = $0 } }
        return (bytes, status)
    }
}
@MainActor private final class ReviewC6Fixture {
    var context: RuntimeDependencyContext?
    var session: ProfileEditSession?
    var approval: ProfileCurrentReviewReadApproval?
    let wire = ReviewC6Wire(), editor = UUID(), lifetime = UUID()
    let base = URL(string: "https://review.example.test/native")!
    lazy var reader = ProfileCurrentReviewReader(baseURL: base, namespace: "synthetic-review",
        currentSession: { [unowned self] in session }, currentApproval: { [unowned self] in approval },
        currentContext: { [unowned self] in context }, transport: wire)
    init() throws {
        context = try Self.context()
        session = try .init(accountID: 41, epoch: 7, token: "synthetic-review-token", viewerRevision: 3)
        approval = try .init(context: XCTUnwrap(context), viewerRevision: 3, expiresAt: Date().addingTimeInterval(600))
    }
    static func context(account: Int = 41, epoch: UInt64 = 7, token: String = "synthetic-review-token", role: String = "player", namespace: String = "synthetic-review", host: String = "https://review.example.test/native") throws -> RuntimeDependencyContext {
        .init(market: .china, baseURL: URL(string: host)!, role: role,
            session: try .init(accountID: account, epoch: epoch, namespace: namespace, token: token, role: role))
    }
    static func response(_ state: String = "REJECTED", live: Bool = false) -> Data {
        Data("{\"code\":200,\"data\":{\"available\":true,\"currentVersion\":8,\"avatar\":{\"versionNo\":7,\"state\":\"\(state)\",\"live\":\(live)}}}".utf8)
    }
    func snapshot(owner: Int = 41, avatar: String = "https://image.example.test/saved.jpg") throws -> ProfileEditSnapshot {
        try JSONDecoder().decode(ProfileEditSnapshot.self, from: JSONSerialization.data(withJSONObject:
            ["id":owner,"nickname":"Synthetic","introduction":"Saved","avatar":avatar,"wechat":"","casePics":"","tagIds":""]))
    }
    func key(_ snapshot: ProfileEditSnapshot, draft: UInt64 = 0, read: Int = 1) -> ProfileCurrentReviewReadKey? {
        reader.key(snapshot: snapshot, editorID: editor, lifetimeID: lifetime, draftRevision: draft, readRevision: read)
    }
}
@MainActor final class ProfileReviewC6ReadTests: XCTestCase {
    func testOnlyOriginalRejectedFactIsExposedForBothLiveValues() throws {
        for state in ["REJECTED","PENDING","APPROVED","NOT_SUBMITTED"] {
            for live in [true,false] {
                let value = try ProfileCurrentReviewReceipt.decode(ReviewC6Fixture.response(state, live: live), status: 200)
                XCTAssertEqual(value.currentVersion, 8); XCTAssertEqual(value.rejectedFact != nil, state == "REJECTED")
                if state == "REJECTED" { XCTAssertEqual(value.rejectedFact?.versionNo,7); XCTAssertEqual(value.rejectedFact?.liveWhenRead,live) }
            }
        }
    }
    func testUnavailableAndNoRecordedAvatarNeverMeanApproved() throws {
        for text in [#"{"code":200,"data":{"available":false}}"#, #"{"code":200,"data":{"available":true,"currentVersion":null,"avatar":null}}"#] {
            XCTAssertNil(try ProfileCurrentReviewReceipt.decode(Data(text.utf8), status: 200).rejectedFact)
        }
    }
    func testUnknownStatesMalformedTypesAndBadVersionOrderFailClosed() {
        let base = String(decoding: ReviewC6Fixture.response(), as: UTF8.self)
        for text in [base.replacingOccurrences(of:"REJECTED",with:"NOT_REQUIRED"),base.replacingOccurrences(of:"REJECTED",with:"rejected"),
            base.replacingOccurrences(of:"\"live\":false",with:"\"live\":0"),base.replacingOccurrences(of:"\"versionNo\":7",with:"\"versionNo\":9"),
            base.replacingOccurrences(of:"\"versionNo\":7",with:"\"versionNo\":0"),base.replacingOccurrences(of:"\"available\":true",with:"\"available\":1"),
            #"{"code":200,"data":{"available":true}}"#] {
            XCTAssertThrowsError(try ProfileCurrentReviewReceipt.decode(Data(text.utf8),status:200))
        }
    }
    func testDuplicateKeysOversizedAndBusinessFailuresAreNotFacts() {
        for bytes in [Data(#"{"code":200,"code":403,"data":{"available":false}}"#.utf8), Data(repeating:32,count:65_537), Data(#"{"code":500,"msg":"请先登录"}"#.utf8)] {
            XCTAssertThrowsError(try ProfileCurrentReviewReceipt.decode(bytes,status:200))
        }
        XCTAssertThrowsError(try ProfileCurrentReviewReceipt.decode(ReviewC6Fixture.response(),status:500))
    }
    func testExactPrincipalOnlyGETHasNoImageOrMemberParameters() async throws {
        let f = try ReviewC6Fixture(), snapshot = try f.snapshot(), key = try XCTUnwrap(f.key(snapshot))
        _ = try await f.reader.read(snapshot:snapshot,key:key,isCurrent:{true})
        let r = try XCTUnwrap(f.wire.requests.first)
        XCTAssertEqual(r.url?.absoluteString,"https://review.example.test/native/api/user/profile/review"); XCTAssertEqual(r.httpMethod,"GET")
        XCTAssertNil(r.url?.query); XCTAssertNil(r.httpBody); XCTAssertNil(r.httpBodyStream); XCTAssertFalse(r.httpShouldHandleCookies)
        XCTAssertEqual(Set((r.allHTTPHeaderFields ?? [:]).keys.map { $0.lowercased() }),["authorization","accept"])
        XCTAssertEqual(f.wire.requests.count,1)
    }
    func testNoGrantWrongOwnerAndRetirementNeverDispatch() async throws {
        let f = try ReviewC6Fixture(), s = try f.snapshot(), key = try XCTUnwrap(f.key(s))
        XCTAssertNil(f.key(try f.snapshot(owner:42))); f.approval = nil; XCTAssertNil(f.key(s))
        do { _ = try await f.reader.read(snapshot:s,key:key,isCurrent:{true}); XCTFail() } catch { }
        f.approval = try .init(context:XCTUnwrap(f.context),viewerRevision:3,expiresAt:Date().addingTimeInterval(600))
        f.reader.retire(); XCTAssertNil(f.key(s)); XCTAssertTrue(f.wire.requests.isEmpty)
    }
    func testExpiredAndInvalidMarketOrRoleCannotCreateReadGrant() throws {
        let context = try ReviewC6Fixture.context()
        XCTAssertThrowsError(try ProfileCurrentReviewReadApproval(context:context,viewerRevision:3,expiresAt:Date().addingTimeInterval(-1)))
        XCTAssertThrowsError(try ProfileCurrentReviewReadApproval(context:context,viewerRevision:3,expiresAt:Date(timeIntervalSince1970:Double.infinity)))
        let wrongRole = RuntimeDependencyContext(market:.china,baseURL:context.baseURL,role:"merchant",session:context.session)
        XCTAssertThrowsError(try ProfileCurrentReviewReadApproval(context:wrongRole,viewerRevision:3,expiresAt:Date().addingTimeInterval(600)))
    }
    func testFullIdentityChangesInvalidateEvenIfAccountNumberStaysSame() throws {
        let variants = [try ReviewC6Fixture.context(account:42), try ReviewC6Fixture.context(epoch:8), try ReviewC6Fixture.context(token:"new-synthetic-token"),
            try ReviewC6Fixture.context(role:"merchant"),try ReviewC6Fixture.context(namespace:"another-realm"),try ReviewC6Fixture.context(host:"https://other.example.test/native")]
        for context in variants {
            let f = try ReviewC6Fixture(), s = try f.snapshot(); XCTAssertNotNil(f.key(s)); f.context=context; XCTAssertNil(f.key(s))
        }
        let f = try ReviewC6Fixture(), s = try f.snapshot()
        f.session = try .init(accountID:41,epoch:7,token:"synthetic-review-token",viewerRevision:4); XCTAssertNil(f.key(s))
    }
    func testExactRoleBytesCannotUseCanonicalUnicodeEquality() throws {
        let f = try ReviewC6Fixture(), s = try f.snapshot()
        f.context = try ReviewC6Fixture.context(role:"café")
        f.approval = try .init(context:XCTUnwrap(f.context),viewerRevision:3,expiresAt:Date().addingTimeInterval(600))
        XCTAssertNotNil(f.key(s))
        f.context = try ReviewC6Fixture.context(role:"cafe\u{301}")
        XCTAssertNil(f.key(s))
        XCTAssertThrowsError(try ReviewC6Fixture.context(token:"non-ascii-é"))
    }
    func testRequestFenceRejectsWriterQueryOtherHostAndExtraHeaders() throws {
        let f = try ReviewC6Fixture()
        var r=URLRequest(url:f.base.appendingPathComponent(ProfileCurrentReviewReader.path));r.httpMethod="GET";r.httpShouldHandleCookies=false
        r.setValue("synthetic-review-token",forHTTPHeaderField:"Authorization");r.setValue("application/json",forHTTPHeaderField:"Accept")
        let a=ProfileCurrentReviewAuthorization(baseURL:f.base,token:"synthetic-review-token",current:{true});XCTAssertTrue(a.accepts(r))
        let changes: [(inout URLRequest)->Void] = [{ $0.httpMethod="POST" },{ $0.httpBody=Data() },{ $0.httpShouldHandleCookies=true },
            { $0.setValue("x",forHTTPHeaderField:"Cookie") },{ $0.setValue("x",forHTTPHeaderField:"X-Extra") },
            { $0.url=URL(string:"https://review.example.test/native/api/user/profile/review?memberId=41") },
            { $0.url=URL(string:"https://review.example.test/native/api/user/update") },{ $0.url=URL(string:"https://other.example.test/native/api/user/profile/review") }]
        for change in changes { var changed=r; change(&changed);XCTAssertFalse(a.accepts(changed)) }
        var forwards=0;try a.forward(r){forwards+=1};XCTAssertThrowsError(try a.forward(r){forwards+=1});XCTAssertEqual(forwards,1)
    }
    func testRevocationAtLastForwardOrReturnRejectsOldResult() async throws {
        for before in [true,false] {
            let f=try ReviewC6Fixture(),s=try f.snapshot(),k=try XCTUnwrap(f.key(s))
            if before { f.wire.before={f.approval?.revoke()} } else { f.wire.after={f.approval?.revoke()} }
            do { _=try await f.reader.read(snapshot:s,key:k,isCurrent:{true});XCTFail() } catch { }
            XCTAssertEqual(f.wire.requests.count,before ? 0:1)
        }
    }
    func testUnforwardedAdapterResponseIsNotAccepted() async throws {
        let f=try ReviewC6Fixture(),s=try f.snapshot(),k=try XCTUnwrap(f.key(s));f.wire.skipForward=true
        do {_=try await f.reader.read(snapshot:s,key:k,isCurrent:{true});XCTFail()}catch{}
        XCTAssertTrue(f.wire.requests.isEmpty)
    }
    func testCurrentUnauthorizedRetiresOnlyDedicatedLease() async throws {
        for status in [401,403] {
            let f=try ReviewC6Fixture(),s=try f.snapshot(),k=try XCTUnwrap(f.key(s)),approval=try XCTUnwrap(f.approval)
            f.wire.status=status
            do {_=try await f.reader.read(snapshot:s,key:k,isCurrent:{true});XCTFail()}catch{}
            XCTAssertTrue(approval.revoked);XCTAssertNotNil(f.session);XCTAssertNil(f.key(s))
        }
    }
    func testLateUnauthorizedCannotRevokeNewLease() async throws {
        let f=try ReviewC6Fixture(),s=try f.snapshot(),k=try XCTUnwrap(f.key(s)),old=try XCTUnwrap(f.approval)
        let replacement=try ProfileCurrentReviewReadApproval(context:XCTUnwrap(f.context),viewerRevision:3,expiresAt:Date().addingTimeInterval(600))
        f.wire.status=401;f.wire.after={f.approval=replacement}
        do {_=try await f.reader.read(snapshot:s,key:k,isCurrent:{true});XCTFail()}catch{}
        XCTAssertFalse(old.revoked);XCTAssertFalse(replacement.revoked)
    }
    func testSourceDraftReadEditorLifetimeAreOnlyLocalFences() throws {
        let f=try ReviewC6Fixture(),s=try f.snapshot(),k=try XCTUnwrap(f.key(s))
        XCTAssertNotEqual(f.key(s,draft:1),k);XCTAssertNotEqual(f.key(s,read:2),k);XCTAssertNotEqual(f.key(try f.snapshot(avatar:"different")),k)
        XCTAssertNotEqual(f.reader.key(snapshot:s,editorID:UUID(),lifetimeID:f.lifetime,draftRevision:0,readRevision:1),k)
        XCTAssertNotEqual(f.reader.key(snapshot:s,editorID:f.editor,lifetimeID:UUID(),draftRevision:0,readRevision:1),k)
    }
    func testObservedSessionABANeverRevivesOldKey() throws {
        let f=try ReviewC6Fixture(),s=try f.snapshot(),k=try XCTUnwrap(f.key(s)),old=f.session
        f.session=nil;XCTAssertNil(f.key(s));f.session=old;XCTAssertNotEqual(f.key(s),k)
    }
    func testFlowFailureClearsOldRejectedWithoutInventingVerdict() async throws {
        let f=try ReviewC6Fixture(),s=try f.snapshot(),k=try XCTUnwrap(f.key(s)),flow=ProfileCurrentReviewFlow()
        await flow.load(reader:f.reader,snapshot:s,key:k,currentKey:{f.key(s)});XCTAssertNotNil(flow.rejectedFact(for:k))
        f.wire.failure=ProfileCurrentReviewFailure.unavailable
        await flow.load(reader:f.reader,snapshot:s,key:k,currentKey:{f.key(s)});XCTAssertNil(flow.rejectedFact(for:k));XCTAssertEqual(flow.state,.unavailable)
    }
    func testFlowInvalidationDuringReadRejectsLateCompletion() async throws {
        let f=try ReviewC6Fixture(),s=try f.snapshot(),k=try XCTUnwrap(f.key(s)),flow=ProfileCurrentReviewFlow()
        f.wire.after={flow.invalidate()};await flow.load(reader:f.reader,snapshot:s,key:k,currentKey:{f.key(s)})
        XCTAssertEqual(flow.state,.idle);XCTAssertNil(flow.rejectedFact(for:k))
    }
    func testCancelledBeforeDispatchNeverForwards() async throws {
        let f=try ReviewC6Fixture(),s=try f.snapshot(),k=try XCTUnwrap(f.key(s))
        let task=Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            do {_=try await f.reader.read(snapshot:s,key:k,isCurrent:{true});XCTFail()}catch{}
        }
        await task.value;XCTAssertTrue(f.wire.requests.isEmpty)
    }
    func testCancelledAfterForwardNeverPublishesResult() async throws {
        let f=try ReviewC6Fixture(),s=try f.snapshot(),k=try XCTUnwrap(f.key(s)),flow=ProfileCurrentReviewFlow()
        f.wire.after={withUnsafeCurrentTask { $0?.cancel() }}
        let task=Task { @MainActor in await flow.load(reader:f.reader,snapshot:s,key:k,currentKey:{f.key(s)}) }
        await task.value;XCTAssertNil(flow.rejectedFact(for:k));XCTAssertEqual(f.wire.requests.count,1)
    }
    func testDelayedOlderResponseCannotReplaceNewerUnavailableResult() async throws {
        let f=try ReviewC6Fixture(),s=try f.snapshot(),old=try XCTUnwrap(f.key(s)),flow=ProfileCurrentReviewFlow()
        var current=old;f.wire.suspendNext=true
        let task=Task { @MainActor in await flow.load(reader:f.reader,snapshot:s,key:old,currentKey:{current}) }
        for _ in 0..<2000 { if f.wire.waiter != nil { break };await Task.yield() }
        guard let waiter=f.wire.waiter else { task.cancel();XCTFail("Synthetic continuation did not start");return }
        current=try XCTUnwrap(f.key(s,read:2));f.wire.bytes=Data(#"{"code":200,"data":{"available":false}}"#.utf8)
        await flow.load(reader:f.reader,snapshot:s,key:current,currentKey:{current})
        waiter.resume(returning:(ReviewC6Fixture.response(),200));await task.value
        XCTAssertEqual(flow.state,.unavailable);XCTAssertNil(flow.rejectedFact(for:current));XCTAssertNil(flow.rejectedFact(for:old))
    }
    func testDelayedDenialAfterRetirementCannotRevokeReplacement() async throws {
        let f=try ReviewC6Fixture(),s=try f.snapshot(),key=try XCTUnwrap(f.key(s)),old=try XCTUnwrap(f.approval)
        f.wire.suspendNext=true
        let task=Task { @MainActor in
            do {_=try await f.reader.read(snapshot:s,key:key,isCurrent:{true});XCTFail()}catch{}
        }
        for _ in 0..<2000 { if f.wire.waiter != nil { break };await Task.yield() }
        guard let waiter=f.wire.waiter else { task.cancel();XCTFail("Synthetic continuation did not start");return }
        let new=try ProfileCurrentReviewReadApproval(context:XCTUnwrap(f.context),viewerRevision:3,expiresAt:Date().addingTimeInterval(600))
        f.reader.retire();f.approval=new;waiter.resume(returning:(Data(),401));await task.value
        XCTAssertFalse(old.revoked);XCTAssertFalse(new.revoked)
    }

    func testObservedRoleABANeverRevivesOldLocalKey() throws {
        let f=try ReviewC6Fixture(),s=try f.snapshot(),key=try XCTUnwrap(f.key(s)),original=f.context
        f.context=try ReviewC6Fixture.context(role:"merchant");XCTAssertNil(f.key(s))
        f.context=original;XCTAssertNotEqual(f.key(s),key)
    }

}
