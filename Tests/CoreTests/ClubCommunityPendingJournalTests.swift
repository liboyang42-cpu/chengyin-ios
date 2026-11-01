import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class CL3FakeTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var body = Data(#"{"code":200,"data":null}"#.utf8)
    var status = 200
    var failWithTimeout = false
    var onSend: (() -> Void)?

    func send(_ request: URLRequest) async throws -> (Data, Int) {
        onSend?()
        requests.append(request)
        if failWithTimeout {
            throw URLError(.timedOut)
        }
        return (body, status)
    }
}

@MainActor
final class ClubCommunityPendingJournalTests: XCTestCase {
    private let identity5 = ClubReadIdentity(accountID: 5, epoch: 1)

    private func makePost(id: Int = 20, clubID: Int = 10, authorID: Int = 5, content: String = "secret body text") throws -> ClubCommunityPost {
        try ClubCommunityPost(json: [
            "id": id,
            "clubId": clubID,
            "authorMemberId": authorID,
            "content": content,
            "images": "https://cdn.example.com/club/secret-1.jpg",
            "version": 2
        ])
    }

    private func makeEvidence(
        identity: ClubReadIdentity? = nil,
        clubID: Int = 10,
        post: ClubCommunityPost? = nil,
        comment: ClubCommunityComment? = nil
    ) -> ClubCommunityEvidence {
        ClubCommunityEvidence(
            identity: identity ?? identity5,
            clubID: clubID,
            joined: true,
            owner: false,
            administrator: false,
            post: post,
            comment: comment
        )
    }

    func testPersistBeforeSendExcludesTokenBodyAndImagesAndRecoversUnknownAcrossRestart() async throws {
        var rawStore: [String: Data] = [:]
        var persistedBeforeTransportSend: Data?
        let journal = ClubCommunityStoredPendingJournal(
            read: { rawStore[$0] },
            write: { data, key in rawStore[key] = data }
        )

        let transport = CL3FakeTransport()
        transport.failWithTimeout = true
        transport.onSend = {
            persistedBeforeTransportSend = rawStore.values.first
        }

        let service = ClubCommunityService(
            dormantBaseURL: URL(string: "https://fixture.invalid")!,
            transport: transport,
            grant: .reviewedInjection
        )
        let secretToken = "Bearer-super-secret-token-999"
        let secretBody = "Sensitive club post content that must never be journaled"
        let secretImage = "https://cdn.example.com/club/private-upload-99.jpg"
        let sessionEpoch1 = try ClubCommunitySession(identity: identity5, token: secretToken)
        let targetPost = try makePost(id: 20, clubID: 10, authorID: 5, content: secretBody)
        let evidence = makeEvidence(clubID: 10, post: targetPost)

        let coordinator1 = ClubCommunityCoordinator(
            service: service,
            currentSession: { sessionEpoch1 },
            refreshEvidence: { $0 },
            journal: journal,
            namespace: { "cn-prod" }
        )
        let review = try await coordinator1.prepare(
            .update(content: secretBody, images: [secretImage], requestID: "req-1"),
            evidence: evidence
        )

        do {
            try await coordinator1.confirm(review)
            XCTFail("Expected unknown failure on transport timeout")
        } catch {
            XCTAssertEqual(error as? ClubCommunityFailure, .unknown)
        }

        // 1. Verify record was persisted BEFORE transport.send executed:
        let preSendBytes = try XCTUnwrap(persistedBeforeTransportSend)
        let preSendRecord = try JSONDecoder().decode(ClubCommunityPendingRecord.self, from: preSendBytes)
        XCTAssertEqual(preSendRecord.operationID, review.id)
        XCTAssertEqual(preSendRecord.operationKind, "edit")
        XCTAssertEqual(preSendRecord.phase, .sending)

        // 2. Verify persisted JSON never contains token, body text, or image URLs:
        let persistedBytes = try XCTUnwrap(rawStore.values.first)
        let persistedString = try XCTUnwrap(String(data: persistedBytes, encoding: .utf8))
        XCTAssertFalse(persistedString.contains(secretToken))
        XCTAssertFalse(persistedString.contains(secretBody))
        XCTAssertFalse(persistedString.contains(secretImage))
        XCTAssertFalse(persistedString.contains("req-1"))

        let postUnknownRecord = try JSONDecoder().decode(ClubCommunityPendingRecord.self, from: persistedBytes)
        XCTAssertEqual(postUnknownRecord.phase, .unknownLocked)
        XCTAssertEqual(coordinator1.outcome, .unknownLocked)
        XCTAssertTrue(coordinator1.isLocked(evidence))
        XCTAssertEqual(transport.requests.count, 1)

        // 3. Simulate app restart with a brand new coordinator instance and a new login epoch:
        let identityEpoch2 = ClubReadIdentity(accountID: 5, epoch: 2)
        let sessionEpoch2 = try ClubCommunitySession(identity: identityEpoch2, token: "replacement-token-epoch-2")
        let evidenceEpoch2 = makeEvidence(identity: identityEpoch2, clubID: 10, post: targetPost)

        let coordinatorAfterRestart = ClubCommunityCoordinator(
            service: service,
            currentSession: { sessionEpoch2 },
            refreshEvidence: { $0 },
            journal: journal,
            namespace: { "cn-prod" }
        )

        // Reading post list does NOT clear or disambiguate the lock:
        transport.failWithTimeout = false
        transport.body = Data(#"{"code":200,"data":{"rows":[{"id":20,"clubId":10,"authorMemberId":5,"content":"\#(secretBody)","version":3}]}}"#.utf8)
        _ = try await service.read(.posts(clubID: 10, page: 1), session: sessionEpoch2, check: {})
        XCTAssertEqual(transport.requests.count, 2)

        // New coordinator recovers the lock as .unknownLocked and refuses duplicate prepare/confirm:
        XCTAssertTrue(coordinatorAfterRestart.isLocked(evidenceEpoch2))
        XCTAssertEqual(coordinatorAfterRestart.outcome, .unknownLocked)
        do {
            _ = try await coordinatorAfterRestart.prepare(
                .update(content: secretBody, images: [secretImage], requestID: "req-2"),
                evidence: evidenceEpoch2
            )
            XCTFail("Expected locked failure after restart")
        } catch {
            XCTAssertEqual(error as? ClubCommunityFailure, .locked)
        }
        // No new write request was sent:
        XCTAssertEqual(transport.requests.count, 2)

        // 4. Wrong operationID cannot release the recovered lock:
        XCTAssertThrowsError(
            try coordinatorAfterRestart.resolvePendingLock(
                for: evidenceEpoch2,
                resolution: .acknowledged(operationID: UUID())
            )
        )
        XCTAssertTrue(coordinatorAfterRestart.isLocked(evidenceEpoch2))

        // 5. Explicit authoritative resolution with the exact operationID releases the lock:
        try coordinatorAfterRestart.resolvePendingLock(
            for: evidenceEpoch2,
            resolution: .rejected(operationID: review.id, code: 409)
        )
        XCTAssertFalse(coordinatorAfterRestart.isLocked(evidenceEpoch2))
        XCTAssertEqual(coordinatorAfterRestart.outcome, .rejected)
    }

    func testPersistenceFailureBeforeSendBlocksNetworkDispatch() async throws {
        let failingJournal = ClubCommunityStoredPendingJournal(
            read: { _ in nil },
            write: { _, _ in throw ClubCommunityPendingJournalFailure.persistenceFailed }
        )
        let transport = CL3FakeTransport()
        let service = ClubCommunityService(
            dormantBaseURL: URL(string: "https://fixture.invalid")!,
            transport: transport,
            grant: .reviewedInjection
        )
        let session = try ClubCommunitySession(identity: identity5, token: "valid-token")
        let post = try makePost()
        let coordinator = ClubCommunityCoordinator(
            service: service,
            currentSession: { session },
            refreshEvidence: { $0 },
            journal: failingJournal
        )
        let review = try await coordinator.prepare(.toggleLike, evidence: makeEvidence(post: post))
        do {
            try await coordinator.confirm(review)
            XCTFail("Expected unavailable failure when journal write fails")
        } catch {
            XCTAssertEqual(error as? ClubCommunityFailure, .unavailable)
        }
        // Zero network requests dispatched when journal persistence fails:
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testIsolationAcrossAccountClubPostAndCommentAndReleaseOnExplicitRejectionOrSuccess() async throws {
        var rawStore: [String: Data] = [:]
        let journal = ClubCommunityStoredPendingJournal(
            read: { rawStore[$0] },
            write: { data, key in rawStore[key] = data }
        )
        let transport = CL3FakeTransport()
        transport.failWithTimeout = true
        let service = ClubCommunityService(
            dormantBaseURL: URL(string: "https://fixture.invalid")!,
            transport: transport,
            grant: .reviewedInjection
        )

        var activeIdentity = identity5
        var activeToken = "token-5"
        let coordinator = ClubCommunityCoordinator(
            service: service,
            currentSession: { try ClubCommunitySession(identity: activeIdentity, token: activeToken) },
            refreshEvidence: { $0 },
            journal: journal
        )

        let post20 = try makePost(id: 20, clubID: 10, authorID: 5)
        let post21 = try makePost(id: 21, clubID: 10, authorID: 5)
        let postInClub11 = try makePost(id: 20, clubID: 11, authorID: 5)
        let comment30 = try ClubCommunityComment(json: ["id": 30, "postId": 20, "memberId": 5, "content": "c"])

        // Lock (account 5, club 10, post 20, comment 0):
        let review20 = try await coordinator.prepare(.toggleLike, evidence: makeEvidence(clubID: 10, post: post20))
        do {
            try await coordinator.confirm(review20)
            XCTFail()
        } catch {
            XCTAssertEqual(error as? ClubCommunityFailure, .unknown)
        }
        XCTAssertTrue(coordinator.isLocked(makeEvidence(clubID: 10, post: post20)))

        // Isolated scopes remain unlocked:
        // - Different post (21) in same club (10):
        XCTAssertFalse(coordinator.isLocked(makeEvidence(clubID: 10, post: post21)))
        // - Different club (11):
        XCTAssertFalse(coordinator.isLocked(makeEvidence(clubID: 11, post: postInClub11)))
        // - Comment (30) under post 20:
        XCTAssertFalse(coordinator.isLocked(makeEvidence(clubID: 10, post: post20, comment: comment30)))
        // - Club-level create (post == nil):
        XCTAssertFalse(coordinator.isLocked(makeEvidence(clubID: 10, post: nil)))
        // - Different account (6) on same club 10 & post 20:
        let identity6 = ClubReadIdentity(accountID: 6, epoch: 1)
        let post20For6 = try makePost(id: 20, clubID: 10, authorID: 6)
        XCTAssertFalse(coordinator.isLocked(makeEvidence(identity: identity6, clubID: 10, post: post20For6)))

        // Explicit server rejection (code: 400) on post21 releases its journal entry immediately:
        transport.failWithTimeout = false
        transport.body = Data(#"{"code":400,"msg":"rejected"}"#.utf8)
        let review21 = try await coordinator.prepare(.toggleLike, evidence: makeEvidence(clubID: 10, post: post21))
        do {
            try await coordinator.confirm(review21)
            XCTFail("Expected server rejection")
        } catch {
            XCTAssertEqual(error as? ClubCommunityFailure, .rejected(400))
        }
        XCTAssertFalse(coordinator.isLocked(makeEvidence(clubID: 10, post: post21)))
        XCTAssertEqual(coordinator.outcome, .rejected)

        // Authoritative 200 success on post21 releases its journal entry immediately:
        transport.body = Data(#"{"code":200,"data":null}"#.utf8)
        let retry21 = try await coordinator.prepare(.toggleLike, evidence: makeEvidence(clubID: 10, post: post21))
        try await coordinator.confirm(retry21)
        XCTAssertFalse(coordinator.isLocked(makeEvidence(clubID: 10, post: post21)))
        XCTAssertEqual(coordinator.outcome, .acknowledgedRefreshRequired)

        // Meanwhile post20's UNKNOWN lock is still intact:
        XCTAssertTrue(coordinator.isLocked(makeEvidence(clubID: 10, post: post20)))
    }

    func testAuthoritativeHTTPPendingOutcomeQueryReconcilesRestartedPendingRecordWithoutUnlockingOnStillPendingOrMismatch() async throws {
        var rawStore: [String: Data] = [:]
        let journal = ClubCommunityStoredPendingJournal(
            read: { rawStore[$0] },
            write: { data, key in rawStore[key] = data }
        )
        let baseURL = URL(string: "https://fixture.invalid")!
        let transport = CL3FakeTransport()
        transport.failWithTimeout = true
        let service = ClubCommunityService(
            dormantBaseURL: baseURL,
            transport: transport,
            grant: .reviewedInjection
        )
        let session = try ClubCommunitySession(identity: identity5, token: "token-5")
        let post = try makePost(id: 20, clubID: 10, authorID: 5)
        let evidence = makeEvidence(clubID: 10, post: post)

        let coordinatorBeforeRestart = ClubCommunityCoordinator(
            service: service,
            currentSession: { session },
            refreshEvidence: { $0 },
            journal: journal
        )
        let review = try await coordinatorBeforeRestart.prepare(
            .update(content: "updated body", images: [], requestID: "req-cl3"),
            evidence: evidence
        )
        do {
            try await coordinatorBeforeRestart.confirm(review)
            XCTFail("Expected timeout into unknownLocked")
        } catch {
            XCTAssertEqual(error as? ClubCommunityFailure, .unknown)
        }

        // Simulate app restart with authoritative HTTP pending outcome query
        transport.failWithTimeout = false
        let outcomeQuery = ClubCommunityHTTPPendingOutcomeQuery(
            dormantBaseURL: baseURL,
            transport: transport,
            enabled: true
        )
        let coordinatorAfterRestart = ClubCommunityCoordinator(
            service: service,
            currentSession: { session },
            refreshEvidence: { $0 },
            journal: journal,
            outcomeQuery: outcomeQuery
        )

        let recoveredRecord = try XCTUnwrap(coordinatorAfterRestart.pendingRecord(for: evidence))
        XCTAssertEqual(recoveredRecord.operationID, review.id)
        XCTAssertEqual(recoveredRecord.postVersion, 2)
        XCTAssertEqual(coordinatorAfterRestart.outcome, .unknownLocked)

        // 1. Server reports PENDING -> lock stays active
        transport.body = Data(
            #"{"code":200,"data":{"operationId":"\#(review.id.uuidString)","requestId":"\#(review.id.uuidString)","status":"PENDING","clubId":10,"postId":20}}"#.utf8
        )
        let stillPending = try await coordinatorAfterRestart.reconcilePendingOperation(for: evidence)
        XCTAssertEqual(stillPending, .unknownLocked)
        XCTAssertTrue(coordinatorAfterRestart.isLocked(evidence))
        XCTAssertEqual(coordinatorAfterRestart.outcome, .unknownLocked)

        // 2. Mismatched operationId in receipt -> fails closed (.invalid) and keeps lock
        transport.body = Data(
            #"{"code":200,"data":{"operationId":"\#(UUID().uuidString)","requestId":"\#(review.id.uuidString)","status":"ACKNOWLEDGED","clubId":10,"postId":20}}"#.utf8
        )
        do {
            _ = try await coordinatorAfterRestart.reconcilePendingOperation(for: evidence)
            XCTFail("Expected mismatched operationId receipt to fail closed")
        } catch {
            XCTAssertEqual(error as? ClubCommunityFailure, .invalid)
        }
        XCTAssertTrue(coordinatorAfterRestart.isLocked(evidence))

        // 3. Authoritative ACKNOWLEDGED receipt for the exact same operationId + requestId releases lock
        transport.body = Data(
            #"{"code":200,"data":{"operationId":"\#(review.id.uuidString)","requestId":"\#(review.id.uuidString)","status":"ACKNOWLEDGED","clubId":10,"postId":20}}"#.utf8
        )
        let reconciled = try await coordinatorAfterRestart.reconcilePendingOperation(for: evidence)
        XCTAssertEqual(reconciled, .acknowledgedRefreshRequired)
        XCTAssertFalse(coordinatorAfterRestart.isLocked(evidence))
        XCTAssertNil(coordinatorAfterRestart.pendingRecord(for: evidence))
        XCTAssertEqual(coordinatorAfterRestart.outcome, .acknowledgedRefreshRequired)
    }
}
