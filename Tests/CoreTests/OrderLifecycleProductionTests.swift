import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Ordinary HTTPTransport fakes; no DEBUG guard or fixture-only production initializer.
@MainActor final class OrderLifecycleProductionTests: XCTestCase {
    private let scope = UUID()
    private let date = Date(timeIntervalSince1970: 1_800_000_000)
    private func order(paid: Bool = false, amount: Int = 20, ownerType: Int = 2) throws -> OrderLifecycleDetail {
        try JSONDecoder().decode(OrderLifecycleDetail.self, from: orderData(paid: paid, amount: amount, ownerType: ownerType))
    }
    private func orderData(paid: Bool = false, amount: Int = 20, ownerType: Int = 2) -> Data {
        Data("{\"id\":77,\"ownerType\":\(ownerType),\"ownerId\":88,\"registrationStatus\":\(paid ? 2 : 1),\"paymentStatus\":\(paid ? 2 : 1),\"verificationStatus\":0,\"payableAmount\":\(amount),\"payExpireTime\":\"2099-01-01T00:00:00Z\",\"refundInfo\":{\"refundable\":true,\"deadline\":\"2099-01-01T00:00:00Z\"}}".utf8)
    }
    private func review(_ action: OrderLifecycleAction = .cancel, ownerType: Int = 2) throws -> OrderLifecycleReview {
        .init(id: UUID(), accountID: 7, scope: scope, detail: try order(paid: action == .refund, ownerType: ownerType),
              action: action, expiresAt: date.addingTimeInterval(60), localAttemptID: UUID())
    }
    private func context(account: Int = 7, epoch: UInt64 = 1, namespace: String = "synthetic") throws -> RuntimeDependencyContext {
        .init(market: .china, baseURL: URL(string: "https://example.com/cn/")!, role: "player",
              session: try .init(accountID: account, epoch: epoch, namespace: namespace, token: "synthetic-only"))
    }
    private func configuration(_ action: OrderLifecycleAction = .cancel, ownerType: Int = 2) throws -> OrderLifecycleProductionConfiguration {
        try .init(market: .china, baseURL: context().baseURL, namespace: "synthetic", accountID: 7, role: "player",
                  sourceRevision: OrderLifecycleSourceContract.revision,
                  approvals: [.init(orderID: 77, ownerType: ownerType, ownerID: 88, action: action,
                                    expiresAt: date.addingTimeInterval(120), signupDocument: action == .payment ? Document.value : nil)],
                  externalCheckoutApproved: true, devicePaymentApproved: true)
    }
    private func make(_ config: OrderLifecycleProductionConfiguration?, holder: Holder, http: HTTP, journal: Journal,
                      provider: Provider? = nil, document: Document? = nil, topicJournal: TopicJournal? = nil, clock: (() -> Date)? = nil, reviewScope: (() -> UUID)? = nil) throws -> OrderLifecycleProductionDispatcher? {
        OrderLifecycleProductionFactory.make(configuration: config, api: try APIConfiguration(baseURL: context().baseURL), transport: http, journal: journal,
              document: document ?? Document(), provider: provider ?? Provider(), sharedGate: TopicSelfPlayOperationGate(), selfPlayJournal: topicJournal ?? TopicJournal(),
              current: { holder.value }, reviewScope: reviewScope ?? { self.scope }, now: clock ?? { self.date })
    }
    private func assertExactForm(_ request: URLRequest, path: String, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(request.httpMethod, "POST", file: file, line: line)
        XCTAssertEqual(request.url?.absoluteString, "https://example.com/cn/" + path, file: file, line: line)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-only", file: file, line: line)
        let contentType = try XCTUnwrap(request.value(forHTTPHeaderField: "Content-Type"), file: file, line: line)
        XCTAssertTrue(contentType.hasPrefix("multipart/form-data; boundary="), file: file, line: line)
        let boundary = String(contentType.dropFirst("multipart/form-data; boundary=".count))
        XCTAssertFalse(boundary.isEmpty, file: file, line: line)
        XCTAssertEqual(request.httpBody, Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"id\"\r\n\r\n77\r\n--\(boundary)--\r\n".utf8), file: file, line: line)
    }
    func testMissingConfigurationAndMismatchedAccountAreOff() throws {
        let holder = Holder(try context()), http = HTTP(detail: orderData()), journal = Journal()
        XCTAssertNil(try make(nil, holder: holder, http: http, journal: journal))
        holder.value = try context(account: 8)
        XCTAssertNil(try make(configuration(), holder: holder, http: http, journal: journal))
        XCTAssertTrue(http.requests.isEmpty)
    }
    func testCancelGrantCannotRefundOrPay() async throws {
        let http = HTTP(detail: orderData()), dispatcher = try XCTUnwrap(make(configuration(), holder: Holder(context()), http: http, journal: Journal()))
        XCTAssertFalse(dispatcher.canDispatch(try review(.refund))); XCTAssertFalse(dispatcher.canDispatch(try review(.payment)))
        do { _ = try await dispatcher.dispatch(review(.refund), visible: { true }); XCTFail("must refuse") } catch { }
        XCTAssertTrue(http.requests.isEmpty)
    }
    func testExactCancelRequestAndAcknowledgmentWithoutInventedSettlement() async throws {
        let http = HTTP(detail: orderData()), journal = Journal()
        let dispatcher = try XCTUnwrap(make(configuration(), holder: Holder(context()), http: http, journal: journal))
        let result = try await dispatcher.dispatch(review(), visible: { true })
        let mutation = try XCTUnwrap(http.requests.first { $0.url?.path.hasSuffix("/cancel") == true })
        XCTAssertEqual(mutation.httpMethod, "POST")
        let contentType = try XCTUnwrap(mutation.value(forHTTPHeaderField: "Content-Type"))
        let boundary = String(contentType.dropFirst("multipart/form-data; boundary=".count))
        XCTAssertEqual(mutation.httpBody, Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"id\"\r\n\r\n77\r\n--\(boundary)--\r\n".utf8))
        XCTAssertEqual(mutation.url?.absoluteString, "https://example.com/cn/api/registration/cancel")
        XCTAssertEqual(mutation.value(forHTTPHeaderField: "Authorization"), "synthetic-only")
        guard case .cancellation(let response, _) = result else { return XCTFail("wrong result") }
        XCTAssertEqual(response.message, "Synthetic acknowledgment"); XCTAssertNil(response.observation)
        XCTAssertNotNil(journal.value)
        do { _ = try await dispatcher.dispatch(review(), visible: { true }); XCTFail("duplicate") } catch { }
        XCTAssertEqual(http.mutations, 1)
    }
    func testRefundUsesIndependentRouteAndKeepsThreeDimensions() async throws {
        let http = HTTP(detail: orderData(paid: true)); http.response = #"{"code":200,"data":{"registrationId":77,"cancellationStatus":"CANCELLED","cashRefundStatus":"PROCESSING","pointsRefundStatus":"RETURNED"}}"#
        let dispatcher = try XCTUnwrap(make(configuration(.refund), holder: Holder(context()), http: http, journal: Journal()))
        guard case .cancellation(let value, _) = try await dispatcher.dispatch(review(.refund), visible: { true }) else { return XCTFail() }
        XCTAssertEqual(value.observation?.cashRefundStatus, "PROCESSING")
        let mutation = try XCTUnwrap(http.requests.first { $0.url?.path.hasSuffix("/cancel-refund") == true })
        try assertExactForm(mutation, path: "api/registration/cancel-refund")
        XCTAssertFalse(http.requests.contains { $0.url?.path.hasSuffix("/cancel") == true })
    }
    func testChangedSnapshotPreventsReservationAndMutation() async throws {
        let http = HTTP(detail: orderData(amount: 21)), journal = Journal()
        let dispatcher = try XCTUnwrap(make(configuration(), holder: Holder(context()), http: http, journal: journal))
        do { _ = try await dispatcher.dispatch(review(), visible: { true }); XCTFail() } catch { }
        XCTAssertNil(journal.value); XCTAssertEqual(http.mutations, 0)
    }
    func testAccountChangeAfterAwaitedReservationKeepsLockWithoutSend() async throws {
        let holder = Holder(try context()), http = HTTP(detail: orderData()), journal = Journal()
        journal.afterReserve = { holder.value = nil }
        let dispatcher = try XCTUnwrap(make(configuration(), holder: holder, http: http, journal: journal))
        do { _ = try await dispatcher.dispatch(review(), visible: { true }); XCTFail() } catch { }
        XCTAssertNotNil(journal.value); XCTAssertEqual(http.mutations, 0)
    }
    func testDismissalAfterAwaitedReservationKeepsLockWithoutSend() async throws {
        let http = HTTP(detail: orderData()), journal = Journal(); var visible = true
        journal.afterReserve = { visible = false }
        let dispatcher = try XCTUnwrap(make(configuration(), holder: Holder(context()), http: http, journal: journal))
        do { _ = try await dispatcher.dispatch(review(), visible: { visible }); XCTFail() } catch { }
        XCTAssertNotNil(journal.value); XCTAssertEqual(http.mutations, 0)
    }
    func testTaskCancellationAfterAwaitedReservationKeepsLockWithoutSend() async throws {
        let http = HTTP(detail: orderData()), journal = Journal()
        let dispatcher = try XCTUnwrap(make(configuration(), holder: Holder(context()), http: http, journal: journal))
        journal.afterReserve = { withUnsafeCurrentTask { $0?.cancel() } }
        let value = try review()
        await Task { do { _ = try await dispatcher.dispatch(value, visible: { true }); XCTFail() } catch { } }.value
        XCTAssertNotNil(journal.value); XCTAssertEqual(http.mutations, 0)
    }
    func testNamespaceChangeInPreflightPreventsMutation() async throws {
        let holder = Holder(try context()), http = HTTP(detail: orderData()), journal = Journal()
        let changed = try context(namespace: "other"); http.onRequest = { _ in holder.value = changed }
        let dispatcher = try XCTUnwrap(make(configuration(), holder: holder, http: http, journal: journal))
        do { _ = try await dispatcher.dispatch(review(), visible: { true }); XCTFail() } catch { }
        XCTAssertNil(journal.value); XCTAssertEqual(http.mutations, 0)
    }
    func testUnknownHTTPOutcomeNeverRetriesAfterDispatcherRecreation() async throws {
        let holder = Holder(try context()), http = HTTP(detail: orderData()), journal = Journal(); http.failMutation = true
        for _ in 0..<2 {
            let dispatcher = try XCTUnwrap(make(configuration(), holder: holder, http: http, journal: journal))
            do { _ = try await dispatcher.dispatch(review(), visible: { true }); XCTFail() } catch { }
        }
        XCTAssertEqual(http.mutations, 1); XCTAssertNotNil(journal.value)
    }
    func testWrongCancellationOrderIsUnknownAndLocked() async throws {
        let http = HTTP(detail: orderData()), journal = Journal(); http.response = #"{"code":200,"data":{"registrationId":99}}"#
        let dispatcher = try XCTUnwrap(make(configuration(), holder: Holder(context()), http: http, journal: journal))
        do { _ = try await dispatcher.dispatch(review(), visible: { true }); XCTFail() } catch { }
        XCTAssertNotNil(journal.value); XCTAssertEqual(http.mutations, 1)
    }
    func testRevokedOrStaleConsentCannotFetchParameters() async throws {
        for consent in [#"{"docType":"activity_host_data_sharing","scene":"activity_signup","eventType":"REVOKE","docVersion":"v1"}"#,
                        #"{"docType":"activity_host_data_sharing","scene":"activity_signup","eventType":"AGREE","docVersion":"old"}"#] {
            let http = HTTP(detail: orderData()), journal = Journal(); http.consent = consent
            let dispatcher = try XCTUnwrap(make(configuration(.payment), holder: Holder(context()), http: http, journal: journal))
            do { _ = try await dispatcher.dispatch(review(.payment), visible: { true }); XCTFail() } catch { }
            XCTAssertEqual(http.mutations, 0); XCTAssertNil(journal.value)
        }
    }
    func testDocumentChangeAfterReservationPreventsPaymentParameters() async throws {
        let http = HTTP(detail: orderData()), journal = Journal(), document = Document()
        journal.afterReserve = { document.changed = true }
        let dispatcher = try XCTUnwrap(make(configuration(.payment), holder: Holder(context()), http: http, journal: journal, document: document))
        do { _ = try await dispatcher.dispatch(review(.payment), visible: { true }); XCTFail() } catch { }
        XCTAssertEqual(http.mutations, 0); XCTAssertNotNil(journal.value)
    }
    func testProviderReturnIsNotPaymentAndUsesServerReadback() async throws {
        let http = HTTP(detail: orderData()), journal = Journal(), provider = Provider()
        let dispatcher = try XCTUnwrap(make(configuration(.payment), holder: Holder(context()), http: http, journal: journal, provider: provider))
        guard case .payment(let flow) = try await dispatcher.dispatch(review(.payment), visible: { true }) else { return XCTFail() }
        XCTAssertEqual(provider.calls, [77]); XCTAssertEqual(flow.phase, .idle); XCTAssertNil(flow.detail)
        let payment = try XCTUnwrap(http.requests.first { $0.url?.path.hasSuffix("/pay/app") == true })
        try assertExactForm(payment, path: "api/registration/pay/app")
        let legalReads = http.requests.filter { $0.url?.path.hasSuffix("/consents/latest") == true }
        XCTAssertFalse(legalReads.isEmpty)
        for request in legalReads {
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/cn/api/compliance/consents/latest")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-only")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            let body = try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: String]
            XCTAssertEqual(body, ["docType": "activity_host_data_sharing", "scene": "activity_signup"])
        }
        http.detail = orderData(paid: true); await flow.reconcile()
        XCTAssertEqual(flow.phase, .paid); try dispatcher.observePaid(flow)
        XCTAssertEqual(journal.value?.paymentObservedPaid, true); XCTAssertEqual(http.mutations, 1)
    }
    func testNewDispatcherCannotUseAnotherDispatchersReadbackToReleaseLock() async throws {
        let holder = Holder(try context()), http = HTTP(detail: orderData()), journal = Journal()
        let original = try XCTUnwrap(make(configuration(.payment), holder: holder, http: http, journal: journal))
        guard case .payment(let flow) = try await original.dispatch(review(.payment), visible: { true }) else { return XCTFail() }
        http.detail = orderData(paid: true); await flow.reconcile(); XCTAssertEqual(flow.phase, .paid)
        let other = try XCTUnwrap(make(configuration(.payment), holder: holder, http: http, journal: journal))
        XCTAssertThrowsError(try other.observePaid(flow)); XCTAssertNotEqual(journal.value?.paymentObservedPaid, true)
        try original.observePaid(flow); XCTAssertEqual(journal.value?.paymentObservedPaid, true)
    }
    func testProviderReadbackSurvivesReviewExpiryAfterLaunch() async throws {
        let http = HTTP(detail: orderData()), journal = Journal(), provider = Provider()
        var clock = date
        provider.onPay = { clock = clock.addingTimeInterval(120) }
        let dispatcher = try XCTUnwrap(make(configuration(.payment), holder: Holder(context()), http: http, journal: journal,
                                            provider: provider, clock: { clock }))
        guard case .payment(let flow) = try await dispatcher.dispatch(review(.payment), visible: { true }) else { return XCTFail() }
        XCTAssertEqual(flow.phase, .idle); XCTAssertEqual(provider.calls, [77]); XCTAssertNotNil(journal.value)
    }
    func testExistingSelfPlayJournalCannotBeBypassed() async throws {
        let http = HTTP(detail: orderData(ownerType: 1)), journal = Journal(), topic = TopicJournal()
        topic.value = .init(owner: "synthetic|china|7", topic: try XCTUnwrap(SelfPlayTopicID(rawValue: 88)), requestID: "synthetic", registrationID: 77)
        let dispatcher = try XCTUnwrap(make(configuration(.payment, ownerType: 1), holder: Holder(context()), http: http, journal: journal, topicJournal: topic))
        do { _ = try await dispatcher.dispatch(review(.payment, ownerType: 1), visible: { true }); XCTFail() } catch { }
        XCTAssertTrue(http.requests.isEmpty); XCTAssertNil(journal.value)
    }
    func testFileJournalIsDurableAndPaidTransitionAllowsOnlySeparateRefund() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("orders.json"), first = OrderLifecycleFileJournal(url: url)
        let record = OrderLifecycleReservation(owner: "synthetic", orderID: 77, attemptID: UUID(), action: .payment)
        try await first.reserve(record)
        let reopened = OrderLifecycleFileJournal(url: url)
        XCTAssertEqual(try reopened.pending(owner: "synthetic", orderID: 77), record)
        do { try await reopened.reserve(record); XCTFail() } catch { }
        XCTAssertThrowsError(try reopened.observePaid(record, detail: order()))
        try reopened.observePaid(record, detail: order(paid: true))
        XCTAssertNil(try reopened.pending(owner: "synthetic", orderID: 77))
        do { try await reopened.reserve(record); XCTFail() } catch { }
        let refund = OrderLifecycleReservation(owner: "synthetic", orderID: 77, attemptID: UUID(), action: .refund)
        try await reopened.reserve(refund)
        XCTAssertEqual(try reopened.pending(owner: "synthetic", orderID: 77), refund)
        do { try await reopened.reserve(refund); XCTFail() } catch { }
    }
    func testOfflineReaderCannotActivateProductionFactory() async throws {
        let http = HTTP(detail: orderData()), journal = Journal()
        let dispatcher = try XCTUnwrap(make(configuration(), holder: Holder(context()), http: http, journal: journal))
        let coordinator = OrderLifecycleCoordinator(reader: OfflineReader(value: try order(), scope: scope), now: { self.date }, production: { dispatcher })
        await coordinator.load(id: 77); coordinator.prepare(.cancel, orderID: 77)
        XCTAssertFalse(coordinator.canDispatch)
        await coordinator.confirm(reviewID: try XCTUnwrap(coordinator.review).id)
        XCTAssertTrue(http.requests.isEmpty); XCTAssertNil(journal.value)
    }
    func testFreshDispatcherRejectsOldReviewAfterSameAccountRelogin() async throws {
        let oldReview = try review(), holder = Holder(try context()), http = HTTP(detail: orderData()), journal = Journal()
        var readerScope = scope
        let original = try XCTUnwrap(make(configuration(), holder: holder, http: http, journal: journal, reviewScope: { readerScope }))
        XCTAssertTrue(original.canDispatch(oldReview))
        holder.value = try context(epoch: 2); readerScope = UUID()
        let reopened = try XCTUnwrap(make(configuration(), holder: holder, http: http, journal: journal, reviewScope: { readerScope }))
        XCTAssertFalse(original.canDispatch(oldReview)); XCTAssertFalse(reopened.canDispatch(oldReview))
        do { _ = try await reopened.dispatch(oldReview, visible: { true }); XCTFail("old review must not migrate to a new epoch") } catch { }
        XCTAssertTrue(http.requests.isEmpty); XCTAssertNil(journal.value)
    }
    func testFullContextChangesAfterReservationCannotSend() async throws {
        let original = try context()
        let changed = [try context(epoch: 2), try context(namespace: "different"),
                       RuntimeDependencyContext(market: .unitedStates, baseURL: original.baseURL, role: original.role, session: original.session),
                       RuntimeDependencyContext(market: .china, baseURL: URL(string: "https://example.com/other/")!, role: original.role, session: original.session),
                       RuntimeDependencyContext(market: .china, baseURL: original.baseURL, role: "club", session: original.session)]
        for value in changed {
            let holder = Holder(original), http = HTTP(detail: orderData()), journal = Journal()
            journal.afterReserve = { holder.value = value }
            let dispatcher = try XCTUnwrap(make(configuration(), holder: holder, http: http, journal: journal))
            do { _ = try await dispatcher.dispatch(review(), visible: { true }); XCTFail() } catch { }
            XCTAssertNotNil(journal.value); XCTAssertEqual(http.mutations, 0)
        }
    }
    func testReaderScopeChangesWithContextWithoutTokenChange() throws {
        var session: OrderLifecycleSession? = try .init(accountID: 7, epoch: 1, token: "synthetic-only", contextID: "CN|origin|namespace|player")
        let reader = OrderLifecycleSessionReader(service: nil, currentSession: { session })
        let first = reader.scope
        session = try .init(accountID: 7, epoch: 1, token: "synthetic-only", contextID: "CN|origin|namespace|club")
        XCTAssertNotEqual(reader.scope, first)
    }
    private func replayConfiguration(_ context: RuntimeDependencyContext, actions: [OrderLifecycleAction] = [.cancel]) throws -> OrderLifecycleProductionConfiguration {
        try .init(market: context.market, baseURL: context.baseURL, namespace: context.session.namespace,
            accountID: context.session.accountID, role: context.role, sourceRevision: OrderLifecycleSourceContract.revision,
            approvals: actions.map { action in
                try .init(orderID: 77, ownerType: 2, ownerID: 88, action: action, expiresAt: date.addingTimeInterval(120),
                          signupDocument: action == .payment ? Document.value : nil)
            }, externalCheckoutApproved: true, devicePaymentApproved: true)
    }
    private func replayHarness(actions: [OrderLifecycleAction] = [.cancel]) throws -> ReplayHarness {
        let captured = try context()
        return ReplayHarness(context: captured, configuration: try replayConfiguration(captured, actions: actions),
                             detail: try order(), data: orderData(), date: date)
    }
    func testProductionUnknownLockSurvivesReloginAndUnavailableFactory() async throws {
        let harness = try replayHarness(); defer { harness.cleanup() }
        harness.http.failMutation = true
        let coordinator = harness.coordinator
        await coordinator.load(id: 77); coordinator.prepare(.cancel, orderID: 77)
        let review = try XCTUnwrap(coordinator.review)
        await coordinator.confirm(reviewID: review.id)
        XCTAssertEqual(harness.http.mutations, 1)
        XCTAssertEqual(coordinator.attempt(orderID: 77), .outcomeUnknown(localAttemptID: review.localAttemptID))
        harness.enabled = false; harness.holder.value = nil; coordinator.invalidateVisible()
        let old = try context()
        harness.holder.value = RuntimeDependencyContext(market: old.market, baseURL: old.baseURL, role: old.role,
            session: try .init(accountID: 7, epoch: 2, namespace: old.session.namespace, token: "synthetic-new-token"))
        await coordinator.load(id: 77); coordinator.prepare(.cancel, orderID: 77)
        XCTAssertNil(coordinator.review); XCTAssertEqual(coordinator.issue, .alreadyAttempted)
        XCTAssertEqual(coordinator.attempt(orderID: 77), .outcomeUnknown(localAttemptID: review.localAttemptID))
        harness.enabled = true
        let freshDispatcher = try XCTUnwrap(harness.dispatcher())
        XCTAssertEqual(try freshDispatcher.pending(orderID: 77)?.attemptID, review.localAttemptID)
        await coordinator.confirm(reviewID: review.id)
        XCTAssertEqual(harness.http.mutations, 1)
    }
    func testProductionReplayOwnerSeparatesAccountMarketOriginAndNamespace() async throws {
        let harness = try replayHarness(); defer { harness.cleanup() }
        harness.http.failMutation = true
        let coordinator = harness.coordinator, original = try context()
        await coordinator.load(id: 77); coordinator.prepare(.cancel, orderID: 77)
        let review = try XCTUnwrap(coordinator.review), staleDispatcher = try XCTUnwrap(harness.dispatcher())
        await coordinator.confirm(reviewID: review.id)
        harness.retainedDispatcher = staleDispatcher
        let alternatives = [try context(account: 8), try context(namespace: "other"),
            RuntimeDependencyContext(market: .china, baseURL: URL(string: "https://example.com/other/")!, role: original.role, session: original.session),
            RuntimeDependencyContext(market: .unitedStates, baseURL: original.baseURL, role: original.role, session: original.session)]
        for other in alternatives {
            harness.holder.value = other
            XCTAssertNil(try staleDispatcher.pending(orderID: 77))
            XCTAssertNil(coordinator.attempt(orderID: 77)); XCTAssertNil(coordinator.detail)
            XCTAssertNil(coordinator.serverMessage); XCTAssertNil(coordinator.review)
        }
        harness.holder.value = try context(epoch: 3)
        XCTAssertNil(try staleDispatcher.pending(orderID: 77))
        XCTAssertEqual(coordinator.attempt(orderID: 77), .outcomeUnknown(localAttemptID: review.localAttemptID))
        harness.retainedDispatcher = nil
        XCTAssertEqual(try XCTUnwrap(harness.dispatcher()).pending(orderID: 77)?.attemptID, review.localAttemptID)
        XCTAssertEqual(harness.http.mutations, 1)
    }
    func testSameOrderInDifferentDeploymentCanReserveWithoutConsumingOriginalLock() async throws {
        let harness = try replayHarness(); defer { harness.cleanup() }
        harness.http.failMutation = true
        let coordinator = harness.coordinator
        await coordinator.load(id: 77); coordinator.prepare(.cancel, orderID: 77)
        let first = try XCTUnwrap(coordinator.review)
        await coordinator.confirm(reviewID: first.id)
        let other = try context(namespace: "independent-deployment")
        harness.holder.value = other; harness.configuration = try replayConfiguration(other)
        await coordinator.load(id: 77); coordinator.prepare(.cancel, orderID: 77)
        let second = try XCTUnwrap(coordinator.review)
        XCTAssertNotEqual(first.localAttemptID, second.localAttemptID)
        await coordinator.confirm(reviewID: second.id)
        XCTAssertEqual(coordinator.attempt(orderID: 77), .outcomeUnknown(localAttemptID: second.localAttemptID))
        harness.holder.value = try context(epoch: 2); harness.configuration = try replayConfiguration(context(epoch: 2))
        await coordinator.load(id: 77); coordinator.prepare(.cancel, orderID: 77)
        XCTAssertNil(coordinator.review)
        XCTAssertEqual(coordinator.attempt(orderID: 77), .outcomeUnknown(localAttemptID: first.localAttemptID))
        XCTAssertEqual(try XCTUnwrap(harness.dispatcher()).pending(orderID: 77)?.attemptID, first.localAttemptID)
        XCTAssertEqual(harness.http.mutations, 2)
    }
    func testRoleChangeCannotUnlockProductionUnknownAttempt() async throws {
        let harness = try replayHarness(); defer { harness.cleanup() }
        harness.http.failMutation = true
        let coordinator = harness.coordinator, original = try context()
        await coordinator.load(id: 77); coordinator.prepare(.cancel, orderID: 77)
        let review = try XCTUnwrap(coordinator.review)
        await coordinator.confirm(reviewID: review.id)
        let changed = RuntimeDependencyContext(market: original.market, baseURL: original.baseURL, role: "club", session: original.session)
        harness.holder.value = changed; harness.configuration = try replayConfiguration(changed)
        await coordinator.load(id: 77); coordinator.prepare(.cancel, orderID: 77)
        XCTAssertNil(coordinator.review); XCTAssertEqual(coordinator.issue, .alreadyAttempted)
        XCTAssertEqual(coordinator.attempt(orderID: 77), .outcomeUnknown(localAttemptID: review.localAttemptID))
        XCTAssertEqual(harness.http.mutations, 1)
    }
    func testProductionLateResponseKeepsCapturedOwnerLockWithoutExposingReceipt() async throws {
        let harness = try replayHarness(); defer { harness.cleanup() }
        let coordinator = harness.coordinator, replacement = try context(account: 8)
        harness.http.response = #"{"code":200,"data":{"registrationId":77,"cancellationStatus":"PRIVATE-SYNTHETIC-STATUS"}}"#
        harness.http.onRequest = { request in
            if request.url?.path.hasSuffix("/cancel") == true { harness.holder.value = replacement }
        }
        await coordinator.load(id: 77); coordinator.prepare(.cancel, orderID: 77)
        let review = try XCTUnwrap(coordinator.review)
        await coordinator.confirm(reviewID: review.id)
        XCTAssertNil(coordinator.attempt(orderID: 77)); XCTAssertNil(coordinator.detail); XCTAssertNil(coordinator.serverMessage)
        harness.holder.value = try context(epoch: 2); harness.enabled = false
        XCTAssertEqual(coordinator.attempt(orderID: 77), .outcomeUnknown(localAttemptID: review.localAttemptID))
        await coordinator.load(id: 77); coordinator.prepare(.cancel, orderID: 77)
        XCTAssertNil(coordinator.review); XCTAssertEqual(harness.http.mutations, 1)
        harness.enabled = true
        XCTAssertEqual(try XCTUnwrap(harness.dispatcher()).pending(orderID: 77)?.attemptID, review.localAttemptID)
    }
    func testPaidHistoryAfterReloginPermitsOnlySeparatelyApprovedRefund() async throws {
        let harness = try replayHarness(actions: [.payment, .refund]); defer { harness.cleanup() }
        let coordinator = harness.coordinator
        await coordinator.load(id: 77); coordinator.prepare(.payment, orderID: 77)
        let paymentReview = try XCTUnwrap(coordinator.review)
        await coordinator.confirm(reviewID: paymentReview.id)
        let flow = try XCTUnwrap(coordinator.paymentReturn)
        harness.http.detail = orderData(paid: true); harness.reader.value = try order(paid: true)
        await flow.reconcile(); XCTAssertEqual(flow.phase, .paid); coordinator.closePaymentReturn()
        XCTAssertNil(try XCTUnwrap(harness.dispatcher()).pending(orderID: 77))
        harness.holder.value = try context(epoch: 2)
        XCTAssertEqual(coordinator.attempt(orderID: 77), .outcomeUnknown(localAttemptID: paymentReview.localAttemptID))
        await coordinator.load(id: 77)
        XCTAssertTrue(coordinator.isAttemptBlocking(.payment, orderID: 77))
        XCTAssertTrue(coordinator.isAttemptBlocking(.cancel, orderID: 77))
        XCTAssertFalse(coordinator.isAttemptBlocking(.refund, orderID: 77))
        coordinator.prepare(.refund, orderID: 77)
        let refundReview = try XCTUnwrap(coordinator.review)
        await coordinator.confirm(reviewID: refundReview.id)
        XCTAssertEqual(harness.http.requests.filter { $0.url?.path.hasSuffix("/pay/app") == true }.count, 1)
        XCTAssertEqual(harness.http.requests.filter { $0.url?.path.hasSuffix("/cancel-refund") == true }.count, 1)
        XCTAssertEqual(try XCTUnwrap(harness.dispatcher()).pending(orderID: 77)?.attemptID, refundReview.localAttemptID)
    }
    func testRawPaidReadbackCannotUnlockUnknownPaymentAfterRelogin() async throws {
        let harness = try replayHarness(actions: [.payment, .refund]); defer { harness.cleanup() }
        harness.http.failMutation = true
        let coordinator = harness.coordinator
        await coordinator.load(id: 77); coordinator.prepare(.payment, orderID: 77)
        let review = try XCTUnwrap(coordinator.review)
        await coordinator.confirm(reviewID: review.id)
        harness.http.detail = orderData(paid: true); harness.reader.value = try order(paid: true)
        harness.holder.value = try context(epoch: 2)
        await coordinator.load(id: 77); coordinator.prepare(.refund, orderID: 77)
        XCTAssertNil(coordinator.review); XCTAssertEqual(coordinator.issue, .alreadyAttempted)
        XCTAssertEqual(coordinator.attempt(orderID: 77), .outcomeUnknown(localAttemptID: review.localAttemptID))
        XCTAssertEqual(try XCTUnwrap(harness.dispatcher()).pending(orderID: 77)?.attemptID, review.localAttemptID)
        XCTAssertEqual(harness.http.mutations, 1)
    }
    func testProductionFactoryRequiresExplicitMatchingReplayContextAndAccount() async throws {
        let harness = try replayHarness(); defer { harness.cleanup() }
        harness.http.failMutation = true
        let coordinator = harness.coordinator
        await coordinator.load(id: 77); coordinator.prepare(.cancel, orderID: 77)
        await coordinator.confirm(reviewID: try XCTUnwrap(coordinator.review).id)
        let dispatcher = try XCTUnwrap(harness.dispatcher())
        let replay = OrderLifecycleReplayContext(context: try context())
        let other = OrderLifecycleReplayContext(context: try context(namespace: "other"))
        let mismatches: [(Int, OrderLifecycleReplayContext?)] = [(7, nil), (8, replay), (7, other)]
        for (accountID, replayContext) in mismatches {
            let reader = MisboundReader(accountID: accountID, scope: harness.reader.scope, replayContext: replayContext, value: try order())
            let unrelated = OrderLifecycleCoordinator(reader: reader, now: { self.date }, production: { dispatcher })
            XCTAssertNil(unrelated.attempt(orderID: 77))
            await unrelated.load(id: 77); unrelated.prepare(.cancel, orderID: 77)
            let review = try XCTUnwrap(unrelated.review)
            XCTAssertFalse(unrelated.canDispatch)
            await unrelated.confirm(reviewID: review.id)
            XCTAssertEqual(unrelated.issue, .dispatchDisabled); XCTAssertNil(unrelated.attempt(orderID: 77))
        }
        XCTAssertEqual(harness.http.mutations, 1)
    }
    func testStableReplayContextExcludesEpochTokenAndRoleButSeparatesDeployment() throws {
        let original = try context()
        let replay = OrderLifecycleReplayContext(context: original)
        let changedSession = try PlayExperienceSession(accountID: 7, epoch: 99, namespace: original.session.namespace, token: "synthetic-new-token")
        let changed = RuntimeDependencyContext(market: original.market, baseURL: original.baseURL, role: "club", session: changedSession)
        XCTAssertEqual(OrderLifecycleReplayContext(context: changed), replay)
        XCTAssertNotEqual(OrderLifecycleReplayContext(context: try context(namespace: "other")), replay)
        var session: OrderLifecycleSession? = try .init(accountID: 7, epoch: 1, token: "synthetic-only", contextID: "player", replayContext: replay)
        let reader = OrderLifecycleSessionReader(service: nil, currentSession: { session })
        let oldScope = reader.scope
        session = try .init(accountID: 7, epoch: 99, token: "synthetic-new-token", contextID: "club", replayContext: replay)
        XCTAssertNotEqual(reader.scope, oldScope); XCTAssertEqual(reader.replayContext, replay)
    }
    @MainActor private final class MisboundReader: OrderLifecycleReading {
        let accountID: Int?
        let scope: UUID
        let replayContext: OrderLifecycleReplayContext?
        let value: OrderLifecycleDetail
        var isConfigured: Bool { true }
        var isOfflineExample: Bool { false }
        init(accountID: Int, scope: UUID, replayContext: OrderLifecycleReplayContext?, value: OrderLifecycleDetail) {
            self.accountID = accountID; self.scope = scope; self.replayContext = replayContext; self.value = value
        }
        func detail(id: Int) async throws -> OrderLifecycleDetail { value }
    }
    @MainActor private final class ReplayReader: OrderLifecycleReading {
        let holder: Holder
        var value: OrderLifecycleDetail
        private var previous: RuntimeDependencyContext?
        private var stamp = UUID()
        init(holder: Holder, value: OrderLifecycleDetail) { self.holder = holder; self.value = value; previous = holder.value }
        var accountID: Int? { holder.value?.session.accountID }
        var replayContext: OrderLifecycleReplayContext? { holder.value.map { OrderLifecycleReplayContext(context: $0) } }
        var scope: UUID {
            if previous != holder.value { previous = holder.value; stamp = UUID() }
            return stamp
        }
        var isConfigured: Bool { true }
        var isOfflineExample: Bool { false }
        func detail(id: Int) async throws -> OrderLifecycleDetail { value }
    }
    @MainActor private final class ReplayHarness {
        let holder: Holder
        let http: HTTP
        let reader: ReplayReader
        let journal: OrderLifecycleFileJournal
        let directory: URL
        let date: Date
        let gate = TopicSelfPlayOperationGate()
        let topicJournal = TopicJournal()
        let provider = Provider()
        var configuration: OrderLifecycleProductionConfiguration?
        var enabled = true
        var retainedDispatcher: OrderLifecycleProductionDispatcher?
        lazy var coordinator = OrderLifecycleCoordinator(reader: reader, now: { [date = self.date] in date }, production: { [weak self] in self?.dispatcher() })
        init(context: RuntimeDependencyContext, configuration: OrderLifecycleProductionConfiguration, detail: OrderLifecycleDetail, data: Data, date: Date) {
            let holder = Holder(context)
            self.holder = holder; reader = ReplayReader(holder: holder, value: detail); http = HTTP(detail: data)
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            self.directory = directory; journal = OrderLifecycleFileJournal(url: directory.appendingPathComponent("orders.json"))
            self.configuration = configuration; self.date = date
        }
        func dispatcher() -> OrderLifecycleProductionDispatcher? {
            guard enabled else { return nil }
            if let retainedDispatcher { return retainedDispatcher }
            guard let context = holder.value, let api = try? APIConfiguration(baseURL: context.baseURL) else { return nil }
            return OrderLifecycleProductionFactory.make(configuration: configuration, api: api, transport: http, journal: journal,
                document: Document(), provider: provider, sharedGate: gate, selfPlayJournal: topicJournal,
                current: { [weak self] in self?.holder.value }, reviewScope: { [weak self] in self?.reader.scope ?? UUID() }, now: { [date = self.date] in date })
        }
        func cleanup() { try? FileManager.default.removeItem(at: directory) }
    }
    @MainActor private final class OfflineReader: OrderLifecycleReading {
        let value: OrderLifecycleDetail
        var accountID: Int? { 7 }; let scope: UUID; var isConfigured: Bool { true }; var isOfflineExample: Bool { true }
        init(value: OrderLifecycleDetail, scope: UUID) { self.value = value; self.scope = scope }
        func detail(id: Int) async throws -> OrderLifecycleDetail { value }
    }
    @MainActor private final class Holder { var value: RuntimeDependencyContext?; init(_ value: RuntimeDependencyContext?) { self.value = value } }
    @MainActor private final class Journal: OrderLifecycleJournaling {
        var value: OrderLifecycleReservation?; var afterReserve: (() -> Void)?
        func pending(owner: String, orderID: Int) throws -> OrderLifecycleReservation? { value?.paymentObservedPaid == true ? nil : value }
        func reserve(_ record: OrderLifecycleReservation) async throws {
            guard value == nil else { throw OrderLifecycleFailure.alreadyAttempted }
            value = record; await Task.yield(); afterReserve?()
        }
        func observePaid(_ record: OrderLifecycleReservation, detail: OrderLifecycleDetail) throws { value?.paymentObservedPaid = true }
    }
    @MainActor private final class TopicJournal: TopicSelfPlayJournaling {
        var value: TopicSelfPlayPending?
        func pending(owner: String, topic: SelfPlayTopicID) throws -> TopicSelfPlayPending? { value }
        func write(_ pending: TopicSelfPlayPending) throws { value = pending }
        func resolve(_ pending: TopicSelfPlayPending, authoritativeOrder: OrderLifecycleDetail) throws { XCTFail("must not clear") }
    }
    @MainActor private final class Document: TopicSelfPlayDocumentProviding {
        static var value: TopicSelfPlayDocument { try! .init(version: "v1", officialURL: URL(string: "https://example.com/legal/signup")!) }
        var changed = false
        func currentDocument(context: RuntimeDependencyContext) async throws -> TopicSelfPlayDocument {
            if changed { return try .init(version: "v2", officialURL: Self.value.officialURL) }
            return Self.value
        }
    }
    @MainActor private final class Provider: TopicSelfPlayPaymentProviding {
        var isConfigured = true; var calls: [Int] = []; var onPay: (() -> Void)?
        func pay(registrationID: Int, parameters: [String: String]) async -> TopicSelfPlayProviderReturn { calls.append(registrationID); onPay?(); return .returned }
    }
    @MainActor private final class HTTP: HTTPTransport {
        var detail: Data; var requests: [URLRequest] = []; var failMutation = false
        var response = #"{"code":200,"msg":"Synthetic acknowledgment"}"#
        var consent = #"{"docType":"activity_host_data_sharing","scene":"activity_signup","eventType":"AGREE","docVersion":"v1"}"#
        var onRequest: ((URLRequest) -> Void)?
        init(detail: Data) { self.detail = detail }
        var mutations: Int { requests.filter { $0.url?.path.hasSuffix("/cancel") == true || $0.url?.path.hasSuffix("/cancel-refund") == true || $0.url?.path.hasSuffix("/pay/app") == true }.count }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request); await Task.yield(); onRequest?(request)
            let path = request.url?.path ?? ""
            if path.hasSuffix("/registration/info") { return (Data("{\"code\":200,\"data\":".utf8) + detail + Data("}".utf8), 200) }
            if path.hasSuffix("/consents/latest") { return (Data("{\"code\":200,\"data\":\(consent)}".utf8), 200) }
            if failMutation { throw URLError(.timedOut) }
            if path.hasSuffix("/pay/app") { return (Data(#"{"code":200,"data":{"payParams":{"appId":"synthetic","partnerId":"1","prepayId":"synthetic","packageValue":"Sign=WXPay","nonceStr":"synthetic","timeStamp":"1","sign":"synthetic"}}}"#.utf8), 200) }
            return (Data(response.utf8), 200)
        }
    }
}
