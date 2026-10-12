import XCTest
@testable import Questify

@MainActor final class MerchantCustomerContactFlowTests: XCTestCase {
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
        var hold = false
        var waiting: CheckedContinuation<Void, Never>?
        init(_ access: MerchantEngagementAccess) { accessValue = access }
        func canExecute(_ command: MerchantEngagementCommand, merchantID: Int) -> Bool { executionAllowed }
        func permitsDevice(_ action: MerchantEngagementDeviceGrant.Action, merchantID: Int) -> Bool { deviceAllowed }
        func access() async throws -> MerchantEngagementAccess { accessValue }
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
        func deliverSynthetic(phone: String, purpose: MerchantContactPurpose) async throws { calls += 1 }
    }
    private func make(current: @escaping () -> Bool = { true }) throws -> (MerchantCustomerContactFlow, Reader) {
        let snap = try snapshot(), selection = try XCTUnwrap(MerchantCustomerContactSelection(scope: scope, authorizationGeneration: nil, snapshot: snap, record: snap.document.rows[0], purpose: .call))
        let reader = try Reader(.init(fields()))
        return (.init(selection: selection, reader: reader, journal: MerchantBusinessMemoryIntentStore(), exports: MerchantExportMemoryRecoveryStore(), current: current), reader)
    }
    func testOpenDoesNotReadOrExecute() throws { let (_, r) = try make(); XCTAssertEqual(r.proofCalls, 0); XCTAssertEqual(r.executeCalls, 0) }
    func testPrepareOnlyCreatesReview() async throws {
        let (f, r) = try make(); await f.prepare(); XCTAssertEqual(f.coordinator.review?.command, f.selection.command); XCTAssertEqual(r.executeCalls, 0)
    }
    func testMissingExecutionGrantCannotDispatch() async throws {
        let (f, r) = try make(); r.executionAllowed = false; await f.prepare(); let review = try XCTUnwrap(f.coordinator.review)
        await f.confirm(review); XCTAssertEqual(r.executeCalls, 0)
    }
    func testDeviceGrantNotInferredFromSyntheticReceipt() async throws {
        let (f, _) = try make(); await f.prepare(); await f.confirm(try XCTUnwrap(f.coordinator.review)); XCTAssertFalse(f.canConsume)
        let d = Delivery(); await f.consume(using: d); XCTAssertEqual(d.calls, 0)
    }
    func testReceiptOneShotWithExplicitFixtureDevicePermission() async throws {
        let (f, r) = try make(); r.deviceAllowed = true; await f.prepare(); await f.confirm(try XCTUnwrap(f.coordinator.review))
        let d = Delivery(); await f.consume(using: d); await f.consume(using: d); XCTAssertEqual(d.calls, 1); XCTAssertTrue(f.consumed)
    }
    func testWrongPurposeAndCustomerRejectedByAdapter() async throws {
        let (f, r) = try make()
        for command in [MerchantEngagementCommand.contact(try .init(61001), .copy), .contact(try .init(61002), .call)] {
            do { _ = try await f.reader.proof(command); XCTFail() } catch {}
        }
        XCTAssertEqual(r.proofCalls, 0)
    }
    func testDifferentMerchantProofRejected() async throws {
        let (f, r) = try make(); r.accessValue = try .init(fields(merchant: 611)); await f.prepare(); XCTAssertNil(f.coordinator.review)
    }
    func testRevokedSensitivePermissionRejected() async throws {
        let (f, r) = try make(); r.accessValue = try .init(fields(sensitive: false)); await f.prepare(); XCTAssertNil(f.coordinator.review)
    }
    func testStaleSourceBeforeOpenDoesNotRead() async throws {
        let (f, r) = try make(current: { false }); await f.prepare(); XCTAssertEqual(r.proofCalls, 0)
    }
    func testFailureThenRetryUsesNewProof() async throws {
        let (f, r) = try make(); r.failProof = true; await f.prepare(); XCTAssertNil(f.coordinator.review)
        r.failProof = false; await f.prepare(); XCTAssertNotNil(f.coordinator.review); XCTAssertEqual(r.proofCalls, 2)
    }
    func testCancelReviewKeepsSelectionButDropsReview() async throws {
        let (f, _) = try make(); await f.prepare(); f.cancelReview(); XCTAssertNil(f.coordinator.review); XCTAssertTrue(f.isCurrent)
    }
    func testCloseInvalidatesPendingProof() async throws {
        let (f, r) = try make(); r.hold = true
        let task = Task { await f.prepare() }; while r.waiting == nil { await Task.yield() }
        f.invalidate(); r.resume(); await task.value; XCTAssertNil(f.coordinator.review); XCTAssertFalse(f.isCurrent)
    }
    func testSourceChangeWhileProofPendingRejected() async throws {
        var current = true; let (f, r) = try make(current: { current }); r.hold = true
        let task = Task { await f.prepare() }; while r.waiting == nil { await Task.yield() }
        current = false; r.resume(); await task.value; XCTAssertNil(f.coordinator.review)
    }
    func testAccountChangeWhileProofPendingRejected() async throws {
        let (f, r) = try make(); r.hold = true
        let task = Task { await f.prepare() }; while r.waiting == nil { await Task.yield() }
        r.scope = .init(realm: "fixture", accountID: 13, epoch: 2); r.resume(); await task.value; XCTAssertNil(f.coordinator.review)
    }
    func testNoUnrelatedDeviceCapability() throws {
        let (f, r) = try make(); r.deviceAllowed = true
        XCTAssertFalse(f.reader.permitsDevice(.saveExport(3), merchantID: 610))
        XCTAssertFalse(f.reader.permitsDevice(.contact(try .init(61001), .copy), merchantID: 610))
        XCTAssertFalse(f.reader.permitsDevice(.contact(try .init(61001), .call), merchantID: 611))
    }
    func testSecondPrepareWhileBusyDoesNotDuplicateProof() async throws {
        let (f, r) = try make(); r.hold = true
        let task = Task { await f.prepare() }; while r.waiting == nil { await Task.yield() }
        await f.prepare(); XCTAssertEqual(r.proofCalls, 1); r.resume(); await task.value
    }
    func testBackgroundInvalidationClearsReceipt() async throws {
        let (f, r) = try make(); r.deviceAllowed = true; await f.prepare(); await f.confirm(try XCTUnwrap(f.coordinator.review))
        f.invalidate(); XCTAssertNil(f.coordinator.receipt); XCTAssertFalse(f.canConsume)
    }
}
