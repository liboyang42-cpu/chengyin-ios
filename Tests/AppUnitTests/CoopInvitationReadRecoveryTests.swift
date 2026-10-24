import XCTest
@testable import Questify

@MainActor final class CoopInvitationReadRecoveryTests: XCTestCase {
    @MainActor private final class Reader: CoopFlowReading {
        var session: CoopFlowSession? = try! .init(accountID: 42, epoch: 1, token: "synthetic-token")
        var calls: [CoopFlowRead] = []
        var topicFailure: Error?, targetFailure: Error?
        var topicIDs = [7]
        var candidateIDs = [81]
        var closed = false, holdTopics = false
        var pending: CheckedContinuation<CoopFlowJSON, Error>?
        func topicResponse() -> CoopFlowJSON {
            .object(["rows": .array(topicIDs.map { .object(["id": .id($0), "name": .string("Synthetic topic"), "inviteWindowOpen": .bool(!closed)]) })])
        }
        func read(_ resource: CoopFlowRead) async throws -> CoopFlowJSON {
            calls.append(resource)
            if case .ownedTopics = resource {
                if holdTopics { holdTopics = false; return try await withCheckedThrowingContinuation { pending = $0 } }
                if let topicFailure { throw topicFailure }; return topicResponse()
            }
            if let targetFailure { throw targetFailure }
            return .array(candidateIDs.map { .object(["id": .id($0 + 1000), "memberId": .id($0), "name": .string("Synthetic partner")]) })
        }
        func settlement(source: CoopFlowSettlement.Source, id: Int) async throws -> CoopFlowSettlement { throw APIError.invalidRequest }
    }
    private func loaded(_ r: Reader) async -> CoopInvitationReadModel {
        let m = CoopInvitationReadModel(reader: r, operationScope: "MERCHANT")
        let permit = m.appear(active: true); await m.loadInitial(permit); return m
    }
    private func select(_ m: CoopInvitationReadModel) {
        m.chooseTopic(7, permit: m.permit)
        if let candidate = m.candidates.first { m.toggle(candidate.id, permit: m.permit) }
    }
    func testTopicRetryDoesNotReadTargetsOrClearTheirSelection() async {
        let r = Reader(); r.topicFailure = APIError.httpStatus(503); let m = await loaded(r)
        m.toggle(m.candidates[0].id, permit: m.permit); let selected = m.selected
        r.topicFailure = nil; await m.retryTopics(m.permit)
        XCTAssertEqual(m.selected, selected); XCTAssertFalse(m.topicsFailed)
        XCTAssertEqual(r.calls, [.ownedTopics(kind: .merchant, scope: "MERCHANT", page: 1), .merchants(name: nil), .ownedTopics(kind: .merchant, scope: "MERCHANT", page: 1)])
    }
    func testTargetRetryDoesNotReadTopicsOrClearChosenTopic() async {
        let r = Reader(); r.targetFailure = APIError.httpStatus(503); let m = await loaded(r)
        m.chooseTopic(7, permit: m.permit); r.targetFailure = nil; await m.retryTargets(m.permit)
        XCTAssertEqual(m.topicID, 7); XCTAssertFalse(m.targetsFailed); XCTAssertEqual(r.calls.count, 3)
        XCTAssertEqual(r.calls.last, .merchants(name: nil))
    }
    func testFailedSecondPageRetriesSamePageAndPreservesFirstPageSelection() async {
        let r = Reader(); r.topicIDs = Array(1...20); let m = await loaded(r); select(m)
        r.topicFailure = APIError.httpStatus(503); await m.more(m.permit)
        XCTAssertEqual(m.topics.count, 20); XCTAssertEqual(m.topicID, 7); let selection = m.selected
        r.topicFailure = nil; r.topicIDs = [21]; await m.retryTopics(m.permit)
        XCTAssertEqual(m.topics.count, 21); XCTAssertEqual(m.selected, selection); XCTAssertFalse(m.hasMore)
        XCTAssertEqual(Array(r.calls.suffix(2)), [.ownedTopics(kind: .merchant, scope: "MERCHANT", page: 2), .ownedTopics(kind: .merchant, scope: "MERCHANT", page: 2)])
    }
    func testTransientFailureRetainsCurrentLanesButPermissionClearsAffectedLane() async {
        let r = Reader(), m = await loaded(r); select(m); let selected = m.selected
        r.topicFailure = APIError.httpStatus(503); await m.retryTopics(m.permit)
        XCTAssertEqual(m.topicID, 7); XCTAssertEqual(m.selected, selected); XCTAssertNotNil(m.contexts(permit: m.permit))
        r.topicFailure = CoopFlowFailure.permission; await m.retryTopics(m.permit)
        XCTAssertNil(m.topicID); XCTAssertTrue(m.topics.isEmpty); XCTAssertEqual(m.selected, selected); XCTAssertNil(m.contexts(permit: m.permit))
        r.topicFailure = nil; await m.retryTopics(m.permit); m.chooseTopic(7, permit: m.permit)
        r.targetFailure = CoopFlowFailure.permission; await m.retryTargets(m.permit)
        XCTAssertEqual(m.topicID, 7); XCTAssertTrue(m.selected.isEmpty); XCTAssertTrue(m.candidates.isEmpty)
    }
    func testSuccessfulReReadRemovesMissingSelectionAndRechecksClosedTopic() async {
        let r = Reader(), m = await loaded(r); select(m); XCTAssertNotNil(m.contexts(permit: m.permit))
        r.closed = true; await m.retryTopics(m.permit)
        XCTAssertEqual(m.topicID, 7); XCTAssertNil(m.contexts(permit: m.permit))
        r.candidateIDs = [82]; await m.retryTargets(m.permit); XCTAssertTrue(m.selected.isEmpty)
        r.topicIDs = [8]; await m.retryTopics(m.permit); XCTAssertNil(m.topicID)
    }
    func testKindChangeInvalidatesBothLanesAndOldQueuedCallbacks() async throws {
        let r = Reader(), m = await loaded(r); select(m); let old = m.permit
        let fresh = try XCTUnwrap(m.changeKind(.club, permit: old))
        XCTAssertTrue(m.topics.isEmpty); XCTAssertTrue(m.candidates.isEmpty); XCTAssertTrue(m.selected.isEmpty)
        await m.retryTargets(old); await m.retryTopics(old); m.chooseTopic(7, permit: old)
        XCTAssertEqual(r.calls.count, 2); await m.loadInitial(fresh)
        XCTAssertEqual(Array(r.calls.suffix(2)), [.ownedTopics(kind: .club, scope: "MERCHANT", page: 1), .clubs(name: nil)])
        XCTAssertNil(m.topicID)
    }
    func testAccountChangeCannotReuseOldSelectionOrDelayedRead() async throws {
        let r = Reader(), m = await loaded(r); select(m); let old = m.permit
        r.session = try .init(accountID: 43, epoch: 2, token: "synthetic-other")
        XCTAssertFalse(m.isCurrent); XCTAssertNil(m.contexts(permit: old)); m.identityChanged()
        await m.retryTargets(old); XCTAssertEqual(r.calls.count, 2)
        await m.loadInitial(m.permit); XCTAssertTrue(m.selected.isEmpty); XCTAssertNil(m.topicID)
    }
    func testHiddenForegroundAndOldRetryCannotDispatchUntilRealAppearance() async {
        let r = Reader(), m = await loaded(r); let old = m.permit
        m.disappear(); m.sceneChanged(active: false); m.sceneChanged(active: true)
        await m.loadInitial(m.permit); await m.retryTargets(old); XCTAssertEqual(r.calls.count, 2)
        let fresh = m.appear(active: true); await m.loadInitial(fresh)
        XCTAssertEqual(r.calls.count, 2); XCTAssertTrue(m.isCurrent)
    }
    func testLateTopicReplyCannotReplaceNewKindOrClearItsLoading() async throws {
        let r = Reader(), m = await loaded(r); r.holdTopics = true
        let oldPermit = m.permit; let old = Task { await m.retryTopics(oldPermit) }
        while r.pending == nil { await Task.yield() }
        let continuation = try XCTUnwrap(r.pending); r.pending = nil
        m.disappear(); r.session = try .init(accountID: 44, epoch: 3, token: "synthetic-third")
        m.identityChanged(); let fresh = m.appear(active: true); r.topicIDs = [8]; await m.loadInitial(fresh)
        continuation.resume(returning: .object(["rows": .array([.object(["id": .id(99), "name": .string("Old"), "inviteWindowOpen": .bool(true)])])]))
        await old.value; XCTAssertEqual(m.topics.map(\.id), [8]); XCTAssertFalse(m.busy)
    }
    func testExplicitContextsKeepMerchantOwnerMemberIDAndOriginalScopeWithoutDispatch() async throws {
        let r = Reader(), m = await loaded(r); select(m)
        let context = try XCTUnwrap(m.contexts(permit: m.permit)?.first)
        XCTAssertEqual(context.recipient.id, 81); XCTAssertEqual(context.recipient.domain, .member)
        XCTAssertEqual(context.topicID, 7); XCTAssertEqual(context.scope, "MERCHANT")
        XCTAssertEqual(context.session, r.session); XCTAssertEqual(r.calls.count, 2)
    }
}


extension CoopInvitationReadRecoveryTests {
    private actor HeldUnauthorizedTransport: HTTPTransport {
        var pending: CheckedContinuation<(Data, Int), Error>?
        var started: Bool { pending != nil }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            try await withCheckedThrowingContinuation { pending = $0 }
        }
        func finish() { let held = pending; pending = nil; held?.resume(returning: (Data(), 401)) }
    }
    func testHiddenTopicLateUnauthorizedDoesNotExpireCurrentSessionWithoutTaskCancellation() async throws {
        let wire = HeldUnauthorizedTransport()
        let session = try CoopFlowSession(accountID: 42, epoch: 1, token: "synthetic")
        var expired = 0
        let reader = CoopFlowSessionReader(service: CoopFlowService(configuration: try .init(baseURL: URL(string: "https://example.test")!), transport: wire), current: { session }, unauthorized: { _ in expired += 1 })
        let model = CoopInvitationReadModel(reader: reader, operationScope: "MERCHANT")
        let permit = model.appear(active: true)
        let task = Task { await model.retryTopics(permit) }
        while !(await wire.started) { await Task.yield() }
        model.disappear(); await wire.finish(); await task.value
        XCTAssertFalse(task.isCancelled); XCTAssertEqual(expired, 0)
        XCTAssertTrue(model.topics.isEmpty); XCTAssertFalse(model.topicsBusy)
    }
    func testOldKindTargetLateUnauthorizedDoesNotExpireReplacementLane() async throws {
        let wire = HeldUnauthorizedTransport()
        let session = try CoopFlowSession(accountID: 42, epoch: 1, token: "synthetic")
        var expired = 0
        let reader = CoopFlowSessionReader(service: CoopFlowService(configuration: try .init(baseURL: URL(string: "https://example.test")!), transport: wire), current: { session }, unauthorized: { _ in expired += 1 })
        let model = CoopInvitationReadModel(reader: reader, operationScope: "MERCHANT")
        let permit = model.appear(active: true)
        let task = Task { await model.retryTargets(permit) }
        while !(await wire.started) { await Task.yield() }
        model.disappear(); let returned = model.appear(active: true)
        XCTAssertNotNil(model.changeKind(.club, permit: returned))
        await wire.finish(); await task.value
        XCTAssertFalse(task.isCancelled); XCTAssertEqual(expired, 0)
        XCTAssertEqual(model.kind, .club); XCTAssertFalse(model.targetsBusy)
        XCTAssertTrue(model.candidates.isEmpty)
    }
    func testCurrentUnauthorizedStillExpiresSessionForBothReadLanes() async throws {
        for topics in [true, false] {
            let wire = HeldUnauthorizedTransport()
            let session = try CoopFlowSession(accountID: 42, epoch: 1, token: "synthetic")
            var expired = 0
            let reader = CoopFlowSessionReader(service: CoopFlowService(configuration: try .init(baseURL: URL(string: "https://example.test")!), transport: wire), current: { session }, unauthorized: { _ in expired += 1 })
            let model = CoopInvitationReadModel(reader: reader, operationScope: "MERCHANT")
            let permit = model.appear(active: true)
            let task = Task { if topics { await model.retryTopics(permit) } else { await model.retryTargets(permit) } }
            while !(await wire.started) { await Task.yield() }
            await wire.finish(); await task.value
            XCTAssertEqual(expired, 1)
            XCTAssertTrue(topics ? model.topicsFailed : model.targetsFailed)
        }
    }
}
