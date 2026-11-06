import Foundation
import XCTest
@testable import QuestifyCore

/// Authored, NOT_RUN. Uses the unchanged in-memory fixture, never a real transport.
@MainActor final class MerchantMarketingCancelledLoadTests: XCTestCase {
    private func make() throws -> (MerchantMarketingCoordinator, MerchantMarketingFixtureTransport) {
        let scope = try MerchantMarketingScope(namespace: "cancelled-read-test", accountID: 700, epoch: 1, token: "synthetic-token")
        let transport = MerchantMarketingFixtureTransport()
        let service = MerchantMarketingService(configuration: try APIConfiguration(baseURL: URL(string: "https://example.com/")!),
            transport: transport, gates: .init(reads: true, insight: true, settlement: false), locks: nil, currentSession: { scope })
        return (MerchantMarketingCoordinator(service: service), transport)
    }
    func testCancelledQueuedLoadPreservesCompletedCurrentRead() async throws {
        let (model, transport) = try make()
        await model.load(.insight)
        XCTAssertNotNil(model.insight)
        XCTAssertNil(model.failure)
        let count = transport.requests.count
        // MainActor cannot start this queued task until this synchronous turn yields.
        let retired = Task { @MainActor in await model.load(.dashboard) }
        retired.cancel()
        await retired.value
        XCTAssertEqual(model.surface, .insight)
        XCTAssertNotNil(model.insight)
        XCTAssertNil(model.failure)
        XCTAssertFalse(model.busy)
        XCTAssertEqual(transport.requests.count, count)
    }
    func testCancelledInitialLoadDoesNotMutateOrDispatch() async throws {
        let (model, transport) = try make()
        let retired = Task { @MainActor in await model.load(.subscriptions) }
        retired.cancel()
        await retired.value
        XCTAssertEqual(model.surface, .dashboard)
        XCTAssertFalse(model.busy)
        XCTAssertNil(model.failure)
        XCTAssertNil(model.subscriptions)
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testNewExplicitLoadStillWorksAfterCancelledQueuedLoad() async throws {
        let (model, transport) = try make()
        let retired = Task { @MainActor in await model.load(.dashboard) }
        retired.cancel()
        await retired.value
        await model.load(.insight)
        XCTAssertEqual(model.surface, .insight)
        XCTAssertNotNil(model.insight)
        XCTAssertNil(model.failure)
        XCTAssertFalse(model.busy)
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(transport.requests.first?.url?.path, "/api/ai/merchant/insight")
    }
}
