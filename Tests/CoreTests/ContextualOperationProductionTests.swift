import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class ContextualOperationProductionTests: XCTestCase {
    private let url = URL(string: "https://example.com/fixture/")!
    private func journal() throws -> OperationDefaultsJournal {
        let suite = "contextual-production-tests-" + UUID().uuidString
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        return OperationDefaultsJournal(defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
    }
    private func context(account: Int = 7, epoch: UInt64 = 1, role: String = "club", namespace: String = "fixture-cn", token: String = "fixture-token", market: RegionalMarket = .china, base: URL? = nil) throws -> RuntimeDependencyContext {
        .init(market: market, baseURL: base ?? url, role: role,
              session: try .init(accountID: account, epoch: epoch, namespace: namespace, token: token))
    }
    private func endpoints(_ paths: Set<String>) throws -> OperationEndpointApproval {
        try .init(baseURL: url, namespace: "fixture-cn", accountID: 7, paths: paths)
    }
    private let clubPaths: Set<String> = ["api/activity/info", "api/club/lead/team-progress", "api/club/lead/edit-ops"]
    private let reviewPaths: Set<String> = ["api/activity/info", "api/topic/info-to-user", "api/comment/add"]
    private func timeApproval(paths: Set<String>? = nil) throws -> ClubOpsTimeApproval {
        try .init(market: .china, endpoints: endpoints(paths ?? clubPaths), targets: [.init(activityID: 8, clubID: 4)])
    }
    private func reviewApproval(paths: Set<String>? = nil, targets: Set<ContextualReviewTarget> = [.topic(8), .activity(8)]) throws -> ContextualReviewApproval {
        try .init(market: .china, endpoints: endpoints(paths ?? reviewPaths), targets: targets)
    }
    private func time(_ wire: ContextualProductionWire, approval: ClubOpsTimeApproval? = nil, current: @escaping () -> RuntimeDependencyContext?) throws -> ClubOpsTimeConfiguredService {
        .init(configuration: try .init(baseURL: url), approval: approval, transport: wire, current: current)
    }
    private func reviews(_ wire: ContextualProductionWire, approval: ContextualReviewApproval? = nil, current: @escaping () -> RuntimeDependencyContext?) throws -> ContextualReviewConfiguredWriter {
        .init(configuration: try .init(baseURL: url), approval: approval, transport: wire, current: current)
    }
    private func timeRequest(id: Int = 8) throws -> ClubOpsTimeRequest { try .init(activityID: id, startDate: "2026-10-03 14:30:00") }
    private let draft = ContextualReviewDraft(rating: 4, contents: " Experience ")

    func testNormalConfiguredWrappersDefaultOffWithZeroRequests() async throws {
        let c = try context(), wire = ContextualProductionWire(), time = try time(wire, current: { c }), review = try reviews(wire, current: { c })
        XCTAssertFalse(time.isConfigured); XCTAssertFalse(review.isConfigured)
        let owner = ClubOpsTimeHost(service: time, journal: try journal()).coordinator(activityID: 8)
        await owner.save(try timeRequest(), expected: try XCTUnwrap(time.session))
        let reviewer = ContextualReviewHost(writer: review, journal: try journal()).coordinator(.topic(8))
        await reviewer.submit(draft, expected: try XCTUnwrap(review.session))
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testEveryReadAndWritePathRequiresIndependentApproval() throws {
        let c = try context(), target = try ClubOpsTimeTarget(activityID: 8, clubID: 4)
        for missing in clubPaths { XCTAssertFalse(try timeApproval(paths: clubPaths.subtracting([missing])).permits(target, context: c)) }
        for missing in ["api/comment/add", "api/topic/info-to-user"] {
            XCTAssertFalse(try reviewApproval(paths: reviewPaths.subtracting([missing])).permits(.topic(8), context: c))
        }
        let topicOnly = try reviewApproval(targets: [.topic(8)])
        XCTAssertFalse(topicOnly.permits(.activity(8), context: c)); XCTAssertFalse(topicOnly.permits(.topic(9), context: c))
        XCTAssertFalse(try timeApproval().permits(.init(activityID: 8, clubID: 5), context: c))
        XCTAssertThrowsError(try ClubOpsTimeApproval(market: .china, endpoints: endpoints(clubPaths), targets: [.init(activityID: 8, clubID: 4), .init(activityID: 8, clubID: 5)]))
    }
    func testMarketNamespaceAccountAndDeploymentMismatchCannotDispatch() async throws {
        let contexts = try [context(account: 9), context(namespace: "other"), context(market: .unitedStates), context(base: URL(string: "https://elsewhere.example/")!)]
        for c in contexts {
            let wire = ContextualProductionWire(), time = try time(wire, approval: timeApproval(), current: { c }), review = try reviews(wire, approval: reviewApproval(), current: { c })
            XCTAssertFalse(time.isConfigured); XCTAssertFalse(review.isConfigured)
            let owner = ClubOpsTimeHost(service: time, journal: try journal()).coordinator(activityID: 8)
            await owner.save(try timeRequest(), expected: try XCTUnwrap(time.session))
            let reviewer = ContextualReviewHost(writer: review, journal: try journal()).coordinator(.topic(8))
            await reviewer.submit(draft, expected: try XCTUnwrap(review.session))
            XCTAssertTrue(wire.requests.isEmpty)
        }
    }
    func testDirectWriterOrCoordinatorWithoutJournalCannotDispatch() async throws {
        let c = try context(), wire = ContextualProductionWire(), time = try time(wire, approval: timeApproval(), current: { c }), review = try reviews(wire, approval: reviewApproval(), current: { c })
        do { try await time.save(timeRequest(), session: XCTUnwrap(time.session)); XCTFail() } catch { XCTAssertEqual(error as? ClubOpsTimeFailure, .disabled) }
        do { try await review.submit(draft, target: .topic(8), session: XCTUnwrap(review.session)); XCTFail() } catch { XCTAssertEqual(error as? ContextualReviewFailure, .notSent) }
        let owner = ClubOpsTimeHost(service: time).coordinator(activityID: 8)
        await owner.save(try timeRequest(), expected: try XCTUnwrap(time.session))
        let reviewer = ContextualReviewHost(writer: review).coordinator(.topic(8))
        await reviewer.submit(draft, expected: try XCTUnwrap(review.session))
        XCTAssertFalse(owner.canSave); XCTAssertFalse(reviewer.canSubmit); XCTAssertTrue(wire.requests.isEmpty)
    }
    func testClubTimeUsesFreshSoldLockLeaderAndExactJSONThenReadback() async throws {
        let c = try context(), wire = ContextualProductionWire(), service = try time(wire, approval: timeApproval(), current: { c })
        let owner = ClubOpsTimeHost(service: service, journal: try journal()).coordinator(activityID: 8)
        await owner.save(try timeRequest(), expected: try XCTUnwrap(service.session))
        XCTAssertEqual(owner.state, .acknowledged); XCTAssertEqual(wire.requests.count, 3)
        XCTAssertEqual(wire.requests[1].httpMethod, "GET")
        XCTAssertEqual(wire.requests[1].url?.query, "activityId=8")
        let body = try JSONDecoder().decode(ClubGovernanceValue.self, from: XCTUnwrap(wire.requests.last?.httpBody))
        XCTAssertEqual(body, .object(["activityId": .integer(8), "startDate": .string("2026-10-03 14:30:00")]))
        XCTAssertEqual(wire.requests.last?.value(forHTTPHeaderField: "Authorization"), "fixture-token")
        let result = try await service.read(activityID: 8, session: XCTUnwrap(service.session))
        XCTAssertEqual(result, "2026-10-03 14:30:00"); XCTAssertEqual(wire.requests.count, 4)
    }
    func testSoldMissingLockWrongClubAndGateNeverReachMutation() async throws {
        for data in [#"{"id":8,"clubId":4,"startDate":"2026-10-03 14:30:00","timeLocationLocked":true}"#,
                     #"{"id":8,"clubId":4,"startDate":"2026-10-03 14:30:00"}"#,
                     #"{"id":8,"clubId":5,"startDate":"2026-10-03 14:30:00","timeLocationLocked":false}"#,
                     #"{"id":9,"clubId":4,"startDate":"2026-10-03 14:30:00","timeLocationLocked":false}"#,
                     #"{"gate":true,"clubId":4}"#] {
            let c = try context(), wire = ContextualProductionWire(); wire.detail = data
            let service = try time(wire, approval: timeApproval(), current: { c }), owner = ClubOpsTimeHost(service: service, journal: try journal()).coordinator(activityID: 8)
            await owner.save(try timeRequest(), expected: try XCTUnwrap(service.session))
            XCTAssertEqual(wire.requests.count, 1); XCTAssertEqual(wire.writes, 0); XCTAssertNotEqual(owner.state, .unknown)
        }
    }
    func testCurrentLeaderMustMatchAccountAndPositiveServerProof() async throws {
        for leader in [#"{"exists":true,"isLeader":true,"leaderMemberId":9}"#,
                       #"{"exists":true,"isLeader":false,"leaderMemberId":7}"#,
                       #"{"exists":false}"#, #"{"exists":true,"leaderMemberId":7}"#] {
            let c = try context(), wire = ContextualProductionWire(); wire.leader = leader
            let service = try time(wire, approval: timeApproval(), current: { c }), owner = ClubOpsTimeHost(service: service, journal: try journal()).coordinator(activityID: 8)
            await owner.save(try timeRequest(), expected: try XCTUnwrap(service.session))
            XCTAssertEqual(owner.state, .rejected); XCTAssertEqual(wire.requests.count, 2); XCTAssertEqual(wire.writes, 0)
        }
    }
    func testOldReviewSnapshotRejectsRoleEpochTokenOrNamespaceChange() async throws {
        let changes = try [context(role: "user"), context(epoch: 2), context(token: "replacement"), context(namespace: "other")]
        for changed in changes {
            var c = try context(); let wire = ContextualProductionWire()
            let service = try time(wire, approval: timeApproval(), current: { c }), writer = try reviews(wire, approval: reviewApproval(), current: { c })
            let oldTime = try XCTUnwrap(service.session), oldReview = try XCTUnwrap(writer.session)
            let owner = ClubOpsTimeHost(service: service, journal: try journal()).coordinator(activityID: 8), reviewer = ContextualReviewHost(writer: writer, journal: try journal()).coordinator(.topic(8))
            c = changed
            await owner.save(try timeRequest(), expected: oldTime); await reviewer.submit(draft, expected: oldReview)
            XCTAssertTrue(wire.requests.isEmpty)
        }
    }
    func testSessionChangeDuringPreflightNeverWritesAndCanRetryFresh() async throws {
        var c = try context(); let replacement = try context(epoch: 2), wire = ContextualProductionWire()
        wire.beforeReply = { _ in c = replacement }
        let writer = try reviews(wire, approval: reviewApproval(), current: { c }), owner = ContextualReviewHost(writer: writer, journal: try journal()).coordinator(.topic(8))
        await owner.submit(draft, expected: try XCTUnwrap(writer.session))
        XCTAssertEqual(owner.state, .notSent); XCTAssertEqual(wire.writes, 0)
        wire.beforeReply = nil
        await owner.submit(draft, expected: try XCTUnwrap(writer.session))
        XCTAssertEqual(owner.state, .acknowledged); XCTAssertEqual(wire.writes, 1)
    }
    func testContextualReviewDomainAndReceiptAreExactWithoutParticipationGate() async throws {
        for target in [ContextualReviewTarget.topic(8), .activity(8)] {
            let c = try context(), wire = ContextualProductionWire(); wire.reviewOwnerType = target.ownerType
            let writer = try reviews(wire, approval: reviewApproval(), current: { c }), store = try journal()
            let owner = ContextualReviewHost(writer: writer, journal: store).coordinator(target)
            await owner.submit(draft, expected: try XCTUnwrap(writer.session))
            XCTAssertEqual(owner.state, .acknowledged); XCTAssertEqual(wire.requests.count, 2)
            XCTAssertEqual(wire.requests[0].url, url.appendingPathComponent(target.detailPath))
            let body = String(decoding: try XCTUnwrap(wire.requests[1].httpBody), as: UTF8.self)
            for (key, value) in try draft.fields(target: target) { XCTAssertTrue(body.contains("name=\"\(key)\"\r\n\r\n\(value)\r\n")) }
            let reopened = ContextualReviewHost(writer: writer, journal: store).coordinator(target)
            XCTAssertEqual(reopened.state, .acknowledged)
            await reopened.submit(draft, expected: try XCTUnwrap(writer.session)); XCTAssertEqual(wire.writes, 1)
        }
    }
    func testWrongMissingOrInaccessibleReviewTargetCannotWrite() async throws {
        for data in [#"{"id":9,"name":"Other"}"#, #"{"id":8,"name":""}"#, #"{"gate":true,"clubId":4}"#] {
            let c = try context(), wire = ContextualProductionWire(); wire.detail = data
            let writer = try reviews(wire, approval: reviewApproval(), current: { c }), owner = ContextualReviewHost(writer: writer, journal: try journal()).coordinator(.topic(8))
            await owner.submit(draft, expected: try XCTUnwrap(writer.session))
            XCTAssertEqual(owner.state, .notSent); XCTAssertEqual(wire.writes, 0)
        }
    }
    func testBareOrMismatchedReceiptIsUnknownAndDurablyLocked() async throws {
        for receipt in [#"{"code":200}"#, #"{"code":200,"data":{"id":3,"memberId":7,"ownerType":2,"ownerId":8,"replyId":0,"rating":4,"contents":"Experience"}}"#,
                        #"{"code":200,"data":{"id":3,"memberId":9,"ownerType":1,"ownerId":8,"replyId":0,"rating":4,"contents":"Experience"}}"#] {
            let c = try context(), wire = ContextualProductionWire(); wire.writeReply = receipt
            let writer = try reviews(wire, approval: reviewApproval(), current: { c }), store = try journal()
            let owner = ContextualReviewHost(writer: writer, journal: store).coordinator(.topic(8))
            await owner.submit(draft, expected: try XCTUnwrap(writer.session)); XCTAssertEqual(owner.state, .unknown)
            let reopened = ContextualReviewHost(writer: writer, journal: store).coordinator(.topic(8))
            await reopened.submit(draft, expected: try XCTUnwrap(writer.session)); XCTAssertEqual(wire.writes, 1)
            XCTAssertEqual(reopened.state, .unknown)
        }
    }
    func testClubUnknownPersistsAcrossNewHostEpochAndReadback() async throws {
        var c = try context(); let wire = ContextualProductionWire(); wire.failWrite = true
        let service = try time(wire, approval: timeApproval(), current: { c }), store = try journal()
        let owner = ClubOpsTimeHost(service: service, journal: store).coordinator(activityID: 8)
        await owner.save(try timeRequest(), expected: try XCTUnwrap(service.session)); XCTAssertEqual(owner.state, .unknown)
        c = try context(epoch: 2); wire.failWrite = false
        _ = try await service.read(activityID: 8, session: XCTUnwrap(service.session))
        let reopened = ClubOpsTimeHost(service: service, journal: store).coordinator(activityID: 8)
        XCTAssertEqual(reopened.state, .unknown); XCTAssertFalse(reopened.canSave)
        await reopened.save(try timeRequest(), expected: try XCTUnwrap(service.session)); XCTAssertEqual(wire.writes, 1)
    }
    func testCancellationBeforeDispatchIsNotSentButAfterDispatchLocks() async throws {
        for afterDispatch in [false, true] {
            let c = try context(), wire = ContextualProductionWire()
            wire.beforeReply = { request in
                if request.url?.path.hasSuffix("/add") == afterDispatch { withUnsafeCurrentTask { $0?.cancel() } }
            }
            let writer = try reviews(wire, approval: reviewApproval(), current: { c }), owner = ContextualReviewHost(writer: writer, journal: try journal()).coordinator(.topic(8))
            let captured = try XCTUnwrap(writer.session)
            let task = Task { await owner.submit(self.draft, expected: captured) }; await task.value
            XCTAssertEqual(wire.writes, afterDispatch ? 1 : 0)
            XCTAssertEqual(owner.state, afterDispatch ? .unknown : .notSent)
        }
    }
    func testRoleChangeAfterMutationLocksOriginalOwnerWithoutExpiringReplacement() async throws {
        var c = try context(); let replacement = try context(role: "user"), wire = ContextualProductionWire()
        wire.beforeReply = { request in if request.url?.path.hasSuffix("/add") == true { c = replacement } }
        let writer = try reviews(wire, approval: reviewApproval(), current: { c }), store = try journal(), owner = ContextualReviewHost(writer: writer, journal: store).coordinator(.topic(8))
        await owner.submit(draft, expected: try XCTUnwrap(writer.session))
        XCTAssertEqual(owner.state, .unknown); XCTAssertEqual(wire.writes, 1)
        XCTAssertEqual(ContextualReviewHost(writer: writer, journal: store).coordinator(.topic(8)).state, .unknown)
    }
    func testDefinitiveBusinessRejectionAllowsFreshReviewedRetry() async throws {
        let c = try context(), wire = ContextualProductionWire(); wire.writeReply = #"{"code":500}"#
        let writer = try reviews(wire, approval: reviewApproval(), current: { c }), owner = ContextualReviewHost(writer: writer, journal: try journal()).coordinator(.topic(8))
        await owner.submit(draft, expected: try XCTUnwrap(writer.session)); XCTAssertEqual(owner.state, .rejected)
        wire.writeReply = nil; await owner.submit(draft, expected: try XCTUnwrap(writer.session))
        XCTAssertEqual(owner.state, .acknowledged); XCTAssertEqual(wire.writes, 2)
    }
    func testJournalWriteFailurePreventsEveryNetworkRequest() async throws {
        let c = try context(), wire = ContextualProductionWire(), store = ContextualFailingJournal()
        let service = try time(wire, approval: timeApproval(), current: { c }), writer = try reviews(wire, approval: reviewApproval(), current: { c })
        let owner = ClubOpsTimeHost(service: service, journal: store).coordinator(activityID: 8)
        let reviewer = ContextualReviewHost(writer: writer, journal: store).coordinator(.topic(8))
        await owner.save(try timeRequest(), expected: try XCTUnwrap(service.session))
        await reviewer.submit(draft, expected: try XCTUnwrap(writer.session))
        XCTAssertEqual(reviewer.state, .notSent); XCTAssertTrue(wire.requests.isEmpty)
    }
    func testUnauthorizedPreflightExpiresOnlyTheStillMatchingContext() async throws {
        for replaced in [false, true] {
            var c = try context(); let replacement = try context(epoch: 2), wire = ContextualProductionWire()
            var expired: [RuntimeDependencyContext] = []
            wire.readReply = (#"{"code":401}"#, 401)
            if replaced { wire.beforeReply = { _ in c = replacement } }
            let writer = ContextualReviewConfiguredWriter(configuration: try .init(baseURL: url), approval: try reviewApproval(),
                transport: wire, current: { c }, onUnauthorized: { expired.append($0) })
            let owner = ContextualReviewHost(writer: writer, journal: try journal()).coordinator(.topic(8))
            await owner.submit(draft, expected: try XCTUnwrap(writer.session))
            XCTAssertEqual(owner.state, .notSent); XCTAssertEqual(wire.writes, 0)
            XCTAssertEqual(expired.count, replaced ? 0 : 1)
        }
    }
    func testSingleUseAuthorizationBindsCommandOwnerAndPendingRecord() throws {
        let first = try timeRequest(), second = try ClubOpsTimeRequest(activityID: 8, startDate: "2026-10-03 15:30:00")
        let authorization = ContextualOperationAuthorization(command: .clubTime(first), owner: "exact-owner", pending: { true })
        XCTAssertThrowsError(try authorization.validate(.clubTime(second), owner: "exact-owner"))
        XCTAssertThrowsError(try authorization.validate(.clubTime(first), owner: "other"))
        try authorization.consume(.clubTime(first), owner: "exact-owner")
        XCTAssertThrowsError(try authorization.consume(.clubTime(first), owner: "exact-owner"))
        XCTAssertThrowsError(try ContextualOperationAuthorization(command: .clubTime(first), owner: "exact-owner", pending: { false }).consume(.clubTime(first), owner: "exact-owner"))
    }
}

@MainActor private final class ContextualProductionWire: HTTPTransport {
    var requests: [URLRequest] = []
    var writes = 0
    var detail = #"{"id":8,"clubId":4,"name":"Fixture","startDate":"2026-10-03 14:30:00","timeLocationLocked":false}"#
    var leader = #"{"exists":true,"isLeader":true,"leaderMemberId":7}"#
    var reviewOwnerType = 1
    var writeReply: String?
    var readReply: (String, Int)?
    var failWrite = false
    var beforeReply: ((URLRequest) -> Void)?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        let path = request.url?.path ?? ""
        let write = path.hasSuffix("/edit-ops") || path.hasSuffix("/add")
        if write { writes += 1 }
        beforeReply?(request)
        if !write, let readReply { return (Data(readReply.0.utf8), readReply.1) }
        if write, failWrite { throw URLError(.timedOut) }
        if write, let writeReply { return (Data(writeReply.utf8), 200) }
        if path.hasSuffix("/edit-ops") { return (Data(#"{"code":200}"#.utf8), 200) }
        if path.hasSuffix("/add") {
            return (Data("{\"code\":200,\"data\":{\"id\":31,\"memberId\":7,\"ownerType\":\(reviewOwnerType),\"ownerId\":8,\"replyId\":0,\"rating\":4,\"contents\":\"Experience\"}}".utf8), 200)
        }
        let body = path.hasSuffix("/team-progress") ? leader : detail
        return (Data("{\"code\":200,\"data\":\(body)}".utf8), 200)
    }
}

@MainActor private final class ContextualFailingJournal: OperationPendingJournal {
    func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? { nil }
    func write(_ record: OperationPendingRecord) throws { throw APIError.malformedResponse }
    func clear(_ record: OperationPendingRecord) throws { throw APIError.malformedResponse }
}
