import XCTest
@testable import QuestifyCore

@MainActor final class MerchantMarketingTests: XCTestCase {
    private final class SessionBox {
        var value: MerchantMarketingScope?
        init(epoch: UInt64 = 1, namespace: String = "fixture-cn", accountID: Int = 700) {
            value = try! MerchantMarketingScope(namespace: namespace, accountID: accountID, epoch: epoch, token: "fixture-token")
        }
    }
    private func raw(_ json: String) throws -> MerchantMarketingValue { try JSONDecoder().decode(MerchantMarketingValue.self, from: Data(json.utf8)) }
    private func service(_ transport: MerchantMarketingFixtureTransport, box: SessionBox? = nil, locks: MerchantPredictionMemoryLocks? = nil, gates: MerchantMarketingService.Gates = .init(reads: true, insight: true, settlement: true)) throws -> MerchantMarketingService {
        let capturedBox = box ?? SessionBox()
        return try MerchantMarketingService(configuration: APIConfiguration(baseURL: URL(string: "https://merchant-marketing.example")!), transport: transport, gates: gates, locks: locks ?? MerchantPredictionMemoryLocks(), currentSession: { capturedBox.value })
    }
    private func review(_ service: MerchantMarketingService) async throws -> MerchantPredictionReview {
        let rounds = try await service.inbox(); return try await service.prepare(round: XCTUnwrap(rounds.first), optionKey: "A")
    }
    func testDefaultGatesDispatchNothing() async throws {
        let transport = MerchantMarketingFixtureTransport(), api = try service(transport, gates: .init())
        do { _ = try await api.dashboard(); XCTFail() } catch { XCTAssertEqual(error as? MerchantMarketingFailure, .unavailable) }
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testMarketingRequiresExactPermissionBeforeDashboard() async throws {
        let transport = MerchantMarketingFixtureTransport(scenario: "project-only"), api = try service(transport)
        do { _ = try await api.dashboard(); XCTFail() } catch { XCTAssertEqual(error as? MerchantMarketingFailure, .denied) }
        XCTAssertEqual(transport.requests.map { $0.url!.path }, ["/api/merchant/access/me"])
    }
    func testPredictionRequiresProjectPermissionNotMarketing() async throws {
        let transport = MerchantMarketingFixtureTransport(scenario: "marketing-only"), api = try service(transport)
        do { _ = try await api.inbox(); XCTFail() } catch { XCTAssertEqual(error as? MerchantMarketingFailure, .denied) }
        XCTAssertEqual(transport.requests.count, 1)
    }
    func testAccessUnknownRoleAndInactiveFailClosed() throws {
        XCTAssertThrowsError(try MerchantMarketingAccess(raw(#"{"active":true,"merchant":{"id":1},"roleCode":"ADMIN","permissions":["merchant:project:manage"]}"#)))
        let access = try MerchantMarketingAccess(raw(#"{"active":false,"permissions":["merchant:project:manage"]}"#))
        XCTAssertFalse(access.canSettlePrediction); XCTAssertFalse(access.canReadMarketing)
    }
    func testOneAggregateRequestAndAbsentRedemptionRate() async throws {
        let transport = MerchantMarketingFixtureTransport(), result = try await service(transport).dashboard()
        XCTAssertEqual(result.couponCount, 3); XCTAssertNil(result.verificationRate)
        XCTAssertEqual(result.funnel[1].rate, 0.25); XCTAssertNil(result.funnel[2].rate)
        XCTAssertEqual(transport.requests.map { $0.url!.path }, ["/api/merchant/access/me", "/api/merchant/marketing-home"])
        XCTAssertTrue(transport.requests.allSatisfy { $0.httpMethod == "POST" && $0.httpBody == nil })
    }
    func testUnknownCountsDoNotBecomeZeros() throws {
        let dashboard = try MerchantMarketingDashboard(raw("{}"))
        XCTAssertNil(dashboard.couponCount); XCTAssertNil(dashboard.received); XCTAssertNil(dashboard.verificationRate)
    }
    func testInsightMissingFactsFailsClosed() async throws {
        let api = try service(MerchantMarketingFixtureTransport(scenario: "missing-facts"))
        do { _ = try await api.insight(); XCTFail() } catch { XCTAssertEqual(error as? MerchantMarketingFailure, .malformed) }
    }
    func testInsightSeparatesFactsMetadataAndAllowlist() async throws {
        let transport = MerchantMarketingFixtureTransport(), result = try await service(transport).insight()
        XCTAssertEqual(result.facts["checkin"]["total"].integer, 9)
        XCTAssertNil(result.facts["checkin"]["redeemRate"].decimal)
        XCTAssertEqual(result.generatedAt, "synthetic"); XCTAssertEqual(result.suggestions[0].destination, .content)
        XCTAssertNil(result.suggestions[1].destination)
        XCTAssertNil(transport.requests[0].httpBody)
    }
    func testInsightIndependentGate() async throws {
        let transport = MerchantMarketingFixtureTransport(), api = try service(transport, gates: .init(reads: true))
        do { _ = try await api.insight(); XCTFail() } catch { XCTAssertEqual(error as? MerchantMarketingFailure, .unavailable) }
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testAIFailureDoesNotRemoveFacts() throws {
        let result = try MerchantMarketingInsight(raw(#"{"facts":{"checkin":{"total":4}},"ai":null,"aiError":"Unavailable","generatedAt":"server-time"}"#))
        XCTAssertNil(result.ai); XCTAssertEqual(result.facts["checkin"]["total"].integer, 4); XCTAssertEqual(result.aiError, "Unavailable")
    }
    func testRouteAllowlistIsExact() {
        XCTAssertEqual(MerchantInsightDestination.allCases.map(\.sourcePath), ["/merchant/coop", "/merchant/decor", "/publish/pro"])
        XCTAssertNil(MerchantInsightDestination(rawValue: "/merchant/coop"))
    }
    func testEmptySubscriptionsAreSuccessful() async throws {
        let result = try await service(MerchantMarketingFixtureTransport(scenario: "empty")).subscriptions()
        XCTAssertTrue(result.isEmpty)
    }
    func testPermanentEntitlementAndQuotaNotCheckout() async throws {
        let api = try service(MerchantMarketingFixtureTransport()), subscriptions = try await api.subscriptions(), caps = try await api.commerce()
        XCTAssertTrue(try XCTUnwrap(subscriptions.first).isPermanent); XCTAssertEqual(caps.premiumTemplate?.remaining, 8)
        XCTAssertTrue(caps.selfCheckoutEnabledByServer); XCTAssertFalse(caps.iOSCheckoutAvailable)
    }
    func testEmptyInboxDoesNotControlAccess() async throws {
        let transport = MerchantMarketingFixtureTransport(scenario: "empty"), api = try service(transport)
        let inbox = try await api.inbox(); XCTAssertTrue(inbox.isEmpty)
        XCTAssertEqual(transport.requests.map { $0.url!.path }, ["/api/merchant/access/me", "/api/merchant/predict/inbox"])
    }
    func testRoundPreservesServerDeadlineAndOptions() throws {
        let round = try MerchantPredictionRound(raw(MerchantMarketingFixtureTransport.roundJSON))
        XCTAssertEqual(round.nodeID, "81"); XCTAssertEqual(round.daysLeft, 0); XCTAssertEqual(round.options.map(\.key), ["A", "B"])
    }
    func testSettlementRequiresAcknowledgedEffects() async throws {
        let transport = MerchantMarketingFixtureTransport(), api = try service(transport), review = try await review(api)
        do { _ = try await api.settle(review, acknowledgedCouponEffects: false); XCTFail() } catch { XCTAssertEqual(error as? MerchantMarketingFailure, .invalid) }
        XCTAssertFalse(transport.requests.contains { $0.url?.path.hasSuffix("settle") == true })
    }
    func testSettlementExactStringBodyAndWinners() async throws {
        let transport = MerchantMarketingFixtureTransport(), locks = MerchantPredictionMemoryLocks(), api = try service(transport, locks: locks), review = try await review(api)
        let result = try await api.settle(review, acknowledgedCouponEffects: true)
        XCTAssertEqual(result.winners, 3); XCTAssertEqual(locks.records.count, 1)
        let request = try XCTUnwrap(transport.requests.last), body = try JSONDecoder().decode([String: String].self, from: XCTUnwrap(request.httpBody))
        XCTAssertEqual(body, ["nodeId":"81", "playDay":"2026-10-01", "settledOption":"A"])
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }
    func testSuccessCannotBeReplayed() async throws {
        let transport = MerchantMarketingFixtureTransport(), api = try service(transport), review = try await review(api)
        _ = try await api.settle(review, acknowledgedCouponEffects: true)
        do { _ = try await api.settle(review, acknowledgedCouponEffects: true); XCTFail() } catch { XCTAssertEqual(error as? MerchantMarketingFailure, .invalid) }
        do { _ = try await self.review(api); XCTFail() } catch { XCTAssertEqual(error as? MerchantMarketingFailure, .locked) }
        XCTAssertEqual(transport.requests.filter { $0.url?.path.hasSuffix("settle") == true }.count, 1)
    }
    func testTimeoutLocksWithoutRetry() async throws {
        let transport = MerchantMarketingFixtureTransport(scenario: "unknown"), locks = MerchantPredictionMemoryLocks(), api = try service(transport, locks: locks), accepted = try await review(api)
        do { _ = try await api.settle(accepted, acknowledgedCouponEffects: true); XCTFail() } catch { XCTAssertEqual(error as? MerchantMarketingFailure, .unknown) }
        XCTAssertEqual(locks.records.count, 1)
        do { _ = try await review(api); XCTFail() } catch { XCTAssertEqual(error as? MerchantMarketingFailure, .locked) }
        XCTAssertEqual(transport.requests.filter { $0.url?.path.hasSuffix("settle") == true }.count, 1)
    }
    func testMissingWinnersIsUnknownNotZero() async throws {
        let transport = MerchantMarketingFixtureTransport(scenario: "malformed-winners"), locks = MerchantPredictionMemoryLocks(), api = try service(transport, locks: locks), accepted = try await review(api)
        do { _ = try await api.settle(accepted, acknowledgedCouponEffects: true); XCTFail() } catch { XCTAssertEqual(error as? MerchantMarketingFailure, .unknown) }
        XCTAssertEqual(locks.records.count, 1)
    }
    func testDefinitiveRejectionLeavesRoundAndAllowsNewReview() async throws {
        let transport = MerchantMarketingFixtureTransport(scenario: "rejected"), locks = MerchantPredictionMemoryLocks(), api = try service(transport, locks: locks), accepted = try await review(api)
        do { _ = try await api.settle(accepted, acknowledgedCouponEffects: true); XCTFail() } catch { XCTAssertEqual(error as? MerchantMarketingFailure, .rejected(403, "Source rejection")) }
        XCTAssertTrue(locks.records.isEmpty); _ = try await review(api)
    }
    func testPermissionChangedAfterReviewDispatchesNoSettlement() async throws {
        let transport = MerchantMarketingFixtureTransport(), api = try service(transport), accepted = try await review(api)
        transport.scenario = "denied"
        do { _ = try await api.settle(accepted, acknowledgedCouponEffects: true); XCTFail() } catch { XCTAssertEqual(error as? MerchantMarketingFailure, .stale) }
        XCTAssertFalse(transport.requests.contains { $0.url?.path.hasSuffix("settle") == true })
    }
    func testRoundChangedAfterReviewDispatchesNoSettlement() async throws {
        let transport = MerchantMarketingFixtureTransport(), api = try service(transport), accepted = try await review(api)
        transport.scenario = "empty"
        do { _ = try await api.settle(accepted, acknowledgedCouponEffects: true); XCTFail() } catch { XCTAssertEqual(error as? MerchantMarketingFailure, .stale) }
        XCTAssertFalse(transport.requests.contains { $0.url?.path.hasSuffix("settle") == true })
    }
    func testSessionChangeRejectsReview() async throws {
        let box = SessionBox(), transport = MerchantMarketingFixtureTransport(), api = try service(transport, box: box), accepted = try await review(api)
        box.value = SessionBox(epoch: 2).value
        do { _ = try await api.settle(accepted, acknowledgedCouponEffects: true); XCTFail() } catch { XCTAssertEqual(error as? MerchantMarketingFailure, .stale) }
        XCTAssertFalse(transport.requests.contains { $0.url?.path.hasSuffix("settle") == true })
    }
    func testOldReadDoesNotCrossAccount() async throws {
        let box = SessionBox(), transport = MerchantMarketingFixtureTransport(), api = try service(transport, box: box)
        transport.beforeReply = { _ in box.value = SessionBox(accountID: 701).value }
        do { _ = try await api.dashboard(); XCTFail() } catch { XCTAssertEqual(error as? MerchantMarketingFailure, .stale) }
        XCTAssertEqual(transport.requests.count, 1)
    }
    func testStorageFailurePreventsDispatch() async throws {
        let locks = MerchantPredictionMemoryLocks(), transport = MerchantMarketingFixtureTransport(), api = try service(transport, locks: locks), accepted = try await review(api)
        locks.failStorage = true
        do { _ = try await api.settle(accepted, acknowledgedCouponEffects: true); XCTFail() } catch { XCTAssertEqual(error as? MerchantMarketingFailure, .storage) }
        XCTAssertFalse(transport.requests.contains { $0.url?.path.hasSuffix("settle") == true })
    }
    func testDurableLocksExcludeEpochButIsolateNamespaceAndAccount() async throws {
        let transport = MerchantMarketingFixtureTransport(), first = try await review(service(transport)), record = try MerchantPredictionLock(first)
        let epoch = try await review(service(transport, box: SessionBox(epoch: 2)))
        let account = try await review(service(transport, box: SessionBox(accountID: 999)))
        let region = try await review(service(transport, box: SessionBox(namespace: "fixture-us")))
        XCTAssertEqual(record.key, try MerchantPredictionLock(epoch).key)
        XCTAssertNotEqual(record.key, try MerchantPredictionLock(account).key)
        XCTAssertNotEqual(record.key, try MerchantPredictionLock(region).key)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try MerchantPredictionFileLocks(directory: directory).acquire(record)
        XCTAssertTrue(try MerchantPredictionFileLocks(directory: directory).contains(record))
        XCTAssertThrowsError(try MerchantPredictionFileLocks(directory: directory).acquire(record))
        let bytes = try FileManager.default.subpathsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".json") }.map { try String(contentsOf: directory.appendingPathComponent($0)) }.joined()
        XCTAssertFalse(bytes.contains("fixture-token")); XCTAssertFalse(bytes.contains("epoch"))
    }
    func testCoordinatorClearsSensitiveStateOnSignOut() async throws {
        let box = SessionBox(), transport = MerchantMarketingFixtureTransport(), model = MerchantMarketingCoordinator(service: try service(transport, box: box))
        await model.load(.insight); XCTAssertNotNil(model.insight)
        box.value = nil; model.sessionChanged(); XCTAssertNil(model.insight); XCTAssertNil(model.review); XCTAssertNil(model.acknowledgement)
    }
    func testCoordinatorUnknownRetainsRoundAndNoAcknowledgement() async throws {
        let model = MerchantMarketingCoordinator(service: try service(MerchantMarketingFixtureTransport(scenario: "unknown")))
        await model.load(.predictions); let round = try XCTUnwrap(model.rounds?.first)
        await model.prepare(round, option: "A"); await model.confirm(couponEffectsAcknowledged: true)
        XCTAssertEqual(model.rounds?.count, 1); XCTAssertNil(model.acknowledgement); XCTAssertEqual(model.failure, .unknown)
    }
    func testDiscardedReviewCannotSubmit() async throws {
        let transport = MerchantMarketingFixtureTransport(), api = try service(transport), accepted = try await review(api)
        api.discardReview()
        do { _ = try await api.settle(accepted, acknowledgedCouponEffects: true); XCTFail() } catch { XCTAssertEqual(error as? MerchantMarketingFailure, .invalid) }
    }
    func testMalformedEndDateIsNotPermanent() throws {
        XCTAssertThrowsError(try MerchantMarketingEntitlement(raw(#"{"subscriptionType":"premium_template","endDate":{}}"#)))
    }
    func testInboxRejectsPageWrapper() async throws {
        let transport = MerchantMarketingFixtureTransport()
        transport.overrideReply = { request in request.url?.path.hasSuffix("inbox") == true ? (Data(#"{"code":200,"data":{"rows":[]}}"#.utf8), 200) : nil }
        do { _ = try await service(transport).inbox(); XCTFail() } catch { XCTAssertEqual(error as? MerchantMarketingFailure, .malformed) }
    }
    func testServer500AfterDispatchRetainsLock() async throws {
        let transport = MerchantMarketingFixtureTransport(), locks = MerchantPredictionMemoryLocks(), api = try service(transport, locks: locks)
        let accepted = try await review(api)
        transport.overrideReply = { request in request.url?.path.hasSuffix("settle") == true ? (Data(#"{"code":500,"msg":"Unconfirmed","data":null}"#.utf8), 500) : nil }
        do { _ = try await api.settle(accepted, acknowledgedCouponEffects: true); XCTFail() } catch { XCTAssertEqual(error as? MerchantMarketingFailure, .unknown) }
        XCTAssertEqual(locks.records.count, 1)
    }
    func testLockExistsBeforeSend() async throws {
        let transport = MerchantMarketingFixtureTransport(), locks = MerchantPredictionMemoryLocks(), api = try service(transport, locks: locks)
        let accepted = try await review(api)
        transport.beforeReply = { request in if request.url?.path.hasSuffix("settle") == true { XCTAssertEqual(locks.records.count, 1) } }
        _ = try await api.settle(accepted, acknowledgedCouponEffects: true)
    }
    func testReadGrantDoesNotGrantSettlement() async throws {
        let transport = MerchantMarketingFixtureTransport(), api = try service(transport, gates: .init(reads: true))
        let rows = try await api.inbox(), count = transport.requests.count
        do { _ = try await api.prepare(round: XCTUnwrap(rows.first), optionKey: "A"); XCTFail() } catch { XCTAssertEqual(error as? MerchantMarketingFailure, .unavailable) }
        XCTAssertEqual(transport.requests.count, count)
    }

}
