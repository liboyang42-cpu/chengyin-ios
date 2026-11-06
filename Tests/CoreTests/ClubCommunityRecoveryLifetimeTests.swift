import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor private final class ClubRecoveryScope {
    var session: ClubCommunitySession
    var namespace="recovery-lifetime"
    init() throws {session=try .init(identity:.init(accountID:5,epoch:1),token:"synthetic-token")}
}
@MainActor private final class ClubRecoveryHTTPTransport: HTTPTransport {
    let response: Data
    var requests: [URLRequest]=[]
    init(operation:UUID) throws {
        response=try JSONSerialization.data(withJSONObject:["code":200,"data":[
            "operationId":operation.uuidString,"requestId":operation.uuidString,"status":"ACKNOWLEDGED",
            "clubId":10,"postId":20,"commentId":0]])
    }
    func send(_ request:URLRequest) async throws -> (Data,Int) {requests.append(request);return(response,200)}
}
/// Deterministic return-boundary hook AFTER the real HTTP adapter's final check.
/// Models the caller's actor resumption; does not replace receipt decoding or validation.
@MainActor private final class ClubRecoveryReturnBoundary: ClubCommunityPendingOutcomeQuerying {
    let original: ClubCommunityHTTPPendingOutcomeQuery
    var afterResult:(() throws -> Void)?
    var allowsAuthoritativeQueries:Bool {original.allowsAuthoritativeQueries}
    init(_ original:ClubCommunityHTTPPendingOutcomeQuery){self.original=original}
    func queryOutcome(for record:ClubCommunityPendingRecord,session:ClubCommunitySession,check:() throws -> Void) async throws -> ClubCommunityPendingQueryResult {
        let value=try await original.queryOutcome(for:record,session:session,check:check)
        try afterResult?();return value
    }
}
@MainActor private struct ClubRecoveryHarness {
    let scope:ClubRecoveryScope
    let query:ClubRecoveryReturnBoundary
    let transport:ClubRecoveryHTTPTransport
    let journal:ClubCommunityInMemoryPendingJournal
    let record:ClubCommunityPendingRecord
    let evidence:ClubCommunityEvidence
    let model:ClubCommunityCoordinator
    init() throws {
        let scope=try ClubRecoveryScope(),journal=ClubCommunityInMemoryPendingJournal()
        let post=try ClubCommunityPost(json:["id":20,"clubId":10,"authorMemberId":5,"content":"synthetic","version":2])
        let evidence=ClubCommunityEvidence(identity:scope.session.identity,clubID:10,joined:true,owner:false,administrator:false,post:post)
        let target=try ClubCommunityPendingTarget(evidence:evidence,namespace:scope.namespace),operation=UUID()
        let record=try ClubCommunityPendingRecord(target:target,operationID:operation,operationKind:"edit",phase:.sending,requestID:operation.uuidString,postVersion:2)
        try journal.recordBeforeSend(record);try journal.markUnknown(target:target,operationID:operation)
        let transport=try ClubRecoveryHTTPTransport(operation:operation),base=URL(string:"https://example.com")!
        let query=ClubRecoveryReturnBoundary(.init(dormantBaseURL:base,transport:transport,enabled:true))
        let model=ClubCommunityCoordinator(service:.init(baseURL:base,transport:transport),currentSession:{scope.session},refreshEvidence:{$0},journal:journal,namespace:{scope.namespace},outcomeQuery:query)
        self.scope=scope;self.query=query;self.transport=transport;self.journal=journal;self.record=record;self.evidence=evidence;self.model=model
    }
}
@MainActor final class ClubCommunityRecoveryLifetimeTests:XCTestCase {
    func testSameOwnerCurrentContextConsumesExactOriginalReceiptWithoutWrite() async throws {
        let h=try ClubRecoveryHarness()
        let outcome=try await h.model.reconcilePendingOperation(for:h.evidence)
        XCTAssertEqual(outcome,.acknowledgedRefreshRequired)
        XCTAssertNil(try h.journal.record(for:h.record.target))
        XCTAssertEqual(h.transport.requests.count,1)
        XCTAssertEqual(h.transport.requests.first?.url?.path,"/api/club/post/operation/receipt")
        XCTAssertFalse(h.model.permitsInjectedWrites)
    }
    func testAccountEpochTokenNamespaceOrVisitChangeAfterFinalAdapterCheckKeepsUnknownLock() async throws {
        for change in ["account","epoch","token","namespace","visit"] {
            let h=try ClubRecoveryHarness()
            defer {h.query.afterResult=nil}
            h.query.afterResult={
                switch change {
                case "account":h.scope.session=try .init(identity:.init(accountID:6,epoch:2),token:"next-token")
                case "epoch":h.scope.session=try .init(identity:.init(accountID:5,epoch:2),token:"synthetic-token")
                case "token":h.scope.session=try .init(identity:.init(accountID:5,epoch:1),token:"next-token")
                case "namespace":h.scope.namespace="another-deployment"
                default:h.model.cancel()
                }
            }
            do {_ = try await h.model.reconcilePendingOperation(for:h.evidence);XCTFail(change)}
            catch {XCTAssertEqual(error as? ClubCommunityFailure,.stale,change)}
            XCTAssertEqual(try h.journal.record(for:h.record.target)?.operationID,h.record.operationID,change)
            XCTAssertEqual(h.model.outcome,.unknownLocked,change)
            XCTAssertEqual(h.transport.requests.count,1,change)
        }
    }
    func testCancelledTaskAfterValidHTTPResultCannotReleaseOriginal() async throws {
        let h=try ClubRecoveryHarness()
        defer {h.query.afterResult=nil}
        h.query.afterResult={withUnsafeCurrentTask{$0?.cancel()}}
        let child=Task {try await h.model.reconcilePendingOperation(for:h.evidence)}
        do {_ = try await child.value;XCTFail()}
        catch {XCTAssertTrue(error is CancellationError)}
        XCTAssertEqual(try h.journal.record(for:h.record.target)?.operationID,h.record.operationID)
        XCTAssertEqual(h.model.outcome,.unknownLocked)
    }
    func testNewOriginalRecordCannotBeReleasedByOlderReadResult() async throws {
        let h=try ClubRecoveryHarness(),newID=UUID()
        defer {h.query.afterResult=nil}
        h.query.afterResult={
            try h.journal.releaseAfterAuthoritativeOutcome(target:h.record.target,resolution:.acknowledged(operationID:h.record.operationID))
            let next=try ClubCommunityPendingRecord(target:h.record.target,operationID:newID,operationKind:"edit",phase:.sending,requestID:newID.uuidString,postVersion:3)
            try h.journal.recordBeforeSend(next)
        }
        do {_ = try await h.model.reconcilePendingOperation(for:h.evidence);XCTFail()}
        catch {XCTAssertEqual(error as? ClubCommunityFailure,.locked)}
        XCTAssertEqual(try h.journal.record(for:h.record.target)?.operationID,newID)
    }
    func testFreshLoginEpochForSameOwnerMayExplicitlyRecoverExistingOriginal() async throws {
        let h=try ClubRecoveryHarness()
        h.scope.session=try .init(identity:.init(accountID:5,epoch:2),token:"new-login-token")
        let outcome=try await h.model.reconcilePendingOperation(for:h.evidence)
        XCTAssertEqual(outcome,.acknowledgedRefreshRequired)
        XCTAssertNil(try h.journal.record(for:h.record.target))
    }
}
