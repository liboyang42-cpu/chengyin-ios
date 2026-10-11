import XCTest
@testable import QuestifyCore

@MainActor final class RoamCreatedStampLookupTests: XCTestCase {
    private final class Reader: RoamExperienceReading {
        var identity: RoamExperienceIdentity?
        var isConfigured = true
        var isOfflineExample = true
        var pages: [Int: RoamAlbumPage] = [:]
        var failure: Error?
        var requests: [Int] = []
        var hold = false
        var pending: [Int: CheckedContinuation<RoamAlbumPage, Error>] = [:]
        private var started: CheckedContinuation<Void, Never>?
        func history() throws -> [RoamHistoryRecord] { XCTFail("Unexpected history read"); return [] }
        func sessionFact(_ query: RoamRecoveryQuery) async throws -> RoamSessionFact { throw APIError.notConfigured }
        func tilePage(afterID: Int, limit: Int) async throws -> RoamTileMemoryPage { throw APIError.notConfigured }
        func shopBadge() async throws -> RoamShopBadge? { throw APIError.notConfigured }
        func album(page: Int, pageSize: Int) async throws -> RoamAlbumPage {
            XCTAssertEqual(pageSize, 20); requests.append(page)
            if let failure { throw failure }
            if hold {
                let index = requests.count
                return try await withCheckedThrowingContinuation { continuation in
                    pending[index] = continuation; started?.resume(); started = nil
                }
            }
            return try XCTUnwrap(pages[page])
        }
        func waitForRequest() async {
            if !pending.isEmpty { return }
            await withCheckedContinuation { started = $0 }
        }
        func release(_ index: Int, page: RoamAlbumPage) {
            let continuation = pending.removeValue(forKey: index)
            XCTAssertNotNil(continuation); continuation?.resume(returning: page)
        }
    }
    private func identity(account: Int = 3, epoch: UInt64 = 1, namespace: String = "stamp-read", realm: String = "https://api.example.com/") throws -> RoamExperienceIdentity {
        .init(scope: try .init(market: "cn", deployment: URL(string: realm)!, accountID: account, namespace: namespace), epoch: epoch)
    }
    private func origin(account: Int = 3, namespace: String = "stamp-read", realm: String = "https://api.example.com/") throws -> RetainedImageScope {
        try .init(accountID: account, epoch: UUID(), realm: realm, destination: .stamp, namespace: namespace)
    }
    private func reader() throws -> Reader { let r = Reader(); r.identity = try identity(); return r }
    private func target(_ reader: Reader, id: Int = 29) throws -> RoamCreatedStampTarget {
        try XCTUnwrap(RoamCreatedStampTarget(phase: .created(id), origin: origin(), reader: reader))
    }
    private func page(_ ids: [Int], number: Int = 1, total: Int? = nil, state: Int = 0, caption: String = "server caption", size: Int = 20) throws -> RoamAlbumPage {
        let rows: [[String: Any]] = ids.map { ["id": $0, "picUrl": "https://media.example.com/\($0).jpg", "caption": caption, "checkState": state] }
        return try JSONDecoder().decode(RoamAlbumPage.self, from: JSONSerialization.data(withJSONObject: ["list": rows, "total": total ?? ids.count, "pageNum": number, "pageSize": size]))
    }
    func testOnlyPositiveConfirmedCreateCanBuildTarget() throws {
        let r = try reader(), source = try origin()
        let phases: [RoamStampCaptureCoordinator.Phase] = [.ready, .review, .uploading, .awaitingCreate, .creating, .unknown, .failed, .unavailable, .created(0), .created(-1)]
        for phase in phases { XCTAssertNil(RoamCreatedStampTarget(phase: phase, origin: source, reader: r)) }
        XCTAssertNotNil(RoamCreatedStampTarget(phase: .created(29), origin: source, reader: r))
        XCTAssertTrue(r.requests.isEmpty)
    }
    func testOriginMustMatchExactOwnerNamespaceAndRealm() throws {
        let r = try reader()
        for source in [try origin(account: 4), try origin(namespace: "different"), try origin(realm: "https://other.example.com/")] {
            XCTAssertNil(RoamCreatedStampTarget(phase: .created(29), origin: source, reader: r))
        }
        r.identity = try identity(namespace: "e\u{301}")
        XCTAssertNil(RoamCreatedStampTarget(phase: .created(29), origin: try origin(namespace: "\u{e9}"), reader: r))
        r.identity = nil
        XCTAssertNil(RoamCreatedStampTarget(phase: .created(29), origin: try origin(), reader: r))
    }
    func testTargetFencesReaderReplacementAndEpoch() throws {
        let r = try reader(), t = try target(r), other = try reader()
        XCTAssertTrue(t.isCurrent(reader: r)); XCTAssertFalse(t.isCurrent(reader: other))
        r.identity = try identity(epoch: 2); XCTAssertFalse(t.isCurrent(reader: r))
    }
    func testReadsOnlyExactVisibleStampAndStopsAfterFound() async throws {
        let r = try reader(); r.pages[1] = try page([8, 29, 31])
        let model = try RoamCreatedStampLookup(target: target(r), reader: r)
        await model.loadNext(); await model.loadNext()
        XCTAssertEqual(model.phase, .found); XCTAssertEqual(model.stamp?.id, 29)
        XCTAssertEqual(model.stamp?.caption, "server caption"); XCTAssertEqual(r.requests, [1])
    }
    func testHiddenOrUnknownModerationDoesNotExposeCaptionOrPhoto() async throws {
        for state in [2, 3, -1] {
            let r = try reader(); r.pages[1] = try page([29], state: state, caption: "must not display")
            let model = try RoamCreatedStampLookup(target: target(r), reader: r)
            await model.loadNext()
            XCTAssertEqual(model.phase, .hidden); XCTAssertNil(model.stamp)
        }
    }
    func testOnlyOnePagePerRequestThenExplicitNextFindsStamp() async throws {
        let r = try reader(); r.pages[1] = try page([8], total: 40); r.pages[2] = try page([29], number: 2, total: 40)
        let model = try RoamCreatedStampLookup(target: target(r), reader: r)
        await model.loadNext(); XCTAssertEqual(model.phase, .more); XCTAssertEqual(r.requests, [1]); XCTAssertNil(model.stamp)
        await model.loadNext(); XCTAssertEqual(model.phase, .found); XCTAssertEqual(r.requests, [1, 2])
    }
    func testExhaustedListIsMissingNotAConstructedStamp() async throws {
        let r = try reader(); r.pages[1] = try page([8])
        let model = try RoamCreatedStampLookup(target: target(r), reader: r)
        await model.loadNext(); await model.loadNext()
        XCTAssertEqual(model.phase, .missing); XCTAssertNil(model.stamp); XCTAssertEqual(r.requests, [1])
    }
    func testPageFailureRetriesSamePageWithoutCreateOrUpload() async throws {
        let r = try reader(); r.pages[1] = try page([8], total: 40); r.pages[2] = try page([29], number: 2, total: 40)
        let model = try RoamCreatedStampLookup(target: target(r), reader: r)
        await model.loadNext(); r.failure = APIError.httpStatus(503); await model.loadNext()
        XCTAssertEqual(model.phase, .failed); XCTAssertNil(model.stamp)
        r.failure = nil; await model.loadNext()
        XCTAssertEqual(r.requests, [1, 2, 2]); XCTAssertEqual(model.stamp?.id, 29)
    }
    func testMismatchedPageAndDuplicateTargetFailClosed() async throws {
        for response in [try page([29], number: 2), try page([29], size: 10), try page([29, 29]), try page([29], total: 0)] {
            let r = try reader(); r.pages[1] = response
            let model = try RoamCreatedStampLookup(target: target(r), reader: r)
            await model.loadNext()
            XCTAssertEqual(model.phase, .failed); XCTAssertNil(model.stamp)
        }
    }
    func testUnconfiguredReaderDoesNotDispatchButExplicitRetryCanRead() async throws {
        let r = try reader(); r.pages[1] = try page([29]); r.isConfigured = false
        let model = try RoamCreatedStampLookup(target: target(r), reader: r)
        await model.loadNext(); XCTAssertEqual(model.phase, .failed); XCTAssertTrue(r.requests.isEmpty)
        r.isConfigured = true; await model.loadNext(); XCTAssertEqual(model.stamp?.id, 29)
    }
    func testOtherReaderCannotUseCapturedTarget() async throws {
        let first = try reader(), other = try reader()
        let model = try RoamCreatedStampLookup(target: target(first), reader: other)
        await model.loadNext(); XCTAssertEqual(model.phase, .unavailable); XCTAssertTrue(other.requests.isEmpty)
    }
    func testUnauthorizedReadCannotRetryUnderOldTarget() async throws {
        let r = try reader(); r.failure = APIError.unauthorized
        let model = try RoamCreatedStampLookup(target: target(r), reader: r)
        await model.loadNext(); await model.loadNext()
        XCTAssertEqual(model.phase, .unavailable); XCTAssertNil(model.stamp); XCTAssertEqual(r.requests, [1])
    }
    func testReaderDisabledDuringReadDoesNotExposeReturnedStamp() async throws {
        let r = try reader(); r.hold = true
        let model = try RoamCreatedStampLookup(target: target(r), reader: r)
        let work = Task { await model.loadNext() }; await r.waitForRequest()
        r.isConfigured = false; r.release(1, page: try page([29])); await work.value
        XCTAssertEqual(model.phase, .failed); XCTAssertNil(model.stamp)
    }
    func testCancelRetiresLateReadAndClearsPrivateResult() async throws {
        let r = try reader(); r.hold = true
        let model = try RoamCreatedStampLookup(target: target(r), reader: r)
        let work = Task { await model.loadNext() }; await r.waitForRequest()
        model.cancel(); r.release(1, page: try page([29])); await work.value
        XCTAssertEqual(model.phase, .idle); XCTAssertNil(model.stamp)
    }
    func testOwnerChangeDuringReadCannotDisplayOldStamp() async throws {
        let r = try reader(); r.hold = true
        let model = try RoamCreatedStampLookup(target: target(r), reader: r)
        let work = Task { await model.loadNext() }; await r.waitForRequest()
        r.identity = try identity(account: 4); r.release(1, page: try page([29])); await work.value
        XCTAssertEqual(model.phase, .unavailable); XCTAssertNil(model.stamp)
    }
    func testRepeatedLoadWhilePendingIsSingleFlight() async throws {
        let r = try reader(); r.hold = true
        let model = try RoamCreatedStampLookup(target: target(r), reader: r)
        let work = Task { await model.loadNext() }; await r.waitForRequest()
        await model.loadNext(); XCTAssertEqual(r.requests, [1]); XCTAssertEqual(model.phase, .loading)
        r.release(1, page: try page([29])); await work.value; XCTAssertEqual(model.phase, .found)
    }
    func testRefreshKeepsNewResponseWhenOldReadCompletesLater() async throws {
        let r = try reader(); r.hold = true
        let model = try RoamCreatedStampLookup(target: target(r), reader: r)
        let old = Task { await model.loadNext() }; await r.waitForRequest()
        r.hold = false; r.pages[1] = try page([29], caption: "new read")
        await model.refresh(); r.release(1, page: try page([29], caption: "old read")); await old.value
        XCTAssertEqual(model.stamp?.caption, "new read"); XCTAssertEqual(r.requests, [1, 1])
    }
    func testTaskCancellationDoesNotPresentAResult() async throws {
        let r = try reader(); r.hold = true
        let model = try RoamCreatedStampLookup(target: target(r), reader: r)
        let work = Task { await model.loadNext() }; await r.waitForRequest(); work.cancel()
        r.release(1, page: try page([29])); await work.value
        XCTAssertEqual(model.phase, .idle); XCTAssertNil(model.stamp)
    }
}
