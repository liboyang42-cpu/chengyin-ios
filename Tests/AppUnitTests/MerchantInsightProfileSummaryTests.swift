import XCTest
@testable import Questify

@MainActor final class MerchantInsightProfileSummaryTests: XCTestCase {
    private func view(_ profile: MerchantMarketingValue, scoped: Bool = true) -> MerchantInsightProfileSummary {
        .init(profile: profile, origin: scoped ? .init(merchantID: 31, readerScope: UUID()) : nil, open: { _ in })
    }
    func testExplicitFalseRemainsUnconfiguredEvenWithCapacityOrDemand() {
        let value = view(.object(["configured": .bool(false), "capacity": .number(20), "demand": .string("A real request")]))
        XCTAssertEqual(value.configurationState, false); XCTAssertEqual(value.capacity, 20)
        XCTAssertEqual(value.demand, "A real request"); XCTAssertTrue(value.canOpen)
    }
    func testMissingNullOrMalformedConfiguredIsUnknownWithoutNavigation() {
        for state in [MerchantMarketingValue.null, .string("false"), .number(0), .object([:])] {
            let value = view(.object(["configured": state, "capacity": .number(20)]))
            XCTAssertNil(value.configurationState); XCTAssertFalse(value.canOpen)
        }
        XCTAssertNil(view(.object([:])).configurationState)
        XCTAssertFalse(view(.null).canOpen)
    }
    func testZeroCapacityIsKnownButMalformedCountsAreNotCoerced() {
        XCTAssertEqual(view(.object(["capacity": .number(0)])).capacity, 0)
        for capacity in [MerchantMarketingValue.bool(false), .string("12"), .number(-1), .number(1.5), .null] {
            XCTAssertNil(view(.object(["capacity": capacity])).capacity)
        }
    }
    func testKnownStateStillNeedsSourceStoreScopeAndTypedRoute() throws {
        XCTAssertFalse(view(.object(["configured": .bool(true)]), scoped: false).canOpen)
        let origin = try XCTUnwrap(MerchantInsightOrigin(merchantID: 31, readerScope: UUID()))
        XCTAssertEqual(MerchantInsightDestination.cooperationSettings(origin).sourcePath, "/merchant/decor/coop-setting")
        XCTAssertNil(MerchantInsightDestination(rawValue: "cooperationSettings"))
        XCTAssertNil(MerchantInsightDestination(rawValue: "/merchant/decor/coop-setting"))
    }
}

@MainActor final class MerchantPredictionReviewOwnerTests: XCTestCase {
    @MainActor private final class Session {
        var scope: MerchantMarketingScope?
        init() throws { scope = try .init(namespace: "synthetic-review-owner", accountID: 7, epoch: 1, token: "synthetic-token") }
    }
    private func fixture() throws -> (MerchantMarketingCoordinator, MerchantMarketingFixtureTransport, Session) {
        let session = try Session(), transport = MerchantMarketingFixtureTransport()
        let service = try MerchantMarketingService(configuration: APIConfiguration(baseURL: XCTUnwrap(URL(string: "https://marketing.example"))),
            transport: transport, gates: .init(reads: true, insight: true, settlement: true),
            locks: MerchantPredictionMemoryLocks(), currentSession: { session.scope })
        return (.init(service: service), transport, session)
    }
    private func open(_ model: MerchantMarketingCoordinator) async throws -> MerchantPredictionReview {
        let round = try XCTUnwrap(model.rounds?.first)
        await model.prepare(round, option: "A")
        return try XCTUnwrap(model.review)
    }
    func testInitialNilBindingNeverAdoptsFutureReview() async throws {
        let (model, transport, _) = try fixture()
        let empty = model.predictionReviewPresentation(for: nil)
        await model.load(.predictions); let review = try await open(model), reads = transport.requests.count
        XCTAssertNil(empty.wrappedValue)
        empty.wrappedValue = review; empty.wrappedValue = nil
        XCTAssertEqual(model.review, review); XCTAssertEqual(transport.requests.count, reads)
    }
    func testOldBindingAndDismissCannotReadOrClearReopenedReview() async throws {
        let (model, transport, _) = try fixture(); await model.load(.predictions)
        let first = try await open(model), old = model.predictionReviewPresentation(for: first)
        XCTAssertEqual(old.wrappedValue, first); old.wrappedValue = nil
        XCTAssertNil(model.review)
        let second = try await open(model), current = model.predictionReviewPresentation(for: second), reads = transport.requests.count
        XCTAssertNotEqual(first.id, second.id); XCTAssertNil(old.wrappedValue)
        old.wrappedValue = second; old.wrappedValue = nil; model.cancelReview(id: first.id)
        XCTAssertEqual(current.wrappedValue, second); XCTAssertEqual(transport.requests.count, reads)
        current.wrappedValue = nil; XCTAssertNil(model.review)
    }
    func testCapturedBindingRejectsOwnerChangeBeforeHostObserver() async throws {
        let (model, transport, session) = try fixture(); await model.load(.predictions)
        let first = try await open(model), binding = model.predictionReviewPresentation(for: first), reads = transport.requests.count
        session.scope = try .init(namespace: "synthetic-review-owner", accountID: 8, epoch: 2, token: "synthetic-token")
        XCTAssertNil(binding.wrappedValue); XCTAssertEqual(transport.requests.count, reads)
        model.sessionChanged(); await model.load(.predictions); let second = try await open(model)
        binding.wrappedValue = nil; model.cancelReview(id: first.id)
        XCTAssertEqual(model.review, second)
    }
}
