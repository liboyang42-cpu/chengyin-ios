import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private func browserProject(_ raw: String) throws -> MerchantProject { try JSONDecoder().decode(MerchantProject.self, from: Data(raw.utf8)) }
private func browserPage(_ rows: [[String: Any]], total: Int? = nil) throws -> MerchantProjectPage {
    var body: [String: Any] = ["rows": rows]; if let total { body["total"] = total }
    return try JSONDecoder().decode(MerchantProjectPage.self, from: JSONSerialization.data(withJSONObject: body))
}
private let browserRows: [[String: Any]] = [
    ["id": 10, "bizType": "topic", "state": "running"],
    ["id": 9, "bizType": "activity", "state": "rejected"],
    ["id": 8, "bizType": "topic", "state": "pending"],
    ["id": 7, "bizType": "topic", "state": "draft"],
    ["id": 6, "bizType": "topic", "state": "rejected"],
    ["id": 5, "bizType": "topic", "state": "rejected"],
    ["id": 4, "bizType": "topic", "state": "future"],
    ["id": 3, "bizType": "topic"],
    ["id": 2, "bizType": "future-kind", "state": "running"]
]
final class MerchantProjectBrowserTests: XCTestCase {
    func testKindsAreDerivedLocallyAndUnknownRowsRemainDiscoverable() throws {
        let page = try browserPage(browserRows), browser = MerchantProjectBrowser(page: page, tab: .topic)
        XCTAssertEqual(browser.tabs, [.topic, .activity, .other]); XCTAssertEqual(browser.count(.topic), 7)
        XCTAssertEqual(browser.count(.activity), 1); XCTAssertEqual(browser.count(.other), 1)
        XCTAssertEqual(MerchantProjectBrowser(page: page, tab: .other).rows.map(\.projectID), [2])
    }
    func testOnlyTwoSourceTabsExistWithoutAnUnknownKind() throws {
        let page = try browserPage(Array(browserRows.dropLast()))
        XCTAssertEqual(MerchantProjectBrowser(page: page, tab: .topic).tabs, [.topic, .activity])
        XCTAssertEqual(MerchantProjectBrowserTab.allCases.count, 3) // No template or guessed state filter.
    }
    func testPendingPriorityKeepsSourceOrderWithinEveryRank() throws {
        let page = try browserPage(browserRows)
        XCTAssertEqual(MerchantProjectBrowser(page: page, tab: .topic).rows.map(\.projectID), [6, 5, 7, 8, 10, 4, 3])
        XCTAssertEqual(page.rows.map(\.projectID), [10, 9, 8, 7, 6, 5, 4, 3, 2])
    }
    func testMissingAndUnknownStateDoNotGetInventedAttention() throws {
        for raw in [#"{"id":1,"bizType":"topic"}"#, #"{"id":1,"bizType":"topic","state":"future","stateText":"Rejected"}"#] {
            let project = try browserProject(raw); XCTAssertEqual(MerchantProjectBrowser.rank(project), 9)
            XCTAssertFalse(MerchantProjectCardFacts(project).attention)
        }
    }
    func testAttentionOnlyUsesTheThreeSourceRawStates() throws {
        for (index, state) in ["rejected", "draft", "pending"].enumerated() {
            let project = try browserProject("{\"id\":1,\"bizType\":\"topic\",\"state\":\"" + state + "\"}")
            XCTAssertEqual(MerchantProjectBrowser.rank(project), index); XCTAssertTrue(MerchantProjectCardFacts(project).attention)
        }
    }
    func testCountsAreLoadedOnlyAndCapWarningIsStillAvailable() throws {
        let page = try browserPage(browserRows, total: 500), browser = MerchantProjectBrowser(page: page, tab: .topic)
        XCTAssertEqual(browser.count(.topic), 7); XCTAssertTrue(browser.page.hasUnloadedRows); XCTAssertEqual(browser.page.total, 500)
    }
    func testEmptyTypeRecoveryIsDistinctFromEmptyPage() throws {
        let activities = try browserPage([["id": 1, "bizType": "activity"]])
        let browser = MerchantProjectBrowser(page: activities, tab: .topic)
        XCTAssertTrue(browser.rows.isEmpty); XCTAssertFalse(browser.page.rows.isEmpty); XCTAssertEqual(browser.alternatives, [.activity])
        let empty = MerchantProjectBrowser(page: try browserPage([]), tab: .topic)
        XCTAssertTrue(empty.alternatives.isEmpty); XCTAssertEqual(empty.tabs, [.topic, .activity])
    }
    func testActivityAndThemeWithSameNumericIDStaySeparate() throws {
        let page = try browserPage([["id": 1, "bizType": "topic"], ["id": 1, "bizType": "activity"]])
        XCTAssertEqual(MerchantProjectBrowser(page: page, tab: .topic).rows.first?.id, "topic:1")
        XCTAssertEqual(MerchantProjectBrowser(page: page, tab: .activity).rows.first?.id, "activity:1")
    }
    func testFulfillerRoleAndPendingCountComeFromExactSourceFields() throws {
        let project = try browserProject(#"{"id":1,"bizType":"activity","ownerType":"merchant","pendingVerifyCount":2,"addressName":" West lane "}"#)
        let facts = MerchantProjectCardFacts(project)
        XCTAssertEqual(facts.role, .fulfiller); XCTAssertEqual(facts.pendingVerifications, 2); XCTAssertEqual(facts.address, "West lane")
    }
    func testMissingCountIsUnknownWhileZeroIsARealValue() throws {
        let absent = try browserProject(#"{"id":1,"bizType":"activity","ownerType":"merchant"}"#)
        let zero = try browserProject(#"{"id":1,"bizType":"activity","ownerType":"merchant","pendingVerifyCount":0}"#)
        XCTAssertNil(MerchantProjectCardFacts(absent).pendingVerifications); XCTAssertEqual(MerchantProjectCardFacts(zero).pendingVerifications, 0)
    }
    func testHostDoesNotExposeMisplacedPendingCountOrInferRoleFromAcceptance() throws {
        let host = try browserProject(#"{"id":1,"bizType":"topic","ownerType":"member","pendingVerifyCount":9,"acceptStatusText":"Accepted"}"#)
        XCTAssertEqual(MerchantProjectCardFacts(host).role, .host); XCTAssertNil(MerchantProjectCardFacts(host).pendingVerifications)
        let unknown = try browserProject(#"{"id":1,"bizType":"activity","pendingVerifyCount":9,"acceptStatusText":"merchantAccepted"}"#)
        XCTAssertNil(MerchantProjectCardFacts(unknown).role); XCTAssertNil(MerchantProjectCardFacts(unknown).pendingVerifications)
    }
    func testUnknownOwnerOrKindDoesNotManufactureHostRole() throws {
        for raw in [#"{"id":1,"bizType":"topic","ownerType":"merchant"}"#, #"{"id":1,"bizType":"activity","ownerType":"future"}"#,
                    #"{"id":1,"bizType":"future-kind","ownerType":"member"}"#] { XCTAssertNil(MerchantProjectCardFacts(try browserProject(raw)).role) }
    }
    func testOptionalCardFieldsAcceptMissingNullButRejectWrongTypes() throws {
        XCTAssertNil(try browserProject(#"{"id":1,"bizType":"topic","state":null,"ownerType":null,"addressName":null,"pendingVerifyCount":null}"#).pendingVerifyCount)
        for raw in [#"{"id":1,"bizType":"topic","state":3}"#, #"{"id":1,"bizType":"topic","ownerType":true}"#,
                    #"{"id":1,"bizType":"topic","addressName":4}"#, #"{"id":1,"bizType":"activity","pendingVerifyCount":true}"#,
                    #"{"id":1,"bizType":"activity","pendingVerifyCount":"2"}"#, #"{"id":1,"bizType":"activity","pendingVerifyCount":-1}"#,
                    #"{"id":1,"bizType":"activity","pendingVerifyCount":1.5}"#] { XCTAssertThrowsError(try browserProject(raw)) }
    }
    func testEmptyAddressDoesNotBecomeAPlaceholderFact() throws {
        let value = try browserProject(#"{"id":1,"bizType":"topic","ownerType":"club","addressName":"   "}"#)
        XCTAssertEqual(MerchantProjectCardFacts(value).role, .host); XCTAssertNil(MerchantProjectCardFacts(value).address)
    }
    func testTabSelectionDoesNotMutateOriginalPageOrCounts() throws {
        let page = try browserPage(browserRows, total: 500)
        for tab in MerchantProjectBrowserTab.allCases {
            let browser = MerchantProjectBrowser(page: page, tab: tab)
            _ = browser.rows; _ = browser.alternatives; XCTAssertEqual(browser.page, page)
        }
    }
}
private final class BrowserTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var data = Data(#"{"code":200,"data":{"rows":[{"id":1,"bizType":"topic","state":"draft","ownerType":"member"},{"id":2,"bizType":"activity","ownerType":"merchant","pendingVerifyCount":0}],"total":2}}"#.utf8)
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return (data, 200) }
}
final class MerchantProjectBrowserServiceTests: XCTestCase {
    private func access(_ permission: String = "merchant:project:manage") throws -> MerchantAccess {
        try JSONDecoder().decode(MerchantAccess.self, from: Data(("{\"active\":true,\"merchant\":{\"id\":31},\"roleCode\":\"MERCHANT_OWNER\",\"permissions\":[\"" + permission + "\"]}").utf8))
    }
    func testExistingProjectRequestScopeAndCapAreUnchanged() async throws {
        let transport = BrowserTransport(); let service = MerchantService(configuration: try .init(baseURL: URL(string: "https://example.test")!), transport: transport)
        let page = try await service.projects(access: access(), token: "fixture-token")
        XCTAssertEqual(transport.requests.count, 1); let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/api/project/my"); XCTAssertEqual(request.httpMethod, "POST")
        let body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
        for (key, value) in ["scope": "MERCHANT", "type": "all", "state": "all", "ownerType": "all", "pageNum": "1", "pageSize": "200"] {
            XCTAssertTrue(body.contains("name=\"" + key + "\"\r\n\r\n" + value + "\r\n"))
        }
        for tab in MerchantProjectBrowserTab.allCases { _ = MerchantProjectBrowser(page: page, tab: tab).rows }
        XCTAssertEqual(transport.requests.count, 1)
    }
    func testMissingProjectGrantStopsBeforeRead() async throws {
        let transport = BrowserTransport(); let service = MerchantService(configuration: try .init(baseURL: URL(string: "https://example.test")!), transport: transport)
        do { _ = try await service.projects(access: access("merchant:basic:read"), token: "fixture-token"); XCTFail() }
        catch { XCTAssertEqual(error as? MerchantReadError, .accessDenied) }
        XCTAssertTrue(transport.requests.isEmpty)
    }
}
