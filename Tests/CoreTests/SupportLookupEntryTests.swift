import XCTest
@testable import QuestifyCore

final class SupportLookupEntryTests: XCTestCase {
    func testFirstJourneySupportLookupBesideWithdrawalAndOrderRecoverOriginal() throws {
        let source = CountingOriginalEvents()
            .add(OriginalAuditEvent(
                requestId: "c11-lookup-order-first", targetType: "ORDER", targetId: 501,
                action: "CREATE", afterJson: "UNKNOWN"))
            .add(OriginalAuditEvent(
                requestId: "c11-lookup-order-first", targetType: "RUN", targetId: 77,
                action: "RUN_ATTACH", afterJson: "UNKNOWN"))
            .add(OriginalAuditEvent(
                requestId: "c11-lookup-run-first", targetType: "RUN", targetId: 2,
                action: "START", afterJson: "PENDING"))
            .add(OriginalAuditEvent(
                requestId: "c11-lookup-run-first", targetType: "ORDER", targetId: 9,
                action: "CREATE", afterJson: "PENDING"))
        let locator = SupportEventLocator(originalEvents: source)
        let projection = SupportCurrentProjection(
            requestId: "c11-lookup-order-first",
            appliedState: SupportEventLocator.projectionAppliedSuccess)
        var entry = SupportLookupEntry(locator: locator)
        let withdrawal = try withdrawalRead()

        entry.appear()
        XCTAssertTrue(entry.appeared)
        XCTAssertEqual(entry.sends, 0)
        XCTAssertEqual(entry.lookups, 0)
        XCTAssertEqual(source.finds, 0)

        let byOrder = try XCTUnwrap(entry.lookupByOrderId(
            501, currentProjection: projection, withdrawal: withdrawal, orderRead: .detail(501)))
        XCTAssertEqual(byOrder.located.requestId, "c11-lookup-order-first")
        XCTAssertEqual(byOrder.located.originalOutcome, "UNKNOWN")
        XCTAssertTrue(byOrder.located.originalIsNotProjectionSuccess)
        XCTAssertNotEqual(byOrder.located.originalOutcome, SupportEventLocator.projectionAppliedSuccess)
        XCTAssertEqual(byOrder.located.orderId, 501)
        XCTAssertEqual(byOrder.withdrawal?.contact.weChatID, "synthetic_support")
        XCTAssertEqual(byOrder.orderRead, .detail(501))
        XCTAssertEqual(entry.sends, 0)
        let mismatchedOrder = try XCTUnwrap(entry.lookupByOrderId(
            501, currentProjection: projection, withdrawal: withdrawal, orderRead: .detail(999)))
        XCTAssertNil(mismatchedOrder.orderRead)
        XCTAssertEqual(mismatchedOrder.located.orderId, 501)
        let listedOrder = try XCTUnwrap(entry.lookupByOrderId(
            501, currentProjection: projection, withdrawal: withdrawal, orderRead: .list))
        XCTAssertNil(listedOrder.orderRead)

        XCTAssertEqual(try locator.locateByRunId(77, currentProjection: projection)?.runId, 77)
        XCTAssertThrowsError(try entry.lookupByRunId(
            77, currentProjection: projection, withdrawal: withdrawal, orderRead: .detail(501))) { error in
            XCTAssertEqual(error as? SupportLocateFailure, .originalMissing(requestId: "RUN:77"))
        }
        XCTAssertNotNil(try locator.locateByOrderId(9, currentProjection: nil))
        XCTAssertThrowsError(try entry.lookupByOrderId(
            9, currentProjection: nil, withdrawal: withdrawal, orderRead: .detail(9))) { error in
            XCTAssertEqual(error as? SupportLocateFailure, .originalMissing(requestId: "ORDER:9"))
        }
        let byRun = try XCTUnwrap(entry.lookupByRunId(
            2, currentProjection: nil, withdrawal: withdrawal, orderRead: .detail(9)))
        XCTAssertEqual(byRun.located.runId, 2)
        XCTAssertEqual(byRun.located.orderId, 9)
        XCTAssertEqual(byRun.orderRead, .detail(9))
        XCTAssertEqual(byRun.withdrawal?.scope.accountID, withdrawal.scope.accountID)
        XCTAssertEqual(entry.sends, 0)

        let recovered = try XCTUnwrap(locator.recoverOriginal(
            originalRequestID: "c11-lookup-order-first", currentProjection: projection))
        XCTAssertEqual(recovered.originalOutcome, "UNKNOWN")
        XCTAssertEqual(source.inner.findByRequestId("c11-lookup-order-first").count, 2)
        XCTAssertEqual(source.inner.findByRequestId("c11-lookup-run-first").count, 2)
        XCTAssertTrue(source.inner.findByRequestId("synthetic_support").isEmpty)
        XCTAssertTrue(source.inner.findByRequestId("RUN:77").isEmpty)
        XCTAssertEqual(entry.sends, 0)
    }

    func testAppearanceDoesNotSendAndBlankIdsDoNotInventEvents() throws {
        let source = CountingOriginalEvents()
        var entry = SupportLookupEntry(locator: SupportEventLocator(originalEvents: source))
        entry.appear()
        entry.appear()
        XCTAssertNil(try entry.lookupByRunId(nil, currentProjection: nil, withdrawal: nil, orderRead: nil))
        XCTAssertNil(try entry.lookupByRunId(0, currentProjection: nil, withdrawal: nil, orderRead: nil))
        XCTAssertNil(try entry.lookupByOrderId(nil, currentProjection: nil, withdrawal: nil, orderRead: nil))
        XCTAssertNil(try entry.lookupByOrderId(-1, currentProjection: nil, withdrawal: nil, orderRead: nil))
        XCTAssertEqual(entry.appeared, true)
        XCTAssertEqual(entry.lookups, 4)
        XCTAssertEqual(entry.sends, 0)
        XCTAssertEqual(source.finds, 0)
        XCTAssertThrowsError(try entry.lookupByRunId(11, currentProjection: nil, withdrawal: nil, orderRead: nil)) { error in
            XCTAssertEqual(error as? SupportLocateFailure, .originalMissing(requestId: "RUN:11"))
        }
        XCTAssertTrue(source.inner.findByRequestId("11").isEmpty)
        XCTAssertEqual(entry.sends, 0)
    }

    func testSameNumberOnTheOtherTypeStaysOriginalMissing() {
        let locator = SupportEventLocator(originalEvents: OtherTypeTargetSource())
        var entry = SupportLookupEntry(locator: locator)
        entry.appear()
        XCTAssertEqual(entry.sends, 0)
        XCTAssertThrowsError(try entry.lookupByRunId(7, currentProjection: nil, withdrawal: nil, orderRead: .detail(7))) { error in
            XCTAssertEqual(error as? SupportLocateFailure, .originalMissing(requestId: "RUN:7"))
        }
        XCTAssertEqual(entry.sends, 0)
    }

    private func withdrawalRead() throws -> WithdrawalSupportSnapshot {
        let scope = WalletCommerceScope(namespace: "synthetic-cn", accountID: 1, epoch: UUID())
        let contact = try WithdrawalSupportContact(weChatID: "synthetic_support")
        let configuration = try WithdrawalSupportConfiguration(
            namespace: "synthetic-cn", market: .china, revision: "r1",
            expiresAt: Date(timeIntervalSince1970: 10_000), contact: contact)
        return WithdrawalSupportSnapshot(
            configuration: configuration, scope: scope,
            approval: WithdrawalSupportApproval(id: "synthetic-review", market: .china))
    }
}

final class CountingOriginalEvents: SupportEventLocator.OriginalEventSource {
    let inner = InMemoryOriginalEventSource()
    private(set) var finds = 0

    @discardableResult
    func add(_ event: OriginalAuditEvent) -> CountingOriginalEvents {
        inner.add(event)
        return self
    }

    func findByRequestId(_ requestId: String) -> [OriginalAuditEvent] {
        finds += 1
        return inner.findByRequestId(requestId)
    }

    func findByTarget(targetType: String, targetId: Int64) -> OriginalAuditEvent? {
        finds += 1
        return inner.findByTarget(targetType: targetType, targetId: targetId)
    }
}

final class OtherTypeTargetSource: SupportEventLocator.OriginalEventSource {
    func findByRequestId(_ requestId: String) -> [OriginalAuditEvent] { [] }
    func findByTarget(targetType: String, targetId: Int64) -> OriginalAuditEvent? {
        OriginalAuditEvent(
            requestId: "req-cross", targetType: "ORDER", targetId: targetId,
            action: "PAY", afterJson: "UNKNOWN")
    }
}
