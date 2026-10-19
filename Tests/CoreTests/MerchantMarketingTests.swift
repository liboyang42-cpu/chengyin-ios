import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
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
    private func formBody(_ request: URLRequest) throws -> [String: String] {
        var components = URLComponents(); components.percentEncodedQuery = try XCTUnwrap(String(data: XCTUnwrap(request.httpBody), encoding: .utf8))
        let items = try XCTUnwrap(components.queryItems)
        XCTAssertEqual(Set(items.map(\.name)).count, items.count)
        return try Dictionary(uniqueKeysWithValues: items.map { ($0.name, try XCTUnwrap($0.value)) })
    }
    private func review(_ service: MerchantMarketingService) async throws -> MerchantPredictionReview {
        let rounds = try await service.inbox(); return try await service.prepare(round: XCTUnwrap(rounds.first), optionKey: "A")
    }
    func testReadOnlyPreparationNeedsNoReplayStoreAndPreservesCompleteSnapshot() async throws {
        let transport = MerchantMarketingFixtureTransport(), box = SessionBox()
        let api = MerchantMarketingService(configuration: try APIConfiguration(baseURL: XCTUnwrap(URL(string: "https://merchant-marketing.example"))),
            transport: transport, gates: .init(reads: true), locks: nil, currentSession: { box.value })
        let accepted = try await review(api)
        XCTAssertEqual(accepted.round.topicID, 12); XCTAssertEqual(accepted.round.betCount, 7)
        XCTAssertFalse(api.permitsSettlement)
        do { _ = try await api.settle(accepted, acknowledgedCouponEffects: true); XCTFail() }
        catch { XCTAssertEqual(error as? MerchantMarketingFailure, .unavailable) }
        XCTAssertTrue(transport.requests.allSatisfy { $0.httpBody == nil })
    }
    func testCompletePredictionReceiptRequiresMatchingChoiceAndConsistentCounts() throws {
        let value = try MerchantPredictionAcknowledgement(raw(#"{"settledOption":"A","totalBets":7,"winners":3,"couponsGranted":2,"rewardConfigured":true}"#), expectedOption: "A")
        XCTAssertEqual(value.totalBets, 7); XCTAssertEqual(value.winners, 3)
        XCTAssertEqual(value.couponsGranted, 2); XCTAssertTrue(value.rewardConfigured)
        for bad in [#"{"winners":3}"#,
                    #"{"settledOption":"B","totalBets":7,"winners":3,"couponsGranted":2,"rewardConfigured":true}"#,
                    #"{"settledOption":"A","totalBets":2,"winners":3,"couponsGranted":2,"rewardConfigured":true}"#,
                    #"{"settledOption":"A","totalBets":7,"winners":3,"couponsGranted":4,"rewardConfigured":true}"#,
                    #"{"settledOption":"A","totalBets":7,"winners":"3","couponsGranted":2,"rewardConfigured":true}"#,
                    #"{"settledOption":"A","totalBets":7,"winners":3,"couponsGranted":2,"rewardConfigured":1}"#] {
            XCTAssertThrowsError(try MerchantPredictionAcknowledgement(raw(bad), expectedOption: "A"))
        }
    }
    func testStrictRoundRejectsWhitespaceOptionKeysInvalidDaysAndNegativeCounts() throws {
        let original = MerchantMarketingFixtureTransport.roundJSON
        for bad in [original.replacingOccurrences(of: "\"key\":\"A\"", with: "\"key\":\" A \""),
                    original.replacingOccurrences(of: "2026-10-01", with: "2026-02-30"),
                    original.replacingOccurrences(of: "\"betCount\":7", with: "\"betCount\":-1"),
                    original.replacingOccurrences(of: "\"nodeId\":81", with: "\"nodeId\":9007199254740993")] {
            XCTAssertThrowsError(try MerchantPredictionRound(raw(bad)))
        }
    }
    func testCanonicallyEquivalentUnicodeKeysCannotMatchAnotherBackendKeyOrReceipt() async throws {
        let composed = "\u{00E9}", decomposed = "e\u{0301}"
        XCTAssertEqual(composed, decomposed) // Swift equality alone is not the backend contract.
        let first = MerchantMarketingFixtureTransport.roundJSON.replacingOccurrences(of: "\"key\":\"A\"", with: "\"key\":\"\(composed)\"")
        let second = MerchantMarketingFixtureTransport.roundJSON.replacingOccurrences(of: "\"key\":\"A\"", with: "\"key\":\"\(decomposed)\"")
        let round = try MerchantPredictionRound(raw(first))
        XCTAssertNotEqual(round, try MerchantPredictionRound(raw(second)))
        let transport = MerchantMarketingFixtureTransport(), api = try service(transport)
        transport.overrideReply = { request in request.url?.path.hasSuffix("inbox") == true
            ? (Data("{\"code\":200,\"data\":[\(first)]}".utf8), 200) : nil }
        do { _ = try await api.prepare(round: round, optionKey: decomposed); XCTFail() }
        catch { XCTAssertEqual(error as? MerchantMarketingFailure, .stale) }
        let receipt: MerchantMarketingValue = .object(["settledOption": .string(decomposed), "totalBets": .number(7),
            "winners": .number(3), "couponsGranted": .number(2), "rewardConfigured": .bool(true)])
        XCTAssertThrowsError(try MerchantPredictionAcknowledgement(receipt, expectedOption: composed))
    }
    func testTopicChangeAfterReviewPreventsSettlementAndIntent() async throws {
        let transport = MerchantMarketingFixtureTransport(), locks = MerchantPredictionMemoryLocks(), api = try service(transport, locks: locks)
        let accepted = try await review(api)
        transport.overrideReply = { request in
            guard request.url?.path.hasSuffix("inbox") == true else { return nil }
            let changed = MerchantMarketingFixtureTransport.roundJSON.replacingOccurrences(of: "\"topicId\":12", with: "\"topicId\":13")
            return (Data("{\"code\":200,\"data\":[\(changed)]}".utf8), 200)
        }
        do { _ = try await api.settle(accepted, acknowledgedCouponEffects: true); XCTFail() }
        catch { XCTAssertEqual(error as? MerchantMarketingFailure, .stale) }
        XCTAssertTrue(locks.records.isEmpty)
        XCTAssertFalse(transport.requests.contains { $0.url?.path.hasSuffix("settle") == true })
    }
    func testSettlementFormEscapesChosenOptionWithoutAddingFields() async throws {
        let transport = MerchantMarketingFixtureTransport(), api = try service(transport)
        transport.overrideReply = { request in
            guard request.url?.path.hasSuffix("inbox") == true else { return nil }
            let changed = MerchantMarketingFixtureTransport.roundJSON.replacingOccurrences(of: "\"key\":\"A\"", with: "\"key\":\"A &+\"")
            return (Data("{\"code\":200,\"data\":[\(changed)]}".utf8), 200)
        }
        let rows = try await api.inbox(), round = try XCTUnwrap(rows.first)
        let review = try await api.prepare(round: round, optionKey: "A &+")
        let receipt = try await api.settle(review, acknowledgedCouponEffects: true)
        XCTAssertEqual(receipt.settledOption, "A &+")
        let request = try XCTUnwrap(transport.requests.last)
        XCTAssertEqual(try formBody(request), ["nodeId":"81", "playDay":"2026-10-01", "settledOption":"A &+"])
        XCTAssertTrue(String(data: request.httpBody!, encoding: .utf8)!.contains("settledOption=A%20%26%2B"))
        XCTAssertFalse(request.httpShouldHandleCookies)
    }
    func testEveryDispatchedHTTPFailureKeepsReplayLock() async throws {
        for status in [401, 403, 404, 408, 409, 429, 500] {
            let transport = MerchantMarketingFixtureTransport(), locks = MerchantPredictionMemoryLocks(), api = try service(transport, locks: locks)
            let accepted = try await review(api)
            transport.overrideReply = { request in request.url?.path.hasSuffix("settle") == true
                ? (Data("{\"code\":\(status),\"data\":null}".utf8), status) : nil }
            do { _ = try await api.settle(accepted, acknowledgedCouponEffects: true); XCTFail() }
            catch { XCTAssertEqual(error as? MerchantMarketingFailure, status == 401 ? .signIn : .unknown) }
            XCTAssertEqual(locks.records.count, 1)
            do { _ = try await review(api); XCTFail() } catch { XCTAssertEqual(error as? MerchantMarketingFailure, .locked) }
        }
    }
    func testDiscardDuringPreparationSuppressesSameSessionUnauthorizedCallback() async throws {
        let transport = MerchantMarketingFixtureTransport(), box = SessionBox()
        var expired = 0
        let api = MerchantMarketingService(configuration: try APIConfiguration(baseURL: XCTUnwrap(URL(string: "https://merchant-marketing.example"))),
            transport: transport, gates: .init(reads: true), locks: nil, currentSession: { box.value }, onUnauthorized: { _ in expired += 1 })
        let rows = try await api.inbox(), round = try XCTUnwrap(rows.first)
        transport.beforeReply = { _ in api.discardReview() }
        transport.overrideReply = { _ in (Data(#"{"code":401}"#.utf8), 401) }
        do { _ = try await api.prepare(round: round, optionKey: "A"); XCTFail() }
        catch { XCTAssertEqual(error as? MerchantMarketingFailure, .stale) }
        XCTAssertEqual(expired, 0)
    }
    func testReviewRetiredAfterDispatchKeepsLockAndSuppressesSuccessAndUnauthorized() async throws {
        for status in [200, 401] {
            let transport = MerchantMarketingFixtureTransport(), box = SessionBox(), locks = MerchantPredictionMemoryLocks()
            var expired = 0
            let api = MerchantMarketingService(configuration: try APIConfiguration(baseURL: XCTUnwrap(URL(string: "https://merchant-marketing.example"))),
                transport: transport, gates: .init(reads: true, settlement: true), locks: locks,
                currentSession: { box.value }, onUnauthorized: { _ in expired += 1 })
            let accepted = try await review(api)
            transport.beforeReply = { request in if request.url?.path.hasSuffix("settle") == true { api.discardReview() } }
            if status == 401 {
                transport.overrideReply = { request in request.url?.path.hasSuffix("settle") == true ? (Data(#"{"code":401}"#.utf8), 401) : nil }
            }
            do { _ = try await api.settle(accepted, acknowledgedCouponEffects: true); XCTFail() }
            catch { XCTAssertEqual(error as? MerchantMarketingFailure, .stale) }
            XCTAssertEqual(locks.records.count, 1); XCTAssertEqual(expired, 0)
            XCTAssertEqual(transport.requests.filter { $0.url?.path.hasSuffix("settle") == true }.count, 1)
        }
    }
    func testFailedPreflightConsumesReviewWithoutCreatingReplayIntent() async throws {
        let transport = MerchantMarketingFixtureTransport(), locks = MerchantPredictionMemoryLocks(), api = try service(transport, locks: locks)
        let accepted = try await review(api)
        transport.overrideReply = { _ in (Data(#"{"code":503}"#.utf8), 503) }
        do { _ = try await api.settle(accepted, acknowledgedCouponEffects: true); XCTFail() } catch { }
        let count = transport.requests.count
        do { _ = try await api.settle(accepted, acknowledgedCouponEffects: true); XCTFail() }
        catch { XCTAssertEqual(error as? MerchantMarketingFailure, .invalid) }
        XCTAssertEqual(transport.requests.count, count); XCTAssertTrue(locks.records.isEmpty)
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
    func testSettlementExactFormBodyAndCompleteReceipt() async throws {
        let transport = MerchantMarketingFixtureTransport(), locks = MerchantPredictionMemoryLocks(), api = try service(transport, locks: locks), review = try await review(api)
        let result = try await api.settle(review, acknowledgedCouponEffects: true)
        XCTAssertEqual(result.winners, 3); XCTAssertEqual(locks.records.count, 1)
        let request = try XCTUnwrap(transport.requests.last), body = try formBody(request)
        XCTAssertEqual(body, ["nodeId":"81", "playDay":"2026-10-01", "settledOption":"A"])
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded; charset=utf-8")
        XCTAssertFalse(request.httpShouldHandleCookies)
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
    func testDispatchedRejectionKeepsRoundLockAndDisallowsNewReview() async throws {
        let transport = MerchantMarketingFixtureTransport(scenario: "rejected"), locks = MerchantPredictionMemoryLocks(), api = try service(transport, locks: locks), accepted = try await review(api)
        do { _ = try await api.settle(accepted, acknowledgedCouponEffects: true); XCTFail() } catch { XCTAssertEqual(error as? MerchantMarketingFailure, .unknown) }
        XCTAssertEqual(locks.records.count, 1)
        do { _ = try await review(api); XCTFail() } catch { XCTAssertEqual(error as? MerchantMarketingFailure, .locked) }
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
    func testReadGrantAllowsFreshReviewButNeverSettlement() async throws {
        let transport = MerchantMarketingFixtureTransport(), api = try service(transport, gates: .init(reads: true))
        let rows = try await api.inbox(), count = transport.requests.count
        let review = try await api.prepare(round: XCTUnwrap(rows.first), optionKey: "A")
        XCTAssertEqual(transport.requests.count, count + 2)
        do { _ = try await api.settle(review, acknowledgedCouponEffects: true); XCTFail() } catch { XCTAssertEqual(error as? MerchantMarketingFailure, .unavailable) }
        XCTAssertEqual(transport.requests.count, count + 2)
        XCTAssertFalse(transport.requests.contains { $0.url?.path.hasSuffix("settle") == true })
    }

}

extension MerchantMarketingTests {
    func testOldReviewCancelDoesNotDiscardReopenedServiceReview() async throws {
        let transport = MerchantMarketingFixtureTransport(), model = MerchantMarketingCoordinator(service: try service(transport))
        await model.load(.predictions); let round = try XCTUnwrap(model.rounds?.first)
        await model.prepare(round, option: "A"); let first = try XCTUnwrap(model.review)
        model.cancelReview(id: first.id)
        await model.prepare(round, option: "B"); let second = try XCTUnwrap(model.review)
        let reads = transport.requests.count
        model.cancelReview(id: first.id)
        XCTAssertEqual(model.review, second); XCTAssertEqual(transport.requests.count, reads)
        await model.confirm(reviewID: second.id, couponEffectsAcknowledged: true)
        XCTAssertEqual(model.acknowledgement?.winners, 3)
        let request = try XCTUnwrap(transport.requests.last)
        let body = try formBody(request)
        XCTAssertEqual(body, ["nodeId": "81", "playDay": "2026-10-01", "settledOption": "B"])
    }
    func testOldAcknowledgementCannotConfirmNewReviewOrCreateIntent() async throws {
        let transport = MerchantMarketingFixtureTransport(), locks = MerchantPredictionMemoryLocks()
        let model = MerchantMarketingCoordinator(service: try service(transport, locks: locks))
        await model.load(.predictions); let round = try XCTUnwrap(model.rounds?.first)
        await model.prepare(round, option: "A"); let first = try XCTUnwrap(model.review)
        model.cancelReview(id: first.id); await model.prepare(round, option: "B")
        let second = try XCTUnwrap(model.review), reads = transport.requests.count
        await model.confirm(reviewID: first.id, couponEffectsAcknowledged: true)
        XCTAssertEqual(model.review, second); XCTAssertEqual(transport.requests.count, reads)
        XCTAssertTrue(locks.records.isEmpty); XCTAssertNil(model.acknowledgement); XCTAssertNil(model.failure)
    }
    func testCapturedQueuedReviewCannotAdoptReplacementAtExecutionTime() async throws {
        let transport = MerchantMarketingFixtureTransport(), model = MerchantMarketingCoordinator(service: try service(transport))
        await model.load(.predictions); let round = try XCTUnwrap(model.rounds?.first)
        await model.prepare(round, option: "A"); let first = try XCTUnwrap(model.review)
        let queued = { await model.confirm(reviewID: first.id, couponEffectsAcknowledged: true) }
        model.cancelReview(id: first.id); await model.prepare(round, option: "B")
        let second = try XCTUnwrap(model.review), reads = transport.requests.count
        await queued()
        XCTAssertEqual(model.review, second); XCTAssertEqual(transport.requests.count, reads)
    }
    func testExactReviewStillUsesUnknownOutcomeLockWithoutResending() async throws {
        let transport = MerchantMarketingFixtureTransport(scenario: "unknown"), locks = MerchantPredictionMemoryLocks()
        let model = MerchantMarketingCoordinator(service: try service(transport, locks: locks))
        await model.load(.predictions); let round = try XCTUnwrap(model.rounds?.first)
        await model.prepare(round, option: "A"); let accepted = try XCTUnwrap(model.review)
        await model.confirm(reviewID: accepted.id, couponEffectsAcknowledged: true)
        XCTAssertEqual(model.failure, .unknown); XCTAssertNil(model.review); XCTAssertEqual(locks.records.count, 1)
        let dispatched = transport.requests.filter { $0.url?.path.hasSuffix("settle") == true }.count
        model.cancelReview(id: accepted.id)
        await model.confirm(reviewID: accepted.id, couponEffectsAcknowledged: true)
        XCTAssertEqual(locks.records.count, 1)
        XCTAssertEqual(transport.requests.filter { $0.url?.path.hasSuffix("settle") == true }.count, dispatched)
        XCTAssertEqual(dispatched, 1); XCTAssertNil(model.acknowledgement)
    }
}
