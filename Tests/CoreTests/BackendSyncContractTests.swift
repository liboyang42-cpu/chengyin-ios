import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// BK backend-sync card: client-visible semantics of later hengyin E-items whose
/// source records carry NO_API_CHANGE. Values mirror the sanitized E02-23/E02-24
/// source contracts; nothing here claims a deployed backend.
/// E02-23 rejects with the existing AjaxResult error shape before act/unact.
private let untrustedLegacyMappingRejection = #"{"code":500,"msg":"旧帖尚无可信社区映射，无法收藏或取消收藏"}"#

@MainActor final class BackendSyncContractTests: XCTestCase {
    private final class LegacyBookmarkWire: HTTPTransport {
        var marked = true
        var writeResponse = untrustedLegacyMappingRejection
        var requests: [URLRequest] = []
        var writes: Int { requests.filter { $0.url?.lastPathComponent == "bookmark" }.count }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            if request.url?.lastPathComponent == "bookmark" { return (Data(writeResponse.utf8), 200) }
            return (Data("{\"code\":200,\"data\":{\"id\":101,\"isBookmarked\":\(marked ? 1 : 0)}}".utf8), 200)
        }
    }
    private final class Journal: OperationPendingJournal {
        var value: OperationPendingRecord?
        func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? {
            guard let value, value.ownerKey == ownerKey, value.targetKey == targetKey else { return nil }; return value
        }
        func write(_ record: OperationPendingRecord) throws { guard value == nil else { throw APIError.invalidRequest }; value = record }
        func clear(_ record: OperationPendingRecord) throws { guard value == record else { throw APIError.invalidRequest }; value = nil }
    }
    private func removal(_ wire: LegacyBookmarkWire, journal: Journal) throws -> (ProfileFavoriteRemovalController, SquarePost, UUID) {
        let scope = UUID()
        let session = try ProfileFavoriteRemovalSession(identity: .init(accountID: 7, epoch: 1, role: "player"), namespace: "synthetic",
                                                        collectionScope: scope, market: .china, token: "synthetic-token")
        let config = try APIConfiguration(baseURL: URL(string: "https://profile.example/native")!)
        let endpoint = try OperationEndpointApproval(baseURL: config.baseURL, namespace: "synthetic", accountID: 7, paths: ProfileFavoriteRemovalApproval.paths)
        let grant = try ProfileFavoriteRemovalApproval(endpoint: endpoint, identity: session.identity, postID: 101, expiresAt: Date(timeIntervalSince1970: 200))
        let controller = ProfileFavoriteRemovalController(configuration: config, approvals: [grant], transport: wire, journal: journal,
                                                          current: { session }, now: { Date(timeIntervalSince1970: 100) })
        let post = try JSONDecoder().decode(SquarePost.self, from: Data(#"{"id":101,"memberId":91,"contents":"Synthetic saved post"}"#.utf8)).qualified(as: .legacySquare)
        return (controller, post, scope)
    }

    // MARK: E02-23 legacy square bookmark identity

    func testE0223UntrustedMappingRejectionIsNeverReportedAsRemovedAndIsNotReplayed() async throws {
        let wire = LegacyBookmarkWire(), journal = Journal()
        let (controller, post, scope) = try removal(wire, journal: journal)
        let id = try XCTUnwrap(controller.begin(post: post, collectionScope: scope))
        await controller.prepare(id); XCTAssertEqual(controller.phase, .reviewed)
        await controller.confirm(try XCTUnwrap(controller.review))
        // Same error envelope as any other code500 after dispatch: keep the durable lock.
        XCTAssertEqual(controller.phase, .unknown); XCTAssertNotNil(journal.value); XCTAssertEqual(wire.writes, 1)
        await controller.reconcile(id)
        XCTAssertEqual(controller.phase, .unknown); XCTAssertEqual(wire.writes, 1)
        // The exact info readback is the only resolver; E02-23 no longer marks unmapped rows.
        wire.marked = false; await controller.reconcile(id)
        XCTAssertEqual(controller.phase, .removed); XCTAssertNil(journal.value); XCTAssertEqual(wire.writes, 1)
    }

    func testE0223UnmarkedLegacyRowNeedsNoWrite() async throws {
        let wire = LegacyBookmarkWire(), journal = Journal(); wire.marked = false
        let (controller, post, scope) = try removal(wire, journal: journal)
        let id = try XCTUnwrap(controller.begin(post: post, collectionScope: scope))
        await controller.prepare(id)
        XCTAssertEqual(controller.phase, .removed); XCTAssertEqual(wire.writes, 0); XCTAssertNil(journal.value)
    }

    func testE0223LegacyPostIsNeverBookmarkedThroughCommunityRouteByEqualNumericID() throws {
        let builder = SocialActionRequestBuilder(configuration: try .init(baseURL: URL(string: "https://example.com/fixture/")!))
        let identity = SocialAccountIdentity(accountID: 81, epoch: 1, role: "player")
        let legacy = SocialActionSnapshot(target: .post(701), post: try SquareSyntheticFixtures.post(id: 701))
        for enabled in [true, false] {
            XCTAssertThrowsError(try builder.make(.postAction(.bookmark, enabled: enabled, requestID: UUID().uuidString), snapshot: legacy,
                                                  identity: identity, token: "synthetic-token")) { XCTAssertEqual($0 as? SocialActionBlock, .changed) }
        }
        let community = SocialActionSnapshot(target: .post(701), post: try SquareReportFixtures.post(id: 701))
        let request = try builder.make(.postAction(.bookmark, enabled: false, requestID: UUID().uuidString), snapshot: community,
                                       identity: identity, token: "synthetic-token")
        XCTAssertEqual(request.url?.path, "/fixture/api/v1/community/posts/701/actions/BOOKMARK"); XCTAssertEqual(request.httpMethod, "DELETE")
    }

    // MARK: E02-24 comment replay binds the parent target

    private final class CommentWire: HTTPTransport {
        var status = 409, body = #"{"code":409,"msg":"同一请求号不能用于不同回复"}"#
        var requests: [URLRequest] = []
        func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return (Data(body.utf8), status) }
    }

    func testE0224CommentRequestIDTravelsWithItsOwnParentAndConflictIsNeverSuccess() async throws {
        let config = try APIConfiguration(baseURL: URL(string: "https://example.com/fixture/")!)
        let identity = SocialAccountIdentity(accountID: 81, epoch: 1, role: "player")
        let post = try SquareReportFixtures.post(id: 701), parent = try XCTUnwrap(SquareReportFixtures.comments(postID: 701).first)
        let reply = SocialActionSnapshot(target: .comment(postID: 701, commentID: parent.id), post: post, comment: parent)
        let command = SocialActionCommand.communityComment(text: "Synthetic reply", requestID: "synthetic-request-0001")
        let request = try SocialActionRequestBuilder(configuration: config).make(command, snapshot: reply, identity: identity, token: "synthetic-token")
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        XCTAssertEqual(payload["parentId"] as? Int, parent.id); XCTAssertEqual(payload["clientRequestId"] as? String, "synthetic-request-0001")
        let root = try SocialActionRequestBuilder(configuration: config).make(command, snapshot: .init(target: .post(701), post: post), identity: identity, token: "synthetic-token")
        XCTAssertNil((try JSONSerialization.jsonObject(with: root.httpBody ?? Data()) as? [String: Any])?["parentId"])
        XCTAssertFalse(command.canRetryAfterUnknown)

        let wire = CommentWire(), service = SocialActionService(configuration: config, transport: wire)
        for (status, expected) in [(409, SocialActionWriteFailure.outcomeUnknown), (200, .rejected)] {
            wire.status = status
            do { _ = try await service.perform(command, snapshot: reply, identity: identity, token: "synthetic-token"); XCTFail("409 conflict accepted") }
            catch { XCTAssertEqual(error as? SocialActionWriteFailure, expected) }
        }
        XCTAssertEqual(wire.requests.count, 2)
    }
}
