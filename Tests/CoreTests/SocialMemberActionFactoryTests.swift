import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor private final class MemberActionFixture {
    let api = try! APIConfiguration(baseURL: URL(string: "https://example.com/member-actions/")!)
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    var context: RuntimeDependencyContext?
    var followed = false
    var mutateProfileOnRead: Int?
    var profileReads = 0
    var readbackFails = false
    var wrongConversation = false
    var writeError = false
    var writeCode = 200
    var onWrite: (() async -> Void)?
    var onRead: (() async -> Void)?
    var onReadback: (() async -> Void)?
    var journal: OperationDefaultsJournal
    let defaults: UserDefaults
    let suite: String
    lazy var transport: MemberActionTransport = MemberActionTransport { [unowned self] request in
        let path = request.url!.path
        if path.hasSuffix("public-info") {
            self.profileReads += 1
            if self.mutateProfileOnRead == self.profileReads { self.followed.toggle() }
            await self.onRead?()
            if self.transport.writes > 0 { await self.onReadback?() }
            if self.readbackFails && self.transport.writes > 0 { throw URLError(.timedOut) }
            return (Data("{\"code\":200,\"data\":{\"id\":82,\"nickname\":\"Member\",\"isFollow\":\(self.followed ? 1 : 0)}}".utf8), 200)
        }
        if path.hasSuffix("conversations") {
            await self.onReadback?()
            if self.readbackFails { throw URLError(.timedOut) }
            let member = self.wrongConversation ? 83 : 82
            return (Data("{\"code\":200,\"data\":[{\"conversationId\":91,\"type\":1,\"counterparty\":{\"id\":\(member)}}]}".utf8), 200)
        }
        self.transport.writes += 1
        await self.onWrite?()
        if self.writeError { throw URLError(.timedOut) }
        if self.writeCode != 200 { return (Data("{\"code\":\(self.writeCode)}".utf8), 200) }
        if path.hasSuffix("follow/action") {
            self.followed = !self.followed
            return (Data("{\"code\":200,\"msg\":\"\(self.followed ? "关注成功" : "取消关注成功")\"}".utf8), 200)
        }
        return (Data(#"{"code":200,"data":{"conversationId":91}}"#.utf8), 200)
    }
    var identity: SocialAccountIdentity { .init(accountID: context?.session.accountID, epoch: context?.session.epoch ?? 0, role: context?.role) }
    init() throws {
        let name = "SocialMemberActionFactoryTests.\(UUID().uuidString)"
        suite = name
        defaults = UserDefaults(suiteName: name)!
        journal = OperationDefaultsJournal(defaults: defaults)
        context = RuntimeDependencyContext(market: .china, baseURL: api.baseURL, role: "player",
            session: try PlayExperienceSession(accountID: 81, epoch: 1, namespace: "approved-cn", token: "test-token"))
    }
    func clean() { defaults.removePersistentDomain(forName: suite) }
    func grant(_ operation: SocialMemberActionOperation = .follow, member: Int = 82, expires: Date? = nil) throws -> SocialMemberActionApproval {
        try .init(endpoint: OperationEndpointApproval(baseURL: api.baseURL, namespace: "approved-cn", accountID: 81, paths: operation.paths),
                  identity: identity, market: .china, operation: operation, memberID: member, expiresAt: expires ?? date.addingTimeInterval(100))
    }
    func access(_ grants: [SocialMemberActionApproval]) -> any SocialActionAccess {
        let account = SocialAccountSessionReader(service: nil, currentSession: { [unowned self] in
            guard let c = self.context else { return .init(guestEpoch: 0) }
            return try! .init(accountID: c.session.accountID, epoch: c.session.epoch, role: c.role, token: c.session.token)
        })
        return SocialMemberActionFactory.make(configuration: api, approvals: grants, transport: transport, journal: journal,
            reader: SquareSessionReader(service: nil, currentSession: { nil }), accountReader: account,
            current: { [unowned self] in self.context }, now: { [unowned self] in self.date })
    }
    func review(_ c: SocialActionCoordinator, command: SocialActionCommand = .toggleFollow) async throws -> SocialActionReview {
        try await c.prepare(command, target: .member(82), ownerID: UUID(), expectedIdentity: identity)
    }
}
@MainActor private final class MemberActionTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var writes = 0
    let operation: (URLRequest) async throws -> (Data, Int)
    init(operation: @escaping (URLRequest) async throws -> (Data, Int)) { self.operation = operation }
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return try await operation(request) }
}
@MainActor final class SocialMemberActionFactoryTests: XCTestCase {
    func testNormalFactoryDefaultOffAndOneActionCannotGrantAnotherOrSquare() throws {
        let f = try MemberActionFixture(); defer { f.clean() }
        XCTAssertEqual(f.access([]).availability, .disabled)
        let access = f.access([try f.grant()])
        XCTAssertEqual(access.availability(for: .toggleFollow, target: .member(82)), .approved)
        XCTAssertEqual(access.availability(for: .toggleFollow, target: .member(83)), .disabled)
        XCTAssertEqual(access.availability(for: .startChat, target: .member(82)), .disabled)
        for command in [SocialActionCommand.communityComment(text: "hello", requestID: "abcdefghijklmnop"), .communityCommentLike(enabled: true, requestID: "abcdefghijklmnop"), .legacyPostLike, .legacyPostReport(reason: "spam"), .report, .comment(text: "hello"), .toggleCommentLike, .editPost(text: "hello"), .newPost(text: "hello"), .action(.like, enabled: true)] {
            XCTAssertEqual(access.availability(for: command, target: .post(82)), .disabled)
        }
        XCTAssertTrue(f.transport.requests.isEmpty)
    }
    func testNormalFactoryFollowUsesExactReviewedDesiredStateAndFreshReadback() async throws {
        let f = try MemberActionFixture(); defer { f.clean() }
        let c = SocialActionCoordinator(access: f.access([try f.grant()]))
        let review = try await f.review(c)
        await c.confirm(review)
        guard case .acknowledged(let receipt) = c.state(target: .member(82)) else { return XCTFail() }
        XCTAssertFalse(receipt.synthetic); XCTAssertEqual(receipt.followed, true)
        XCTAssertEqual(f.transport.writes, 1); XCTAssertEqual(f.profileReads, 4)
        let write = try XCTUnwrap(f.transport.requests.first { $0.url?.path.hasSuffix("follow/action") == true })
        let body = String(data: write.httpBody!, encoding: .utf8)!
        XCTAssertTrue(body.contains("name=\"follow_member_id\"\r\n\r\n82"))
        XCTAssertTrue(body.contains("name=\"follow\"\r\n\r\n1"))
        XCTAssertEqual(write.value(forHTTPHeaderField: "Authorization"), "test-token")
        await c.confirm(review); XCTAssertEqual(f.transport.writes, 1)
    }
    func testUnfollowFreezesZeroRatherThanLegacyToggle() async throws {
        let f = try MemberActionFixture(); defer { f.clean() }; f.followed = true
        let c = SocialActionCoordinator(access: f.access([try f.grant()]))
        await c.confirm(try await f.review(c))
        let write = try XCTUnwrap(f.transport.requests.first { $0.url?.path.hasSuffix("follow/action") == true })
        XCTAssertTrue(String(data: write.httpBody!, encoding: .utf8)!.contains("name=\"follow\"\r\n\r\n0"))
    }
    func testStartRequiresCurrentDirectConversationForExactCounterparty() async throws {
        for wrong in [false, true] {
            let f = try MemberActionFixture(); defer { f.clean() }; f.wrongConversation = wrong
            let c = SocialActionCoordinator(access: f.access([try f.grant(.startChat)]))
            await c.confirm(try await f.review(c, command: .startChat))
            if wrong { XCTAssertEqual(c.state(target: .member(82)), .outcomeUnknown) }
            else { guard case .acknowledged(let receipt) = c.state(target: .member(82)) else { return XCTFail() }; XCTAssertEqual(receipt.conversationID, 91) }
            XCTAssertEqual(f.transport.writes, 1)
            XCTAssertEqual(f.transport.requests.last?.url?.path, "/member-actions/api/im/conversations")
        }
    }
    func testChangedReviewedFollowStateFailsBeforeDispatch() async throws {
        let f = try MemberActionFixture(); defer { f.clean() }; f.mutateProfileOnRead = 2
        let c = SocialActionCoordinator(access: f.access([try f.grant()]))
        await c.confirm(try await f.review(c))
        XCTAssertEqual(c.state(target: .member(82)), .notSent); XCTAssertEqual(f.transport.writes, 0)
    }
    func testUnknownWritePersistsAcrossNewFactoryJournalAndReloginWithoutReplay() async throws {
        let f = try MemberActionFixture(); defer { f.clean() }; f.writeError = true
        let c = SocialActionCoordinator(access: f.access([try f.grant()]))
        await c.confirm(try await f.review(c)); XCTAssertEqual(c.state(target: .member(82)), .outcomeUnknown)
        f.journal = OperationDefaultsJournal(defaults: f.defaults)
        let old = f.context!
        f.context = .init(market: old.market, baseURL: old.baseURL, role: "merchant",
            session: try .init(accountID: 81, epoch: 2, namespace: "approved-cn", token: "new-token"))
        let replacement = SocialActionCoordinator(access: f.access([try f.grant()]))
        XCTAssertEqual(replacement.state(target: .member(82)), .outcomeUnknown)
        do { _ = try await f.review(replacement); XCTFail() } catch { XCTAssertEqual(error as? SocialActionBlock, .pending) }
        XCTAssertEqual(f.transport.writes, 1)
    }
    func testAcknowledgementWithoutReadbackAndServerErrorRetainReplayLock() async throws {
        for code in [200, 500] {
            let f = try MemberActionFixture(); defer { f.clean() }; f.readbackFails = true; f.writeCode = code
            let access = f.access([try f.grant()]); let c = SocialActionCoordinator(access: access)
            await c.confirm(try await f.review(c))
            XCTAssertEqual(c.state(target: .member(82)), .outcomeUnknown)
            XCTAssertTrue(access.hasPending(target: .member(82))); XCTAssertEqual(f.transport.writes, 1)
        }
    }
    func testLeaveDuringPreflightSendsNothingAndDuringWriteRetainsUnknown() async throws {
        for duringWrite in [false, true] {
            let f = try MemberActionFixture(); defer { f.clean() }
            let c = SocialActionCoordinator(access: f.access([try f.grant()]))
            let review = try await f.review(c)
            let leave = { c.leaveScreen(target: review.target, expectedIdentity: review.identity, ownerID: review.ownerID) }
            if duringWrite { f.onWrite = leave }
            else { f.onRead = leave }
            await c.confirm(review)
            XCTAssertEqual(f.transport.writes, duringWrite ? 1 : 0)
            if duringWrite { XCTAssertEqual(c.state(target: .member(82)), .outcomeUnknown) }
        }
    }
    func testTokenChangeAfterDispatchCannotAcknowledgeOrReadWithNewCredential() async throws {
        let f = try MemberActionFixture(); defer { f.clean() }
        let grant = try f.grant(), old = f.context!
        let c = SocialActionCoordinator(access: f.access([grant]))
        let review = try await f.review(c)
        f.onWrite = { f.context = .init(market: old.market, baseURL: old.baseURL, role: old.role,
            session: try! .init(accountID: 81, epoch: 1, namespace: "approved-cn", token: "replacement")) }
        await c.confirm(review)
        XCTAssertEqual(c.state(target: .member(82)), .outcomeUnknown)
        XCTAssertEqual(f.profileReads, 3)
        XCTAssertTrue(f.transport.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "test-token" })
    }
    func testTokenChangeBetweenReviewAndConfirmInvalidatesExactReview() async throws {
        let f = try MemberActionFixture(); defer { f.clean() }
        let c = SocialActionCoordinator(access: f.access([try f.grant()]))
        let review = try await f.review(c), old = f.context!
        f.context = .init(market: old.market, baseURL: old.baseURL, role: old.role,
            session: try .init(accountID: 81, epoch: 1, namespace: "approved-cn", token: "replacement"))
        await c.confirm(review)
        XCTAssertEqual(c.state(target: .member(82)), .notSent); XCTAssertEqual(f.transport.writes, 0)
    }
    func testCancellationBeforeConfirmationNeverSends() async throws {
        let f = try MemberActionFixture(); defer { f.clean() }
        let c = SocialActionCoordinator(access: f.access([try f.grant()]))
        let review = try await f.review(c)
        let task = Task { await Task.yield(); await c.confirm(review) }
        task.cancel(); await task.value
        XCTAssertEqual(f.transport.writes, 0)
    }
    func testRoleOrNamespaceChangeDuringFinalReadbackNeverAcknowledges() async throws {
        for operation in SocialMemberActionOperation.allCases {
            for changeRole in [true, false] {
                let f = try MemberActionFixture(); defer { f.clean() }
                let old = f.context!, grant = try f.grant(operation)
                let access = f.access([grant]), c = SocialActionCoordinator(access: access)
                let review = try await f.review(c, command: operation == .follow ? .toggleFollow : .startChat)
                f.onReadback = {
                    f.context = .init(market: old.market, baseURL: old.baseURL, role: changeRole ? "merchant" : old.role,
                        session: try! .init(accountID: 81, epoch: 1, namespace: changeRole ? "approved-cn" : "replacement", token: "test-token"))
                }
                await c.confirm(review)
                XCTAssertEqual(c.state(target: .member(82)), .outcomeUnknown)
                XCTAssertEqual(f.transport.writes, 1)
                // Return to the old namespace solely to inspect its durable unknown lock.
                f.context = old
                XCTAssertTrue(access.hasPending(target: .member(82)))
            }
        }
    }
    func testWrongScopeExpiredAndDuplicateGrantsCannotDispatch() throws {
        let f = try MemberActionFixture(); defer { f.clean() }
        let grant = try f.grant()
        XCTAssertEqual(f.access([try f.grant(expires: f.date)]).availability, .disabled)
        XCTAssertEqual(f.access([grant, grant]).availability(for: .toggleFollow, target: .member(82)), .disabled)
        let old = f.context!
        for (market, origin, namespace, role, epoch) in [(RegionalMarket.unitedStates, old.baseURL, "approved-cn", "player", UInt64(1)),
            (.china, URL(string: "https://other.example.com/")!, "approved-cn", "player", 1),
            (.china, old.baseURL, "other", "player", 1), (.china, old.baseURL, "approved-cn", "merchant", 1),
            (.china, old.baseURL, "approved-cn", "player", 2)] {
            f.context = .init(market: market, baseURL: origin, role: role,
                session: try .init(accountID: 81, epoch: epoch, namespace: namespace, token: "test-token"))
            XCTAssertEqual(f.access([grant]).availability, .disabled)
        }
        XCTAssertTrue(f.transport.requests.isEmpty)
    }
    func testExtraPathsAndSelfTargetCannotConstructGrant() throws {
        let f = try MemberActionFixture(); defer { f.clean() }
        let endpoint = try OperationEndpointApproval(baseURL: f.api.baseURL, namespace: "approved-cn", accountID: 81,
            paths: SocialMemberActionOperation.follow.paths.union(["api/comment/add"]))
        XCTAssertThrowsError(try SocialMemberActionApproval(endpoint: endpoint, identity: f.identity, market: .china,
            operation: .follow, memberID: 82, expiresAt: f.date))
        XCTAssertThrowsError(try f.grant(member: 81))
    }
}
