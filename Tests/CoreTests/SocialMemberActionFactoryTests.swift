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
    var readError: Error?
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
            if let error = self.readError { throw error }
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
    func owner(approved: @escaping (RuntimeDependencyContext) -> [SocialMemberActionApproval],
               onUnauthorized: @escaping (RuntimeDependencyContext) -> Void = { _ in }) -> SocialMemberActionSessionOwner {
        SocialMemberActionSessionOwner(configuration: api, transport: transport, journal: journal,
            current: { [unowned self] in self.context }, currentIdentity: { [unowned self] in self.identity },
            approvals: approved, onUnauthorized: onUnauthorized, now: { [unowned self] in self.date })
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


@MainActor final class SocialMemberActionSessionOwnerTests: XCTestCase {
    private func context(_ old: RuntimeDependencyContext, account: Int? = nil, epoch: UInt64? = nil,
                         role: String? = nil, token: String? = nil, namespace: String? = nil,
                         baseURL: URL? = nil, market: RegionalMarket? = nil) throws -> RuntimeDependencyContext {
        .init(market: market ?? old.market, baseURL: baseURL ?? old.baseURL, role: role ?? old.role,
              session: try .init(accountID: account ?? old.session.accountID, epoch: epoch ?? old.session.epoch,
                namespace: namespace ?? old.session.namespace, token: token ?? old.session.token))
    }
    private func grant(_ context: RuntimeDependencyContext, operation: SocialMemberActionOperation = .follow) throws -> SocialMemberActionApproval {
        try .init(endpoint: OperationEndpointApproval(baseURL: context.baseURL, namespace: context.session.namespace,
                  accountID: context.session.accountID, paths: operation.paths),
                  identity: .init(accountID: context.session.accountID, epoch: context.session.epoch, role: context.role),
                  market: .china, operation: operation, memberID: 82, expiresAt: Date(timeIntervalSince1970: 1_800_000_100))
    }
    func testReleasedOwnerCannotReviveEscapedReviewInEqualReplacementContext() async throws {
        let f = try MemberActionFixture(); defer { f.clean() }
        let original = f.context!, approved = try grant(original)
        var owner: SocialMemberActionSessionOwner? = f.owner { $0 == original ? [approved] : [] }
        weak var releasedOwner = owner
        let old = owner!.coordinator, oldAccess = owner!.access, review = try await f.review(old)
        owner = nil
        XCTAssertNil(releasedOwner)
        let replacement = f.owner { $0 == original ? [approved] : [] }
        XCTAssertFalse(replacement.coordinator === old)
        XCTAssertEqual(replacement.coordinator.identity, review.identity)
        XCTAssertNil(oldAccess.identity.accountID)
        XCTAssertEqual(oldAccess.availability, .disabled)
        do { _ = try await oldAccess.snapshot(target: .member(82)); XCTFail() }
        catch { XCTAssertEqual(error as? SocialActionBlock, .cancelled) }
        await old.confirm(review)
        XCTAssertEqual(f.transport.writes, 0)
        await replacement.coordinator.confirm(try await f.review(replacement.coordinator))
        guard case .acknowledged = replacement.coordinator.state(target: .member(82)) else { return XCTFail() }
        XCTAssertEqual(f.transport.writes, 1)
    }
    func testReleasedOwnerLateReadbackPreservesExactUnknownRecordInEqualReplacementContext() async throws {
        let f = try MemberActionFixture(); defer { f.clean() }
        let original = f.context!, approved = try grant(original)
        let parts = ["social-member-v1", original.market.rawValue, original.baseURL.absoluteString,
                     original.session.namespace, String(original.session.accountID)]
        let key = parts.map { "\($0.utf8.count):\($0)" }.joined(separator: "|")
        var owner: SocialMemberActionSessionOwner? = f.owner { $0 == original ? [approved] : [] }
        weak var releasedOwner = owner
        let old = owner!.coordinator, review = try await f.review(old)
        var dispatchedRecord: OperationPendingRecord?
        f.onWrite = { dispatchedRecord = try? f.journal.pending(ownerKey: key, targetKey: "member|82") }
        f.onReadback = { owner = nil }
        await old.confirm(review)
        XCTAssertNil(releasedOwner)
        let record = try XCTUnwrap(dispatchedRecord)
        XCTAssertEqual(try f.journal.pending(ownerKey: key, targetKey: "member|82"), record)
        f.onWrite = nil; f.onReadback = nil
        let replacement = f.owner { $0 == original ? [approved] : [] }
        XCTAssertEqual(replacement.coordinator.state(target: .member(82)), .outcomeUnknown)
        // A current ordinary read does not reconcile a receipt or authorize a retry.
        _ = try await replacement.access.snapshot(target: .member(82))
        XCTAssertEqual(try f.journal.pending(ownerKey: key, targetKey: "member|82"), record)
        XCTAssertEqual(replacement.coordinator.state(target: .member(82)), .outcomeUnknown)
        do { _ = try await f.review(replacement.coordinator); XCTFail() }
        catch { XCTAssertEqual(error as? SocialActionBlock, .pending) }
        XCTAssertEqual(f.transport.writes, 1)
    }
    func testObservedRoleABAWithoutCredentialChangeCannotResurrectOldReview() async throws {
        let f = try MemberActionFixture(); defer { f.clean() }
        let original = f.context!, approved = try grant(original)
        let owner = f.owner { $0 == original ? [approved] : [] }
        let old = owner.coordinator, review = try await f.review(old)
        f.context = try context(original, role: "merchant"); owner.synchronizeSession()
        f.context = original; owner.synchronizeSession()
        let replacement = owner.coordinator
        XCTAssertFalse(replacement === old)
        XCTAssertEqual(replacement.identity, review.identity)
        XCTAssertEqual(replacement.availability, .approved)
        XCTAssertNil(old.identity.accountID)
        await old.confirm(review)
        XCTAssertEqual(f.transport.writes, 0)
        await replacement.confirm(try await f.review(replacement))
        guard case .acknowledged = replacement.state(target: .member(82)) else { return XCTFail() }
        XCTAssertEqual(f.transport.writes, 1)
    }
    func testGuestFirstThenLoginRebuildsBothAndCurrentExactActionsStillAcknowledge() async throws {
        let f = try MemberActionFixture(); defer { f.clean() }
        let signedIn = f.context!, approved = try [grant(signedIn), grant(signedIn, operation: .startChat)]
        var selected: [RuntimeDependencyContext] = []
        let owner = f.owner { selected.append($0); return $0 == signedIn ? approved : [] }
        f.context = nil
        let guestAccess = owner.access, guestCoordinator = owner.coordinator
        XCTAssertTrue(selected.isEmpty); XCTAssertEqual(guestAccess.availability, .disabled)
        f.context = signedIn; owner.synchronizeSession()
        let current = owner.coordinator
        XCTAssertFalse(current === guestCoordinator); XCTAssertTrue(current === owner.coordinator)
        XCTAssertTrue(owner.access === owner.access); XCTAssertEqual(selected, [signedIn])
        XCTAssertNil(guestAccess.identity.accountID); XCTAssertEqual(guestAccess.availability, .disabled)
        for command in [SocialActionCommand.toggleFollow, .startChat] {
            let review = try await f.review(current, command: command)
            await current.confirm(review)
            guard case .acknowledged(let receipt) = current.state(target: .member(82)) else { return XCTFail() }
            XCTAssertFalse(receipt.synthetic)
        }
        XCTAssertEqual(f.transport.writes, 2)
    }
    func testEveryContextComponentReplacesPairAndRevokesEscapedAccess() async throws {
        let f = try MemberActionFixture(); defer { f.clean() }
        let original = f.context!, approved = try grant(original)
        let changes = try [context(original, account: 83), context(original, epoch: 2),
            context(original, role: "merchant"), context(original, token: "replacement"),
            context(original, namespace: "other-realm"), context(original, baseURL: URL(string: "https://other.example.test")!),
            context(original, market: .unitedStates)]
        for changed in changes {
            f.context = original
            let owner = f.owner { $0 == original ? [approved] : [] }
            let old = owner.coordinator, oldAccess = owner.access
            f.context = changed; owner.synchronizeSession()
            let current = owner.coordinator
            XCTAssertFalse(current === old); XCTAssertEqual(current.identity, f.identity)
            XCTAssertEqual(current.availability, .disabled)
            XCTAssertNil(old.identity.accountID); XCTAssertEqual(oldAccess.availability, .disabled)
            do { _ = try await oldAccess.snapshot(target: .member(82)); XCTFail() }
            catch { XCTAssertEqual(error as? SocialActionBlock, .cancelled) }
        }
        XCTAssertTrue(f.transport.requests.isEmpty)
    }
    func testEqualContextAfterObservedLogoutNeverReactivatesOldReview() async throws {
        let f = try MemberActionFixture(); defer { f.clean() }
        let original = f.context!, approved = try grant(original)
        let owner = f.owner { $0 == original ? [approved] : [] }
        let old = owner.coordinator, oldAccess = owner.access, review = try await f.review(old)
        f.context = nil; owner.synchronizeSession()
        f.context = original; owner.synchronizeSession()
        let current = owner.coordinator
        XCTAssertFalse(current === old); XCTAssertEqual(oldAccess.availability, .disabled)
        await old.confirm(review)
        XCTAssertEqual(f.transport.writes, 0)
        await current.confirm(try await f.review(current))
        XCTAssertEqual(f.transport.writes, 1)
    }
    func testChangedCredentialWithoutIdentityChangeRequiresNewReviewAndUsesOnlyCurrentToken() async throws {
        let f = try MemberActionFixture(); defer { f.clean() }
        let original = f.context!, updated = try context(original, token: "replacement"), approved = try grant(original)
        let owner = f.owner { $0 == original || $0 == updated ? [approved] : [] }
        let old = owner.coordinator, review = try await f.review(old)
        f.context = updated
        // A retained access detects and permanently revokes itself even before the owner getter.
        XCTAssertEqual(old.availability, .disabled)
        let current = owner.coordinator
        await old.confirm(review); XCTAssertEqual(f.transport.writes, 0)
        await current.confirm(try await f.review(current))
        let writes = f.transport.requests.filter { $0.url?.path.hasSuffix("follow/action") == true }
        XCTAssertEqual(writes.count, 1); XCTAssertEqual(writes.first?.value(forHTTPHeaderField: "Authorization"), "replacement")
    }
    func testCurrentNewAccountAndRoleWorkOnlyWithTheirIndependentlySuppliedGrants() async throws {
        let f = try MemberActionFixture(); defer { f.clean() }
        let original = f.context!, updated = try context(original, account: 83, epoch: 2, role: "merchant", token: "new-account")
        let before = try grant(original), after = try grant(updated)
        let owner = f.owner { $0 == original ? [before] : ($0 == updated ? [after] : []) }
        let old = owner.coordinator
        f.context = updated; owner.synchronizeSession()
        let current = owner.coordinator
        XCTAssertEqual(current.availability(for: .toggleFollow, target: .member(82)), .approved)
        XCTAssertEqual(current.availability(for: .startChat, target: .member(82)), .disabled)
        XCTAssertEqual(current.availability(for: .toggleFollow, target: .member(83)), .disabled)
        XCTAssertEqual(current.availability(for: .legacyPostLike, target: .post(82)), .disabled)
        await current.confirm(try await f.review(current))
        guard case .acknowledged = current.state(target: .member(82)) else { return XCTFail() }
        XCTAssertNil(old.identity.accountID); XCTAssertEqual(f.transport.writes, 1)
    }
    func testDelayedPrepareSuccessAndThrown401CannotPublishIntoReplacementCoordinator() async throws {
        for failure in [false, true] {
            let f = try MemberActionFixture(); defer { f.clean() }
            let original = f.context!, updated = try context(original, epoch: 2, token: "replacement"), approved = try grant(original)
            let owner = f.owner { $0 == original ? [approved] : [] }
            let old = owner.coordinator
            f.onRead = { f.context = updated; owner.synchronizeSession() }
            if failure { f.readError = APIError.unauthorized }
            do { _ = try await f.review(old); XCTFail() }
            catch { XCTAssertEqual(error as? SocialActionBlock, .cancelled) }
            XCTAssertEqual(owner.coordinator.state(target: .member(82)), .idle)
            XCTAssertEqual(f.context, updated); XCTAssertEqual(f.transport.writes, 0)
        }
    }
    func testDelayedFallback401CannotExpireNewSession() async throws {
        let f = try MemberActionFixture(); defer { f.clean() }
        let original = f.context!, updated = try context(original, epoch: 2, token: "replacement")
        var expirations = 0
        let owner = f.owner(approved: { _ in [] }, onUnauthorized: { _ in expirations += 1 })
        let old = owner.access
        f.onRead = { f.context = updated; owner.synchronizeSession() }
        f.readError = APIError.unauthorized
        do { _ = try await old.snapshot(target: .member(82)); XCTFail() }
        catch { XCTAssertEqual(error as? SocialActionBlock, .cancelled) }
        XCTAssertEqual(expirations, 0); XCTAssertEqual(f.context, updated)
        XCTAssertEqual(owner.coordinator.state(target: .member(82)), .idle)
    }
    func testRevokedFallback401CannotExpireEqualRestoredContextButCurrent401StillExpires() async throws {
        let f = try MemberActionFixture(); defer { f.clean() }
        let original = f.context!
        var expirations = 0
        let owner = f.owner(approved: { _ in [] }, onUnauthorized: { _ in expirations += 1 })
        let old = owner.access
        f.onRead = { f.context = nil; owner.synchronizeSession(); f.context = original; owner.synchronizeSession() }
        f.readError = APIError.unauthorized
        do { _ = try await old.snapshot(target: .member(82)); XCTFail() }
        catch { XCTAssertEqual(error as? SocialActionBlock, .cancelled) }
        XCTAssertEqual(expirations, 0)
        f.onRead = nil
        do { _ = try await owner.access.snapshot(target: .member(82)); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        XCTAssertEqual(expirations, 1)
    }
    func testPreflightChangeDispatchesNothingAndCannotAffectFreshState() async throws {
        let f = try MemberActionFixture(); defer { f.clean() }
        let original = f.context!, updated = try context(original, role: "merchant"), approved = try grant(original)
        let owner = f.owner { $0 == original ? [approved] : [] }
        let old = owner.coordinator, review = try await f.review(old)
        f.onRead = { f.context = updated; owner.synchronizeSession() }
        await old.confirm(review)
        XCTAssertEqual(f.transport.writes, 0); XCTAssertEqual(owner.coordinator.state(target: .member(82)), .idle)
    }
    func testLateWriteSuccessAnd401KeepCanonicalUnknownAcrossOwnerReplacementAndRelaunch() async throws {
        for failure in [false, true] {
            let f = try MemberActionFixture(); defer { f.clean() }
            let original = f.context!, updated = try context(original, epoch: 2, role: "merchant", token: "replacement")
            let before = try grant(original), after = try grant(updated)
            let grants: (RuntimeDependencyContext) -> [SocialMemberActionApproval] = { $0 == original ? [before] : ($0 == updated ? [after] : []) }
            let owner = f.owner(approved: grants), old = owner.coordinator, review = try await f.review(old)
            f.onWrite = { f.context = updated; owner.synchronizeSession() }
            if failure { f.writeCode = 401 }
            await old.confirm(review)
            XCTAssertEqual(owner.coordinator.state(target: .member(82)), .outcomeUnknown)
            XCTAssertEqual(f.profileReads, 3); XCTAssertEqual(f.transport.writes, 1)
            f.journal = OperationDefaultsJournal(defaults: f.defaults)
            let relaunched = f.owner(approved: grants)
            XCTAssertEqual(relaunched.coordinator.state(target: .member(82)), .outcomeUnknown)
            do { _ = try await f.review(relaunched.coordinator); XCTFail() }
            catch { XCTAssertEqual(error as? SocialActionBlock, .pending) }
            // Existing owner format is byte-for-byte unchanged and excludes epoch/role/token.
            let parts = ["social-member-v1", original.market.rawValue, original.baseURL.absoluteString,
                         original.session.namespace, String(original.session.accountID)]
            let key = parts.map { "\($0.utf8.count):\($0)" }.joined(separator: "|")
            XCTAssertNotNil(try f.journal.pending(ownerKey: key, targetKey: "member|82"))
            f.context = try context(updated, account: 83)
            XCTAssertFalse(relaunched.access.hasPending(target: .member(82)))
            f.context = try context(updated, namespace: "different-realm")
            XCTAssertFalse(relaunched.access.hasPending(target: .member(82)))
            f.context = updated
            XCTAssertTrue(relaunched.access.hasPending(target: .member(82)))
            XCTAssertEqual(f.transport.writes, 1)
        }
    }
    func testScopedSquareFallbackPreservesGenerationAndDropsRoleChange401() async throws {
        for generation in [SquareContentGeneration.legacySquare, .communityV1] {
            let f = try MemberActionFixture(); defer { f.clean() }
            var change: (() -> Void)?
            var expirations = 0
            let transport = MemberActionTransport { _ in
                if let change { change(); throw APIError.unauthorized }
                let data = generation == .legacySquare ? Data(SquareSyntheticFixtures.legacyPostJSON.utf8) : SquareReportFixtures.postData()
                return (Data("{\"code\":200,\"data\":\(String(data: data, encoding: .utf8)!)}".utf8), 200)
            }
            let owner = SocialMemberActionSessionOwner(configuration: f.api, transport: transport, journal: f.journal,
                current: { f.context }, currentIdentity: { f.identity }, approvals: { _ in [] },
                onUnauthorized: { _ in expirations += 1 })
            let old = owner.access
            let snapshot = try await old.snapshot(target: .post(701), generation: generation)
            XCTAssertEqual(snapshot.post?.generation, generation)
            XCTAssertEqual(transport.requests.first?.url?.path, generation == .legacySquare
                ? "/member-actions/api/creativesquare/info" : "/member-actions/api/v1/community/posts/701")
            let updated = try context(f.context!, role: "merchant")
            change = { f.context = updated; owner.synchronizeSession() }
            do { _ = try await old.snapshot(target: .post(701), generation: generation); XCTFail() }
            catch { XCTAssertEqual(error as? SocialActionBlock, .cancelled) }
            change = nil
            XCTAssertEqual(expirations, 0); XCTAssertEqual(owner.coordinator.identity.role, "merchant")
            XCTAssertEqual(owner.coordinator.availability, .disabled)
        }
    }
    func testRevokedAccessNeverClearsPendingWhenReadbackArrives() async throws {
        let f = try MemberActionFixture(); defer { f.clean() }
        let original = f.context!, approved = try grant(original)
        let owner = f.owner { $0 == original ? [approved] : [] }, old = owner.coordinator
        let review = try await f.review(old)
        f.onReadback = { f.context = nil; owner.synchronizeSession(); f.context = original; owner.synchronizeSession() }
        await old.confirm(review)
        XCTAssertEqual(owner.coordinator.state(target: .member(82)), .outcomeUnknown)
        XCTAssertEqual(f.transport.writes, 1)
    }
}
