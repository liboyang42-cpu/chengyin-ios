import XCTest
@testable import Questify

@MainActor final class MerchantCustomerContactStageTests: XCTestCase {
    private func fields(merchant: Int = 610, sensitive: Bool = true) -> MerchantBusinessObject {
        ["active": .bool(true), "merchant": .object(["id": .int(merchant)]), "roleCode": .string("MERCHANT_MANAGER"),
         "permissions": .array((["merchant:crm:read"] + (sensitive ? ["merchant:crm:sensitive:read"] : [])).map(MerchantBusinessValue.string))]
    }
    private func snapshot(phone: String = "138****0000", sensitive: Bool = true, customer: Int = 61001) throws -> MerchantBusinessSnapshot {
        let row: MerchantBusinessObject = ["customerMemberId": .int(customer), "displayName": .string("Synthetic customer"),
            "arrivedCount": .int(0), "pendingCount": .int(0), "refundedCount": .int(0), "paidAmount": .null, "phone": .string(phone)]
        return try .init(access: .init(fields(sensitive: sensitive)), document: .init(query: .customers(.init()), payload: .object(["total": .int(1), "rows": .array([.object(row)])])))
    }
    private let scope = MerchantBusinessScope(realm: "fixture", accountID: 12, epoch: 1)
    @MainActor private final class Reader: MerchantEngagementReading {
        var scope: MerchantBusinessScope? = .init(realm: "fixture", accountID: 12, epoch: 1)
        var authorizationGeneration: UUID? = UUID()
        var isConfigured = true
        var isSyntheticEnabled = true
        var executionAllowed = true
        var deviceAllowed = false
        var accessValue: MerchantEngagementAccess
        var proofCalls = 0, executeCalls = 0
        var failProof = false
        var failAccess = false
        var hold = false
        var waiting: CheckedContinuation<Void, Never>?
        init(_ access: MerchantEngagementAccess) { accessValue = access }
        func canExecute(_ command: MerchantEngagementCommand, merchantID: Int) -> Bool { executionAllowed }
        func permitsDevice(_ action: MerchantEngagementDeviceGrant.Action, merchantID: Int) -> Bool { deviceAllowed }
        func access() async throws -> MerchantEngagementAccess { if failAccess { throw MerchantBusinessFailure.denied }; return accessValue }
        func read(_ query: MerchantEngagementQuery) async throws -> MerchantEngagementPayload { throw MerchantBusinessFailure.disabled }
        func proof(_ command: MerchantEngagementCommand) async throws -> MerchantEngagementProof {
            proofCalls += 1
            if hold { await withCheckedContinuation { waiting = $0 } }
            if failProof { throw MerchantBusinessFailure.denied }
            return .init(access: accessValue)
        }
        func execute(_ command: MerchantEngagementCommand, requestID: String, proof: MerchantEngagementProof, scope: MerchantBusinessScope) async throws -> MerchantEngagementReceipt {
            executeCalls += 1; return try .init(command: command, value: .object(["phone": .string("+12025550123")]))
        }
        func resume() { hold = false; waiting?.resume(); waiting = nil }
    }
    @MainActor private final class Delivery: MerchantContactDelivering {
        var calls = 0
        var fails = false
        func deliverSynthetic(phone: String, purpose: MerchantContactPurpose) async throws { calls += 1; if fails { throw MerchantBusinessFailure.invalid } }
    }
    private func make(current: @escaping () -> Bool = { true }) throws -> (MerchantCustomerContactFlow, Reader) {
        let snap = try snapshot(), selection = try XCTUnwrap(MerchantCustomerContactSelection(scope: scope, authorizationGeneration: nil, snapshot: snap, record: snap.document.rows[0], purpose: .call))
        let reader = try Reader(.init(fields()))
        return (.init(selection: selection, reader: reader, journal: MerchantBusinessMemoryIntentStore(), exports: MerchantExportMemoryRecoveryStore(), current: current), reader)
    }
    private func prepared() async throws -> (MerchantCustomerContactFlow, Reader) {
        let (flow, reader) = try make(); reader.deviceAllowed = true
        await flow.prepare(); await flow.confirm(try XCTUnwrap(flow.coordinator.review))
        XCTAssertNotNil(flow.coordinator.receipt)
        return (flow, reader)
    }
    func testFreshAccessFailureNeverClaimsDeviceAttemptOrRestoresNumber() async throws {
        let (flow, reader) = try await prepared(); reader.failAccess = true
        let delivery = Delivery(); await flow.consume(using: delivery)
        XCTAssertTrue(flow.accessIssue); XCTAssertFalse(flow.deviceIssue)
        XCTAssertFalse(flow.consumed); XCTAssertNil(flow.coordinator.receipt)
        await flow.consume(using: delivery)
        XCTAssertEqual(delivery.calls, 0); XCTAssertEqual(reader.executeCalls, 1)
    }
    func testDeviceFailureIsSeparateAndCannotReuseNumber() async throws {
        let (flow, reader) = try await prepared(); let delivery = Delivery(); delivery.fails = true
        await flow.consume(using: delivery); await flow.consume(using: delivery)
        XCTAssertFalse(flow.accessIssue); XCTAssertTrue(flow.deviceIssue)
        XCTAssertFalse(flow.consumed); XCTAssertNil(flow.coordinator.receipt)
        XCTAssertEqual(delivery.calls, 1); XCTAssertEqual(reader.executeCalls, 1)
    }
    func testSuccessRemainsOneShot() async throws {
        let (flow, _) = try await prepared(); let delivery = Delivery()
        await flow.consume(using: delivery); await flow.consume(using: delivery)
        XCTAssertTrue(flow.consumed); XCTAssertFalse(flow.accessIssue); XCTAssertFalse(flow.deviceIssue)
        XCTAssertEqual(delivery.calls, 1); XCTAssertNil(flow.coordinator.receipt)
    }
    func testRetiredSelectionDoesNotContactOrDisplayFailure() async throws {
        let (flow, _) = try await prepared(); flow.invalidate(); let delivery = Delivery()
        await flow.consume(using: delivery)
        XCTAssertFalse(flow.accessIssue); XCTAssertFalse(flow.deviceIssue); XCTAssertEqual(delivery.calls, 0)
    }
}
