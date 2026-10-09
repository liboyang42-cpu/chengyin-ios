import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class GlobalSearchRetentionReaderIdentity {}
private actor GlobalSearchRetentionTransport: HTTPTransport {
    let deniedStatus: Int
    let deniedCode: Int
    init(status: Int = 200, code: Int = 200) { deniedStatus = status; deniedCode = code }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let path = request.url!.path
        if path.hasSuffix("merchant/list") { return (Data("{\"code\":\(deniedCode),\"data\":[]}".utf8), deniedStatus) }
        let rows = path.hasSuffix("topic/list") ? SearchMapSyntheticFixtures.topics :
            path.hasSuffix("activity/list") ? SearchMapSyntheticFixtures.activities : SearchMapSyntheticFixtures.clubs
        let payload = path.hasSuffix("club/list") ? rows : "{\"rows\":\(rows)}"
        return (Data("{\"code\":200,\"data\":\(payload)}".utf8), 200)
    }
}

final class GlobalSearchRetainedResultsTests: XCTestCase {
    private let reader = GlobalSearchRetentionReaderIdentity()
    private let scope = UUID()
    private func context(_ query: GlobalSearchQuery = .init(keyword: "walk"), scope: UUID? = nil,
                         authenticated: Bool = true, configured: Bool = true,
                         readerID: ObjectIdentifier? = nil) -> GlobalSearchResultContext {
        .init(readerID: readerID ?? ObjectIdentifier(reader), scope: scope ?? self.scope,
              isAuthenticated: authenticated, isConfigured: configured, query: query)
    }
    private func row(_ kind: GlobalSearchKind, _ id: Int = 1) -> GlobalSearchRow {
        .init(kind: kind, sourceID: id, title: "Synthetic \(kind.rawValue) \(id)")
    }
    private func seeded() -> GlobalSearchRetainedResults {
        var state = GlobalSearchRetainedResults()
        let ticket = state.begin(in: context())
        XCTAssertTrue(state.finish(.init(rows: GlobalSearchKind.allCases.map { row($0) }), ticket: ticket, in: context()))
        return state
    }
    func testSameQueryRefreshKeepsPreviouslyReadRowsWhilePending() throws {
        var state = seeded(); let before = try XCTUnwrap(state.snapshot(in: context()))
        let ticket = state.begin(in: context())
        XCTAssertTrue(state.accepts(ticket, in: context()))
        XCTAssertEqual(state.snapshot(in: context()), before)
    }
    func testOnlyFailedLanesRetainAndSuccessfulLanesReplaceInDomainOrder() throws {
        var state = seeded(); let ticket = state.begin(in: context())
        let value = GlobalSearchResults(rows: [row(.merchant, 8), row(.activity, 9)], failedKinds: [.topic, .club])
        XCTAssertTrue(state.finish(value, ticket: ticket, in: context()))
        let result = try XCTUnwrap(state.snapshot(in: context()))
        XCTAssertEqual(result.results.rows.map(\.id), ["topic-1", "activity-9", "club-1", "merchant-8"])
        XCTAssertEqual(result.retainedKinds, [.topic, .club])
        XCTAssertEqual(result.results.failedKinds, [.topic, .club])
    }
    func testSuccessfulEmptyClearsOldRowsAndDoesNotBecomeRetention() throws {
        var state = seeded(); let ticket = state.begin(in: context())
        state.finish(.init(rows: [], failedKinds: [.merchant]), ticket: ticket, in: context())
        let value = try XCTUnwrap(state.snapshot(in: context()))
        XCTAssertEqual(value.results.rows.map(\.id), ["merchant-1"])
        XCTAssertEqual(value.retainedKinds, [.merchant])
        let retry = state.begin(in: context()); state.finish(.init(rows: []), ticket: retry, in: context())
        XCTAssertEqual(state.snapshot(in: context())?.results.rows, [])
        XCTAssertEqual(state.snapshot(in: context())?.retainedKinds, [])
    }
    func testGatedLanePurgesEvenWhenAlsoMarkedFailedAndCannotResurrectLater() throws {
        var state = seeded(); let ticket = state.begin(in: context())
        state.finish(.init(rows: [row(.merchant, 999)], failedKinds: [.merchant], gatedKinds: [.merchant]), ticket: ticket, in: context())
        XCTAssertEqual(state.snapshot(in: context())?.results.rows, [])
        XCTAssertEqual(state.snapshot(in: context())?.retainedKinds, [])
        let retry = state.begin(in: context()); state.finish(.init(rows: [], failedKinds: [.merchant]), ticket: retry, in: context())
        XCTAssertEqual(state.snapshot(in: context())?.results.rows, [])
    }
    func testAllFailedWithoutBaselineStaysFailureWithoutInventingRows() throws {
        var state = GlobalSearchRetainedResults(); let ticket = state.begin(in: context())
        state.finish(.init(rows: [], failedKinds: GlobalSearchKind.allCases), ticket: ticket, in: context())
        let value = try XCTUnwrap(state.snapshot(in: context()))
        XCTAssertTrue(value.results.allFailed); XCTAssertTrue(value.results.rows.isEmpty); XCTAssertTrue(value.retainedKinds.isEmpty)
    }
    func testAllFailedRetainsKnownRowsAndRepeatedFailureDoesNotDuplicateThem() throws {
        var state = seeded()
        for _ in 0..<3 {
            let ticket = state.begin(in: context())
            state.finish(.init(rows: [], failedKinds: GlobalSearchKind.allCases), ticket: ticket, in: context())
            XCTAssertEqual(state.snapshot(in: context())?.results.rows.count, 4)
            XCTAssertEqual(state.snapshot(in: context())?.retainedKinds, GlobalSearchKind.allCases)
        }
    }
    func testReaderAccountEpochAuthenticationAndConfigurationChangesHideRows() {
        var state = seeded(); let ticket = state.begin(in: context()); let otherReader = GlobalSearchRetentionReaderIdentity()
        for changed in [context(scope: UUID()), context(authenticated: false), context(configured: false), context(readerID: ObjectIdentifier(otherReader))] {
            XCTAssertNil(state.snapshot(in: changed)); XCTAssertFalse(state.accepts(ticket, in: changed))
            XCTAssertFalse(state.finish(.init(rows: [row(.merchant, 8)]), ticket: ticket, in: changed))
        }
    }
    func testExactUTF8QueryIdentityRejectsCanonicalEquivalenceAndWhitespaceChange() {
        let composed = context(.init(keyword: "Caf\u{00E9}")); let decomposed = context(.init(keyword: "Cafe\u{0301}"))
        XCTAssertEqual("Caf\u{00E9}", "Cafe\u{0301}"); XCTAssertNotEqual(composed, decomposed)
        var raw = GlobalSearchQuery(keyword: "walk"); raw.keyword = "walk "
        XCTAssertNotEqual(context(raw), context())
        var state = GlobalSearchRetainedResults(); let ticket = state.begin(in: composed)
        XCTAssertFalse(state.finish(.init(rows: [row(.topic)]), ticket: ticket, in: decomposed))
    }
    func testAllFilterFieldsParticipateInExactContext() {
        for query in [GlobalSearchQuery(keyword: "walk", categoryID: 7), .init(keyword: "walk", startDate: "2030-01-01"),
                      .init(keyword: "walk", endDate: "2030-01-01"), .init(keyword: "walk", minimumPrice: 1), .init(keyword: "walk", maximumPrice: 9)] {
            XCTAssertNotEqual(context(query), context())
        }
    }
    func testQueryABAAndConcurrentRefreshCannotApplyOlderTicket() {
        var state = seeded(); let a = context(), b = context(.init(keyword: "other"))
        let first = state.begin(in: a); _ = state.begin(in: b); let latest = state.begin(in: a)
        XCTAssertNil(state.snapshot(in: a)); XCTAssertFalse(state.accepts(first, in: a))
        XCTAssertFalse(state.finish(.init(rows: [row(.topic, 7)]), ticket: first, in: a))
        XCTAssertTrue(state.finish(.init(rows: [row(.activity, 8)]), ticket: latest, in: a))
        let olderRefresh = state.begin(in: a); let newerRefresh = state.begin(in: a)
        XCTAssertFalse(state.fail(olderRefresh, in: a))
        XCTAssertTrue(state.finish(.init(rows: [row(.merchant, 9)]), ticket: newerRefresh, in: a))
        XCTAssertEqual(state.snapshot(in: a)?.results.rows.map(\.id), ["merchant-9"])
    }
    func testLeavingCancelsPendingWorkWithoutBreakingBackToAcceptedResults() {
        var state = seeded(); let before = state.snapshot(in: context())
        let ticket = state.begin(in: context()); state.cancelPending()
        XCTAssertEqual(state.snapshot(in: context()), before)
        XCTAssertFalse(state.finish(.init(rows: [row(.topic)]), ticket: ticket, in: context()))
        state.invalidate(); XCTAssertNil(state.snapshot(in: context()))
    }
    func testThrownDenialPurgesInsteadOfMarkingOldRowsStale() {
        var state = seeded(); let ticket = state.begin(in: context())
        XCTAssertTrue(state.fail(ticket, in: context())); XCTAssertNil(state.snapshot(in: context()))
        XCTAssertFalse(state.finish(.init(rows: [row(.topic)]), ticket: ticket, in: context()))
    }
    private func service(status: Int = 200, code: Int = 200) throws -> SearchMapService {
        try .init(configuration: APIConfiguration(baseURL: URL(string: "https://example.com/")!),
                  transport: GlobalSearchRetentionTransport(status: status, code: code))
    }
    func testExplicitHTTPAndBusinessPermissionDenialEscapeGlobalLaneFallback() async throws {
        for (status, code, expected) in [(403, 200, APIError.httpStatus(403)), (200, 403, APIError.businessCode(403))] {
            do { _ = try await service(status: status, code: code).search(.init(keyword: "walk")); XCTFail("Denied result must not be treated as retryable") }
            catch { XCTAssertEqual(error as? APIError, expected) }
        }
    }
    func testGuest401KeepsPublicRowsButGatesTheDeniedLane() async throws {
        for (status, code) in [(401, 200), (200, 401)] {
            let value = try await service(status: status, code: code).search(.init(keyword: "walk"))
            XCTAssertEqual(value.gatedKinds, [.merchant]); XCTAssertFalse(value.rows.isEmpty)
            XCTAssertFalse(value.rows.contains { $0.kind == .merchant }); XCTAssertTrue(value.failedKinds.isEmpty)
        }
    }
    func testTransientHTTPFailureRemainsLaneFailureForRetention() async throws {
        let value = try await service(status: 503).search(.init(keyword: "walk"))
        XCTAssertEqual(value.failedKinds, [.merchant]); XCTAssertTrue(value.gatedKinds.isEmpty)
        XCTAssertFalse(value.rows.isEmpty)
    }
}
