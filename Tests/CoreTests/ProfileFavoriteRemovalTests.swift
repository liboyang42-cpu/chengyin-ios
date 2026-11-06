import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class ProfileFavoriteRemovalTests: XCTestCase {
    private final class Context { var session: ProfileFavoriteRemovalSession?; var now=Date(timeIntervalSince1970:100); var unauthorizedCount = 0; init(_ session: ProfileFavoriteRemovalSession) { self.session=session } }
    private final class Wire: HTTPTransport {
        var marked=true, unknown=false, malformed=false, missingState=false, failRead=false
        var requests:[URLRequest]=[]
        var pending:CheckedContinuation<(Data,Int),Error>?
        var suspendRead=false, suspendWrite=false, unauthorizedRead=false, unauthorizedWrite=false
        var writes:Int { requests.filter { $0.url?.lastPathComponent == "bookmark" }.count }
        func send(_ request: URLRequest) async throws -> (Data,Int) {
            requests.append(request)
            if request.url?.lastPathComponent == "bookmark" {
                if unknown { throw URLError(.timedOut) }
                if unauthorizedWrite { return (Data(#"{"code":401}"#.utf8), 401) }
                marked=false
                if suspendWrite { return try await withCheckedThrowingContinuation { pending=$0 } }
                 return (Data((malformed ? "html" : #"{"code":200}"#).utf8),200)
            }
            if suspendRead { return try await withCheckedThrowingContinuation { pending=$0 } }
            if unauthorizedRead { return (Data(#"{"code":401}"#.utf8), 200) }
            if failRead { throw URLError(.notConnectedToInternet) }
            let field=missingState ? "" : ",\"isBookmarked\":\(marked ? 1 : 0)"
            return (Data("{\"code\":200,\"data\":{\"id\":101\(field)}}".utf8),200)
        }
    }
    private final class Journal: OperationPendingJournal {
        var value:OperationPendingRecord?; var fails=false; var clearFailsAfterRemoval=false; var readFails=false; var unreadableAfterClear=false
        func pending(ownerKey:String,targetKey:String)throws->OperationPendingRecord? {
            if readFails { throw APIError.malformedResponse }
            guard let value else { return nil }; return value.ownerKey == ownerKey && value.targetKey == targetKey ? value : nil
        }
        func write(_ record:OperationPendingRecord)throws { if fails || value != nil { throw APIError.invalidRequest };value=record }
        func clear(_ record:OperationPendingRecord)throws { guard value==record else { throw APIError.invalidRequest };value=nil; if unreadableAfterClear { readFails = true }; if clearFailsAfterRemoval { throw APIError.malformedResponse } }
    }
    private struct Fixture {
        let scope:UUID;let context:Context;let wire:Wire;let journal:Journal;let controller:ProfileFavoriteRemovalController;let post:SquarePost
    }
    private func fixture(approved:Bool=true, journal:Journal?=nil, epoch:UInt64=1, pendingState: ProfileFavoriteRemovalPendingState? = nil) throws -> Fixture {
        let scope=UUID(), session=try ProfileFavoriteRemovalSession(identity:.init(accountID:7,epoch:epoch,role:"player"),namespace:"synthetic",collectionScope:scope,market:.china,token:"synthetic-token")
        let context=Context(session), wire=Wire(), journal=journal ?? Journal()
        let config=try APIConfiguration(baseURL:URL(string:"https://profile.example/native")!)
        let endpoint=try OperationEndpointApproval(baseURL:config.baseURL,namespace:"synthetic",accountID:7,paths:ProfileFavoriteRemovalApproval.paths)
        let grant=try ProfileFavoriteRemovalApproval(endpoint:endpoint,identity:session.identity,postID:101,expiresAt:Date(timeIntervalSince1970:200))
        let controller=ProfileFavoriteRemovalController(configuration:config,approvals:approved ? [grant] : [],transport:wire,journal:journal,current:{ context.session },onUnauthorized:{ context.unauthorizedCount += 1 },pendingState:pendingState,now:{ context.now })
        let post=try JSONDecoder().decode(SquarePost.self,from:Data(#"{"id":101,"memberId":91,"contents":"Synthetic saved post"}"#.utf8)).qualified(as:.legacySquare)
        return .init(scope:scope,context:context,wire:wire,journal:journal,controller:controller,post:post)
    }
    private func prepare(_ f:Fixture) async throws -> UUID {
        let id=try XCTUnwrap(f.controller.begin(post:f.post,collectionScope:f.scope));await f.controller.prepare(id);return id
    }
    private func confirm(_ f:Fixture) async throws { let r=try XCTUnwrap(f.controller.review);await f.controller.confirm(r) }
    private func wait(_ wire:Wire) async { for _ in 0..<100 where wire.pending == nil { await Task.yield() };XCTAssertNotNil(wire.pending) }
    func testNoApprovalMeansNoEntryOrReadOrWrite() throws {
        let f=try fixture(approved:false);XCTAssertFalse(f.controller.isAvailable(post:f.post,collectionScope:f.scope));XCTAssertNil(f.controller.begin(post:f.post,collectionScope:f.scope));XCTAssertTrue(f.wire.requests.isEmpty)
    }
    func testReviewAndCancelNeverSubmit() async throws {
        let f=try fixture();let id=try await prepare(f);XCTAssertEqual(f.controller.phase,.reviewed);f.controller.retire(id)
        XCTAssertEqual(f.wire.writes,0);XCTAssertNil(f.journal.value)
    }
    func testExactRemovalBodyAndVerifiedReadback() async throws {
        let f=try fixture();_ = try await prepare(f);try await confirm(f)
        XCTAssertEqual(f.controller.phase,.removed);XCTAssertEqual(f.wire.writes,1);XCTAssertEqual(f.wire.requests.count,4);XCTAssertNil(f.journal.value)
        let req=try XCTUnwrap(f.wire.requests.first { $0.url?.lastPathComponent == "bookmark" })
        let body=String(data:req.httpBody ?? Data(),encoding:.utf8) ?? ""
        XCTAssertTrue(body.contains("name=\"bookmark\"\r\n\r\n0\r\n"));XCTAssertTrue(body.contains("name=\"id\"\r\n\r\n101\r\n"));XCTAssertTrue(body.contains("name=\"request_id\""));XCTAssertFalse(body.contains("member_id"))
        XCTAssertEqual(req.value(forHTTPHeaderField:"Authorization"),"synthetic-token")
    }
    func testAlreadyUnbookmarkedIsReadOnlySuccess() async throws {
        let f=try fixture();f.wire.marked=false;_ = try await prepare(f)
        XCTAssertEqual(f.controller.phase,.removed);XCTAssertEqual(f.wire.writes,0)
    }
    func testFreshPrewriteStateAvoidsUnnecessaryWrite() async throws {
        let f=try fixture();_ = try await prepare(f);f.wire.marked=false;try await confirm(f)
        XCTAssertEqual(f.controller.phase,.removed);XCTAssertEqual(f.wire.writes,0)
    }
    func testDuplicateConfirmCannotSubmitAgain() async throws {
        let f=try fixture();_ = try await prepare(f);let review=try XCTUnwrap(f.controller.review)
        await f.controller.confirm(review);await f.controller.confirm(review);XCTAssertEqual(f.wire.writes,1)
    }
    func testUnknownWriteKeepsDurableLockAndReadOnlyReconcileDoesNotReplay() async throws {
        let f=try fixture();let id=try await prepare(f);f.wire.unknown=true;try await confirm(f)
        XCTAssertEqual(f.controller.phase,.unknown);XCTAssertNotNil(f.journal.value)
        await f.controller.reconcile(id);XCTAssertEqual(f.controller.phase,.unknown);XCTAssertEqual(f.wire.writes,1)
        f.wire.marked=false;await f.controller.reconcile(id)
        XCTAssertEqual(f.controller.phase,.removed);XCTAssertNil(f.journal.value);XCTAssertEqual(f.wire.writes,1)
    }
    func testUnknownLockSurvivesNewControllerAndLoginEpoch() async throws {
        let first=try fixture();_ = try await prepare(first);first.wire.unknown=true;try await confirm(first)
        let second=try fixture(journal:first.journal,epoch:2);_ = try await prepare(second)
        XCTAssertEqual(second.controller.phase,.unknown);XCTAssertTrue(second.wire.requests.isEmpty)
    }
    func testMalformedWriteAcknowledgementNeverClearsLock() async throws {
        let f=try fixture();_ = try await prepare(f);f.wire.malformed=true;try await confirm(f)
        XCTAssertEqual(f.controller.phase,.unknown);XCTAssertNotNil(f.journal.value);XCTAssertEqual(f.wire.writes,1)
    }
    func testMissingStateIsNotUnbookmarked() async throws {
        let f=try fixture();f.wire.missingState=true;_ = try await prepare(f)
        XCTAssertEqual(f.controller.phase,.failed);XCTAssertNil(f.controller.review);XCTAssertEqual(f.wire.writes,0)
    }
    func testFailedPreflightCanRetryReadWithoutWriting() async throws {
        let f=try fixture();f.wire.failRead=true;let id=try await prepare(f);XCTAssertEqual(f.controller.phase,.failed)
        f.wire.failRead=false;await f.controller.retryPreparation(id);XCTAssertEqual(f.controller.phase,.reviewed);XCTAssertEqual(f.wire.writes,0)
    }
    func testExpiredGrantBeforeConfirmNeverWrites() async throws {
        let f=try fixture();_ = try await prepare(f);f.context.now=Date(timeIntervalSince1970:201);try await confirm(f)
        XCTAssertEqual(f.wire.writes,0);XCTAssertNil(f.journal.value)
    }
    func testRetiredIdentityCannotConfirm() async throws {
        let f=try fixture();_ = try await prepare(f);f.context.session=nil;try await confirm(f)
        XCTAssertEqual(f.wire.writes,0)
    }
    func testWrongGenerationOrCollectionScopeCannotBegin() throws {
        let f=try fixture();XCTAssertNil(f.controller.begin(post:f.post.qualified(as:.communityV1),collectionScope:f.scope));XCTAssertNil(f.controller.begin(post:f.post,collectionScope:UUID()))
        XCTAssertTrue(f.wire.requests.isEmpty)
    }
    func testJournalFailureStopsBeforeDispatch() async throws {
        let f=try fixture();_ = try await prepare(f);f.journal.fails=true;try await confirm(f);XCTAssertEqual(f.wire.writes,0)
    }
    func testClosingDuringPreflightDropsLateReview() async throws {
        let f=try fixture();f.wire.suspendRead=true;let id=try XCTUnwrap(f.controller.begin(post:f.post,collectionScope:f.scope))
        let task=Task { await f.controller.prepare(id) };await wait(f.wire);f.controller.retire(id)
        f.wire.pending?.resume(returning:(Data(#"{"code":200,"data":{"id":101,"isBookmarked":1}}"#.utf8),200));f.wire.pending=nil;await task.value
        XCTAssertNil(f.controller.review);XCTAssertEqual(f.controller.phase,.idle);XCTAssertEqual(f.wire.writes,0)
    }
    func testOldPresentationDismissCannotRetireNewReview() async throws {
        let f=try fixture();let first=try await prepare(f);f.controller.retire(first);let second=try await prepare(f)
        f.controller.retire(first);XCTAssertEqual(f.controller.presentationID,second);XCTAssertEqual(f.controller.phase,.reviewed)
    }
    func testThrowingClearWithVerifiedAbsentRecordCompletesKnownRemoval() async throws {
        let f=try fixture();_ = try await prepare(f);f.journal.clearFailsAfterRemoval=true;try await confirm(f)
        XCTAssertEqual(f.controller.phase,.removed);XCTAssertNil(f.journal.value);XCTAssertEqual(f.wire.writes,1)
    }
    func testThrowingReconcileClearWithVerifiedAbsentRecordCompletesWithoutResend() async throws {
        let f=try fixture();let id=try await prepare(f);f.wire.unknown=true;try await confirm(f)
        f.wire.marked=false;f.journal.clearFailsAfterRemoval=true;await f.controller.reconcile(id)
        XCTAssertEqual(f.controller.phase,.removed);XCTAssertNil(f.journal.value);XCTAssertEqual(f.wire.writes,1)
    }
    func testUnreadableCleanupQuarantineSurvivesRetirementAndControllerReplacement() async throws {
        let state = ProfileFavoriteRemovalPendingState(), first = try fixture(pendingState: state)
        let id = try await prepare(first)
        first.journal.unreadableAfterClear = true; first.journal.clearFailsAfterRemoval = true
        try await confirm(first)
        XCTAssertEqual(first.controller.phase, .unknown); XCTAssertNil(first.journal.value)
        first.controller.retire(id)
        let next = try fixture(journal: first.journal, epoch: 2, pendingState: state)
        XCTAssertEqual(next.controller.recoveryAvailability(collectionScope: next.scope), .unreadable)
        _ = try await prepare(next)
        XCTAssertEqual(next.controller.phase, .failed); XCTAssertEqual(next.wire.writes, 0)
        next.journal.readFails = false; next.journal.unreadableAfterClear = false
        XCTAssertEqual(next.controller.recoveryAvailability(collectionScope: next.scope), .pending([101]))
        let recovery = try XCTUnwrap(next.controller.beginRecovery(postID: 101, collectionScope: next.scope))
        next.wire.marked = false; await next.controller.reconcile(recovery)
        XCTAssertEqual(next.controller.phase, .removed); XCTAssertEqual(next.wire.writes, 0)
        XCTAssertEqual(next.controller.recoveryAvailability(collectionScope: next.scope), .pending([]))
    }
    func testApprovalRejectsBroadOrUnrelatedPaths() throws {
        let config=try APIConfiguration(baseURL:URL(string:"https://profile.example/native")!)
        let endpoint=try OperationEndpointApproval(baseURL:config.baseURL,namespace:"synthetic",accountID:7,paths:["api/user/follow/action"])
        XCTAssertThrowsError(try ProfileFavoriteRemovalApproval(endpoint:endpoint,identity:.init(accountID:7,epoch:1),postID:101,expiresAt:Date()))
    }
    func testLateRetiredWriteCannotRestoreAlreadyReconciledRecord() async throws {
        let f = try fixture(), first = try await prepare(f)
        let review = try XCTUnwrap(f.controller.review)
        f.wire.suspendWrite = true
        let old = Task { await f.controller.confirm(review) }; await wait(f.wire)
        XCTAssertNotNil(f.journal.value)
        f.controller.retire(first)
        let recovery = try XCTUnwrap(f.controller.beginRecovery(postID: 101, collectionScope: f.scope))
        await f.controller.reconcile(recovery)
        XCTAssertEqual(f.controller.phase, .removed); XCTAssertNil(f.journal.value)
        f.wire.pending?.resume(returning: (Data(#"{"code":200}"#.utf8), 200)); f.wire.pending = nil
        await old.value
        XCTAssertEqual(f.controller.presentationID, recovery)
        XCTAssertEqual(f.controller.phase, .removed); XCTAssertNil(f.journal.value)
        XCTAssertEqual(f.wire.writes, 1)
    }
    func testLateRetiredReconciliationCannotRestoreAlreadyResolvedRecord() async throws {
        let f = try fixture(), first = try await prepare(f)
        f.wire.unknown = true; try await confirm(f); f.wire.suspendRead = true
        let old = Task { await f.controller.reconcile(first) }; await wait(f.wire)
        f.controller.retire(first); f.wire.suspendRead = false; f.wire.marked = false
        let next = try XCTUnwrap(f.controller.beginRecovery(postID: 101, collectionScope: f.scope))
        await f.controller.reconcile(next)
        XCTAssertNil(f.journal.value)
        f.wire.pending?.resume(returning: (Data(#"{"code":200,"data":{"id":101,"isBookmarked":0}}"#.utf8), 200))
        f.wire.pending = nil; await old.value
        XCTAssertNil(f.journal.value); XCTAssertEqual(f.controller.phase, .removed)
        XCTAssertEqual(f.controller.presentationID, next); XCTAssertEqual(f.wire.writes, 1)
    }
    func testMissingSavedRowCanOpenOnlyReadOnlyPendingRecovery() async throws {
        let f = try fixture(), first = try await prepare(f)
        f.wire.unknown = true; try await confirm(f); f.controller.retire(first)
        // No SquarePost or fetched collection row is supplied to recovery.
        XCTAssertEqual(f.controller.recoveryAvailability(collectionScope: f.scope), .pending([101]))
        let id = try XCTUnwrap(f.controller.beginRecovery(postID: 101, collectionScope: f.scope))
        XCTAssertEqual(f.controller.phase, .unknown); XCTAssertNil(f.controller.review)
        f.wire.marked = false; await f.controller.reconcile(id)
        XCTAssertEqual(f.controller.phase, .removed)
        XCTAssertEqual(f.controller.recoveryAvailability(collectionScope: f.scope), .pending([]))
        XCTAssertEqual(f.wire.writes, 1)
    }
    func testRecoveryCannotCreateACommandWithoutAnExistingExactPendingRecord() throws {
        let f = try fixture()
        XCTAssertEqual(f.controller.recoveryAvailability(collectionScope: f.scope), .pending([]))
        XCTAssertNil(f.controller.beginRecovery(postID: 101, collectionScope: f.scope))
        XCTAssertNil(f.controller.beginRecovery(postID: 102, collectionScope: f.scope))
        XCTAssertTrue(f.wire.requests.isEmpty)
    }
    func testRecoveryRejectsWrongTargetScopeExpiredOrRetiredAccount() async throws {
        let f = try fixture(), first = try await prepare(f)
        f.wire.unknown = true; try await confirm(f); f.controller.retire(first)
        XCTAssertNil(f.controller.beginRecovery(postID: 102, collectionScope: f.scope))
        XCTAssertNil(f.controller.beginRecovery(postID: 101, collectionScope: UUID()))
        f.context.now = Date(timeIntervalSince1970: 201)
        XCTAssertEqual(f.controller.recoveryAvailability(collectionScope: f.scope), .pending([]))
        XCTAssertNil(f.controller.beginRecovery(postID: 101, collectionScope: f.scope))
        f.context.session = nil
        XCTAssertEqual(f.controller.recoveryAvailability(collectionScope: f.scope), .unavailable)
        XCTAssertNotNil(f.journal.value); XCTAssertEqual(f.wire.writes, 1)
    }
    func testCorruptJournalShowsUnreadableAndBlocksRecoveryAndDispatch() async throws {
        let f = try fixture(); f.journal.readFails = true
        XCTAssertEqual(f.controller.recoveryAvailability(collectionScope: f.scope), .unreadable)
        XCTAssertNil(f.controller.beginRecovery(postID: 101, collectionScope: f.scope))
        _ = try await prepare(f)
        XCTAssertEqual(f.controller.phase, .failed); XCTAssertEqual(f.wire.writes, 0)
    }
    func testCurrentEnvelopeUnauthorizedInvokesScopedExpiration() async throws {
        let f = try fixture(); f.wire.unauthorizedRead = true
        _ = try await prepare(f)
        XCTAssertEqual(f.context.unauthorizedCount, 1); XCTAssertEqual(f.wire.writes, 0)
        XCTAssertNil(f.controller.review)
    }
    func testUnauthorizedAfterDispatchPreservesPendingRecord() async throws {
        let f = try fixture(); _ = try await prepare(f); f.wire.unauthorizedWrite = true
        try await confirm(f)
        XCTAssertEqual(f.context.unauthorizedCount, 1); XCTAssertEqual(f.controller.phase, .unknown)
        XCTAssertNotNil(f.journal.value); XCTAssertEqual(f.wire.writes, 1)
    }
    func testLateUnauthorizedCannotExpireSuccessorContext() async throws {
        let f = try fixture(); f.wire.suspendRead = true
        let id = try XCTUnwrap(f.controller.begin(post: f.post, collectionScope: f.scope))
        let old = Task { await f.controller.prepare(id) }; await wait(f.wire)
        f.controller.retire(id); f.context.session = nil
        f.wire.pending?.resume(returning: (Data(#"{"code":401}"#.utf8), 401)); f.wire.pending = nil
        await old.value
        XCTAssertEqual(f.context.unauthorizedCount, 0); XCTAssertEqual(f.controller.phase, .idle)
    }
    func testRetiringDuringPrewriteReadPreventsLateDispatch() async throws {
        let f = try fixture(), id = try await prepare(f), review = try XCTUnwrap(f.controller.review)
        f.wire.suspendRead = true
        let old = Task { await f.controller.confirm(review) }; await wait(f.wire)
        f.controller.retire(id)
        f.wire.pending?.resume(returning: (Data(#"{"code":200,"data":{"id":101,"isBookmarked":1}}"#.utf8), 200))
        f.wire.pending = nil; await old.value
        XCTAssertEqual(f.wire.writes, 0); XCTAssertNil(f.journal.value)
        XCTAssertEqual(f.controller.phase, .idle)
    }

}
