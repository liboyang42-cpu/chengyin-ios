import XCTest
import SwiftUI
@testable import Questify

@MainActor final class MerchantLedgerDenialPropagationTests: XCTestCase {
    func testDetailDenialPropagatesOnceToParentWithoutReturnRefresh() async throws {
        let reader = LedgerDeniedReader()
        let denied = expectation(description: "current detail denied")
        var returns = 0
        let owner = MerchantLedgerSettlementOwner(scope: reader.scope, authorizationGeneration: reader.authorizationGeneration)
        let model = MerchantLedgerBatchDetailModel(reader: reader, batchID: 66001, owner: owner,
            onDenied: { denied.fulfill() }, onReturn: { returns += 1 })
        model.appear()
        await fulfillment(of: [denied], timeout: 1)
        XCTAssertEqual(model.state.slot.failureKey, "merchant.business.denied")
        XCTAssertNil(model.state.slot.snapshot)
        XCTAssertEqual(returns, 0)
        model.disappear()
        XCTAssertEqual(returns, 1)
    }
    func testOrdinaryDetailFailureDoesNotRevokeParent() async throws {
        let reader = LedgerDeniedReader(); reader.failure = .stale
        let received = expectation(description: "read returned"); reader.onRead = { received.fulfill() }
        var denials = 0
        let model = MerchantLedgerBatchDetailModel(reader: reader, batchID: 66001,
            owner: .init(scope: reader.scope, authorizationGeneration: reader.authorizationGeneration),
            onDenied: { denials += 1 }, onReturn: {})
        model.appear()
        await fulfillment(of: [received], timeout: 1)
        await Task.yield()
        XCTAssertEqual(denials, 0)
        model.disappear()
    }
}
@MainActor private final class LedgerDeniedReader: MerchantBusinessReading {
    var scope: MerchantBusinessScope? = .init(realm: "fixture", accountID: 42, epoch: 1)
    var authorizationGeneration: UUID? = UUID()
    var isConfigured: Bool { true }
    var isOfflineExample: Bool { false }
    var canExecuteSyntheticMutation: Bool { false }
    var failure: MerchantBusinessFailure = .denied
    var onRead: () -> Void = {}
    func access() async throws -> MerchantBusinessAccess { throw failure }
    func snapshot(_ query: MerchantBusinessQuery) async throws -> MerchantBusinessSnapshot { onRead(); throw failure }
    func execute(_ mutation: MerchantBusinessMutation, requestID: String, scope: MerchantBusinessScope) async throws -> MerchantBusinessReceipt { throw MerchantBusinessFailure.disabled }
}
