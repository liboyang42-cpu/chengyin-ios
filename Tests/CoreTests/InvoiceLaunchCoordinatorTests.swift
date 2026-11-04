import XCTest
@testable import QuestifyCore

@MainActor final class InvoiceLaunchCoordinatorTests: XCTestCase {
    private typealias S = InvoiceLaunchTestSupport
    func testApplyWritesDurablyBeforeDispatchAndReadsOriginalID() async throws {
        let h = try S.Harness(); h.wire.responses = [try S.success(S.application()), try S.success(S.application())]
        h.wire.beforeSend = { XCTAssertNotNil(try h.store.load()) }
        let result = try await h.coordinator().apply(h.command())
        XCTAssertEqual(result.id, 51); XCTAssertNil(try h.store.load())
        XCTAssertEqual(h.wire.requests.map { $0.url!.lastPathComponent }, ["apply", "detail"])
        let body = try JSONSerialization.jsonObject(with: h.wire.requests[0].httpBody!) as! [String: Any]
        XCTAssertEqual(Set(body.keys), ["requestId", "titleId", "orderIds"])
        XCTAssertEqual(body["requestId"] as? String, "synthetic-original-request")
    }
    func testStorageFailureOrDisabledMutationPreventsDispatch() async throws {
        let h = try S.Harness(); h.memory.failWrite = true
        await S.expect(.storageUnavailable) { _ = try await h.coordinator().apply(h.command()) }
        XCTAssertTrue(h.wire.requests.isEmpty)
        h.memory.failWrite = false; h.mutations = false
        await S.expect(.disabled) { _ = try await h.coordinator().apply(h.command()) }
        XCTAssertTrue(h.wire.requests.isEmpty); XCTAssertNil(try h.store.load())
    }
    func testUnknownApplyRetainsOriginalAndNeverUsesListOrAnotherWrite() async throws {
        let h = try S.Harness(); h.wire.failNext = true
        await S.expect(.outcomeUnknown) { _ = try await h.coordinator().apply(h.command()) }
        let original = try XCTUnwrap(h.store.load())
        let restarted = try S.Harness(memory: h.memory, captured: S.session(epoch: 2))
        await S.expect(.originalReadUnavailable) { _ = try await restarted.coordinator().recover() }
        await S.expect(.pendingConflict) { _ = try await restarted.coordinator().apply(restarted.command()) }
        XCTAssertTrue(restarted.wire.requests.isEmpty); XCTAssertEqual(try restarted.store.load(), original)
    }
    func testReadFailureAfterApplyRecoversByCheckpointedOriginalIDOnly() async throws {
        let h = try S.Harness(); h.wire.responses = [try S.success(S.application())]
        do { _ = try await h.coordinator().apply(h.command()); XCTFail("Expected failed readback") } catch {}
        XCTAssertEqual(try h.store.load()?.applicationID, 51)
        let restarted = try S.Harness(memory: h.memory, captured: S.session(epoch: 2))
        restarted.wire.responses = [try S.success(S.application(status: "ISSUED"))]
        let result = try await restarted.coordinator().recover()
        if case .application(let app) = result { XCTAssertEqual(app.status, .issued) } else { XCTFail("Expected original application") }
        XCTAssertEqual(restarted.wire.requests.count, 1)
        XCTAssertEqual(restarted.wire.requests.first?.url?.lastPathComponent, "detail")
        XCTAssertNil(try restarted.store.load())
    }
    func testCodedRollbackClearsOnlyWriteFailureAndInProgressKeepsOriginal() async throws {
        let h = try S.Harness(); h.wire.responses = [try S.failure("INVOICE_ORDER_NOT_ELIGIBLE")]
        await S.expect(.rejected("INVOICE_ORDER_NOT_ELIGIBLE")) { _ = try await h.coordinator().apply(h.command()) }
        XCTAssertNil(try h.store.load())
        h.wire.responses = [try S.failure("INVOICE_REQUEST_IN_PROGRESS")]
        await S.expect(.outcomeUnknown) { _ = try await h.coordinator().apply(h.command()) }
        XCTAssertNotNil(try h.store.load())
        let read = try S.Harness(); read.wire.responses = [try S.success(S.application()), try S.failure("INVOICE_NOT_FOUND")]
        await S.expect(.rejected("INVOICE_NOT_FOUND")) { _ = try await read.coordinator().apply(read.command()) }
        XCTAssertNotNil(try read.store.load())
    }
    func testSaveTitleReadsMaskProjectionAndUnknownNeverResubmitsPII() async throws {
        let h = try S.Harness(), draft = try InvoiceLaunchTitleDraft(titleType: "PERSONAL", titleName: "Synthetic title")
        h.wire.responses = [try S.success(S.title), try S.success([S.title])]
        let result = try await h.coordinator().saveTitle(draft); XCTAssertEqual(result.id, 11); XCTAssertNil(try h.store.load())
        h.wire.failNext = true
        await S.expect(.outcomeUnknown) { _ = try await h.coordinator().saveTitle(draft) }
        let count = h.wire.requests.count
        await S.expect(.originalReadUnavailable) { _ = try await h.coordinator().recover() }
        XCTAssertEqual(h.wire.requests.count, count)
        let saved = String(decoding: try XCTUnwrap(h.memory.values.values.first), as: UTF8.self)
        XCTAssertFalse(saved.contains("Synthetic title")); XCTAssertFalse(saved.contains("taxNo"))
    }
    func testUnknownCancelRecoversOnlyCancelledOriginalDetail() async throws {
        let h = try S.Harness(); h.wire.failNext = true
        await S.expect(.outcomeUnknown) { _ = try await h.coordinator().cancel(id: 51) }
        h.wire.responses = [try S.success(S.application())]
        await S.expect(.outcomeUnknown) { _ = try await h.coordinator().recover() }; XCTAssertNotNil(try h.store.load())
        h.wire.responses = [try S.success(S.application(status: "CANCELLED"))]
        _ = try await h.coordinator().recover(); XCTAssertNil(try h.store.load())
        XCTAssertEqual(h.wire.requests.map { $0.url!.lastPathComponent }, ["cancel", "detail", "detail"])
    }
    func testDeleteTitleUsesOriginalIDAndReadsAuthoritativeAbsence() async throws {
        let h = try S.Harness(); h.wire.responses = [try S.success(NSNull()), try S.success([])]
        try await h.coordinator().deleteTitle(id: 11); XCTAssertNil(try h.store.load())
        h.wire.failNext = true
        await S.expect(.outcomeUnknown) { try await h.coordinator().deleteTitle(id: 11) }
        h.wire.responses = [try S.success([])]
        let recovered = try await h.coordinator().recover(); XCTAssertEqual(recovered, .titleAbsent(11))
        XCTAssertEqual(h.wire.requests.map { $0.url!.lastPathComponent }, ["delete", "titles", "delete", "titles"])
    }
    func testStaleMutationResponsePreservesPendingAndDoesNotExpireNewAccount() async throws {
        let h = try S.Harness(); h.wire.responses = [try S.success(S.application())]
        h.wire.afterSend = { h.current = try? S.session(account: 8) }
        await S.expect(.outcomeUnknown) { _ = try await h.coordinator().apply(h.command()) }
        XCTAssertNotNil(try h.store.load()); XCTAssertNil(try h.store.load()?.applicationID)
        XCTAssertEqual(h.wire.requests.count, 1); XCTAssertEqual(h.unauthorized, 0)
    }
    func testConcurrentDoubleTapAndMismatchedReceiptCannotReleaseOriginal() async throws {
        let h = try S.Harness(), coordinator = try h.coordinator(); h.wire.suspendNext = true
        let first = Task { try await coordinator.apply(h.command()) }
        for _ in 0..<1000 { if h.wire.suspended != nil { break }; await Task.yield() }
        XCTAssertNotNil(h.wire.suspended)
        await S.expect(.pendingConflict) { _ = try await coordinator.apply(h.command()) }
        h.wire.suspended?.resume(returning: try S.success(S.application(orders: [99]))); h.wire.suspended = nil
        await S.expect(.outcomeUnknown) { _ = try await first.value }
        XCTAssertNotNil(try h.store.load()); XCTAssertEqual(h.wire.requests.count, 1)
    }
    func testRequestReusedAndServerErrorsNeverPermitAnotherApply() async throws {
        for response in [try S.failure("INVOICE_REQUEST_REUSED"), (Data("{}".utf8), 502),
                         (Data("{\"code\":200,\"data\":null}".utf8), 200)] {
            let h = try S.Harness(); h.wire.responses = [response]
            await S.expect(.outcomeUnknown) { _ = try await h.coordinator().apply(h.command()) }
            XCTAssertNotNil(try h.store.load())
            await S.expect(.pendingConflict) { _ = try await h.coordinator().apply(h.command()) }
            XCTAssertEqual(h.wire.requests.count, 1)
        }
    }
    func testMissingOriginalDetailAndPresentTitleRetainUnknownRecords() async throws {
        let h = try S.Harness(); h.wire.failNext = true
        await S.expect(.outcomeUnknown) { _ = try await h.coordinator().cancel(id: 51) }
        h.wire.responses = [try S.failure("INVOICE_NOT_FOUND")]
        await S.expect(.rejected("INVOICE_NOT_FOUND")) { _ = try await h.coordinator().recover() }
        XCTAssertNotNil(try h.store.load())
        let deletion = try S.Harness(); deletion.wire.failNext = true
        await S.expect(.outcomeUnknown) { try await deletion.coordinator().deleteTitle(id: 11) }
        deletion.wire.responses = [try S.success([S.title])]
        await S.expect(.outcomeUnknown) { _ = try await deletion.coordinator().recover() }
        XCTAssertNotNil(try deletion.store.load())
    }
    func testCancelAcknowledgementRequiresSeparateOriginalReadAndRetainsOnStorageFailure() async throws {
        let h = try S.Harness(); h.wire.responses = [try S.success(S.application(status: "CANCELLED")), try S.success(S.application(status: "CANCELLED"))]
        h.memory.failRemove = true
        await S.expect(.storageUnavailable) { _ = try await h.coordinator().cancel(id: 51) }
        XCTAssertNotNil(try h.store.load())
        XCTAssertEqual(h.wire.requests.map { $0.url!.lastPathComponent }, ["cancel", "detail"])
    }
}
