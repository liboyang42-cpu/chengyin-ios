import XCTest
@testable import Questify

private actor SearchMapRefreshTransport: HTTPTransport {
    private let delayed: Bool
    private var continuations: [(String, CheckedContinuation<(Data, Int), Error>)] = []
    private(set) var paths: [String] = []
    var pendingCount: Int { continuations.count }
    init(delayed: Bool = false) { self.delayed = delayed }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let path = request.url!.path; paths.append(path)
        if delayed {
            return try await withCheckedThrowingContinuation { continuations.append((path, $0)) }
        }
        return response(path)
    }
    private func response(_ path: String) -> (Data, Int) {
        let value = path.hasSuffix("/activity/list")
            ? #"{"code":200,"data":{"rows":[{"id":2,"name":"Synthetic refreshed activity","latitude":1,"longitude":2}],"total":1}}"#
            : #"{"code":200,"data":[{"poiId":2,"name":"Synthetic refreshed point","lat":1,"lng":2}]}"#
        return (Data(value.utf8), 200)
    }
    func release(unauthorized: Bool = false) {
        let current = continuations; continuations = []
        for (path, continuation) in current {
            continuation.resume(returning: unauthorized ? (Data(#"{"code":401}"#.utf8), 200) : response(path))
        }
    }
}

@MainActor final class SearchMapRefreshPresentationTests: XCTestCase {
    private var query: CityNodeSearchQuery {
        .init(filter: .init(), area: .init(coordinate: RoamCoordinate(latitude: 1, longitude: 2)!, label: "Synthetic"))
    }
    private func service(_ transport: any HTTPTransport) throws -> SearchMapService {
        .init(configuration: try APIConfiguration(baseURL: URL(string: "https://example.test/")!), transport: transport)
    }
    func testExplicitRefreshUsesExistingTwoReadsWithoutReselectingManualArea() async throws {
        let transport = SearchMapRefreshTransport()
        let context = try SearchMapContext(accountID: 1, epoch: 1, token: "synthetic")
        let selection = ManualMapAreaSelection()
        let reader = SearchMapSessionReader(service: try service(transport), currentContext: { context }, manualAreaSelection: selection)
        reader.selectManualArea(query.area)
        let revision = reader.manualAreaRevision
        let previous = try await reader.citySearch(query)
        var pagination = SearchMapPagination()
        pagination.reset(query: query, scope: reader.scope, manualAreaRevision: revision, result: previous)
        var refresh = SearchMapRefresh()
        let ticket = try XCTUnwrap(refresh.begin(query: query, scope: reader.scope, manualAreaRevision: revision, result: previous, pagination: pagination))
        let result = try await reader.citySearch(ticket.query)
        let update = try XCTUnwrap(refresh.finish(ticket, result: result, query: query, scope: reader.scope, manualAreaRevision: reader.manualAreaRevision))
        XCTAssertEqual(reader.manualAreaRevision, revision)
        XCTAssertEqual(update.pagination.rows.map(\.id), [2])
        let paths = await transport.paths
        XCTAssertEqual(paths.filter { $0 == "/api/activity/list" }.count, 2)
        XCTAssertEqual(paths.filter { $0 == "/api/city/nodes" }.count, 2)
        XCTAssertEqual(paths.count, 4)
    }
    func testSessionOrAreaChangeDiscardsLateRefreshAndCannotExpireNewAccount() async throws {
        for variant in 0..<3 {
            let transport = SearchMapRefreshTransport(delayed: true)
            var context = try SearchMapContext(accountID: 1, epoch: 1, token: "synthetic")
            var expired = 0
            let selection = ManualMapAreaSelection()
            let reader = SearchMapSessionReader(service: try service(transport), currentContext: { context },
                onUnauthorized: { _ in expired += 1 }, manualAreaSelection: selection)
            reader.selectManualArea(query.area)
            let captured = query
            let task = Task { try await reader.citySearch(captured) }
            while (await transport.pendingCount) < 2 { await Task.yield() }
            if variant == 2 { reader.selectManualArea(query.area) }
            else { context = try SearchMapContext(accountID: 2, epoch: 2, token: "new-synthetic") }
            await transport.release(unauthorized: variant == 1)
            do { _ = try await task.value; XCTFail("Retired refresh must not return a snapshot") }
            catch { XCTAssertTrue(error is CancellationError) }
            XCTAssertEqual(expired, 0)
        }
    }
    func testDismissalBeforeQueuedRefreshPreventsDispatchAndRetryGetsNewTicket() async throws {
        let reader = SearchMapFixtureReader(scenario: .pagination)
        let previous = try await reader.citySearch(query)
        var pagination = SearchMapPagination()
        pagination.reset(query: query, scope: reader.scope, manualAreaRevision: 0, result: previous)
        var refresh = SearchMapRefresh()
        let owner = ManualMapReadTaskOwner()
        var dispatched = 0
        let old = try XCTUnwrap(refresh.begin(query: query, scope: reader.scope, manualAreaRevision: 0, result: previous, pagination: pagination))
        owner.start { dispatched += 1 }
        owner.deactivate(); refresh.cancelPending()
        await Task.yield(); XCTAssertEqual(dispatched, 0)
        owner.activate()
        let current = try XCTUnwrap(refresh.begin(query: query, scope: reader.scope, manualAreaRevision: 0, result: previous, pagination: pagination))
        XCTAssertNotEqual(old, current)
        owner.start { dispatched += 1 }
        while dispatched == 0 { await Task.yield() }
        XCTAssertEqual(dispatched, 1)
        XCTAssertNil(refresh.finish(old, result: previous, query: query, scope: reader.scope, manualAreaRevision: 0))
        owner.deactivate(); refresh.cancelPending()
    }
    func testOwnerCancellationSuppressesNoncooperativeLateRefresh() async throws {
        let transport = SearchMapRefreshTransport(delayed: true)
        let context = try SearchMapContext(accountID: 1, epoch: 1, token: "synthetic")
        let reader = SearchMapSessionReader(service: try service(transport), currentContext: { context })
        let owner = ManualMapReadTaskOwner()
        var applied = false; var finished = false
        let captured = query
        owner.start {
            defer { finished = true }
            do { _ = try await reader.citySearch(captured); applied = true } catch { }
        }
        while (await transport.pendingCount) < 2 { await Task.yield() }
        owner.deactivate()
        await transport.release()
        while !finished { await Task.yield() }
        XCTAssertFalse(applied)
    }
}
