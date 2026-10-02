import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class SocialWriteTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var response = #"{"code":200}"#
    var status = 200
    var failure: Error?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); if let failure { throw failure }; return (Data(response.utf8), status)
    }
}
@MainActor private final class SocialTestActionAccess: SocialActionAccess {
    var identity = SocialAccountIdentity(accountID: 81, epoch: 1, role: "player")
    var availability: SocialActionAvailability = .syntheticOnly
    var calls = 0
    var reads = 0
    var onSnapshot: (() async throws -> Void)?
    var onPerform: (() async throws -> SocialActionReceipt)?
    var post: SquarePost = try! SquareSyntheticFixtures.post()
    func snapshot(target: SocialActionTarget) async throws -> SocialActionSnapshot {
        reads += 1; try await onSnapshot?()
        if let id = target.memberID { return try .init(target: target, profile: SocialAccountSyntheticFixtures.profile(id: id)) }
        return .init(target: target, post: target.postID == nil ? nil : post,
                     comment: try target.commentID.flatMap { id in try SquareSyntheticFixtures.comments().first { $0.id == id } })
    }
    func perform(_ command: SocialActionCommand, snapshot: SocialActionSnapshot, expectedIdentity: SocialAccountIdentity) async throws -> SocialActionReceipt {
        calls += 1
        if let onPerform { return try await onPerform() }; return .init(synthetic: true)
    }
}
@MainActor final class SocialActionTests: XCTestCase {
    let identity = SocialAccountIdentity(accountID: 81, epoch: 1, role: "player")
    private func builder() throws -> SocialActionRequestBuilder { .init(configuration: try .init(baseURL: URL(string: "https://example.com/fixture/")!)) }
    private func snapshot(_ target: SocialActionTarget) throws -> SocialActionSnapshot {
        if let id = target.memberID { return try .init(target: target, profile: SocialAccountSyntheticFixtures.profile(id: id)) }
        return try .init(target: target, post: target.postID == nil ? nil : SquareSyntheticFixtures.post(),
                         comment: target.commentID.flatMap { id in try SquareSyntheticFixtures.comments().first { $0.id == id } })
    }
    private func request(_ command: SocialActionCommand, target: SocialActionTarget) throws -> URLRequest {
        try builder().make(command, snapshot: snapshot(target), identity: identity, token: "synthetic-token")
    }
    private func fields(_ request: URLRequest) -> String { String(data: request.httpBody ?? Data(), encoding: .utf8) ?? "" }
    private func prepare(_ coordinator: SocialActionCoordinator, access: SocialTestActionAccess, target: SocialActionTarget = .newPost, command: SocialActionCommand = .newPost(text: "Synthetic post"), owner: UUID = UUID()) async throws -> SocialActionReview {
        try await coordinator.prepare(command, target: target, ownerID: owner, expectedIdentity: access.identity)
    }
    func testNewPostUsesExactLegacyContractAndStableIntentID() throws {
        let command = SocialActionCommand.createPost(text: "Example & 示例", requestID: "abcdefghijklmnop")
        let r = try request(command, target: .newPost)
        XCTAssertEqual(r.url?.path, "/fixture/api/creativesquare/action")
        XCTAssertEqual(r.httpMethod, "POST"); XCTAssertTrue(fields(r).contains("name=\"request_id\"\r\n\r\nabcdefghijklmnop"))
        XCTAssertTrue(fields(r).contains("name=\"pics\"\r\n\r\n\r\n"))
        XCTAssertFalse(fields(r).contains("author")); XCTAssertFalse(fields(r).contains("latitude"))
        XCTAssertTrue(fields(try request(command, target: .newPost)).contains("abcdefghijklmnop"))
    }
    func testEditingOmitsMediaAndRetainsSourceAssociation() throws {
        let r = try request(.editPost(text: "Revised"), target: .post(701))
        XCTAssertTrue(fields(r).contains("name=\"id\"\r\n\r\n701"))
        XCTAssertTrue(fields(r).contains("name=\"data_id\"\r\n\r\n31")); XCTAssertTrue(fields(r).contains("name=\"data_type\"\r\n\r\n2"))
        XCTAssertFalse(fields(r).contains("name=\"pics\"")); XCTAssertFalse(fields(r).contains("request_id"))
    }
    func testCommentAndReplyOnlySendSourceReplyID() throws {
        for (target, replyID) in [(SocialActionTarget.post(701), 0), (.comment(postID: 701, commentID: 802), 802)] {
            let r = try request(.comment(text: "Example reply"), target: target)
            XCTAssertEqual(r.url?.path, "/fixture/api/comment/add")
            for (key, value) in [("owner_type", "3"), ("owner_id", "701"), ("rating", "0"), ("reply_id", String(replyID))] {
                XCTAssertTrue(fields(r).contains("name=\"\(key)\"\r\n\r\n\(value)"))
            }
            XCTAssertFalse(fields(r).contains("parent_id")); XCTAssertFalse(fields(r).contains("author_id"))
        }
    }
    func testPostActionsUseExplicitSourceJSONMethods() throws {
        for action in SocialPostAction.allCases {
            for enabled in [true, false] {
                let r = try request(.postAction(action, enabled: enabled, requestID: "abcdefghijklmnop"), target: .post(701))
                XCTAssertEqual(r.httpMethod, enabled ? "POST" : "DELETE")
                XCTAssertEqual(r.url?.path, "/fixture/api/v1/community/posts/701/actions" + (enabled ? "" : "/\(action.rawValue)"))
                let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: r.httpBody!) as? [String: String])
                XCTAssertEqual(body["requestId"], "abcdefghijklmnop")
                XCTAssertEqual(body["actionType"], enabled ? action.rawValue : nil)
                XCTAssertEqual(body["source"], enabled ? "APP_SQUARE" : nil)
            }
        }
    }
    func testReportAndCommentToggleCannotInventReasonOrDesiredState() throws {
        let comment = SocialActionTarget.comment(postID: 701, commentID: 802)
        let r = try request(.toggleCommentLike, target: comment)
        XCTAssertEqual(r.url?.path, "/fixture/api/comment/like"); XCTAssertFalse(fields(r).contains("enabled"))
        for (target, path) in [(SocialActionTarget.post(701), "api/creativesquare/report"), (comment, "api/comment/report")] {
            let report = try request(.report, target: target)
            XCTAssertEqual(report.url?.path, "/fixture/\(path)"); XCTAssertFalse(fields(report).contains("reason")); XCTAssertFalse(fields(report).contains("evidence"))
        }
    }
    func testOwnerAndCommentPermissionsAreRevalidated() throws {
        let other = SocialAccountIdentity(accountID: 82, epoch: 1)
        XCTAssertThrowsError(try builder().make(.editPost(text: "No permission"), snapshot: snapshot(.post(701)), identity: other, token: "synthetic"))
        let post = try JSONDecoder().decode(SquarePost.self, from: Data(SquareSyntheticFixtures.wrappedPostJSON.utf8))
        let locked = SocialActionSnapshot(target: .post(702), post: post)
        XCTAssertThrowsError(try builder().make(.comment(text: "No permission"), snapshot: locked, identity: identity, token: "synthetic"))
        XCTAssertThrowsError(try request(.newPost(text: "   "), target: .newPost))
    }
    func testFollowAndStartUseSourceFieldNamesAndNeverTargetSelf() throws {
        let follow = try request(.toggleFollow, target: .member(82))
        XCTAssertEqual(follow.url?.path, "/fixture/api/user/follow/action")
        XCTAssertTrue(fields(follow).contains("name=\"follow_member_id\"\r\n\r\n82"))
        let chat = try request(.startChat, target: .member(82))
        XCTAssertEqual(chat.url?.path, "/fixture/api/im/start")
        XCTAssertTrue(fields(chat).contains("name=\"target_member_id\"\r\n\r\n82"))
        XCTAssertThrowsError(try request(.toggleFollow, target: .member(81)))
    }
    func testDormantServicePreservesSourceAcknowledgementWithoutInventingPost() async throws {
        let t = SocialWriteTransport()
        let service = SocialActionService(configuration: try .init(baseURL: URL(string: "https://example.com")!), transport: t)
        let receipt = try await service.perform(.newPost(text: "Example"), snapshot: snapshot(.newPost), identity: identity, token: "synthetic")
        XCTAssertFalse(receipt.synthetic); XCTAssertNil(receipt.conversationID); XCTAssertNil(receipt.followed); XCTAssertEqual(t.requests.count, 1)
    }
    func testDormantServiceFailureClassificationAndNoAutomaticRetry() async throws {
        for (response, status, expected) in [(#"{"code":400}"#, 200, SocialActionWriteFailure.rejected), (#"{"code":200}"#, 500, .outcomeUnknown), ("{}", 200, .outcomeUnknown)] {
            let t = SocialWriteTransport(); t.response = response; t.status = status
            let service = SocialActionService(configuration: try .init(baseURL: URL(string: "https://example.com")!), transport: t)
            do { _ = try await service.perform(.newPost(text: "Example"), snapshot: snapshot(.newPost), identity: identity, token: "synthetic"); XCTFail() }
            catch { XCTAssertEqual(error as? SocialActionWriteFailure, expected) }
            XCTAssertEqual(t.requests.count, 1)
        }
    }
    func testFollowReceiptDoesNotGuessChangedServerCopy() async throws {
        let t = SocialWriteTransport()
        let service = SocialActionService(configuration: try .init(baseURL: URL(string: "https://example.com")!), transport: t)
        for (message, expected) in [("取消关注成功", false), ("关注成功", true)] {
            t.response = "{\"code\":200,\"msg\":\"\(message)\"}"
            let r = try await service.perform(.toggleFollow, snapshot: snapshot(.member(82)), identity: identity, token: "synthetic")
            XCTAssertEqual(r.followed, expected)
        }
        t.response = #"{"code":200,"msg":"New localized server copy"}"#
        do { _ = try await service.perform(.toggleFollow, snapshot: snapshot(.member(82)), identity: identity, token: "synthetic"); XCTFail() }
        catch { XCTAssertEqual(error as? SocialActionWriteFailure, .outcomeUnknown) }
    }
    func testConversationNeedsPositiveServerID() async throws {
        let t = SocialWriteTransport()
        let service = SocialActionService(configuration: try .init(baseURL: URL(string: "https://example.com")!), transport: t)
        t.response = #"{"code":200,"data":{"conversationId":901}}"#
        let r = try await service.perform(.startChat, snapshot: snapshot(.member(82)), identity: identity, token: "synthetic")
        XCTAssertEqual(r.conversationID, 901)
        t.response = #"{"code":200,"data":{"conversationId":0}}"#
        do { _ = try await service.perform(.startChat, snapshot: snapshot(.member(82)), identity: identity, token: "synthetic"); XCTFail() }
        catch { XCTAssertEqual(error as? SocialActionWriteFailure, .outcomeUnknown) }
    }
    func testDisabledCoordinatorNeverCallsWriter() async throws {
        let access = SocialTestActionAccess(); access.availability = .disabled
        let coordinator = SocialActionCoordinator(access: access)
        let review = try await prepare(coordinator, access: access)
        await coordinator.confirm(review)
        XCTAssertEqual(access.calls, 0); XCTAssertEqual(coordinator.state(target: .newPost), .notSent)
    }
    func testReviewCancellationAndDuplicateConfirmation() async throws {
        let access = SocialTestActionAccess(), owner = UUID()
        let coordinator = SocialActionCoordinator(access: access)
        let cancelled = try await prepare(coordinator, access: access, owner: owner)
        coordinator.cancel(cancelled); await coordinator.confirm(cancelled); XCTAssertEqual(access.calls, 0)
        let review = try await prepare(coordinator, access: access, owner: owner)
        await coordinator.confirm(review); await coordinator.confirm(review)
        XCTAssertEqual(access.calls, 1); XCTAssertEqual(coordinator.state(target: .newPost), .acknowledged(.init(synthetic: true)))
    }
    func testRoleChangeInvalidatesReviewWithoutSending() async throws {
        let access = SocialTestActionAccess(), coordinator = SocialActionCoordinator(access: SocialTestActionAccess())
        _ = coordinator // separate instance must never validate another owner's review
        let active = SocialActionCoordinator(access: access)
        let review = try await prepare(active, access: access)
        access.identity = .init(accountID: 81, epoch: 1, role: "merchant")
        await active.confirm(review); XCTAssertEqual(access.calls, 0)
    }
    func testPreflightContentChangeRequiresNewReview() async throws {
        let access = SocialTestActionAccess(), coordinator: SocialActionCoordinator
        coordinator = .init(access: access)
        let review = try await prepare(coordinator, access: access, target: .post(701), command: .editPost(text: "New text"))
        access.post = try JSONDecoder().decode(SquarePost.self, from: Data(SquareSyntheticFixtures.legacyPostJSON.replacingOccurrences(of: "A synthetic city walk", with: "Changed source text").utf8))
        await coordinator.confirm(review)
        XCTAssertEqual(access.calls, 0); XCTAssertEqual(coordinator.state(target: .post(701)), .notSent)
    }
    func testUnknownLocksAccountTargetAcrossLogoutAndRelogin() async throws {
        let access = SocialTestActionAccess(); access.onPerform = { throw URLError(.timedOut) }
        let coordinator = SocialActionCoordinator(access: access)
        let review = try await prepare(coordinator, access: access)
        await coordinator.confirm(review); XCTAssertEqual(coordinator.state(target: .newPost), .outcomeUnknown)
        access.identity = .init(accountID: 82, epoch: 2); XCTAssertEqual(coordinator.state(target: .newPost), .idle)
        access.identity = .init(accountID: 81, epoch: 3); XCTAssertEqual(coordinator.state(target: .newPost), .outcomeUnknown)
        do { _ = try await prepare(coordinator, access: access); XCTFail() } catch { XCTAssertEqual(error as? SocialActionBlock, .pending) }
        XCTAssertEqual(access.calls, 1)
    }
    func testAccountSwitchAfterDispatchCannotPublishStaleSuccess() async throws {
        let access = SocialTestActionAccess()
        access.onPerform = { access.identity = .init(accountID: 82, epoch: 2); return .init(synthetic: true) }
        let coordinator = SocialActionCoordinator(access: access), old = access.identity
        let review = try await prepare(coordinator, access: access)
        await coordinator.confirm(review); XCTAssertEqual(coordinator.state(target: .newPost), .idle)
        access.identity = .init(accountID: old.accountID, epoch: 3)
        XCTAssertEqual(coordinator.state(target: .newPost), .outcomeUnknown)
    }
    func testLeavingDuringDispatchKeepsUnknownLock() async throws {
        let access = SocialTestActionAccess(), owner = UUID()
        let coordinator = SocialActionCoordinator(access: access), original = access.identity
        access.onPerform = {
            coordinator.leaveScreen(target: .newPost, expectedIdentity: original, ownerID: owner)
            return .init(synthetic: true)
        }
        let review = try await prepare(coordinator, access: access, owner: owner)
        await coordinator.confirm(review)
        XCTAssertEqual(coordinator.state(target: .newPost), .outcomeUnknown)
    }
    func testCrossCoordinatorReviewAndWrongOwnerCannotCancel() async throws {
        let access = SocialTestActionAccess(), owner = UUID()
        let first = SocialActionCoordinator(access: access), other = SocialActionCoordinator(access: access)
        let review = try await prepare(first, access: access, owner: owner)
        await other.confirm(review); XCTAssertEqual(access.calls, 0)
        first.leaveScreen(target: .newPost, expectedIdentity: access.identity, ownerID: UUID())
        XCTAssertEqual(first.state(target: .newPost), .reviewing)
        first.leaveScreen(target: .newPost, expectedIdentity: access.identity, ownerID: owner)
        XCTAssertEqual(first.state(target: .newPost), .idle)
    }
}
