import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor private final class HostControllerMockHTTP: HTTPTransport {
    var responses: [(Data, Int)] = []
    private(set) var requests: [URLRequest] = []

    func enqueueJSON(_ body: String, status: Int = 200) {
        responses.append((Data(body.utf8), status))
    }

    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        guard !responses.isEmpty else { throw URLError(.timedOut) }
        return responses.removeFirst()
    }
}

@MainActor private final class HostRecordingEviction: SquareWorkspaceMediaEviction {
    private(set) var evicted: [Set<URL>] = []
    var all: Set<URL> { evicted.reduce(into: Set<URL>()) { $0.formUnion($1) } }
    func evict(_ urls: Set<URL>) { evicted.append(urls) }
}

@MainActor final class TopicLikeHostControllerTests: XCTestCase {
    private let baseURL = URL(string: "https://example.com")!
    private let mediaURL = URL(string: "https://media.example.com/b05/post-1.jpg")!
    private let deniedJSON = #"{"code":404,"msg":"帖文不存在或不可见"}"#
    private let likeAckJSON = #"{"code":200,"msg":"点赞成功"}"#

    private func postDetailJSON(id: Int = 1, author: Int = 11, lifecycle: String = "PUBLISHED") -> String {
        "{\"code\":200,\"data\":{\"post\":{\"id\":\(id),\"authorId\":\(author),\"version\":3,\"lifecycle\":\"\(lifecycle)\",\"audience\":\"PUBLIC\",\"body\":\"post body\"},\"media\":[{\"id\":11,\"mediaType\":\"IMAGE\",\"derivedObjectKey\":\"\(mediaURL.absoluteString)\"}]}}"
    }

    private func makeWorkspace(
        http: HostControllerMockHTTP,
        eviction: HostRecordingEviction,
        account: Int = 11
    ) throws -> SquareWorkspaceCoordinator {
        let session = try SquareWorkspaceSession(accountID: account, namespace: "synthetic-host", epoch: 1)
        var grants = SquareWorkspaceGrants()
        grants.live = true
        let service = SquareWorkspaceService(configuration: try .init(baseURL: baseURL), transport: http)
        return SquareWorkspaceCoordinator(
            session: session,
            store: SquareWorkspaceStore(storage: SquareWorkspaceMemoryStorage()),
            service: service,
            grants: grants,
            currentSession: { session },
            token: { "synthetic-token" },
            mediaEviction: eviction
        )
    }

    private func makeScope(account: Int = 11, epoch: UInt64 = 1) throws -> TopicLikeScope {
        try TopicLikeScope(accountID: account, epoch: epoch, namespace: "synthetic-host")
    }

    func testForegroundReturnRevalidationIsGatedOnPriorBackgroundEntry() async throws {
        let http = HostControllerMockHTTP()
        http.enqueueJSON(postDetailJSON())
        http.enqueueJSON(postDetailJSON())
        let eviction = HostRecordingEviction()
        let workspace = try makeWorkspace(http: http, eviction: eviction)
        let host = TopicLikeHostController(workspace: workspace)

        _ = try await workspace.revalidate(postID: 1)
        XCTAssertEqual(http.requests.count, 1)

        // Foreground return without prior background transition is ignored.
        let skipped = try await host.revalidateIfNeeded(trigger: .foregroundReturn)
        XCTAssertNil(skipped)
        XCTAssertEqual(http.requests.count, 1)
        XCTAssertEqual(host.revalidationCount, 0)

        // Entering background enables a single foreground revalidation pass.
        host.noteDidEnterBackground()
        XCTAssertTrue(host.hasEnteredBackground)
        let refreshed = try await host.revalidateIfNeeded(trigger: .foregroundReturn)
        XCTAssertEqual(refreshed?.id, 1)
        XCTAssertFalse(host.hasEnteredBackground)
        XCTAssertEqual(host.lastRevalidationTrigger, .foregroundReturn)
        XCTAssertEqual(host.revalidationCount, 1)
        XCTAssertEqual(http.requests.count, 2)

        // Duplicate foreground event without another background entry is gated out.
        let duplicate = try await host.revalidateIfNeeded(trigger: .foregroundReturn)
        XCTAssertNil(duplicate)
        XCTAssertEqual(http.requests.count, 2)
    }

    func testCommunityLeaveAndShareRevocationAlwaysTriggerRevalidateAndEvictOn404() async throws {
        let http = HostControllerMockHTTP()
        http.enqueueJSON(postDetailJSON())
        http.enqueueJSON(deniedJSON)
        let eviction = HostRecordingEviction()
        let workspace = try makeWorkspace(http: http, eviction: eviction)
        let host = TopicLikeHostController(workspace: workspace)

        _ = try await host.revalidateIfNeeded(postID: 1, trigger: .communityLeave)
        XCTAssertEqual(workspace.lastPost?.id, 1)
        XCTAssertEqual(host.lastRevalidationTrigger, .communityLeave)

        do {
            _ = try await host.revalidateIfNeeded(trigger: .shareRevocation)
            XCTFail("Expected business 404 revocation")
        } catch {
            XCTAssertEqual(error as? SquareWorkspaceFailure, .rejected(404))
        }
        XCTAssertNil(workspace.lastPost)
        XCTAssertEqual(eviction.all, [mediaURL])
        XCTAssertEqual(host.lastRevalidationTrigger, .shareRevocation)
        XCTAssertEqual(host.revalidationCount, 2)
    }

    func testTopicLikeHostControllerStateTransitionsAndReadbackConfirmation() async throws {
        let http = HostControllerMockHTTP()
        http.enqueueJSON(likeAckJSON)
        http.enqueueJSON(likeAckJSON)
        let scope = try makeScope()
        let factory = TopicLikeOperationFactory(configuration: try .init(baseURL: baseURL))
        let host = TopicLikeHostController(
            likeGrantEnabled: true,
            requestBuilder: factory.request,
            transport: http,
            currentScope: { scope },
            token: { "synthetic-token" }
        )

        // 1. Write acknowledged without immediate readback leaves state in .awaitingReadback(.like).
        let stateAfterAck = try await host.setLikeDirection(topicID: 201, direction: .like)
        XCTAssertEqual(stateAfterAck, .awaitingReadback(.like))
        XCTAssertNil(host.confirmedLiked(topicID: 201))

        // Duplicate tap of same pending direction is coalesced without issuing a network request.
        let coalesced = try await host.setLikeDirection(topicID: 201, direction: .like)
        XCTAssertEqual(coalesced, .awaitingReadback(.like))
        XCTAssertEqual(http.requests.count, 1)

        // Fresh readback confirms the like state.
        let observed = try await host.performReadback(topicID: 201) { _, _ in true }
        XCTAssertTrue(observed)
        XCTAssertEqual(host.state(for: 201), .confirmed(liked: true))
        XCTAssertEqual(host.confirmedLiked(topicID: 201), true)

        // 2. Unlike with inline readback transitions all the way to .confirmed(liked: false).
        let stateAfterUnlike = try await host.setLikeDirection(topicID: 201, direction: .unlike) { _, _ in false }
        XCTAssertEqual(stateAfterUnlike, .confirmed(liked: false))
        XCTAssertEqual(host.confirmedLiked(topicID: 201), false)
        XCTAssertEqual(http.requests.count, 2)
    }

    func testTransportTimeoutProducesUnknownStateBlockingResendUntilReadback() async throws {
        let http = HostControllerMockHTTP() // empty queue -> throws timedOut
        let scope = try makeScope()
        let factory = TopicLikeOperationFactory(configuration: try .init(baseURL: baseURL))
        let host = TopicLikeHostController(
            likeGrantEnabled: true,
            requestBuilder: factory.request,
            transport: http,
            currentScope: { scope },
            token: { "synthetic-token" }
        )

        let uncertain = try await host.setLikeDirection(topicID: 305, direction: .like)
        XCTAssertEqual(uncertain, .unknown(.like))
        XCTAssertEqual(http.requests.count, 1)

        // While .unknown, any resend is blocked until readback resolves server state.
        let blocked = try await host.setLikeDirection(topicID: 305, direction: .unlike)
        XCTAssertEqual(blocked, .unknown(.like))
        XCTAssertEqual(http.requests.count, 1)

        let resolved = try await host.performReadback(topicID: 305) { _, _ in false }
        XCTAssertTrue(resolved)
        XCTAssertEqual(host.state(for: 305), .mismatch(requested: .like, liked: false))
        XCTAssertEqual(host.confirmedLiked(topicID: 305), false)
    }

    func testDisabledGrantBlocksLikeWriteAndReadback() async throws {
        let http = HostControllerMockHTTP()
        http.enqueueJSON(likeAckJSON)
        let scope = try makeScope()
        let factory = TopicLikeOperationFactory(configuration: try .init(baseURL: baseURL))
        let host = TopicLikeHostController(
            likeGrantEnabled: false,
            requestBuilder: factory.request,
            transport: http,
            currentScope: { scope },
            token: { "synthetic-token" }
        )

        do {
            _ = try await host.setLikeDirection(topicID: 201, direction: .like)
            XCTFail("Expected disabled error when likeGrantEnabled is false")
        } catch {
            XCTAssertEqual(error as? SquareWorkspaceFailure, .disabled)
        }
        XCTAssertTrue(http.requests.isEmpty)
    }
}
