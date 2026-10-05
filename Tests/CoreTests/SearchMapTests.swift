import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private actor SearchMapTestTransport: HTTPTransport {
    var responses: [String:(String,Int)] = [:]
    private(set) var requests: [URLRequest] = []
    func set(_ path: String, _ json: String, status: Int = 200) { responses[path] = (json,status) }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        let key = request.url!.path
        let (json,status) = responses[key] ?? (#"{"code":200,"data":[]}"#, 200)
        return (Data(json.utf8), status)
    }
}
private actor SearchMapSuspendedTransport: HTTPTransport {
    var continuation: CheckedContinuation<(Data,Int),Error>?
    var pending: Bool { continuation != nil }
    func send(_ request: URLRequest) async throws -> (Data,Int) {
        try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func finish(_ json: String) { continuation?.resume(returning: (Data(json.utf8),200)); continuation = nil }
}
private actor SearchMapAggregateSuspendedTransport: HTTPTransport {
    private var pending: [(URLRequest, CheckedContinuation<(Data, Int), Error>)] = []
    var pendingCount: Int { pending.count }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        try await withCheckedThrowingContinuation { pending.append((request, $0)) }
    }
    func finishAll(unauthorized: Bool) {
        let requests = pending; pending = []
        for (request, continuation) in requests {
            let paged = request.url!.path.contains("topic") || request.url!.path.contains("activity")
            let json = unauthorized ? #"{"code":401,"data":"invalid"}"# :
                (paged ? #"{"code":200,"data":{"rows":[]}}"# : #"{"code":200,"data":[]}"#)
            continuation.resume(returning: (Data(json.utf8), 200))
        }
    }
}
final class SearchMapTests: XCTestCase {
    private func service(_ transport: any HTTPTransport) throws -> SearchMapService {
        SearchMapService(configuration: try APIConfiguration(baseURL: URL(string: "https://example.com/test/")!), transport: transport)
    }
    private func decode<T: Decodable>(_ type: T.Type, _ text: String) throws -> T { try JSONDecoder().decode(type, from: Data(text.utf8)) }
    private func seed(_ transport: SearchMapTestTransport) async {
        for (path,data) in [("topic/list", "{\"rows\":\(SearchMapSyntheticFixtures.topics)}"),
                            ("activity/list", "{\"rows\":\(SearchMapSyntheticFixtures.activities)}"),
                            ("club/list", SearchMapSyntheticFixtures.clubs), ("merchant/list", SearchMapSyntheticFixtures.merchants)] {
            await transport.set("/test/api/" + path, "{\"code\":200,\"data\":\(data)}")
        }
    }
    func testBlankSearchMakesNoRequests() async throws {
        let t = SearchMapTestTransport()
        let result = try await service(t).search(.init(keyword: " \n "))
        XCTAssertTrue(result.rows.isEmpty)
        let requests = await t.requests; XCTAssertTrue(requests.isEmpty)
    }
    func testFourDomainsUseExactRoutesJSONAndMultipartWithNoServerDatePrice() async throws {
        let t = SearchMapTestTransport(); await seed(t)
        let result = try await service(t).search(.init(keyword: " Example & 城 ", categoryID: 7, startDate: "2030-01-01", endDate: "2030-12-31", minimumPrice: 10, maximumPrice: 100), token: "synthetic-token")
        XCTAssertEqual(result.rows.map(\.id), ["topic-71","activity-71","activity-73","club-71","merchant-71"])
        let requests = await t.requests
        XCTAssertEqual(Set(requests.compactMap { $0.url?.path }), Set(["/test/api/topic/list", "/test/api/activity/list", "/test/api/club/list", "/test/api/merchant/list"]))
        for request in requests {
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-token")
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
            if request.url!.path.contains("club") || request.url!.path.contains("merchant") {
                XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
                let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String:Any])
                XCTAssertEqual(Set(body.keys), Set(["name", "categoryId"]))
                XCTAssertEqual(body["name"] as? String, "Example & 城")
                XCTAssertEqual(body["categoryId"] as? Int, 7)
                XCTAssertFalse(body["categoryId"] is String)
            } else {
                let body = String(decoding: request.httpBody!, as: UTF8.self)
                XCTAssertTrue(body.contains("name=\"category_id\"")); XCTAssertTrue(body.contains("name=\"pageSize\"\r\n\r\n12"))
                for forbidden in ["startDate","endDate","minPrice","maxPrice","sort_type"] { XCTAssertFalse(body.contains("name=\"\(forbidden)\"")) }
            }
        }
    }
    func testCategoryOnlySearchForwardsAllDomainsWithoutKeywordOrSort() async throws {
        let transport = SearchMapTestTransport(); await seed(transport)
        _ = try await service(transport).search(.init(keyword: " \n ", categoryID: 7), token: "synthetic")
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 4)
        for request in requests {
            if request.url!.path.contains("club") || request.url!.path.contains("merchant") {
                let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
                XCTAssertEqual(Set(body.keys), Set(["name", "categoryId"]))
                XCTAssertEqual(body["name"] as? String, "")
                XCTAssertEqual(body["categoryId"] as? Int, 7)
            } else {
                let body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
                XCTAssertTrue(body.contains("name=\"category_id\"\r\n\r\n7"))
                for forbidden in ["keyword", "name", "categoryId", "sort_type"] {
                    XCTAssertFalse(body.contains("name=\"\(forbidden)\""))
                }
            }
        }
    }
    func testChangingAndClearingCategoryPreservesUnfilteredWireShape() async throws {
        let transport = SearchMapTestTransport(); await seed(transport)
        let categories: [Int?] = [nil, 7, 9, nil]
        for category in categories {
            _ = try await service(transport).search(.init(keyword: "  Café & 城  ", categoryID: category), token: "synthetic")
            let requests = Array((await transport.requests).suffix(4))
            XCTAssertEqual(requests.count, 4)
            for request in requests {
                if request.url!.path.contains("club") || request.url!.path.contains("merchant") {
                    let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
                    XCTAssertEqual(Set(body.keys), Set(category == nil ? ["name"] : ["name", "categoryId"]))
                    XCTAssertEqual(body["name"] as? String, "Café & 城")
                    XCTAssertEqual(body["categoryId"] as? Int, category)
                    if category == nil {
                        XCTAssertEqual(body as? [String: String], ["name": "Café & 城"])
                    }
                } else {
                    let body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
                    XCTAssertTrue(body.contains("name=\"keyword\"\r\n\r\nCafé & 城"))
                    XCTAssertTrue(body.contains("name=\"pageNum\"\r\n\r\n1"))
                    XCTAssertTrue(body.contains("name=\"pageSize\"\r\n\r\n12"))
                    XCTAssertEqual(body.contains("name=\"category_id\""), category != nil)
                    if let category { XCTAssertTrue(body.contains("name=\"category_id\"\r\n\r\n\(category)")) }
                    for forbidden in ["categoryId", "sort_type", "latitude", "longitude"] {
                        XCTAssertFalse(body.contains("name=\"\(forbidden)\""))
                    }
                }
            }
        }
    }
    func testGuestSkipsPrivateClubAndPreservesThreePublicSources() async throws {
        let t = SearchMapTestTransport(); await seed(t)
        let result = try await service(t).search(.init(keyword: "sample", categoryID: 7))
        XCTAssertEqual(result.gatedKinds, [.club]); XCTAssertTrue(result.failedKinds.isEmpty)
        XCTAssertEqual(Set(result.rows.map(\.kind)), Set([.topic,.activity,.merchant]))
        let requests = await t.requests
        XCTAssertEqual(requests.count, 3); XCTAssertFalse(requests.contains { $0.url?.path == "/test/api/club/list" })
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil })
        let merchant = try XCTUnwrap(requests.first { $0.url?.path == "/test/api/merchant/list" })
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(merchant.httpBody)) as? [String: Any])
        XCTAssertEqual(body["categoryId"] as? Int, 7)
    }
    func testPartialFailuresRemainVisibleAndAllFailedIsDistinct() async throws {
        let t = SearchMapTestTransport(); await seed(t)
        await t.set("/test/api/merchant/list", #"{"code":500,"data":[]}"#)
        let result = try await service(t).search(.init(keyword: "sample"), token: "synthetic")
        XCTAssertEqual(result.failedKinds, [.merchant]); XCTAssertFalse(result.allFailed); XCTAssertEqual(result.rows.count, 4)
        for path in ["topic/list","activity/list","club/list"] { await t.set("/test/api/" + path, "bad", status: 503) }
        let failed = try await service(t).search(.init(keyword: "sample"), token: "synthetic")
        XCTAssertTrue(failed.allFailed); XCTAssertTrue(failed.rows.isEmpty)
    }
    func testClientFiltersRespectMissingFactsBoundariesAndDomainExemptions() throws {
        let query = GlobalSearchQuery(startDate: "2030-05-01", endDate: "2030-05-31", minimumPrice: 20, maximumPrice: 100)
        XCTAssertTrue(query.matches(kind: .activity, date: "2030-05-01 08:00:00", price: 20))
        XCTAssertFalse(query.matches(kind: .activity, date: "2030-06-01", price: 50))
        XCTAssertFalse(query.matches(kind: .activity, date: nil, price: 101))
        XCTAssertTrue(query.matches(kind: .topic, date: nil, price: nil))
        XCTAssertTrue(query.matches(kind: .merchant, date: "1900-01-01", price: 9000))
        XCTAssertTrue(query.matches(kind: .club, date: "1900-01-01", price: 9000))
        XCTAssertTrue(GlobalSearchQuery(minimumPrice: 0, maximumPrice: 1000).matches(kind: .activity, date: nil, price: 5000))
    }
    func testInvalidFiltersAndTokensNeverReachTransport() async throws {
        let t = SearchMapTestTransport()
        for query in [GlobalSearchQuery(keyword: "x", categoryID: 0), .init(keyword: "x", categoryID: -1), .init(keyword: "x", minimumPrice: .nan), .init(keyword: "x", minimumPrice: 60, maximumPrice: 50), .init(keyword: "x", startDate: "2030-08-01", endDate: "2030-01-01")] {
            do { _ = try await service(t).search(query); XCTFail() } catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        }
        for token in ["", " \n", "x\r\ny"] {
            do { _ = try await service(t).search(.init(keyword: "x"), token: token); XCTFail() } catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        }
        let requests = await t.requests; XCTAssertTrue(requests.isEmpty)
    }
    func testTypedDestinationAndMerchantIDDoNotUseMemberID() throws {
        for kind in GlobalSearchKind.allCases {
            let row = GlobalSearchRow(kind: kind, sourceID: 71, title: "same")
            switch (kind,row.destination) {
            case (.topic,.topic(71)),(.activity,.activity(71)),(.club,.club(71)),(.merchant,.merchant(71)): break
            default: XCTFail()
            }
        }
        let merchant = try decode([SearchMapMerchant].self, SearchMapSyntheticFixtures.merchants)[0]
        XCTAssertEqual(merchant.id, 71); XCTAssertEqual(merchant.tags, ["Coffee","Culture"])
    }
    func testCityNodesUseGETCamelCaseAndActivitySourceUsesFormSnakeCase() async throws {
        let t = SearchMapTestTransport(); await seed(t)
        await t.set("/test/api/city/nodes", "{\"code\":200,\"data\":\(SearchMapSyntheticFixtures.cityNodes)}")
        let area = RoamSearchArea(coordinate: RoamCoordinate(latitude: 1, longitude: 2)!, label: "Manual")
        let query = CityNodeSearchQuery(filter: .init(keyword: "a & 城", categoryID: 7, minimumPrice: 20), area: area, tag: "Coffee & books", cityRole: "meet", sortType: 2)
        let result = try await service(t).citySearch(query, token: "synthetic")
        XCTAssertEqual(result.nodes.first?.poiID, 71); XCTAssertEqual(result.missingCoordinateCount, 1)
        let requests = await t.requests
        let city = try XCTUnwrap(requests.first { $0.url?.path == "/test/api/city/nodes" })
        XCTAssertEqual(city.httpMethod, "GET"); XCTAssertNil(city.httpBody)
        let fields = Dictionary(uniqueKeysWithValues: URLComponents(url: city.url!, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name,$0.value!) })
        XCTAssertEqual(fields, ["lat":"1.0","lng":"2.0","radius":"20000","keyword":"a & 城","categoryId":"7","tag":"Coffee & books","cityRole":"meet"])
        let activity = try XCTUnwrap(requests.first { $0.url?.path == "/test/api/activity/list" })
        let form = String(decoding: activity.httpBody!, as: UTF8.self)
        XCTAssertTrue(form.contains("name=\"sort_type\"\r\n\r\n2")); XCTAssertTrue(form.contains("name=\"pageSize\"\r\n\r\n50"))
        XCTAssertFalse(form.contains("minPrice")); XCTAssertFalse(form.contains("categoryId"))
    }
    func testGuestCitySearchKeepsActivitiesAndDoesNotCallPrivateNodes() async throws {
        let t = SearchMapTestTransport(); await seed(t)
        let query = CityNodeSearchQuery(filter: .init(), area: .init(coordinate: RoamCoordinate(latitude: 1, longitude: 2)!, label: ""))
        let result = try await service(t).citySearch(query)
        XCTAssertEqual(result.nodeFailure, .unauthorized); XCTAssertEqual(result.activities.count, 2)
        let requests = await t.requests; XCTAssertEqual(requests.count, 1)
    }
    func testCityCoordinateGuardsDoNotInventPins() throws {
        for json in [#"{"poiId":1,"name":"missing"}"#, #"{"poiId":1,"lat":0,"lng":0}"#, #"{"poiId":1,"lat":91,"lng":1}"#, #"{"poiId":1,"lat":"NaN","lng":1}"#] {
            XCTAssertNil(try decode(SearchMapCityNode.self, json).coordinate)
        }
        XCTAssertNotNil(try decode(SearchMapCityNode.self, #"{"poiId":1,"lat":0,"lng":1}"#).coordinate)
    }
    func testCityNodeDetailChecksRequestedIdentityAndDoesNotDecodePhone() async throws {
        let t = SearchMapTestTransport()
        await t.set("/test/api/city/nodes/71", #"{"code":200,"data":{"poiId":72,"name":"wrong"}}"#)
        do { _ = try await service(t).cityNode(id: 71, token: "synthetic"); XCTFail() } catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        let requests = await t.requests; XCTAssertEqual(requests.first?.httpMethod, "GET")
    }
    func testNearbyAndReverseGeocodeHonorExactFormsAndManualFallback() async throws {
        let t = SearchMapTestTransport()
        await t.set("/test/api/map/nearby", "{\"code\":200,\"data\":\(SearchMapSyntheticFixtures.nearby)}")
        await t.set("/test/api/map/reverse-geocode", #"{"code":200,"data":{"city":"","manualInputRequired":true,"reason":"MAP_RATE_LIMITED"}}"#)
        let result = try await service(t).nearby(area: .init(coordinate: RoamCoordinate(latitude: 1, longitude: 2)!, label: ""))
        XCTAssertEqual(result.nodes.first?.nodeId, 909); XCTAssertEqual(result.nodes.first?.topicId, 72)
        XCTAssertTrue(result.city.manualInputRequired); XCTAssertTrue(result.city.worthRetrying); XCTAssertFalse(result.cityFailed)
        let requests = await t.requests; XCTAssertEqual(requests.map { $0.url!.path }, ["/test/api/map/nearby","/test/api/map/reverse-geocode"])
        XCTAssertTrue(String(decoding: requests[0].httpBody!, as: UTF8.self).contains("name=\"radius\"\r\n\r\n2000.0"))
    }
    func testReverseFailureDoesNotHideNearbyButAuthenticated401IsNotSwallowed() async throws {
        let t = SearchMapTestTransport()
        let area = RoamSearchArea(coordinate: RoamCoordinate(latitude: 1, longitude: 2)!, label: "")
        await t.set("/test/api/map/nearby", "{\"code\":200,\"data\":\(SearchMapSyntheticFixtures.nearby)}")
        await t.set("/test/api/map/reverse-geocode", "bad", status: 503)
        let result = try await service(t).nearby(area: area)
        XCTAssertEqual(result.nodes.count, 1); XCTAssertTrue(result.cityFailed)
        await t.set("/test/api/map/reverse-geocode", #"{"code":401}"#)
        do { _ = try await service(t).nearby(area: area, token: "synthetic"); XCTFail() } catch { XCTAssertEqual(error as? APIError, .unauthorized) }
    }
    func testStatusPrecedesMalformedPayload() async throws {
        for (json,status) in [("html",401),(#"{"code":401,"data":"bad"}"#,200),(#"{"code":500,"data":[]}"#,200)] {
            let t = SearchMapTestTransport(); await t.set("/test/api/category/list",json,status:status)
            do { _ = try await service(t).categories(); XCTFail() }
            catch { XCTAssertEqual(error as? APIError, status == 401 || json.contains("401") ? .unauthorized : .businessCode(500)) }
        }
    }
    func testMalformedMissingDataCannotBecomeEmptySuccess() async throws {
        let t = SearchMapTestTransport(); await t.set("/test/api/category/list", #"{"code":200}"#)
        do { _ = try await service(t).categories(); XCTFail() } catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
    }
    func testHistoryIsLocalBoundedTrimmedAndDeduplicated() {
        let original = (1...12).map(String.init)
        let value = SearchHistoryPolicy.adding(" 3 ", to: original)
        XCTAssertEqual(value.first, "3"); XCTAssertEqual(value.count, 10); XCTAssertEqual(value.filter { $0 == "3" }.count, 1)
        XCTAssertEqual(SearchHistoryPolicy.adding("   ", to: value), value)
    }
    func testStraightLineDistanceFiniteNoInventedETAOrInstructions() throws {
        let a = RoamCoordinate(latitude: 0, longitude: 0)!, b = RoamCoordinate(latitude: 0, longitude: 1)!
        let result = SearchRoutePreview.straightLine(.init(origin: a, destination: b, mode: .walking))
        XCTAssertEqual(result.distanceMeters, 111194.9, accuracy: 1)
        XCTAssertTrue(result.isStraightLine); XCTAssertNil(result.etaSeconds); XCTAssertTrue(result.steps.isEmpty)
        XCTAssertTrue(SearchRoutePreview.distance(a, RoamCoordinate(latitude: 0, longitude: 180)!).isFinite)
        XCTAssertEqual(SearchRoutePreview.distance(a,a), 0)
        XCTAssertThrowsError(try SearchRoutePreview(coordinates: [a,b], distanceMeters: .nan, etaSeconds: nil, steps: [], isStraightLine: false))
    }
    @MainActor func testQueryFenceRejectsOldQueryScopeAndCancellation() {
        let gate = SearchMapQueryGate(), scope = UUID()
        let first = gate.begin(scope: scope), second = gate.begin(scope: scope)
        XCTAssertFalse(gate.accepts(first, scope: scope)); XCTAssertTrue(gate.accepts(second, scope: scope))
        XCTAssertFalse(gate.accepts(second, scope: UUID())); gate.invalidate(); XCTAssertFalse(gate.accepts(second, scope: scope))
    }
    @MainActor func testUnconfiguredReaderDoesNotSendAndGuestScopeRotates() async throws {
        var context = SearchMapContext(guestEpoch: 1)
        let reader = SearchMapSessionReader(service: nil, currentContext: { context })
        let scope = reader.scope; context = .init(guestEpoch: 2)
        XCTAssertNotEqual(scope, reader.scope)
        do { _ = try await reader.search(.init(keyword: "x")); XCTFail() } catch { XCTAssertEqual(error as? APIError, .notConfigured) }
    }
    @MainActor func testAccountTokenEpochAndGuestTransitionsDropStaleSuccessAndUnauthorized() async throws {
        let first = try SearchMapContext(accountID: 1, epoch: 1, token: "synthetic-first")
        let transitions = [SearchMapContext(guestEpoch: 2), try SearchMapContext(accountID: 2, epoch: 1, token: "synthetic-first"), try SearchMapContext(accountID: 1, epoch: 2, token: "synthetic-first"), try SearchMapContext(accountID: 1, epoch: 1, token: "synthetic-next")]
        for next in transitions {
            for unauthorized in [false,true] {
                let t = SearchMapSuspendedTransport(); var context = first; var expirations = 0
                let reader = SearchMapSessionReader(service: try service(t), currentContext: { context }, onUnauthorized: { _ in expirations += 1 })
                let task = Task { try await reader.categories() }
                while !(await t.pending) { await Task.yield() }
                context = next
                await t.finish(unauthorized ? #"{"code":401}"# : #"{"code":200,"data":[]}"#)
                do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
                XCTAssertEqual(expirations, 0)
            }
        }
    }
    @MainActor func testCategoryAggregateRejectsAccountChangeAndCancellationBeforeUnauthorizedExpiry() async throws {
        let first = try SearchMapContext(accountID: 1, epoch: 1, token: "synthetic-first")
        for cancel in [false, true] {
            for unauthorized in [false, true] {
                let transport = SearchMapAggregateSuspendedTransport()
                var context = first; var expirations = 0
                let reader = SearchMapSessionReader(service: try service(transport), currentContext: { context },
                    onUnauthorized: { _ in expirations += 1 })
                let task = Task { try await reader.search(.init(keyword: "sample", categoryID: 7)) }
                while (await transport.pendingCount) < 4 { await Task.yield() }
                if cancel { task.cancel() }
                else { context = try SearchMapContext(accountID: 2, epoch: 1, token: "synthetic-next") }
                await transport.finishAll(unauthorized: unauthorized)
                do { _ = try await task.value; XCTFail("Obsolete category search was accepted") }
                catch { XCTAssertTrue(error is CancellationError) }
                XCTAssertEqual(expirations, 0)
            }
        }
    }
    @MainActor func testCurrentAggregate401ExpiresOnlySignedInContext() async throws {
        let t = SearchMapTestTransport(); await seed(t)
        await t.set("/test/api/merchant/list", #"{"code":401,"data":"bad"}"#)
        let context = try SearchMapContext(accountID: 1, epoch: 1, token: "synthetic")
        var expired: [SearchMapContext] = []
        let reader = SearchMapSessionReader(service: try service(t), currentContext: { context }, onUnauthorized: { expired.append($0) })
        do { _ = try await reader.search(.init(keyword: "x", categoryID: 7)); XCTFail() } catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        XCTAssertEqual(expired, [context])
        let guest = SearchMapSessionReader(service: try service(t), currentContext: { .init(guestEpoch: 1) }, onUnauthorized: { _ in XCTFail() })
        let partial = try await guest.search(.init(keyword: "x")); XCTAssertEqual(partial.gatedKinds, [.club,.merchant])
    }
}
