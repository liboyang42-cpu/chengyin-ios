import XCTest
@testable import QuestifyCore

@MainActor final class WithdrawalSupportConfigurationTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1000)
    private func configuration(namespace: String = "synthetic-cn", market: RegionalMarket = .china,
                               revision: String = "r1", expiry: Date? = nil) throws -> WithdrawalSupportConfiguration {
        try .init(namespace: namespace, market: market, revision: revision, expiresAt: expiry ?? date.addingTimeInterval(60),
                  contact: .init(weChatID: "synthetic_support"))
    }
    func testUnavailableDoesNotFetchOrExposeContact() async {
        var calls = 0
        let reader = WithdrawalSupportReader(source: { calls += 1; return nil }, session: {
            .init(namespace: "synthetic-cn", accountID: 1, epoch: UUID())
        })
        do { _ = try await reader.read(); XCTFail("unapproved source") } catch {}
        XCTAssertEqual(calls, 0)
    }
    func testFreshCopyAndRevocationAtActionTime() async throws {
        let scope = WalletCommerceScope(namespace: "synthetic-cn", accountID: 1, epoch: UUID())
        var approval: WithdrawalSupportApproval? = .init(id: "synthetic-review", market: .china)
        var value: WithdrawalSupportConfiguration? = try configuration()
        var now = date
        let reader = WithdrawalSupportReader(source: { value }, approval: { approval }, now: { now }, session: { scope })
        let shown = try await reader.read()
        let copied = try await reader.contactForCopy(shown)
        XCTAssertEqual(copied, "synthetic_support")
        approval = nil
        do { _ = try await reader.contactForCopy(shown); XCTFail("revoked approval") } catch {}
        approval = .init(id: "synthetic-review", market: .china)
        value = nil
        do { _ = try await reader.contactForCopy(shown); XCTFail("revoked contact") } catch {}
        value = try configuration()
        now = date.addingTimeInterval(60)
        do { _ = try await reader.contactForCopy(shown); XCTFail("expired") } catch {}
    }
    func testMarketNamespaceRevisionAndAccountABARejected() async throws {
        var scope = WalletCommerceScope(namespace: "synthetic-cn", accountID: 1, epoch: UUID())
        var value = try configuration()
        let reader = WithdrawalSupportReader(source: { value }, approval: { .init(id: "review", market: .china) }, now: { self.date }, session: { scope })
        let shown = try await reader.read()
        value = try configuration(namespace: "other")
        do { _ = try await reader.read(); XCTFail("namespace") } catch {}
        value = try configuration(market: .unitedStates)
        do { _ = try await reader.read(); XCTFail("market") } catch {}
        value = try configuration(revision: "r2")
        do { _ = try await reader.contactForCopy(shown); XCTFail("revision") } catch {}
        value = try configuration()
        scope = .init(namespace: scope.namespace, accountID: scope.accountID, epoch: UUID())
        do { _ = try await reader.contactForCopy(shown); XCTFail("ABA") } catch {}
    }
    func testInFlightScopeAndApprovalChangesRejected() async throws {
        var scope = WalletCommerceScope(namespace: "synthetic-cn", accountID: 1, epoch: UUID())
        var approval: WithdrawalSupportApproval? = .init(id: "review", market: .china)
        let value = try configuration()
        let reader = WithdrawalSupportReader(source: {
            scope = .init(namespace: scope.namespace, accountID: 2, epoch: UUID())
            return value
        }, approval: { approval }, now: { self.date }, session: { scope })
        do { _ = try await reader.read(); XCTFail("in-flight account change") } catch {}
        let revoked = WithdrawalSupportReader(source: { approval = nil; return value }, approval: { approval }, now: { self.date }, session: { scope })
        do { _ = try await revoked.read(); XCTFail("in-flight revocation") } catch {}
    }
    func testCancelledReadDoesNotReturnContact() async throws {
        let value = try configuration()
        let scope = WalletCommerceScope(namespace: "synthetic-cn", accountID: 1, epoch: UUID())
        let reader = WithdrawalSupportReader(source: { value }, approval: { .init(id: "review", market: .china) }, now: { self.date }, session: { scope })
        let task = Task { try await reader.read() }
        task.cancel()
        do { _ = try await task.value; XCTFail("cancelled") } catch {}
    }
}

final class WithdrawalSupportActionFenceTests: XCTestCase {
    func testCloseOrBackgroundRetiresQueuedCopyAndRetry() {
        var fence = WithdrawalSupportActionFence(); let offered = fence.id
        fence.invalidate()
        XCTAssertFalse(fence.accepts(offered)); XCTAssertNil(fence.begin(offered: offered))
    }
    func testNewActionRetiresBothOldCompletionAndDuplicateQueuedAction() throws {
        var fence = WithdrawalSupportActionFence(); let offered = fence.id
        let current = try XCTUnwrap(fence.begin(offered: offered))
        XCTAssertNotEqual(current, offered); XCTAssertTrue(fence.accepts(current))
        XCTAssertNil(fence.begin(offered: offered)); XCTAssertTrue(fence.accepts(current))
    }
    func testReopenedPageCannotLendLifetimeToPriorAction() throws {
        var fence = WithdrawalSupportActionFence(); let old = fence.id
        fence.invalidate(); let reopened = fence.id
        let current = try XCTUnwrap(fence.begin(offered: reopened))
        XCTAssertNil(fence.begin(offered: old)); XCTAssertTrue(fence.accepts(current))
        fence.invalidate(); XCTAssertFalse(fence.accepts(current))
    }
    func testIndependentScreensCannotAcceptEachOthersTickets() {
        var first = WithdrawalSupportActionFence(); let second = WithdrawalSupportActionFence()
        let original = first.id
        XCTAssertNil(first.begin(offered: second.id)); XCTAssertTrue(first.accepts(original))
    }
}
