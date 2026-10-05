import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class SquareGovernanceTests: XCTestCase {
    func fixture() -> (SquareGovernanceCoordinator, SquareGovernanceSyntheticAccess, SquareGovernanceSyntheticTransport) {
        let transport = SquareGovernanceSyntheticTransport()
        return (.init(service: .init(offlineBaseURL: URL(string: "https://square-governance.invalid")!, transport: transport), journal: .ephemeral()), .init(), transport)
    }
    func testDefaultTransportGrantsOff() async throws {
        let (_, access, transport) = fixture()
        let service = SquareGovernanceService(baseURL: URL(string: "https://square-governance.invalid")!, transport: transport)
        XCTAssertFalse(service.allowsInjectedWrites)
        do { _ = try await service.enforcements(token: access.token!, check: {}); XCTFail() } catch { XCTAssertEqual(error as? SquareGovernanceFailure, .disabled) }
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testExactReadPathsLimitsAndCursor() async throws {
        let (coordinator, access, transport) = fixture()
        _ = try await coordinator.load(access: access)
        XCTAssertEqual(transport.requests.map { $0.httpMethod! }, ["GET", "GET", "GET"])
        XCTAssertEqual(transport.requests[0].url?.query, "limit=30")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "Authorization"), "synthetic-only-token")
        XCTAssertEqual(transport.requests[1].url?.query, "limit=50")
        _ = try await coordinator.service.notifications(cursor: 81, token: access.token!, check: {})
        XCTAssertEqual(transport.requests.last?.url?.query, "limit=50&cursor=81")
    }
    func testAppealWireTrimEmptyEvidenceAndStableID() async throws {
        let (coordinator, access, _) = fixture(); let snapshot = try await coordinator.load(access: access)
        let review = try coordinator.prepare(.appeal(enforcementID: 91, reason: "  facts \n"), snapshot: snapshot, access: access)
        let request = try coordinator.service.command(review, token: access.token!)
        let body = try JSONDecoder().decode(SquareGovernanceJSON.self, from: request.httpBody!)
        XCTAssertEqual(request.url?.path, "/api/v1/community/appeals"); XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(body["reason"], .string("facts")); XCTAssertEqual(body["enforcementId"], .integer(91))
        XCTAssertEqual(body["evidenceAssetIds"], .array([])); XCTAssertEqual(body["requestId"], .string(review.requestID))
    }
    func testPartialPreferencesPreserveOmittedKeys() async throws {
        let (coordinator, access, _) = fixture(); let snapshot = try await coordinator.load(access: access)
        let review = try coordinator.prepare(.preferences([.socialEnabled: true]), snapshot: snapshot, access: access)
        let request = try coordinator.service.command(review, token: access.token!)
        XCTAssertEqual(request.httpMethod, "PATCH")
        XCTAssertEqual(try JSONDecoder().decode(SquareGovernanceJSON.self, from: request.httpBody!), .object(["socialEnabled": .bool(true)]))
    }
    func testMarkReadExactRequest() async throws {
        let (coordinator, access, _) = fixture(); let snapshot = try await coordinator.load(access: access)
        let review = try coordinator.prepare(.markRead(notificationID: 81), snapshot: snapshot, access: access)
        let request = try coordinator.service.command(review, token: access.token!)
        XCTAssertEqual(request.url?.path, "/api/v1/community/notifications/81/read")
        XCTAssertTrue(review.requestID.hasPrefix("notification-read-"))
    }
    func testApprovalHasExpectedVersion() async throws {
        let (coordinator, access, _) = fixture(); let snapshot = try await coordinator.load(access: access)
        let review = try coordinator.prepare(.approveComment(postID: 71, commentID: 61), snapshot: snapshot, access: access)
        let request = try coordinator.service.command(review, token: access.token!)
        XCTAssertEqual(request.url?.path, "/api/v1/community/posts/71/comments/61/approve")
        XCTAssertEqual(try JSONDecoder().decode(SquareGovernanceJSON.self, from: request.httpBody!)["expectedVersion"], .integer(3))
    }
    func testDeleteUsesMultipartOnlyID() async throws {
        let (coordinator, access, _) = fixture(); let snapshot = try await coordinator.load(access: access)
        let review = try coordinator.prepare(.deleteOwnComment(commentID: 62), snapshot: snapshot, access: access)
        let request = try coordinator.service.command(review, token: access.token!)
        XCTAssertEqual(request.url?.path, "/api/comment/delete")
        XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")!.hasPrefix("multipart/form-data"))
        let body = String(data: request.httpBody!, encoding: .utf8)!
        XCTAssertTrue(body.contains("name=\"id\"\r\n\r\n62")); XCTAssertFalse(body.contains("requestId")); XCTAssertFalse(body.contains("expectedVersion"))
    }
    func testPostAuthorCannotDeleteOthersComment() async throws {
        let (coordinator, access, _) = fixture(); let snapshot = try await coordinator.load(access: access)
        XCTAssertThrowsError(try coordinator.prepare(.deleteOwnComment(commentID: 61), snapshot: snapshot, access: access))
        XCTAssertTrue(snapshot.comments[0].canApprove(snapshot.identity)); XCTAssertFalse(snapshot.comments[0].canDelete(snapshot.identity))
    }
    func testCommentAuthorCannotApproveOthersPost() async throws {
        let (coordinator, access, _) = fixture(); let snapshot = try await coordinator.load(access: access)
        XCTAssertThrowsError(try coordinator.prepare(.approveComment(postID: 71, commentID: 62), snapshot: snapshot, access: access))
    }
    func testUnknownVersionLocksApproval() {
        let comment = SquareGovernanceComment(id: 1, postID: 2, postAuthorID: 11, raw: .object(["author_id": .integer(12), "author_approval_state": .string("PENDING")]))
        XCTAssertFalse(comment.canApprove(.init(accountID: 11, epoch: 1, namespace: "test")))
    }
    func testReasonLimitsAndTargetValidation() async throws {
        let (coordinator, access, _) = fixture(); let snapshot = try await coordinator.load(access: access)
        for action in [SquareGovernanceAction.appeal(enforcementID: 91, reason: " \n"), .appeal(enforcementID: 91, reason: String(repeating: "a", count: 1001)), .appeal(enforcementID: 92, reason: "facts"), .markRead(notificationID: 0), .preferences([:])] {
            XCTAssertThrowsError(try coordinator.prepare(action, snapshot: snapshot, access: access))
        }
    }
    func testUnknownPreferenceIsNotAssumedFalse() {
        let snapshot = SquareGovernanceSnapshot(identity: .init(accountID: 11, epoch: 1, namespace: "test"), enforcements: [], notifications: [], preferences: .object([:]))
        XCTAssertThrowsError(try SquareGovernanceCoordinator.validate(.preferences([.socialEnabled: true]), snapshot: snapshot))
    }
    func testAlreadyAppealedAndUnknownAppealTypeLock() throws {
        for value in [SquareGovernanceJSON.string("SUBMITTED"), .integer(7)] {
            let record = try SquareEnforcement(raw: .object(["id": .integer(1), "appeal_status": value]))
            XCTAssertFalse(record.canRequestReview)
        }
    }
    func testNotificationPayloadStringObjectAndUnknown() throws {
        let string = try SquareGovernanceNotification(raw: .object(["id": .integer(1), "payload_json": .string("{\"action\":\"APPEAL_SUBMITTED\"}")]))
        XCTAssertEqual(string.action, "APPEAL_SUBMITTED")
        let object = try SquareGovernanceNotification(raw: .object(["id": .integer(2), "payload_json": .object(["action": .string("REPORT_STAGE_REVIEW"), "publicNote": .string("Pending")])]))
        XCTAssertEqual(object.publicNote, "Pending")
        let malformed = try SquareGovernanceNotification(raw: .object(["id": .integer(3), "payload_json": .string("{")]))
        XCTAssertEqual(malformed.action, "UNKNOWN")
    }
    func testFreshCommentVersionChangeBlocksDispatch() async throws {
        let (coordinator, access, transport) = fixture(); let snapshot = try await coordinator.load(access: access)
        let review = try coordinator.prepare(.approveComment(postID: 71, commentID: 61), snapshot: snapshot, access: access)
        access.comments = []
        do { _ = try await coordinator.confirm(review, access: access); XCTFail() } catch { XCTAssertEqual(error as? SquareGovernanceFailure, .staleReview) }
        XCTAssertTrue(transport.requests.allSatisfy { $0.httpMethod == "GET" })
    }
    func testSessionEpochChangeBlocksReview() async throws {
        let (coordinator, access, _) = fixture(); let snapshot = try await coordinator.load(access: access)
        access.identity = .init(accountID: 11, epoch: 2, namespace: "square-governance-synthetic")
        XCTAssertThrowsError(try coordinator.prepare(.markRead(notificationID: 81), snapshot: snapshot, access: access))
    }
    func testExpiryBlocksBeforeSend() async throws {
        let (coordinator, access, transport) = fixture(); let snapshot = try await coordinator.load(access: access)
        let now = Date(); let review = try coordinator.prepare(.markRead(notificationID: 81), snapshot: snapshot, access: access, now: now)
        do { _ = try await coordinator.confirm(review, access: access, now: now.addingTimeInterval(301)); XCTFail() } catch { XCTAssertEqual(error as? SquareGovernanceFailure, .staleReview) }
        XCTAssertEqual(transport.requests.count, 3)
    }
    func testAcknowledgementDoesNotInventAppealSuccess() async throws {
        let (coordinator, access, _) = fixture(); let snapshot = try await coordinator.load(access: access)
        let review = try coordinator.prepare(.appeal(enforcementID: 91, reason: "facts"), snapshot: snapshot, access: access)
        let receipt = try await coordinator.confirm(review, access: access)
        XCTAssertEqual(receipt, .acknowledgedNeedsRefresh)
        XCTAssertNil(snapshot.enforcements[0].appealStatus)
        do { _ = try await coordinator.confirm(review, access: access); XCTFail() } catch { XCTAssertEqual(error as? SquareGovernanceFailure, .outcomeLocked) }
    }
    func testAmbiguousFailureLocksTargetAcrossNewReview() async throws {
        let (coordinator, access, transport) = fixture(); let snapshot = try await coordinator.load(access: access)
        transport.mutationFailure = .unknown
        let review = try coordinator.prepare(.deleteOwnComment(commentID: 62), snapshot: snapshot, access: access)
        do { _ = try await coordinator.confirm(review, access: access); XCTFail() } catch { XCTAssertEqual(error as? SquareGovernanceFailure, .unknown) }
        XCTAssertThrowsError(try coordinator.prepare(.deleteOwnComment(commentID: 62), snapshot: snapshot, access: access))
        XCTAssertEqual(transport.requests.filter { $0.httpMethod != "GET" }.count, 1)
    }
    func testEnvelopeNon200NeverSuccess() throws {
        for code in [401, 403, 409, 500] {
            XCTAssertThrowsError(try SquareGovernanceService.decode(Data("{\"code\":\(code)}".utf8), status: 200, mutation: true))
        }
        XCTAssertThrowsError(try SquareGovernanceService.decode(Data("{}".utf8), status: 200, mutation: true))
        XCTAssertEqual(try SquareGovernanceService.decode(Data("{\"code\":\"200\"}".utf8), status: 200, mutation: true), .null)
    }
}
