import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private func browserPage(_ ids: [Int], total: Int? = nil) throws -> MerchantTemplatePage {
    var object: [String: Any] = ["rows": ids.map { ["id": $0, "title": "Synthetic \($0)"] }]
    if let total { object["total"] = total }
    return try JSONDecoder().decode(MerchantTemplatePage.self, from: JSONSerialization.data(withJSONObject: object))
}
private func browserAccess(_ merchant: Int = 31, allowed: Bool = true) throws -> MerchantOperationsAccess {
    let object: [String: Any] = ["active": true, "merchant": ["id": merchant], "roleCode": "MERCHANT_OWNER",
                              "permissions": allowed ? ["merchant:project:manage"] : []]
    return try JSONDecoder().decode(MerchantOperationsAccess.self, from: JSONSerialization.data(withJSONObject: object))
}
private func browserResult(_ ids: [Int], total: Int? = nil, merchant: Int = 31) throws -> MerchantTemplatePageRead {
    .init(page: try browserPage(ids, total: total), access: try browserAccess(merchant))
}
final class MerchantTemplatePageTests: XCTestCase {
    func testKnownUnknownAndEmptyTotalsRemainDistinct() throws {
        XCTAssertEqual(try browserPage([1], total: 12).total, 12)
        XCTAssertNil(try browserPage([1]).total); XCTAssertEqual(try browserPage([], total: 0).total, 0)
        let value = try JSONDecoder().decode(MerchantTemplatePage.self, from: Data(#"{"rows":[],"total":"12"}"#.utf8))
        XCTAssertEqual(value.total, 12)
    }
    func testMalformedRowShapesIDsAndDuplicateRecordsFail() throws {
        for raw in ["null", "[]", #"{"rows":null}"#, #"{"rows":[{"id":0,"title":"A"}]}"#,
                    #"{"rows":[{"id":1,"title":"A"},{"id":1,"title":"B"}]}"#] {
            XCTAssertThrowsError(try JSONDecoder().decode(MerchantTemplatePage.self, from: Data(raw.utf8)))
        }
    }
    func testMalformedAndUnderstatedTotalsFailRatherThanBecomeZero() throws {
        for raw in [#"{"rows":[],"total":-1}"#, #"{"rows":[],"total":1.5}"#,
                    #"{"rows":[],"total":"bad"}"#, #"{"rows":[],"total":{}}"#,
                    #"{"rows":[{"id":1,"title":"A"}],"total":0}"#] {
            XCTAssertThrowsError(try JSONDecoder().decode(MerchantTemplatePage.self, from: Data(raw.utf8)))
        }
    }
}

@MainActor private final class BrowserReader: MerchantOperationsReading {
    let fixture = MerchantOperationsFixtureReader()
    var scope: UUID { fixture.scope }
    var isConfigured: Bool { true }
    var isAuthenticated: Bool { fixture.isAuthenticated }
    var isOfflineExample: Bool { true }
    var replies: [Int: [Result<MerchantTemplatePageRead, Error>]] = [:]
    var calls: [Int] = []
    var suspend = false
    var pending: [(Int, CheckedContinuation<MerchantTemplatePageRead, Error>)] = []
    func access() async throws -> MerchantOperationsAccess { try await fixture.access() }
    func document(_ destination: MerchantOperationsDestination) async throws -> MerchantOperationsDocument { try await fixture.document(destination) }
    func saveExample(_ draft: MerchantOperationsDraft) async throws { try await fixture.saveExample(draft) }
    func templatePage(page: Int) async throws -> MerchantTemplatePageRead {
        calls.append(page)
        if suspend { return try await withCheckedThrowingContinuation { pending.append((page, $0)) } }
        guard var queue = replies[page], !queue.isEmpty else { throw APIError.malformedResponse }
        let result = queue.removeFirst(); replies[page] = queue; return try result.get()
    }
}
@MainActor final class MerchantTemplateBrowserTests: XCTestCase {
    private func first() async throws -> (BrowserReader, MerchantTemplateBrowser) {
        let reader = BrowserReader(); reader.replies[1] = [.success(try browserResult(Array(1...10), total: 25))]
        let browser = MerchantTemplateBrowser(reader: reader); await browser.refresh()
        return (reader, browser)
    }
    func testAll105TemplatesAreReachableAndEndStopsRequests() async throws {
        let reader = MerchantOperationsFixtureReader(); try reader.configureTemplateBrowserFixture()
        let browser = MerchantTemplateBrowser(reader: reader); await browser.refresh()
        XCTAssertEqual(browser.rows.count, 10); XCTAssertEqual(browser.total, 105)
        for _ in 0..<10 { await browser.loadMore() }
        XCTAssertEqual(browser.rows.count, 105); XCTAssertEqual(browser.rows.last?.id, 175)
        XCTAssertEqual(browser.page, 11); XCTAssertFalse(browser.hasMore); await browser.loadMore()
        XCTAssertEqual(reader.templatePageRequests, Array(1...11)); XCTAssertEqual(reader.saveCount, 0)
    }
    func testUnknownTotalUsesFullPageWithoutInventingCount() async throws {
        let reader = BrowserReader(); reader.replies[1] = [.success(try browserResult(Array(1...10)))]
        reader.replies[2] = [.success(try browserResult([11, 12]))]
        let browser = MerchantTemplateBrowser(reader: reader); await browser.refresh()
        XCTAssertNil(browser.total); XCTAssertTrue(browser.hasMore); await browser.loadMore()
        XCTAssertNil(browser.total); XCTAssertFalse(browser.hasMore); XCTAssertEqual(browser.rows.count, 12)
    }
    func testFirstFailureRetryAndGenuineEmptyAreDifferent() async throws {
        let reader = BrowserReader(); reader.replies[1] = [.failure(APIError.httpStatus(503)), .success(try browserResult([], total: 0))]
        let browser = MerchantTemplateBrowser(reader: reader); await browser.refresh()
        XCTAssertNotNil(browser.issue); XCTAssertFalse(browser.loaded); XCTAssertFalse(browser.canOpen)
        await browser.refresh(); XCTAssertNil(browser.issue); XCTAssertTrue(browser.loaded)
        XCTAssertTrue(browser.rows.isEmpty); XCTAssertTrue(browser.canOpen); XCTAssertFalse(browser.hasMore)
    }
    func testAppendFailureRetainsRowsAndRetriesSamePage() async throws {
        let (reader, browser) = try await first(); reader.replies[2] = [.failure(APIError.httpStatus(503)), .success(try browserResult(Array(11...20), total: 25))]
        await browser.loadMore(); XCTAssertNotNil(browser.loadMoreIssue); XCTAssertEqual(browser.page, 1)
        XCTAssertEqual(browser.rows.map(\.id), Array(1...10)); XCTAssertTrue(browser.canLoadMore)
        await browser.loadMore(); XCTAssertNil(browser.loadMoreIssue); XCTAssertEqual(browser.page, 2)
        XCTAssertEqual(reader.calls, [1, 2, 2]); XCTAssertEqual(browser.rows.count, 20)
    }
    func testRefreshFailureRetainsSnapshotAndBlocksAppendingUntilRefreshed() async throws {
        let (reader, browser) = try await first(); reader.replies[1] = [.failure(APIError.httpStatus(503)), .success(try browserResult([41], total: 1))]
        await browser.refresh(); XCTAssertNotNil(browser.issue); XCTAssertEqual(browser.rows.count, 10)
        XCTAssertEqual(browser.total, 25); XCTAssertFalse(browser.canLoadMore)
        await browser.loadMore(); XCTAssertEqual(reader.calls, [1, 1])
        await browser.refresh(); XCTAssertEqual(browser.rows.map(\.id), [41]); XCTAssertNil(browser.issue)
    }
    func testRefreshSupersedesLateAppendWithoutMixingSnapshots() async throws {
        let (reader, browser) = try await first(); reader.suspend = true
        let more = Task { await browser.loadMore() }; while reader.pending.count < 1 { await Task.yield() }
        let fresh = Task { await browser.refresh() }; while reader.pending.count < 2 { await Task.yield() }
        reader.pending[1].1.resume(returning: try browserResult([51], total: 1)); await fresh.value
        reader.pending[0].1.resume(returning: try browserResult(Array(11...20), total: 25)); await more.value
        XCTAssertEqual(browser.rows.map(\.id), [51]); XCTAssertEqual(browser.page, 1); XCTAssertFalse(browser.isBusy)
    }
    func testOverlappingPageFailsAtomicallyWithoutSilentDedupOrAdvance() async throws {
        let (reader, browser) = try await first(); reader.replies[2] = [.success(try browserResult(Array(10...19), total: 25))]
        await browser.loadMore(); XCTAssertNotNil(browser.loadMoreIssue)
        XCTAssertEqual(browser.rows.map(\.id), Array(1...10)); XCTAssertEqual(browser.page, 1)
    }
    func testEmptyPageWithKnownRemainingRowsIsNotFalseCompletion() async throws {
        let (reader, browser) = try await first(); reader.replies[2] = [.success(try browserResult([], total: 25))]
        await browser.loadMore(); XCTAssertNotNil(browser.loadMoreIssue); XCTAssertTrue(browser.hasMore); XCTAssertEqual(browser.page, 1)
    }
    func testUnexpectedOversizedPageCannotClaimPaginationWorked() async throws {
        let reader = BrowserReader(); reader.replies[1] = [.success(try browserResult(Array(1...11), total: 11))]
        let browser = MerchantTemplateBrowser(reader: reader); await browser.refresh()
        XCTAssertNotNil(browser.issue); XCTAssertTrue(browser.rows.isEmpty); XCTAssertFalse(browser.loaded)
    }
    func testChangedMerchantAccessClearsEarlierMerchantRows() async throws {
        let (reader, browser) = try await first(); reader.replies[2] = [.success(try browserResult(Array(11...20), total: 25, merchant: 99))]
        await browser.loadMore(); XCTAssertTrue(browser.rows.isEmpty); XCTAssertFalse(browser.loaded)
        XCTAssertEqual(browser.issue, .key("merchant.templateBrowser.accessChanged")); XCTAssertFalse(browser.canLoadMore)
    }
    func testPermissionOrAuthenticationFailureClearsRetainedRows() async throws {
        let failures: [Error] = [MerchantOperationsFailure.accessDenied, APIError.unauthorized]
        for failure in failures {
            let (reader, browser) = try await first(); reader.replies[2] = [.failure(failure)]
            await browser.loadMore(); XCTAssertTrue(browser.rows.isEmpty); XCTAssertNotNil(browser.issue); XCTAssertFalse(browser.loaded)
        }
    }
    func testAccountSwitchCannotReceivePriorAccountLatePage() async throws {
        let (reader, browser) = try await first(); reader.suspend = true
        let more = Task { await browser.loadMore() }; while reader.pending.isEmpty { await Task.yield() }
        reader.fixture.switchAccount(); XCTAssertTrue(browser.rows.isEmpty); XCTAssertNil(browser.total)
        reader.pending[0].1.resume(returning: try browserResult(Array(11...20), total: 25)); await more.value
        XCTAssertFalse(browser.isCurrent); XCTAssertTrue(browser.rows.isEmpty)
    }
    func testLeavingCancelsLateReadAndReturnRefreshesCanonicalFirstPage() async throws {
        let (reader, browser) = try await first(); reader.suspend = true
        let more = Task { await browser.loadMore() }; while reader.pending.isEmpty { await Task.yield() }
        browser.deactivate(); reader.pending[0].1.resume(returning: try browserResult(Array(11...20), total: 25)); await more.value
        XCTAssertFalse(browser.isCurrent); XCTAssertTrue(browser.rows.isEmpty)
        reader.suspend = false; reader.replies[1] = [.success(try browserResult([61], total: 1))]
        await browser.refresh(); XCTAssertEqual(browser.rows.map(\.id), [61]); XCTAssertEqual(reader.calls, [1, 2, 1])
    }
    func testRepeatedLoadMoreWhileBusyDoesNotDuplicateRequest() async throws {
        let (reader, browser) = try await first(); reader.suspend = true
        let more = Task { await browser.loadMore() }; while reader.pending.isEmpty { await Task.yield() }
        await browser.loadMore(); XCTAssertEqual(reader.calls, [1, 2])
        reader.pending[0].1.resume(returning: try browserResult(Array(11...20), total: 25)); await more.value
    }
    func testCancelledCallerCannotCommitItsResponse() async throws {
        let (reader, browser) = try await first(); reader.suspend = true
        let more = Task { await browser.loadMore() }; while reader.pending.isEmpty { await Task.yield() }
        more.cancel(); reader.pending[0].1.resume(returning: try browserResult(Array(11...20), total: 25)); await more.value
        XCTAssertEqual(browser.rows.count, 10); XCTAssertEqual(browser.page, 1); XCTAssertFalse(browser.isBusy)
    }
    func testFixtureReadAfterEditorSaveUsesCanonicalTitle() async throws {
        let reader = MerchantOperationsFixtureReader(); try reader.configureTemplateBrowserFixture(count: 21)
        let browser = MerchantTemplateBrowser(reader: reader); await browser.refresh()
        guard case .draft(.template(var template)) = try await reader.document(.template(71)) else { return XCTFail() }
        template.title = "Synthetic saved title"; try await reader.saveExample(.template(template))
        await browser.refresh(); XCTAssertEqual(browser.rows.first?.title, "Synthetic saved title")
    }
}

private final class BrowserTransport: HTTPTransport {
    var replies: [String] = [], requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); guard !replies.isEmpty else { throw APIError.malformedResponse }
        return (Data(replies.removeFirst().utf8), 200)
    }
}
@MainActor final class MerchantTemplateBrowserServiceTests: XCTestCase {
    private let access = #"{"code":200,"data":{"active":true,"merchant":{"id":31},"roleCode":"MERCHANT_OWNER","permissions":["merchant:project:manage"]}}"#
    private func reader(_ transport: BrowserTransport, onUnauthorized: @escaping (MerchantOperationsSession) -> Void = { _ in }) throws -> MerchantOperationsSessionReader {
        let config = try APIConfiguration(baseURL: URL(string: "https://example.test/prod-api")!)
        let session = try MerchantOperationsSession(accountID: 7, epoch: 1, token: "synthetic-token", storageNamespace: "browser-test")
        return .init(service: .init(configuration: config, transport: transport), currentSession: { session }, onUnauthorized: onUnauthorized)
    }
    func testExactReadFormPreservesMiniPagingAndExistingGrant() async throws {
        let transport = BrowserTransport(); transport.replies = [access, #"{"code":200,"data":{"rows":[{"id":101,"title":"Page 2"}],"total":11}}"#]
        let reader = try reader(transport); let value = try await reader.templatePage(page: 2)
        XCTAssertEqual(value.page.rows.first?.id, 101); XCTAssertEqual(value.access.identity.merchantID, 31)
        XCTAssertEqual(transport.requests.count, 2); XCTAssertFalse(reader.canSave)
        let request = try XCTUnwrap(transport.requests.last); XCTAssertEqual(request.url?.path, "/prod-api/api/template/my-list")
        XCTAssertEqual(request.httpMethod, "POST")
        let body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
        for (key, value) in ["is_quote": "", "keyword": "", "category_id": "", "pageNum": "2", "pageSize": "10"] {
            XCTAssertTrue(body.contains("name=\"\(key)\"\r\n\r\n\(value)\r\n"))
        }
        XCTAssertFalse(body.contains("draft_status")); XCTAssertFalse(body.contains("publish_status"))
    }
    func testInvalidPageDoesNotRequestAccessOrList() async throws {
        let transport = BrowserTransport(); let reader = try reader(transport)
        do { _ = try await reader.templatePage(page: 0); XCTFail() } catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testDeniedGrantStopsBeforeMyList() async throws {
        let transport = BrowserTransport(); transport.replies = [access.replacingOccurrences(of: "merchant:project:manage", with: "merchant:basic:read")]
        let reader = try reader(transport)
        do { _ = try await reader.templatePage(page: 1); XCTFail() } catch { XCTAssertEqual(error as? MerchantOperationsFailure, .accessDenied) }
        XCTAssertEqual(transport.requests.count, 1)
    }
    func testUnauthorizedListUsesExistingSessionCallback() async throws {
        let transport = BrowserTransport(); transport.replies = [access, #"{"code":401,"msg":"Synthetic expired"}"#]
        var rejected = 0; let reader = try reader(transport, onUnauthorized: { _ in rejected += 1 })
        do { _ = try await reader.templatePage(page: 1); XCTFail() } catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        XCTAssertEqual(rejected, 1); XCTAssertEqual(transport.requests.count, 2)
    }
}
