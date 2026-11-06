import XCTest
import Foundation
@testable import QuestifyCore

@MainActor final class InvoiceLaunchApplyTitleBindingTests: XCTestCase {
    private typealias S = InvoiceLaunchTestSupport
    private func original(_ title: Any?) -> [String: Any] {
        var app = S.application()
        app["requestId"] = "synthetic-original-request"
        app["titleId"] = title
        return app
    }
    func testReusedRequestWithSameOrdersButDifferentTitleNeverClearsOnRestart() async throws {
        let h = try S.Harness(); h.originalReceipts = true
        h.wire.responses = [try S.failure("INVOICE_REQUEST_REUSED")]
        await S.expect(.outcomeUnknown) { _ = try await h.coordinator().apply(h.command()) }
        let pending = try XCTUnwrap(h.store.load())
        let restarted = try S.Harness(memory: h.memory, captured: S.session(epoch: 2))
        restarted.originalReceipts = true
        restarted.wire.responses = [try S.success(original("12"))]
        await S.expect(.outcomeUnknown) { _ = try await restarted.coordinator().recover() }
        XCTAssertEqual(try restarted.store.load(), pending)
        XCTAssertEqual(restarted.wire.requests.map { $0.url!.path }, ["/native/api/invoice/request"])
    }
    func testOlderProjectionWithoutTitleCannotResolveUnknownOriginal() async throws {
        for title: Any? in [nil, NSNull()] {
            let h = try S.Harness(); h.originalReceipts = true; h.wire.failNext = true
            await S.expect(.outcomeUnknown) { _ = try await h.coordinator().apply(h.command()) }
            let pending = try XCTUnwrap(h.store.load())
            h.wire.responses = [try S.success(original(title))]
            await S.expect(.outcomeUnknown) { _ = try await h.coordinator().recover() }
            XCTAssertEqual(try h.store.load(), pending)
            XCTAssertEqual(h.wire.requests.count, 2)
        }
    }
    func testExactPersistedTitleAndOrdersResolveAcrossRestartWithoutMutation() async throws {
        let h = try S.Harness(); h.originalReceipts = true; h.wire.failNext = true
        await S.expect(.outcomeUnknown) { _ = try await h.coordinator().apply(h.command()) }
        let restarted = try S.Harness(memory: h.memory, captured: S.session(epoch: 2))
        restarted.originalReceipts = true
        restarted.wire.responses = [try S.success(original("11"))]
        let recovered = try await restarted.coordinator().recover()
        guard case .application(let app) = recovered else { return XCTFail("Expected exact original") }
        XCTAssertEqual(app.titleId, 11)
        XCTAssertNil(try restarted.store.load())
        XCTAssertEqual(restarted.wire.requests.count, 1)
    }
    func testKnownMismatchingTitleInMutationSuccessRetainsOriginal() async throws {
        let h = try S.Harness(); h.originalReceipts = true
        h.wire.responses = [try S.success(original("12"))]
        await S.expect(.outcomeUnknown) { _ = try await h.coordinator().apply(h.command()) }
        XCTAssertNotNil(try h.store.load())
        XCTAssertEqual(h.wire.requests.count, 1)
    }
    func testLegacyListStillDecodesButMalformedTitleIdentityFails() async throws {
        let h = try S.Harness()
        h.wire.responses = [try S.success([S.application()])]
        let list = try await h.service.applications()
        XCTAssertNil(list.first?.titleId)
        for invalid: Any in ["0", "-1", "01", "9223372036854775808", true] {
            XCTAssertThrowsError(try JSONDecoder().decode(InvoiceLaunchApplication.self, from: S.data(original(invalid))))
        }
        let exact = try JSONDecoder().decode(InvoiceLaunchApplication.self, from: S.data(original(String(Int64.max))))
        XCTAssertEqual(exact.titleId, Int64.max)
    }
}
