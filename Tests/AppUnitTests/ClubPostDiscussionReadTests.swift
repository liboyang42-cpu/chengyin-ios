import XCTest
@testable import Questify

@MainActor final class ClubPostDiscussionReadTests: XCTestCase {
    private actor Transport: HTTPTransport {
        var requests: [URLRequest] = []
        private var pending: [Int: CheckedContinuation<(Data, Int), Error>] = [:]
        private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            let index = requests.count; requests.append(request)
            let ready = waiters.filter { $0.0 <= requests.count }; waiters.removeAll { $0.0 <= requests.count }
            ready.forEach { $0.1.resume() }
            return try await withCheckedThrowingContinuation { pending[index] = $0 }
        }
        func waitForRequests(_ count: Int) async {
            if requests.count >= count { return }
            await withCheckedContinuation { waiters.append((count, $0)) }
        }
        func reply(_ index: Int, rows: [[String: Any]], status: Int = 200) throws {
            let data = try JSONSerialization.data(withJSONObject: ["code": 200, "data": rows])
            pending.removeValue(forKey: index)?.resume(returning: (data, status))
        }
    }
    private final class Owner {
        var session = try! ClubCommunitySession(identity: .init(accountID: 701, epoch: 1), token: "synthetic-discussion")
        var current = true
    }
    private func make(_ transport: Transport, _ owner: Owner) throws -> ClubPostDiscussionReader {
        let post = try ClubCommunityPost(json: ["id": 91, "clubId": 81, "content": "Synthetic post"])
        let target = try XCTUnwrap(ClubPostDiscussionSelection(post: post, acceptedPosts: [post], context: .init(clubID: 81,
            identity: owner.session.identity, readScope: UUID(), viewerRevision: 1)))
        let context = ClubCommunityContext(service: .init(baseURL: URL(string: "https://fixture.invalid")!, transport: transport),
            currentSession: { owner.session }, coordinator: nil, evidence: { _, _, _ in throw ClubCommunityFailure.unavailable })
        return ClubPostDiscussionReader(target: target, context: context)
    }
    private func row(_ id: Int = 501, post: Int = 91) -> [String: Any] {
        ["id": id, "postId": post, "memberId": 702, "nickname": "Synthetic author", "content": "Synthetic comment"]
    }
    func testReadsExactPostAndPageThroughExistingReadOnlyService() async throws {
        let transport = Transport(), owner = Owner(), model = try make(transport, owner)
        let task = Task { await model.load(page: 2, isCurrent: { owner.current }) }
        await transport.waitForRequests(1)
        let requests = await transport.requests, request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.path, "/api/club/post/comment/list"); XCTAssertEqual(request.httpMethod, "POST")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Int])
        XCTAssertEqual(body, ["postId": 91, "pageNum": 2, "pageSize": 50])
        try await transport.reply(0, rows: [row()]); await task.value
        XCTAssertEqual(model.phase, .ready); XCTAssertEqual(model.page, 2); XCTAssertEqual(model.comments.map(\.id), [501])
    }
    func testSuccessfulEmptyIsReadyAndFailureIsNotEmptySuccess() async throws {
        let transport = Transport(), owner = Owner(), model = try make(transport, owner)
        let empty = Task { await model.load(page: 1, isCurrent: { owner.current }) }
        await transport.waitForRequests(1); try await transport.reply(0, rows: []); await empty.value
        XCTAssertEqual(model.phase, .ready); XCTAssertTrue(model.comments.isEmpty)
        let failure = Task { await model.load(page: 1, isCurrent: { owner.current }) }
        await transport.waitForRequests(2); try await transport.reply(1, rows: [], status: 503); await failure.value
        XCTAssertEqual(model.phase, .failed); XCTAssertFalse(model.hasNext)
    }
    func testWrongPostAndDuplicateCommentIDsFailClosed() async throws {
        for rows in [[row(post: 92)], [row(), row()]] {
            let transport = Transport(), owner = Owner(), model = try make(transport, owner)
            let task = Task { await model.load(page: 1, isCurrent: { owner.current }) }
            await transport.waitForRequests(1); try await transport.reply(0, rows: rows); await task.value
            XCTAssertEqual(model.phase, .failed); XCTAssertTrue(model.comments.isEmpty)
        }
    }
    func testNoRequestWhenSourceAlreadyClosedOrIdentityChanged() async throws {
        let transport = Transport(), owner = Owner(), model = try make(transport, owner)
        owner.current = false; await model.load(page: 1, isCurrent: { owner.current })
        owner.current = true; owner.session = try .init(identity: .init(accountID: 702, epoch: 2), token: "synthetic-second")
        await model.load(page: 1, isCurrent: { owner.current })
        let count = await transport.requests.count; XCTAssertEqual(count, 0)
    }
    func testLateResponseAfterSourceSwitchOrRoleChangeCannotPublish() async throws {
        let transport = Transport(), owner = Owner(), model = try make(transport, owner)
        let task = Task { await model.load(page: 1, isCurrent: { owner.current }) }
        await transport.waitForRequests(1); owner.current = false
        try await transport.reply(0, rows: [row()]); await task.value
        XCTAssertTrue(model.comments.isEmpty); XCTAssertNotEqual(model.phase, .ready)
    }
    func testLateResponseAfterLogoutCannotPublish() async throws {
        let transport = Transport(), owner = Owner(), model = try make(transport, owner)
        let task = Task { await model.load(page: 1, isCurrent: { owner.current }) }
        await transport.waitForRequests(1); owner.session = try .init(identity: .init(accountID: nil, epoch: 2), token: nil)
        try await transport.reply(0, rows: [row()]); await task.value
        XCTAssertTrue(model.comments.isEmpty); XCTAssertNotEqual(model.phase, .ready)
    }
    func testRefreshLatestWinsWhenOlderPageArrivesLast() async throws {
        let transport = Transport(), owner = Owner(), model = try make(transport, owner)
        let first = Task { await model.load(page: 1, isCurrent: { owner.current }) }
        await transport.waitForRequests(1)
        let next = Task { await model.load(page: 2, isCurrent: { owner.current }) }
        await transport.waitForRequests(2); try await transport.reply(1, rows: [row(502)]); await next.value
        try await transport.reply(0, rows: [row(501)]); await first.value
        XCTAssertEqual(model.comments.map(\.id), [502]); XCTAssertEqual(model.page, 2); XCTAssertEqual(model.phase, .ready)
    }
    func testInvalidateCloseRetiresPendingRequestWithoutSharedCoordinator() async throws {
        let transport = Transport(), owner = Owner(), model = try make(transport, owner)
        let task = Task { await model.load(page: 1, isCurrent: { owner.current }) }
        await transport.waitForRequests(1); model.invalidate()
        try await transport.reply(0, rows: [row()]); await task.value
        XCTAssertEqual(model.phase, .idle); XCTAssertTrue(model.comments.isEmpty)
    }
    func testRetryUsesSameFailedPageAndRestoresRead() async throws {
        let transport = Transport(), owner = Owner(), model = try make(transport, owner)
        let first = Task { await model.load(page: 3, isCurrent: { owner.current }) }
        await transport.waitForRequests(1); try await transport.reply(0, rows: [], status: 503); await first.value
        let retry = Task { await model.load(page: model.page, isCurrent: { owner.current }) }
        await transport.waitForRequests(2); try await transport.reply(1, rows: [row()]); await retry.value
        XCTAssertEqual(model.page, 3); XCTAssertEqual(model.phase, .ready)
    }
    func testNextPageAvailabilityUsesAcceptedPageSize() async throws {
        let transport = Transport(), owner = Owner(), model = try make(transport, owner)
        let task = Task { await model.load(page: 1, isCurrent: { owner.current }) }
        await transport.waitForRequests(1); try await transport.reply(0, rows: (1...50).map { row($0) }); await task.value
        XCTAssertTrue(model.hasNext)
        let next = Task { await model.load(page: 2, isCurrent: { owner.current }) }
        await transport.waitForRequests(2); try await transport.reply(1, rows: []); await next.value
        XCTAssertFalse(model.hasNext); XCTAssertTrue(model.comments.isEmpty); XCTAssertEqual(model.phase, .ready)
    }
}
