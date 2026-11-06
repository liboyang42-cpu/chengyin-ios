import XCTest
@testable import Questify

@MainActor private final class EntryReadService: MerchantGameNodeServing {
    var scope = UUID(), isAuthenticated = true, permitsWrites = false
    var calls = 0
    var waiting: [CheckedContinuation<MerchantGameNodeEntriesResult, Never>] = []
    func loadEntries() async -> MerchantGameNodeEntriesResult {
        calls += 1
        return await withCheckedContinuation { waiting.append($0) }
    }
    func loadProjection(activityID: Int) async -> MerchantGameNodeLoadResult { fatalError("Not an entry read") }
    func issueLiveCode(activityID: Int, nodeID: Int) async -> MerchantGameNodeLiveCodeResult { fatalError("No code issuance") }
    func submit(_ command: MerchantGameNodeCommand) async -> MerchantGameNodeWriteResult { fatalError("No writes") }
    func readReceipt(activityID: Int, requestID: String) async -> MerchantGameNodeReceiptResult { fatalError("No receipt request") }
    func persistPending(_ index: MerchantGameNodePendingIndex) -> Bool { false }
    func restorePending(activityID: Int) -> MerchantGameNodePendingIndex? { nil }
    func clearPending(activityID: Int) { XCTFail("No journal mutation") }
}

@MainActor final class MerchantGameNodeEntryReadModelTests: XCTestCase {
    private func awaitCalls(_ service: EntryReadService, _ count: Int) async {
        for _ in 0..<100 where service.calls < count { await Task.yield() }
        XCTAssertEqual(service.calls, count)
    }
    func testDepartureBeforeClaimDoesNotRead() async throws {
        let service = EntryReadService(), model = MerchantGameNodeEntryReadModel()
        model.appear(service: service); let ticket = try XCTUnwrap(model.request)
        model.disappear(); await model.read(ticket, service: service)
        XCTAssertEqual(service.calls, 0); XCTAssertNil(model.currentResult(service: service))
    }
    func testSameScopeLateResultAfterDepartureIsIgnoredAndReturnCanRead() async throws {
        let service = EntryReadService(), model = MerchantGameNodeEntryReadModel()
        model.appear(service: service); let first = try XCTUnwrap(model.request)
        let old = Task { await model.read(first, service: service) }
        await awaitCalls(service, 1); model.disappear(); model.appear(service: service)
        let next = try XCTUnwrap(model.request); XCTAssertNotEqual(first.id, next.id)
        service.waiting.removeFirst().resume(returning: .failure(.server("old")))
        await old.value; XCTAssertNil(model.currentResult(service: service))
        let current = Task { await model.read(next, service: service) }
        await awaitCalls(service, 2); service.waiting.removeFirst().resume(returning: .ready([]))
        await current.value; XCTAssertEqual(model.currentResult(service: service), .ready([]))
    }
    func testCompletedRowsRemainOnChildReturnWithoutAnotherRequest() async throws {
        let service = EntryReadService(), model = MerchantGameNodeEntryReadModel()
        model.appear(service: service); let ticket = try XCTUnwrap(model.request)
        let task = Task { await model.read(ticket, service: service) }
        await awaitCalls(service, 1); service.waiting.removeFirst().resume(returning: .ready([])); await task.value
        model.disappear(); model.appear(service: service)
        XCTAssertEqual(model.currentResult(service: service), .ready([])); XCTAssertNil(model.request)
        XCTAssertEqual(service.calls, 1)
    }
    func testRetryHasNewOwnershipAndOldTicketCannotClaim() async throws {
        let service = EntryReadService(), model = MerchantGameNodeEntryReadModel()
        model.appear(service: service); let old = try XCTUnwrap(model.request)
        model.refresh(service: service); let next = try XCTUnwrap(model.request)
        XCTAssertNotEqual(old.id, next.id); await model.read(old, service: service)
        XCTAssertEqual(service.calls, 0)
    }
    func testCancellationAndChangedScopeDoNotPublish() async throws {
        for changeScope in [false, true] {
            let service = EntryReadService(), model = MerchantGameNodeEntryReadModel()
            model.appear(service: service); let ticket = try XCTUnwrap(model.request)
            let task = Task { await model.read(ticket, service: service) }
            await awaitCalls(service, 1)
            if changeScope { service.scope = UUID() } else { task.cancel() }
            service.waiting.removeFirst().resume(returning: .ready([])); await task.value
            XCTAssertNil(model.currentResult(service: service))
        }
    }
    func testReplacedServiceWithSameScopeCannotUseOldResult() async throws {
        let first = EntryReadService(), next = EntryReadService(), model = MerchantGameNodeEntryReadModel()
        next.scope = first.scope
        model.appear(service: first); let ticket = try XCTUnwrap(model.request)
        model.appear(service: next)
        await model.read(ticket, service: first)
        XCTAssertEqual(first.calls, 0); XCTAssertNil(model.currentResult(service: first))
    }
}
