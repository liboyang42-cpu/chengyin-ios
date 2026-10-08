import SwiftUI
import XCTest
@testable import Questify

// Authored app-hosted tests. They do not establish a simulator/visual pass.
@MainActor final class MerchantCustomerDetailSectionsTests: XCTestCase {
    private func access(_ permissions: [String]) throws -> MerchantBusinessAccess {
        try .init(["active": .bool(true), "merchant": .object(["id": .int(610), "name": .string("Synthetic store")]),
                   "roleCode": .string("MERCHANT_MANAGER"), "permissions": .array(permissions.map(MerchantBusinessValue.string))])
    }
    private func detail(amount: MerchantBusinessValue = .string("42.00")) throws -> MerchantCustomerDetailPresentation {
        var payload = try XCTUnwrap(MerchantBusinessSyntheticFixtures.decode(MerchantBusinessSyntheticFixtures.customer).object)
        var summary = try XCTUnwrap(payload["summary"]?.object); summary["paidAmount"] = amount
        payload["summary"] = .object(summary)
        return try .init(customerID: .init(61001), payload: .object(payload))
    }
    func testReadOnlyPermissionDoesNotExposeReturnedSensitiveAmount() throws {
        let view = MerchantCustomerDetailSections(detail: try detail(), access: try access(["merchant:crm:read"])) { _ in EmptyView() }
        XCTAssertTrue(view.canRead)
        XCTAssertNil(view.paidAmount)
    }
    func testSensitivePermissionAloneDoesNotExposeCustomerOrAmount() throws {
        let view = MerchantCustomerDetailSections(detail: try detail(), access: try access(["merchant:crm:sensitive:read"])) { _ in EmptyView() }
        XCTAssertFalse(view.canRead)
        XCTAssertNil(view.paidAmount)
    }
    func testBothPermissionsExposeOnlyExactNonNullAmount() throws {
        let grant = try access(["merchant:crm:read", "merchant:crm:sensitive:read"])
        let populated = MerchantCustomerDetailSections(detail: try detail(), access: grant) { _ in EmptyView() }
        XCTAssertEqual(populated.paidAmount, "CNY 42.00")
        let absent = MerchantCustomerDetailSections(detail: try detail(amount: .null), access: grant) { _ in EmptyView() }
        XCTAssertNil(absent.paidAmount)
        let zero = MerchantCustomerDetailSections(detail: try detail(amount: .string("0.00")), access: grant) { _ in EmptyView() }
        XCTAssertEqual(zero.paidAmount, "CNY 0.00")
    }

    @MainActor private final class Reader: MerchantBusinessReading {
        var scope: MerchantBusinessScope? = .init(realm: "synthetic://customer-detail", accountID: 99001, epoch: 1)
        var authorizationGeneration: UUID? = UUID()
        let isConfigured = true
        let isOfflineExample = true
        let canExecuteSyntheticMutation = false
        var pending: [Int: CheckedContinuation<MerchantBusinessSnapshot, Error>] = [:]
        var calls = 0
        var grant: MerchantBusinessAccess
        init(grant: MerchantBusinessAccess) { self.grant = grant }
        func access() async throws -> MerchantBusinessAccess { grant }
        func snapshot(_ query: MerchantBusinessQuery) async throws -> MerchantBusinessSnapshot {
            calls += 1; let call = calls
            return try await withCheckedThrowingContinuation { pending[call] = $0 }
        }
        func execute(_ mutation: MerchantBusinessMutation, requestID: String, scope: MerchantBusinessScope) async throws -> MerchantBusinessReceipt {
            XCTFail("The read-only customer projection must never dispatch")
            throw MerchantBusinessFailure.disabled
        }
        func respond(_ call: Int, query: MerchantBusinessQuery, error: Error? = nil) throws {
            let continuation = try XCTUnwrap(pending.removeValue(forKey: call))
            if let error { continuation.resume(throwing: error); return }
            let document = try MerchantBusinessDocument(query: query, payload: MerchantBusinessSyntheticFixtures.payload(query))
            continuation.resume(returning: .init(access: grant, document: document))
        }
    }
    private func waitForPending(_ reader: Reader, _ call: Int) async throws {
        for _ in 0..<100 {
            if reader.pending[call] != nil { return }
            await Task.yield()
        }
        throw MerchantBusinessFailure.pending
    }
    func testLateAccountAndAuthorizationResponsesCannotRepopulateCustomer() async throws {
        for drift in ["logout", "account", "authorization"] {
            let reader = Reader(grant: try access(["merchant:crm:read"]))
            let model = MerchantBusinessViewModel(reader: reader, journal: MerchantBusinessMemoryIntentStore())
            let query = MerchantBusinessQuery.customer(try .init(61001))
            let load = Task { await model.load(query) }
            try await waitForPending(reader, 1)
            switch drift {
            case "logout": reader.scope = nil
            case "account": reader.scope = .init(realm: "synthetic://customer-detail", accountID: 99002, epoch: 2)
            default: reader.authorizationGeneration = UUID()
            }
            try reader.respond(1, query: query); await load.value
            XCTAssertNil(model.coordinator.snapshot, drift)
        }
    }
    func testDismissalAndCancelledReadCannotRepopulateCustomer() async throws {
        for cancel in [false, true] {
            let reader = Reader(grant: try access(["merchant:crm:read"]))
            let model = MerchantBusinessViewModel(reader: reader, journal: MerchantBusinessMemoryIntentStore())
            let query = MerchantBusinessQuery.customer(try .init(61001))
            let load = Task { await model.load(query) }
            try await waitForPending(reader, 1)
            if cancel { load.cancel() } else { model.invalidate() }
            try reader.respond(1, query: query); await load.value
            XCTAssertNil(model.coordinator.snapshot)
        }
    }
    func testOlderReadCannotReplaceRefreshedCustomerProjection() async throws {
        let reader = Reader(grant: try access(["merchant:crm:read"]))
        let model = MerchantBusinessViewModel(reader: reader, journal: MerchantBusinessMemoryIntentStore())
        let query = MerchantBusinessQuery.customer(try .init(61001))
        let old = Task { await model.load(query) }; try await waitForPending(reader, 1)
        let latest = Task { await model.load(query) }; try await waitForPending(reader, 2)
        try reader.respond(2, query: query); await latest.value
        let current = try XCTUnwrap(model.coordinator.snapshot)
        XCTAssertNotNil(current.document.customerDetail)
        try reader.respond(1, query: query, error: MerchantBusinessFailure.denied); await old.value
        XCTAssertEqual(model.coordinator.snapshot, current)
        XCTAssertNil(model.coordinator.failureKey)
    }
    func testPermissionFailureOnRefreshClearsPreviousCustomer() async throws {
        let reader = Reader(grant: try access(["merchant:crm:read"]))
        let model = MerchantBusinessViewModel(reader: reader, journal: MerchantBusinessMemoryIntentStore())
        let query = MerchantBusinessQuery.customer(try .init(61001))
        let first = Task { await model.load(query) }; try await waitForPending(reader, 1)
        try reader.respond(1, query: query); await first.value
        XCTAssertNotNil(model.coordinator.snapshot?.document.customerDetail)
        let refresh = Task { await model.load(query) }; try await waitForPending(reader, 2)
        XCTAssertNil(model.coordinator.snapshot)
        try reader.respond(2, query: query, error: MerchantBusinessFailure.denied); await refresh.value
        XCTAssertNil(model.coordinator.snapshot)
        XCTAssertEqual(model.coordinator.failureKey, "merchant.business.denied")
    }
}
