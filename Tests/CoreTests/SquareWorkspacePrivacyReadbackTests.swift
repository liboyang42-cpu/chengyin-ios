import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Synthetic, explicitly released reads. No server, account, or deletion is used.
@MainActor private final class PrivacyReadbackHTTP: HTTPTransport {
    var responses: [Int: String] = [:]
    var suspended: Set<Int> = []
    private(set) var requests: [URLRequest] = []
    private var pending: [Int: CheckedContinuation<(Data, Int), Error>] = [:]
    private var waiters: [Int: CheckedContinuation<Void, Never>] = [:]
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        let index = requests.count
        if suspended.contains(index) {
            return try await withCheckedThrowingContinuation {
                pending[index] = $0; waiters.removeValue(forKey: index)?.resume()
            }
        }
        waiters.removeValue(forKey: index)?.resume()
        guard let response = responses[index] else { throw URLError(.timedOut) }
        return (Data(response.utf8), 200)
    }
    func waitForRequest(_ index: Int) async {
        if requests.count >= index { return }
        await withCheckedContinuation { waiters[index] = $0 }
    }
    func release(_ index: Int, response: String) {
        pending.removeValue(forKey: index)?.resume(returning: (Data(response.utf8), 200))
    }
}

@MainActor final class SquareWorkspacePrivacyReadbackTests: XCTestCase {
    private let denied = #"{"code":404,"msg":"Post unavailable"}"#
    private func detail(_ id: Int = 701, author: Int = 81, lifecycle: String = "DRAFT") -> String {
        "{\"code\":200,\"data\":{\"post\":{\"id\":\(id),\"authorId\":\(author),\"version\":3,\"lifecycle\":\"\(lifecycle)\"}}}"
    }
    private func history(_ body: String) -> String {
        "{\"code\":200,\"data\":[{\"body\":\"\(body)\"}]}"
    }
    private func identity(_ account: Int = 81, epoch: UInt64 = 1) throws -> SquareWorkspaceSession {
        try .init(accountID: account, namespace: "synthetic-privacy", epoch: epoch)
    }
    private func model(_ http: PrivacyReadbackHTTP, current: (() -> SquareWorkspaceSession?)? = nil,
                       store: SquareWorkspaceStore? = nil, live: Bool = true) throws -> SquareWorkspaceCoordinator {
        let session = try identity(); var grants = SquareWorkspaceGrants(); grants.live = live
        let service = SquareWorkspaceService(configuration: try .init(baseURL: URL(string: "https://example.com")!), transport: http)
        return .init(session: session, store: store ?? .init(storage: SquareWorkspaceMemoryStorage()), service: service,
                     grants: grants, currentSession: current ?? { session }, token: { "synthetic-only" })
    }
    private func shown(_ model: SquareWorkspaceCoordinator) -> String? {
        model.revisionData.flatMap { String(data: $0, encoding: .utf8) }
    }
    func testOwnerHistoryReadsExactDetailThenHistoryAndShowsBoundPost() async throws {
        let http = PrivacyReadbackHTTP(); http.responses = [1: detail(), 2: history("Original history")]
        let coordinator = try model(http)
        let data = try await coordinator.revisions(postID: 701)
        XCTAssertEqual(coordinator.revisionPostID, 701); XCTAssertEqual(coordinator.revisionData, data)
        XCTAssertFalse(coordinator.revisionsLoading)
        XCTAssertEqual(http.requests.map { $0.url!.path }, ["/api/v1/community/posts/701", "/api/v1/community/posts/701/revisions"])
        XCTAssertTrue(http.requests.allSatisfy { $0.httpMethod == "GET" && $0.httpBody == nil && $0.cachePolicy == .reloadIgnoringLocalCacheData })
    }
    func testDeletedDetailBusiness404ClearsPreviouslyDisplayedHistory() async throws {
        let http = PrivacyReadbackHTTP(); http.responses = [1: detail(), 2: history("Old private body"), 3: denied]
        let coordinator = try model(http); _ = try await coordinator.revisions(postID: 701)
        XCTAssertNotNil(coordinator.revisionData)
        do { _ = try await coordinator.revisions(postID: 701); XCTFail() }
        catch { XCTAssertEqual(error as? SquareWorkspaceFailure, .rejected(404)) }
        XCTAssertNil(coordinator.revisionData); XCTAssertFalse(coordinator.revisionsLoading)
        XCTAssertEqual(http.requests.count, 3, "Denied detail must not fetch revisions")
    }
    func testDeletionBetweenDetailAndHistoryRejectsWithoutOldBodyFallback() async throws {
        let http = PrivacyReadbackHTTP(); http.responses = [1: detail(), 2: history("Old private body"), 3: detail(), 4: denied]
        let coordinator = try model(http); _ = try await coordinator.revisions(postID: 701)
        do { _ = try await coordinator.revisions(postID: 701); XCTFail() }
        catch { XCTAssertEqual(error as? SquareWorkspaceFailure, .rejected(404)) }
        XCTAssertNil(coordinator.revisionData); XCTAssertEqual(http.requests.count, 4)
    }
    func testTimeoutClearsHistoryAndSuccessfulRetryShowsOnlyNewResult() async throws {
        let http = PrivacyReadbackHTTP(); http.responses = [1: detail(), 2: history("Old private body")]
        let coordinator = try model(http); _ = try await coordinator.revisions(postID: 701)
        do { _ = try await coordinator.revisions(postID: 701); XCTFail() }
        catch { XCTAssertEqual((error as? URLError)?.code, .timedOut) }
        XCTAssertNil(coordinator.revisionData); XCTAssertFalse(coordinator.revisionsLoading)
        http.responses[4] = detail(); http.responses[5] = history("Fresh authorized body")
        _ = try await coordinator.revisions(postID: 701)
        XCTAssertTrue(shown(coordinator)?.contains("Fresh authorized body") == true)
        XCTAssertFalse(shown(coordinator)?.contains("Old private body") == true)
        XCTAssertTrue(http.requests.allSatisfy { $0.httpMethod == "GET" })
    }
    func testOtherPostSelectionClearsHistoryBeforeFirstSuspendedRead() async throws {
        let http = PrivacyReadbackHTTP(); http.responses = [1: detail(), 2: history("First post"), 4: history("Second post")]; http.suspended = [3]
        let coordinator = try model(http); _ = try await coordinator.revisions(postID: 701)
        let second = Task { try await coordinator.revisions(postID: 702) }; await http.waitForRequest(3)
        XCTAssertNil(coordinator.revisionData); XCTAssertEqual(coordinator.revisionPostID, 702); XCTAssertTrue(coordinator.revisionsLoading)
        http.release(3, response: detail(702)); _ = try await second.value
        XCTAssertTrue(shown(coordinator)?.contains("Second post") == true)
    }
    func testSupersededHistorySuccessCannotOverwriteNewPost() async throws {
        let http = PrivacyReadbackHTTP(); http.responses = [1: detail(), 3: detail(702), 4: history("Current post")]; http.suspended = [2]
        let coordinator = try model(http)
        let old = Task { try await coordinator.revisions(postID: 701) }; await http.waitForRequest(2)
        let current = try await coordinator.revisions(postID: 702)
        http.release(2, response: history("Stale post"))
        do { _ = try await old.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(coordinator.revisionPostID, 702); XCTAssertEqual(coordinator.revisionData, current)
        XCTAssertFalse(coordinator.revisionsLoading)
    }
    func testSupersededHistoryFailureCannotSurfaceOverNewResult() async throws {
        let http = PrivacyReadbackHTTP(); http.responses = [1: detail(), 3: detail(702), 4: history("Current post")]; http.suspended = [2]
        let coordinator = try model(http)
        let old = Task { try await coordinator.revisions(postID: 701) }; await http.waitForRequest(2)
        let current = try await coordinator.revisions(postID: 702)
        http.release(2, response: denied)
        do { _ = try await old.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(coordinator.revisionData, current)
    }
    func testDismissOrBackgroundInvalidationRejectsLateHistory() async throws {
        let http = PrivacyReadbackHTTP(); http.responses = [1: detail()]; http.suspended = [2]
        let coordinator = try model(http)
        let read = Task { try await coordinator.revisions(postID: 701) }; await http.waitForRequest(2)
        coordinator.clearRevisions(); http.release(2, response: history("Late private body"))
        do { _ = try await read.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertNil(coordinator.revisionData); XCTAssertNil(coordinator.revisionPostID); XCTAssertFalse(coordinator.revisionsLoading)
    }
    func testIntentInvalidatedBeforeTaskStartsMakesNoRequest() async throws {
        let http = PrivacyReadbackHTTP(), coordinator = try model(http)
        let queued = try coordinator.prepareRevisions(postID: 701)
        coordinator.clearRevisions()
        do { _ = try await coordinator.revisions(queued); XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(http.requests.isEmpty)
        XCTAssertNil(coordinator.revisionData); XCTAssertNil(coordinator.revisionPostID); XCTAssertFalse(coordinator.revisionsLoading)
    }
    func testOldQueuedIntentCannotClearNewHistoryOrStartAnyRequest() async throws {
        let http = PrivacyReadbackHTTP(); http.responses = [1: detail(702), 2: history("Current post")]
        let coordinator = try model(http)
        let queued = try coordinator.prepareRevisions(postID: 701)
        let current = try coordinator.prepareRevisions(postID: 702)
        let displayed = try await coordinator.revisions(current)
        do { _ = try await coordinator.revisions(queued); XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(http.requests.count, 2)
        XCTAssertEqual(coordinator.revisionPostID, 702); XCTAssertEqual(coordinator.revisionData, displayed)
        XCTAssertFalse(coordinator.revisionsLoading)
    }
    func testCancelledQueuedConvenienceReadCannotResetNewHistory() async throws {
        let http = PrivacyReadbackHTTP(); http.responses = [1: detail(702), 2: history("Current post")]
        let coordinator = try model(http)
        let queued = Task { try await coordinator.revisions(postID: 701) }
        queued.cancel()
        let displayed = try await coordinator.revisions(postID: 702)
        do { _ = try await queued.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(http.requests.count, 2)
        XCTAssertEqual(coordinator.revisionPostID, 702); XCTAssertEqual(coordinator.revisionData, displayed)
        XCTAssertFalse(coordinator.revisionsLoading)
    }
    func testPreparedIntentIsSingleUseAndCannotReuseOldAuthorization() async throws {
        let http = PrivacyReadbackHTTP(); http.responses = [1: detail(), 2: history("Current post")]
        let coordinator = try model(http), intent = try coordinator.prepareRevisions(postID: 701)
        let displayed = try await coordinator.revisions(intent)
        do { _ = try await coordinator.revisions(intent); XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(http.requests.count, 2); XCTAssertEqual(coordinator.revisionData, displayed)
    }
    func testInvalidationDuringDetailStopsBeforeHistoryRequest() async throws {
        let http = PrivacyReadbackHTTP(); http.suspended = [1]
        let coordinator = try model(http)
        let read = Task { try await coordinator.revisions(postID: 701) }; await http.waitForRequest(1)
        coordinator.clearRevisions(); http.release(1, response: detail())
        do { _ = try await read.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(http.requests.count, 1); XCTAssertNil(coordinator.revisionData)
    }
    func testAccountOrEpochChangeDuringHistoryCannotPublish() async throws {
        for replacement in [try identity(82), try identity(epoch: 2)] {
            let http = PrivacyReadbackHTTP(); http.responses = [1: detail()]; http.suspended = [2]
            var current: SquareWorkspaceSession? = try identity()
            let coordinator = try model(http, current: { current })
            let read = Task { try await coordinator.revisions(postID: 701) }; await http.waitForRequest(2)
            current = replacement; http.release(2, response: history("Old account history"))
            do { _ = try await read.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
            XCTAssertNil(coordinator.revisionData); XCTAssertNil(coordinator.revisionPostID)
            XCTAssertEqual(coordinator.status, "squareWorkspace.sessionChanged")
        }
    }
    func testNonOwnerCannotFetchHistoryAndUnchangedAuthorStatesStillRead() async throws {
        let http = PrivacyReadbackHTTP(); http.responses = [1: detail(author: 82)]
        let coordinator = try model(http)
        do { _ = try await coordinator.revisions(postID: 701); XCTFail() }
        catch { XCTAssertEqual(error as? SquareWorkspaceFailure, .ownerRequired) }
        XCTAssertEqual(http.requests.count, 1); XCTAssertNil(coordinator.revisionData)
        for lifecycle in ["DRAFT", "CHECKING", "LIMITED", "HIDDEN", "REMOVED", "PUBLISHED"] {
            let next = http.requests.count + 1
            http.responses[next] = detail(lifecycle: lifecycle); http.responses[next + 1] = history(lifecycle)
            _ = try await coordinator.revisions(postID: 701)
            XCTAssertTrue(shown(coordinator)?.contains(lifecycle) == true)
        }
    }
    func testServerRefreshFailureClearsHistoryButPreservesUnsentLocalDraft() async throws {
        let http = PrivacyReadbackHTTP(); http.responses = [1: detail(), 2: history("Old history"), 3: denied]
        let store = SquareWorkspaceStore(storage: SquareWorkspaceMemoryStorage())
        let coordinator = try model(http, store: store), draft = SquareWorkspaceFixtures.draft()
        try coordinator.saveLocal(draft, lane: .communityV1)
        _ = try await coordinator.revisions(postID: 701)
        do { try await coordinator.loadServer(); XCTFail() } catch { }
        XCTAssertNil(coordinator.revisionData); XCTAssertNil(coordinator.revisionPostID)
        XCTAssertEqual(try store.entries(session: identity()).first?.draft, draft)
    }
    func testDefaultOffHistoryReadMakesNoRequest() async throws {
        let http = PrivacyReadbackHTTP(), coordinator = try model(http, live: false)
        do { _ = try await coordinator.revisions(postID: 701); XCTFail() }
        catch { XCTAssertEqual(error as? SquareWorkspaceFailure, .disabled) }
        XCTAssertTrue(http.requests.isEmpty); XCTAssertNil(coordinator.revisionData); XCTAssertFalse(coordinator.revisionsLoading)
    }
}
