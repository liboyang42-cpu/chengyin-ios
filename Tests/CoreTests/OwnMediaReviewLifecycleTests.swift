import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private actor OwnMediaLifecycleWire: HTTPTransport {
    var requests: [URLRequest] = []
    var pending: [Int: CheckedContinuation<(Data, Int), Error>] = [:]
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); let index = requests.count
        return try await withCheckedThrowingContinuation { pending[index] = $0 }
    }
    func isWaiting(_ index: Int) -> Bool { pending[index] != nil }
    func finish(_ index: Int, json: String, status: Int = 200) {
        pending.removeValue(forKey: index)?.resume(returning: (Data(json.utf8), status))
    }
}

/// Authored only under the no-Swift/Apple/CI freeze. All inputs are synthetic.
@MainActor final class OwnMediaReviewLifecycleTests: XCTestCase {
    private final class Reader: OwnMediaReading {
        var scope = UUID()
        var isSignedIn = true
        var isAvailable = true
        var calls: [Int64?] = []
        var pending: [Int: CheckedContinuation<OwnMediaPage, Error>] = [:]
        func page(before cursor: Int64?) async throws -> OwnMediaPage {
            calls.append(cursor); let index = calls.count
            // Intentionally ignores cancellation, as a late network completion can.
            return try await withCheckedThrowingContinuation { pending[index] = $0 }
        }
        func finish(_ index: Int, _ page: OwnMediaPage) { pending.removeValue(forKey: index)?.resume(returning: page) }
        func fail(_ index: Int, _ error: Error) { pending.removeValue(forKey: index)?.resume(throwing: error) }
        func drain() { for value in pending.values { value.resume(throwing: CancellationError()) }; pending = [:] }
    }
    private func page(_ ids: [Int64]) -> OwnMediaPage {
        .init(rows: ids.map { .init(id: $0, reviewState: .hold, reviewReason: "Synthetic reason", mediaType: .image) })
    }
    private func wait(_ reader: Reader, _ index: Int) async throws {
        for _ in 0..<2000 { if reader.pending[index] != nil { return }; await Task.yield() }
        XCTFail("Missing synthetic request \(index)"); throw APIError.invalidRequest
    }
    private func loaded(_ flow: OwnMediaReviewController, _ reader: Reader) async throws {
        let task = try XCTUnwrap(flow.appear(foreground: true)); try await wait(reader, 1)
        reader.finish(1, page(Array((151...200).reversed()).map { Int64($0) })); await task.value
        XCTAssertEqual(flow.rows.count, 50); XCTAssertEqual(flow.nextCursor, 151)
    }

    func testNoLeaseGuestAndBackgroundNeverDispatch() async {
        for kind in ["guest", "dormant", "background"] {
            let reader = Reader()
            reader.isSignedIn = kind != "guest"; reader.isAvailable = kind != "dormant"
            let flow = OwnMediaReviewController(reader: reader)
            XCTAssertNil(flow.appear(foreground: kind != "background"))
            XCTAssertNil(flow.refresh()); XCTAssertNil(flow.more()); XCTAssertNil(flow.retry())
            XCTAssertEqual(reader.calls.count, 0); XCTAssertTrue(flow.rows.isEmpty)
            XCTAssertEqual(flow.phase, kind == "guest" ? .signedOut : (kind == "dormant" ? .unavailable : .idle))
            flow.disappear()
        }
    }

    func testFirstFailureIsNotEmptyAndExactRetryThenEmptyIsAuthoritative() async throws {
        let reader = Reader(), flow = OwnMediaReviewController(reader: reader)
        defer { flow.disappear(); reader.drain() }
        let first = try XCTUnwrap(flow.appear(foreground: true)); try await wait(reader, 1)
        reader.fail(1, APIError.httpStatus(503)); await first.value
        XCTAssertEqual(flow.phase, .failed); XCTAssertTrue(flow.canRetry); XCTAssertNil(flow.nextCursor)
        let retry = try XCTUnwrap(flow.retry()); try await wait(reader, 2)
        XCTAssertNil(reader.calls[1]); XCTAssertNil(flow.retry())
        reader.finish(2, page([])); await retry.value
        XCTAssertEqual(flow.phase, .ready); XCTAssertTrue(flow.rows.isEmpty); XCTAssertFalse(flow.canLoadMore)
    }

    func testMoreFailureRetainsOriginalCursorAndRepeatedRetryIsLocked() async throws {
        let reader = Reader(), flow = OwnMediaReviewController(reader: reader)
        defer { flow.disappear(); reader.drain() }
        try await loaded(flow, reader)
        let more = try XCTUnwrap(flow.more()); try await wait(reader, 2)
        XCTAssertNil(flow.more()); XCTAssertEqual(reader.calls.count, 2)
        reader.fail(2, APIError.httpStatus(503)); await more.value
        XCTAssertEqual(flow.rows.count, 50); XCTAssertEqual(flow.nextCursor, 151)
        XCTAssertTrue(flow.moreFailed); XCTAssertFalse(flow.canLoadMore)
        let retry = try XCTUnwrap(flow.retry()); try await wait(reader, 3)
        XCTAssertEqual(reader.calls[2], 151); XCTAssertNil(flow.retry()); XCTAssertNil(flow.more())
        reader.finish(3, page([150, 149])); await retry.value
        XCTAssertEqual(flow.rows.count, 52); XCTAssertEqual(flow.rows.last?.id, 149)
        XCTAssertFalse(flow.moreFailed); XCTAssertNil(flow.nextCursor)
    }

    func testRefreshCancelsOldPageAndLateSuccessCannotSpliceOrUnlockNewRead() async throws {
        let reader = Reader(), flow = OwnMediaReviewController(reader: reader)
        defer { flow.disappear(); reader.drain() }
        try await loaded(flow, reader)
        let old = try XCTUnwrap(flow.more()); try await wait(reader, 2)
        let fresh = try XCTUnwrap(flow.refresh()); try await wait(reader, 3)
        XCTAssertTrue(old.isCancelled); XCTAssertNil(reader.calls[2]); XCTAssertNil(flow.refresh())
        reader.finish(2, page([150])); await old.value
        XCTAssertTrue(flow.isLoading); XCTAssertTrue(flow.rows.isEmpty); XCTAssertEqual(flow.phase, .loading)
        reader.finish(3, page([900])); await fresh.value
        XCTAssertEqual(flow.rows.map(\.id), [900]); XCTAssertFalse(flow.isLoading)
    }

    func testIdenticalRefreshCursorDoesNotAdoptRetiredOlderPage() async throws {
        let reader = Reader(), flow = OwnMediaReviewController(reader: reader)
        defer { flow.disappear(); reader.drain() }
        try await loaded(flow, reader)
        let old = try XCTUnwrap(flow.more()); try await wait(reader, 2)
        let fresh = try XCTUnwrap(flow.refresh()); try await wait(reader, 3)
        let sameIDs = Array((151...200).reversed()).map(Int64.init)
        reader.finish(3, page(sameIDs)); await fresh.value
        XCTAssertEqual(flow.nextCursor, 151)
        reader.finish(2, page([150, 149])); await old.value
        XCTAssertEqual(flow.rows.map(\.id), sameIDs)
        XCTAssertEqual(flow.nextCursor, 151)
        XCTAssertFalse(flow.isLoading)
        let current = try XCTUnwrap(flow.more()); try await wait(reader, 4)
        reader.finish(4, page([150])); await current.value
        XCTAssertEqual(flow.rows.map(\.id), sameIDs + [150])
    }

    func testLatePageFailureCannotReplaceNewSuccess() async throws {
        let reader = Reader(), flow = OwnMediaReviewController(reader: reader)
        defer { flow.disappear(); reader.drain() }
        try await loaded(flow, reader)
        let old = try XCTUnwrap(flow.more()); try await wait(reader, 2)
        let fresh = try XCTUnwrap(flow.refresh()); try await wait(reader, 3)
        reader.finish(3, page([900])); await fresh.value
        reader.fail(2, OwnMediaReadFailure.rejected(code: 403)); await old.value
        XCTAssertEqual(flow.phase, .ready); XCTAssertEqual(flow.rows.map(\.id), [900])
        XCTAssertFalse(flow.canRetry)
    }

    func testDisappearCancelsClearsAndReopenReadsFromNewest() async throws {
        let reader = Reader(), flow = OwnMediaReviewController(reader: reader)
        defer { flow.disappear(); reader.drain() }
        try await loaded(flow, reader)
        let old = try XCTUnwrap(flow.more()); try await wait(reader, 2)
        flow.disappear(); XCTAssertTrue(old.isCancelled); XCTAssertTrue(flow.rows.isEmpty)
        XCTAssertNil(flow.refresh()); XCTAssertNil(flow.more())
        let reopened = try XCTUnwrap(flow.appear(foreground: true)); try await wait(reader, 3)
        XCTAssertNil(reader.calls[2]); reader.finish(2, page([150])); await old.value
        XCTAssertTrue(flow.rows.isEmpty); XCTAssertTrue(flow.isLoading)
        reader.finish(3, page([201])); await reopened.value
        XCTAssertEqual(flow.rows.map(\.id), [201])
    }

    func testBackgroundClearsAndOnlyVisibleForegroundRestarts() async throws {
        let reader = Reader(), flow = OwnMediaReviewController(reader: reader)
        defer { flow.disappear(); reader.drain() }
        try await loaded(flow, reader)
        let old = try XCTUnwrap(flow.more()); try await wait(reader, 2)
        XCTAssertNil(flow.setForeground(false)); XCTAssertTrue(old.isCancelled); XCTAssertTrue(flow.rows.isEmpty)
        XCTAssertNil(flow.refresh()); reader.finish(2, page([150])); await old.value
        let foreground = try XCTUnwrap(flow.setForeground(true)); try await wait(reader, 3)
        XCTAssertNil(reader.calls[2]); reader.finish(3, page([202])); await foreground.value
        XCTAssertEqual(flow.rows.map(\.id), [202])
        flow.disappear(); flow.setForeground(false); XCTAssertNil(flow.setForeground(true))
        XCTAssertEqual(reader.calls.count, 3)
    }

    func testScopeChangeMasksImmediatelyAndCannotBeReusedAfterReauthentication() async throws {
        let reader = Reader(), flow = OwnMediaReviewController(reader: reader)
        defer { flow.disappear(); reader.drain() }
        try await loaded(flow, reader)
        let old = try XCTUnwrap(flow.more()); try await wait(reader, 2)
        reader.scope = UUID()
        XCTAssertTrue(flow.rows.isEmpty); XCTAssertEqual(flow.phase, .unavailable)
        flow.synchronizeAccess(); XCTAssertTrue(old.isCancelled)
        reader.finish(2, page([150])); await old.value
        XCTAssertNil(flow.appear(foreground: true)); XCTAssertNil(flow.refresh()); XCTAssertNil(flow.retry())
        XCTAssertEqual(reader.calls.count, 2)
        let newFlow = OwnMediaReviewController(reader: reader)
        let newRead = try XCTUnwrap(newFlow.appear(foreground: true)); try await wait(reader, 3)
        reader.finish(3, page([800])); await newRead.value
        XCTAssertEqual(newFlow.rows.map(\.id), [800]); newFlow.disappear()
    }

    func testRevocationAndSignoutClearSuccessfulPrivateRowsWithoutNewRequest() async throws {
        for signedOut in [false, true] {
            let reader = Reader(), flow = OwnMediaReviewController(reader: reader)
            defer { flow.disappear(); reader.drain() }
            try await loaded(flow, reader)
            if signedOut { reader.isSignedIn = false } else { reader.isAvailable = false }
            XCTAssertTrue(flow.rows.isEmpty); XCTAssertNil(flow.nextCursor)
            flow.synchronizeAccess()
            XCTAssertEqual(flow.phase, signedOut ? .signedOut : .unavailable)
            XCTAssertNil(flow.retry()); XCTAssertNil(flow.refresh()); XCTAssertEqual(reader.calls.count, 1)
        }
    }

    func testDeniedPageClearsRowsAndExplicitRefreshCanRecoverWithSameLease() async throws {
        let reader = Reader(), flow = OwnMediaReviewController(reader: reader)
        defer { flow.disappear(); reader.drain() }
        try await loaded(flow, reader)
        let more = try XCTUnwrap(flow.more()); try await wait(reader, 2)
        reader.fail(2, OwnMediaReadFailure.rejected(code: 403)); await more.value
        XCTAssertEqual(flow.phase, .denied); XCTAssertTrue(flow.rows.isEmpty); XCTAssertFalse(flow.canRetry)
        let refresh = try XCTUnwrap(flow.refresh()); try await wait(reader, 3)
        XCTAssertNil(reader.calls[2]); reader.finish(3, page([300])); await refresh.value
        XCTAssertEqual(flow.rows.map(\.id), [300])
    }

    func testMalformedOlderPageNeverPartiallyAppendsAndCanRetryExactBoundary() async throws {
        for ids in [[Int64(150), 150], [152], [0], [149, 150]] {
            let reader = Reader(), flow = OwnMediaReviewController(reader: reader)
            defer { flow.disappear(); reader.drain() }
            try await loaded(flow, reader)
            let more = try XCTUnwrap(flow.more()); try await wait(reader, 2)
            reader.finish(2, page(ids)); await more.value
            XCTAssertEqual(flow.rows.count, 50); XCTAssertEqual(flow.nextCursor, 151)
            XCTAssertTrue(flow.canRetry); XCTAssertTrue(flow.moreFailed)
        }
    }

    func testCancellationFromCurrentReaderLeavesRetryNotPermanentSpinner() async throws {
        let reader = Reader(), flow = OwnMediaReviewController(reader: reader)
        defer { flow.disappear(); reader.drain() }
        let first = try XCTUnwrap(flow.appear(foreground: true)); try await wait(reader, 1)
        reader.fail(1, CancellationError()); await first.value
        XCTAssertFalse(flow.isLoading); XCTAssertEqual(flow.phase, .failed); XCTAssertTrue(flow.canRetry)
    }

    func testCancelledOriginalWire401CannotExpireCurrentSessionAfterRefresh() async throws {
        let wire = OwnMediaLifecycleWire()
        let service = OwnMediaService(configuration: try APIConfiguration(baseURL: URL(string: "https://media.example/native")!), transport: wire)
        let session = try OwnMediaSession(accountID: 7, epoch: 1, token: "synthetic-media", approval: UUID())
        var unauthorizedCount = 0
        let reader = OwnMediaSessionReader(service: service, currentSession: { session }, onUnauthorized: { _ in unauthorizedCount += 1 })
        let flow = OwnMediaReviewController(reader: reader)
        defer { flow.disappear() }
        func waitForWire(_ index: Int) async throws {
            for _ in 0..<2000 { if await wire.isWaiting(index) { return }; await Task.yield() }
            XCTFail("Missing synthetic wire request"); throw APIError.invalidRequest
        }
        let first = try XCTUnwrap(flow.appear(foreground: true)); try await waitForWire(1)
        let rows = (151...200).reversed().map { "{\"assetId\":\($0),\"reviewState\":\"HOLD\"}" }.joined(separator: ",")
        await wire.finish(1, json: "{\"code\":200,\"data\":[\(rows)]}"); await first.value
        let old = try XCTUnwrap(flow.more()); try await waitForWire(2)
        let fresh = try XCTUnwrap(flow.refresh()); try await waitForWire(3)
        await wire.finish(3, json: #"{"code":200,"data":[{"assetId":"900","reviewState":"APPROVED"}]}"#); await fresh.value
        await wire.finish(2, json: #"{"code":401}"#, status: 401); await old.value
        XCTAssertTrue(old.isCancelled); XCTAssertEqual(unauthorizedCount, 0)
        XCTAssertEqual(flow.rows.map(\.id), [900]); XCTAssertEqual(flow.phase, .ready)
    }

}
