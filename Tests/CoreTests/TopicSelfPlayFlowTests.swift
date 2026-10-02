import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class TopicSelfPlayFlowTests: XCTestCase {
    static func topic(price: Int = 0, closed: Bool = false) throws -> TopicDetail {
        try JSONDecoder().decode(TopicDetail.self, from: Data("{\"id\":77,\"name\":\"Synthetic trail\",\"selfPlay\":1,\"selfPlayPrice\":\(price),\"merchantClosed\":\(closed)}".utf8))
    }
    static func order(owner: Int = 77, payment: Int = 1, registration: Int = 2, amount: Int = 0) throws -> OrderLifecycleDetail {
        try JSONDecoder().decode(OrderLifecycleDetail.self, from: Data("{\"id\":701,\"ownerType\":1,\"ownerId\":\(owner),\"paymentStatus\":\(payment),\"registrationStatus\":\(registration),\"payableAmount\":\(amount)}".utf8))
    }
    func testTopicRequestNeverUsesActivityDomainOrInventsQuote() throws {
        let intent = try TopicSelfPlayIntent(topic: XCTUnwrap(SelfPlayTopicID(rawValue: 77)), realName: "Synthetic", phone: "13800000000", requestID: "synthetic-intent")
        let body = try JSONDecoder().decode([String: ProjectEditJSON].self, from: JSONEncoder().encode(intent))
        XCTAssertEqual(body["ownerType"], .number(1)); XCTAssertEqual(body["ownerId"], .number(77))
        XCTAssertEqual(body["payChannel"], .string("APP")); XCTAssertEqual(body["isUsePoint"], .number(0))
        XCTAssertNil(body["topicId"]); XCTAssertNil(body["quoteSign"]); XCTAssertNil(body["ticketId"])
        XCTAssertThrowsError(try JSONDecoder().decode(SelfPlayTopicID.self, from: Data("-1".utf8)))
    }
    func testCancelReviewDoesNotConsentCreateOrJournal() async throws {
        let client = try Client(), journal = Journal(), flow = TopicSelfPlayFlow(topic: try Self.topic(), client: client, journal: journal)
        await flow.open(); fill(flow); XCTAssertTrue(flow.prepare()); flow.cancelReview()
        XCTAssertNil(flow.review); XCTAssertTrue(client.calls.isEmpty); XCTAssertNil(journal.value)
    }
    func testConsentFailurePreventsCreateAndJournal() async throws {
        let client = try Client(); client.failConsent = true
        let journal = Journal(), flow = TopicSelfPlayFlow(topic: try Self.topic(), client: client, journal: journal)
        await flow.open(); fill(flow); flow.prepare(); await flow.confirm(try XCTUnwrap(flow.review))
        XCTAssertEqual(client.calls, ["fresh", "consent"]); XCTAssertNil(journal.value); XCTAssertEqual(flow.phase, .editing)
    }
    func testFreeResponseIsNotSuccessUntilAuthoritativeReadback() async throws {
        let client = try Client(), journal = Journal(), flow = TopicSelfPlayFlow(topic: try Self.topic(), client: client, journal: journal)
        await flow.open(); fill(flow); flow.prepare(); await flow.confirm(try XCTUnwrap(flow.review))
        XCTAssertEqual(client.calls.prefix(3), ["fresh", "consent", "create"])
        XCTAssertEqual(journal.value?.registrationID, 701); XCTAssertEqual(flow.phase, .verifying)
        let result = try XCTUnwrap(flow.result); await result.reconcile()
        XCTAssertEqual(result.phase, .accepted); flow.closeResult(result.phase); XCTAssertEqual(flow.phase, .complete)
    }
    func testUnknownCreateCannotReplayAfterReopen() async throws {
        let client = try Client(); client.failCreate = true
        let journal = Journal(), flow = TopicSelfPlayFlow(topic: try Self.topic(), client: client, journal: journal)
        await flow.open(); fill(flow); flow.prepare(); await flow.confirm(try XCTUnwrap(flow.review))
        let requestID = journal.value?.requestID; flow.leave(); await flow.open()
        XCTAssertNotNil(requestID); XCTAssertEqual(flow.phase, .unknown); XCTAssertFalse(flow.canCreate)
        XCTAssertEqual(journal.value?.requestID, requestID); XCTAssertEqual(client.calls.filter { $0 == "create" }.count, 1)
    }
    func testChangedPricePreventsConsentAndCreate() async throws {
        let client = try Client(); client.fresh = try Self.topic(price: 9)
        let flow = TopicSelfPlayFlow(topic: try Self.topic(), client: client, journal: Journal())
        await flow.open(); fill(flow); flow.prepare(); await flow.confirm(try XCTUnwrap(flow.review))
        XCTAssertEqual(client.calls, ["fresh"]); XCTAssertNil(flow.pending)
    }
    func testWrongTopicOrderNeverUnlocksPass() async throws {
        let client = try Client(); client.orderValue = try Self.order(owner: 78)
        let flow = TopicSelfPlayFlow(topic: try Self.topic(), client: client, journal: Journal())
        await flow.open(); fill(flow); flow.prepare(); await flow.confirm(try XCTUnwrap(flow.review))
        XCTAssertEqual(flow.phase, .unknown); XCTAssertNil(flow.result)
    }
    func testAccountChangeBeforeConfirmationCannotCreate() async throws {
        let client = try Client(), flow = TopicSelfPlayFlow(topic: try Self.topic(), client: client, journal: Journal())
        await flow.open(); fill(flow); flow.prepare(); let review = try XCTUnwrap(flow.review)
        client.session = nil; await flow.confirm(review); XCTAssertTrue(client.calls.isEmpty)
    }
    func testPaidPendingOrderWithoutProviderRemainsRecoverable() async throws {
        let client = try Client(); client.fresh = try Self.topic(price: 9); client.orderValue = try Self.order(registration: 1, amount: 9)
        let flow = TopicSelfPlayFlow(topic: try Self.topic(price: 9), client: client, journal: Journal())
        await flow.open(); fill(flow); flow.prepare(); await flow.confirm(try XCTUnwrap(flow.review))
        XCTAssertEqual(flow.phase, .paymentUnavailable); XCTAssertEqual(flow.registrationID, 701)
        XCTAssertFalse(flow.canCreate); XCTAssertFalse(client.calls.contains("params"))
    }
    func testRuntimeBodyGuardRejectsActivityAndConsentVersionInjection() throws {
        let base = URL(string: "https://example.com/scoped/")!
        var body: [String: ProjectEditJSON] = ["ownerType": .number(2), "ownerId": .number(77), "realName": .string("Synthetic"), "phone": .string("13800000000"), "isUsePoint": .number(0), "payChannel": .string("APP"), "requestId": .string("test")]
        func request(_ body: [String: ProjectEditJSON]) throws -> URLRequest { try OperationAdapterHTTP.json(configuration: APIConfiguration(baseURL: base), path: "api/registration/create", body: JSONEncoder().encode(body), token: "synthetic") }
        XCTAssertFalse(TopicSelfPlayRuntimeTransport.validates(try request(body), baseURL: base)); body["ownerType"] = .number(1)
        XCTAssertTrue(TopicSelfPlayRuntimeTransport.validates(try request(body), baseURL: base)); body["docVersion"] = .string("invented")
        XCTAssertFalse(TopicSelfPlayRuntimeTransport.validates(try request(body), baseURL: base))
    }
    func testOnlyAuthoritativeClosedOrderAllowsNewReview() async throws {
        let client = try Client(), journal = Journal(), topic = try Self.topic()
        var record = TopicSelfPlayPending(owner: try XCTUnwrap(client.session).storageKey, topic: try XCTUnwrap(SelfPlayTopicID(rawValue: 77)), requestID: "original", registrationID: 701)
        record.paymentAttempted = true; journal.value = record
        let flow = TopicSelfPlayFlow(topic: topic, client: client, journal: journal)
        await flow.open(); await flow.prepareNewOrderAfterClosure()
        XCTAssertEqual(journal.value, record); XCTAssertFalse(flow.canCreate)
        client.orderValue = try Self.order(payment: 3, registration: 4)
        await flow.prepareNewOrderAfterClosure()
        XCTAssertNil(journal.value); XCTAssertNil(flow.pending); XCTAssertTrue(flow.canCreate)
        XCTAssertFalse(flow.consented); XCTAssertEqual(flow.realName, ""); XCTAssertTrue(client.calls.allSatisfy { $0 == "read" })
    }
    func testLeaveInCreateJournalCallbackKeepsLockWithoutCreate() async throws { try await assertJournalFence(.create, invalidation: .leave) }
    func testSessionChangeInCreateJournalCallbackKeepsLockWithoutCreate() async throws { try await assertJournalFence(.create, invalidation: .sessionChange) }
    func testCancellationInCreateJournalCallbackKeepsLockWithoutCreate() async throws { try await assertJournalFence(.create, invalidation: .cancelTask) }
    func testLeaveInNewPaymentJournalCallbackKeepsAttemptWithoutProvider() async throws { try await assertJournalFence(.newPayment, invalidation: .leave) }
    func testSessionChangeInNewPaymentJournalCallbackKeepsAttemptWithoutProvider() async throws { try await assertJournalFence(.newPayment, invalidation: .sessionChange) }
    func testCancellationInNewPaymentJournalCallbackKeepsAttemptWithoutProvider() async throws { try await assertJournalFence(.newPayment, invalidation: .cancelTask) }
    func testLeaveInExistingPaymentJournalCallbackKeepsAttemptWithoutProvider() async throws { try await assertJournalFence(.existingPayment, invalidation: .leave) }
    func testSessionChangeInExistingPaymentJournalCallbackKeepsAttemptWithoutProvider() async throws { try await assertJournalFence(.existingPayment, invalidation: .sessionChange) }
    func testCancellationInExistingPaymentJournalCallbackKeepsAttemptWithoutProvider() async throws { try await assertJournalFence(.existingPayment, invalidation: .cancelTask) }
    private enum JournalBoundary { case create, newPayment, existingPayment }
    private enum JournalInvalidation { case leave, sessionChange, cancelTask }
    private func assertJournalFence(_ boundary: JournalBoundary, invalidation: JournalInvalidation) async throws {
        let client = try Client(), journal = Journal(), provider = Provider()
        let originalSession = try XCTUnwrap(client.session)
        client.fresh = try Self.topic(price: 9); client.orderValue = try Self.order(registration: 1, amount: 9)
        client.suppliedParameters = ["synthetic": "test-only"]
        if boundary == .existingPayment {
            journal.value = TopicSelfPlayPending(owner: originalSession.storageKey, topic: try XCTUnwrap(SelfPlayTopicID(rawValue: 77)), requestID: "retained-intent", registrationID: 701)
        }
        let flow = TopicSelfPlayFlow(topic: try Self.topic(price: 9), client: client, provider: provider, journal: journal)
        await flow.open()
        if boundary == .existingPayment { await flow.prepareExistingPayment(); XCTAssertNotNil(flow.paymentReview) }
        else { fill(flow); XCTAssertTrue(flow.prepare()) }
        client.calls.removeAll()
        var callbackCount = 0
        var callsAtFence: [String] = []
        var writtenLock: TopicSelfPlayPending?
        journal.onWrite = { record in
            let atBoundary = boundary == .create ? record.registrationID == nil : record.paymentAttempted == true
            guard atBoundary else { return }
            callbackCount += 1; callsAtFence = client.calls; writtenLock = record
            switch invalidation {
            case .leave: flow.leave()
            case .sessionChange:
                client.session = .init(namespace: originalSession.namespace, accountID: 2, epoch: UUID(), role: "player", region: .china)
            case .cancelTask: withUnsafeCurrentTask { $0?.cancel() }
            }
        }
        // Cancel only this operation, never the XCTest runner's task.
        if boundary == .existingPayment {
            let review = try XCTUnwrap(flow.paymentReview)
            let task = Task { @MainActor in await flow.confirmExistingPayment(review, consented: true) }
            await task.value; XCTAssertEqual(task.isCancelled, invalidation == .cancelTask)
        } else {
            let review = try XCTUnwrap(flow.review)
            let task = Task { @MainActor in await flow.confirm(review) }
            await task.value; XCTAssertEqual(task.isCancelled, invalidation == .cancelTask)
        }
        XCTAssertEqual(callbackCount, 1)
        XCTAssertEqual(client.calls, callsAtFence)
        XCTAssertTrue(provider.registrationIDs.isEmpty)
        let lock = try XCTUnwrap(writtenLock)
        XCTAssertEqual(journal.value, lock); XCTAssertEqual(flow.pending, lock)
        XCTAssertFalse(flow.canCreate); XCTAssertNil(flow.result)
        if boundary == .create {
            XCTAssertEqual(client.calls, ["fresh", "consent"])
            XCTAssertNil(lock.registrationID); XCTAssertEqual(lock.paymentAttempted, false)
        } else {
            XCTAssertEqual(client.calls, boundary == .newPayment ? ["fresh", "consent", "create", "read", "params"] : ["read", "consent", "params"])
            XCTAssertEqual(lock.registrationID, 701); XCTAssertEqual(lock.paymentAttempted, true)
        }
        // Reopening under the original account must not erase either conservative lock.
        journal.onWrite = nil; client.session = originalSession
        await flow.open(); await flow.prepareExistingPayment()
        XCTAssertEqual(journal.value, lock); XCTAssertEqual(flow.pending, lock)
        XCTAssertEqual(flow.phase, .unknown); XCTAssertFalse(flow.canCreate); XCTAssertNil(flow.paymentReview)
        XCTAssertEqual(client.calls, callsAtFence); XCTAssertTrue(provider.registrationIDs.isEmpty)
    }
    private final class Provider: TopicSelfPlayPaymentProviding {
        var isConfigured = true
        var registrationIDs: [Int] = []
        func pay(registrationID: Int, parameters: [String: String]) async -> TopicSelfPlayProviderReturn {
            registrationIDs.append(registrationID); return .returned
        }
    }
    private func fill(_ flow: TopicSelfPlayFlow) { flow.realName = "Synthetic"; flow.phone = "13800000000"; flow.consented = true }
    private final class Journal: TopicSelfPlayJournaling {
        var value: TopicSelfPlayPending?
        var onWrite: ((TopicSelfPlayPending) -> Void)?
        func pending(owner: String, topic: SelfPlayTopicID) throws -> TopicSelfPlayPending? { value }
        func write(_ pending: TopicSelfPlayPending) throws { value = pending; onWrite?(pending) }
        func resolve(_ pending: TopicSelfPlayPending, authoritativeOrder: OrderLifecycleDetail) throws {
            guard pending == value, pending.registrationID == authoritativeOrder.id, [3, 4].contains(authoritativeOrder.registrationStatus ?? 0) else { throw APIError.invalidRequest }; value = nil
        }
    }
    private final class Client: TopicSelfPlayServing {
        var session: PublishingSession? = .init(namespace: "fixture", accountID: 1, epoch: UUID(), role: "player", region: .china)
        var configured: Bool { session != nil }
        var calls: [String] = []; var failConsent = false; var failCreate = false
        var suppliedParameters: [String: String]?
        var fresh: TopicDetail; var orderValue: OrderLifecycleDetail
        init() throws { fresh = try TopicSelfPlayFlowTests.topic(); orderValue = try TopicSelfPlayFlowTests.order() }
        func document() async throws -> TopicSelfPlayDocument { try .init(version: "synthetic-current", officialURL: URL(string: "https://example.com/notice")!) }
        func freshTopic(_ topic: SelfPlayTopicID) async throws -> TopicDetail { calls.append("fresh"); return fresh }
        func recordConsent(requestID: String, document: TopicSelfPlayDocument) async throws { calls.append("consent"); if failConsent { throw TopicSelfPlayFailure.consent } }
        func create(_ intent: TopicSelfPlayIntent) async throws -> RegistrationCreateResult {
            calls.append("create"); if failCreate { throw TopicSelfPlayFailure.unknown }
            return try JSONDecoder().decode(RegistrationCreateResult.self, from: Data(#"{"registrationId":701,"payableAmount":0}"#.utf8))
        }
        func paymentParameters(registrationID: Int) async throws -> [String: String] {
            calls.append("params"); guard let suppliedParameters else { throw TopicSelfPlayFailure.unavailable }; return suppliedParameters
        }
        func readOrder(registrationID: Int) async throws -> OrderLifecycleDetail { calls.append("read"); return orderValue }
    }
}
