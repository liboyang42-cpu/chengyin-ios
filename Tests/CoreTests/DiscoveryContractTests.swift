import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class DiscoveryFixtureTransport: HTTPTransport {
    var response: String
    var status: Int
    private(set) var requests: [URLRequest] = []
    init(_ response: String = #"{"code":200,"data":[]}"#, status: Int = 200) {
        self.response = response; self.status = status
    }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        return (Data(response.utf8), status)
    }
}

final class DiscoveryContractTests: XCTestCase {
    private func service(_ transport: DiscoveryFixtureTransport) throws -> DiscoveryService {
        try DiscoveryService(configuration: APIConfiguration(baseURL: URL(string: "https://api.example.com/prod-api")!), transport: transport)
    }
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }
    private func body(_ transport: DiscoveryFixtureTransport) throws -> String {
        let request = try XCTUnwrap(transport.requests.last)
        return try XCTUnwrap(String(data: XCTUnwrap(request.httpBody), encoding: .utf8))
    }

    func testHomeBannersUseExactMultipartFieldsAndAllowAnonymousRead() async throws {
        let transport = DiscoveryFixtureTransport()
        let items = try await service(transport).banners()
        XCTAssertTrue(items.isEmpty)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/prod-api/api/common/banner")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        let content = try body(transport)
        XCTAssertTrue(content.contains("name=\"showType\"\r\n\r\n1\r\n"))
        XCTAssertTrue(content.contains("name=\"linkType\"\r\n\r\n0\r\n"))
    }
    func testRootCategoriesAlwaysSendParentZeroAndRawToken() async throws {
        let transport = DiscoveryFixtureTransport()
        _ = try await service(transport).categories(type: 4, token: "fixture-token")
        XCTAssertEqual(transport.requests.first?.url?.path, "/prod-api/api/category/list")
        XCTAssertEqual(transport.requests.first?.value(forHTTPHeaderField: "Authorization"), "fixture-token")
        let content = try body(transport)
        XCTAssertTrue(content.contains("name=\"parentid\"\r\n\r\n0\r\n"))
        XCTAssertTrue(content.contains("name=\"type\"\r\n\r\n4\r\n"))
    }
    func testAllPacksOmitsFilterAndCategoryInsteadOfSendingSingleNodeDefault() async throws {
        let transport = DiscoveryFixtureTransport()
        _ = try await service(transport).playTemplates(keyword: "   ")
        let content = try body(transport)
        XCTAssertFalse(content.contains("pack_type"))
        XCTAssertFalse(content.contains("categoryId"))
        XCTAssertFalse(content.contains("category_id"))
        XCTAssertFalse(content.contains("keyword"))
    }
    func testPlayListUsesSnakeCasePackTypeAndKeepsSearchValue() async throws {
        let transport = DiscoveryFixtureTransport(#"{"code":200,"data":{"rows":[{"id":3,"title":" Search "}]}}"#)
        let items = try await service(transport).playTemplates(keyword: "一段 & two", packType: .story)
        XCTAssertEqual(items.map(\.title), ["Search"])
        XCTAssertEqual(transport.requests.first?.url?.path, "/prod-api/api/template/list")
        let content = try body(transport)
        XCTAssertTrue(content.contains("name=\"pack_type\"\r\n\r\n1\r\n"))
        XCTAssertTrue(content.contains("一段 & two"))
    }
    func testHomeAndTopicShelfUseEmptyJSONNotMultipartAndNoPaging() async throws {
        let transport = DiscoveryFixtureTransport(#"{"code":200,"data":{}}"#)
        _ = try await service(transport).templateHome(token: "fixture-token")
        XCTAssertEqual(transport.requests.first?.url?.path, "/prod-api/api/template/homeData")
        XCTAssertEqual(transport.requests.first?.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(try body(transport), "{}")
        transport.response = #"{"code":200,"data":[]}"#
        _ = try await service(transport).topicTemplates()
        XCTAssertEqual(transport.requests.last?.url?.path, "/prod-api/api/template/topic-template/list")
        XCTAssertEqual(transport.requests.last?.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(try body(transport), "{}")
    }
    func testPlayDetailUsesIDAndPreservesRichPublicSections() async throws {
        let transport = DiscoveryFixtureTransport(#"{"code":200,"data":{"id":8,"title":"Walk","description":"Intro","ruleInstructions":"Rules","requiredMaterials":"Paper","usageLocation":"Park","storyText":"Creator","storyImg":"https://example.com/story.png","validationMethod":4,"questionName":"Prompt"}}"#)
        let item = try await service(transport).playTemplate(id: 8)
        XCTAssertEqual(transport.requests.first?.url?.path, "/prod-api/api/template/info")
        XCTAssertTrue(try body(transport).contains("name=\"id\"\r\n\r\n8\r\n"))
        XCTAssertEqual(item.description, "Intro")
        XCTAssertEqual(item.ruleInstructions, "Rules")
        XCTAssertEqual(item.requiredMaterials, "Paper")
        XCTAssertEqual(item.usageLocation, "Park")
        XCTAssertEqual(item.creatorNote, "Creator")
        XCTAssertEqual(item.verification, .shopQR)
        XCTAssertEqual(item.questionName, "Prompt")
    }
    func testInvalidIDAndHeaderInjectionNeverReachTransport() async throws {
        let transport = DiscoveryFixtureTransport()
        do { _ = try await service(transport).playTemplate(id: 0); XCTFail("Expected rejection") }
        catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        do { _ = try await service(transport).banners(token: "bad\r\nHeader: injected"); XCTFail("Expected rejection") }
        catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testGatewayUnauthorizedPrecedesMalformedJSON() async throws {
        let transport = DiscoveryFixtureTransport("<html>login</html>", status: 401)
        do { _ = try await service(transport).playTemplate(id: 1); XCTFail("Expected auth error") }
        catch { XCTAssertEqual(error as? APIError, .unauthorized) }
    }
    func testEnvelopeUnauthorizedPrecedesMalformedDataAndMessage() async throws {
        let transport = DiscoveryFixtureTransport(#"{"code":401,"msg":{"reason":"login"},"data":"not-a-template"}"#)
        do { _ = try await service(transport).playTemplate(id: 1); XCTFail("Expected auth error") }
        catch { XCTAssertEqual(error as? APIError, .unauthorized) }
    }
    func testHTTPFailureIsNotAnEmptyShelf() async throws {
        let transport = DiscoveryFixtureTransport(#"{"code":200,"data":[]}"#, status: 503)
        do { _ = try await service(transport).topicTemplates(); XCTFail("Expected HTTP error") }
        catch { XCTAssertEqual(error as? APIError, .httpStatus(503)) }
    }
    func testBusinessFailureIsNotAnEmptyHome() async throws {
        let transport = DiscoveryFixtureTransport(#"{"code":500,"msg":"failed","data":{}}"#)
        do { _ = try await service(transport).templateHome(); XCTFail("Expected business error") }
        catch { XCTAssertEqual(error as? APIError, .businessCode(500)) }
    }
    func testTemplateRefusalsRetainReasonAndRetrySemantics() async throws {
        let cases: [(String, DiscoveryTemplateUnavailable, Bool)] = [
            ("模板不存在", .notFound, false), ("模板已删除", .deleted, false),
            ("模板审核中", .underReview, true), ("模板已下架", .offline, false),
            ("暂时不可用", .unknown, true)
        ]
        for (message, reason, retryable) in cases {
            let transport = DiscoveryFixtureTransport("{\"code\":500,\"msg\":\"\(message)\"}")
            do { _ = try await service(transport).playTemplate(id: 1); XCTFail("Expected refusal") }
            catch { XCTAssertEqual(error as? DiscoveryTemplateUnavailable, reason) }
            XCTAssertEqual(reason.retryable, retryable)
        }
    }
    func testMissingNullableListsAreEmptyButMalformedShapesFail() async throws {
        for json in [#"{"code":200}"#, #"{"code":200,"data":null}"#, #"{"code":200,"data":{"rows":null}}"#] {
            let items = try await service(DiscoveryFixtureTransport(json)).playTemplates()
            XCTAssertTrue(items.isEmpty)
        }
        for json in [#"{"code":200,"data":42}"#, #"{"code":200,"data":{"rows":false}}"#, #"{"code":200,"data":[{"id":0}]}"#, #"{"code":200,"data":[false]}"#, #"{"data":[]}"#] {
            do { _ = try await service(DiscoveryFixtureTransport(json)).playTemplates(); XCTFail("Malformed success must fail: \(json)") }
            catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        }
    }
    func testNullBannerAndCategoryDataAreEmptyButWrongTypeFails() async throws {
        let transport = DiscoveryFixtureTransport(#"{"code":200,"data":null}"#)
        let banners = try await service(transport).banners()
        let categories = try await service(transport).categories()
        XCTAssertTrue(banners.isEmpty); XCTAssertTrue(categories.isEmpty)
        transport.response = #"{"code":200,"data":{"rows":[]}}"#
        do { _ = try await service(transport).banners(); XCTFail("Banner contract requires array") }
        catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
    }
    func testHomeKeepsFiveIndependentSectionsAndCategoryNames() throws {
        let value = try decode(DiscoveryTemplateHome.self, #"{"total":9,"categoryList":[{"id":2,"categoryName":"City","name":"fallback","type":4}],"bannerList":[{"id":1}],"latestList":[{"id":2}],"recommendList":[{"id":3}],"mustPlayList":[{"id":4}],"hotList":[{"id":1},{"id":5}]}"#)
        XCTAssertEqual(value.total, 9)
        XCTAssertEqual(value.categories.first?.name, "City")
        XCTAssertEqual(value.banner.map(\.id), [1])
        XCTAssertEqual(value.latest.map(\.id), [2])
        XCTAssertEqual(value.recommended.map(\.id), [3])
        XCTAssertEqual(value.mustPlay.map(\.id), [4])
        XCTAssertEqual(value.hot.map(\.id), [1, 5])
        XCTAssertFalse(value.isEmpty)
    }
    func testMissingHomeTotalRemainsUnknownAndNullableSectionsAreEmpty() throws {
        let value = try decode(DiscoveryTemplateHome.self, #"{"categoryList":null,"hotList":null}"#)
        XCTAssertNil(value.total); XCTAssertTrue(value.isEmpty); XCTAssertTrue(value.categories.isEmpty)
    }
    func testNullablePlayMetadataDoesNotBecomeZeroDurationOrNoVerification() throws {
        let item = try decode(DiscoveryPlayTemplate.self, #"{"id":1,"title":"  ","duration":null,"players":null,"validationMethod":null,"packType":null}"#)
        XCTAssertEqual(item.title, "")
        XCTAssertNil(item.durationMinutes); XCTAssertNil(item.playersText); XCTAssertNil(item.verification)
        XCTAssertEqual(item.pack, .single)
    }
    func testNumericPlayersAndPublisherArePreserved() throws {
        let item = try decode(DiscoveryPlayTemplate.self, #"{"id":1,"players":6,"publisher":42,"storyText":"  "}"#)
        XCTAssertEqual(item.playersText, "6"); XCTAssertEqual(item.creatorNote, "42")
    }
    func testCreatorFallbackAndUnknownCodes() throws {
        let item = try decode(DiscoveryPlayTemplate.self, #"{"id":1,"players":"--","duration":0,"storyText":" note ","publisher":"publisher","packType":99,"validationMethod":99}"#)
        XCTAssertEqual(item.creatorNote, "note")
        XCTAssertNil(item.playersText); XCTAssertNil(item.durationMinutes); XCTAssertNil(item.pack)
        XCTAssertEqual(item.verification, .other)
    }
    func testVerificationCodesMatchSharedFlutterTable() {
        let expected: [DiscoveryVerification] = [.none, .text, .photo, .choice, .shopQR, .gps, .preferences, .sensor]
        for (code, value) in expected.enumerated() { XCTAssertEqual(DiscoveryVerification(code: code), value) }
    }
    func testTopicTemplateRemainsSeparateAndUnknownStatusIsExperimental() throws {
        let item = try decode(DiscoveryTopicTemplate.self, #"{"id":8,"name":"Route","chapterCount":3,"locationCount":9,"categoryIds":"1, 10, 3","totalTime":90,"previewOnly":true}"#)
        XCTAssertEqual(item.name, "Route"); XCTAssertEqual(item.chapterCount, 3); XCTAssertEqual(item.locationCount, 9)
        XCTAssertEqual(item.totalTime, 90); XCTAssertTrue(item.previewOnly); XCTAssertFalse(item.isVerified)
        XCTAssertTrue(item.matchesCategory(nil)); XCTAssertTrue(item.matchesCategory(10)); XCTAssertFalse(item.matchesCategory(0))
        XCTAssertFalse(item.matchesCategory(2))
    }
    func testPublicTopicDurationPreservesIntegralSecondsAndExplicitZero() throws {
        for seconds in [0, 1, 59, 60, 90, 5400, Int.max] {
            let item = try decode(DiscoveryTopicTemplate.self, "{\"id\":1,\"totalTime\":\(seconds)}")
            XCTAssertEqual(item.totalTime, seconds)
        }
    }
    func testPublicTopicMissingDurationRemainsUnknown() throws {
        for json in [#"{"id":1,"templateStatus":"VERIFIED"}"#, #"{"id":1,"totalTime":null,"templateStatus":"VERIFIED"}"#] {
            let item = try decode(DiscoveryTopicTemplate.self, json)
            XCTAssertNil(item.totalTime); XCTAssertTrue(item.isVerified)
        }
    }
    func testPublicTopicMalformedDurationNeverBecomesMinutesOrUnknown() {
        for value in ["-1", "0.5", "true", "{}", "[]", "9223372036854775808", "\"30\"", "\"30分钟\"", "\"30 minutes\"", "\"\""] {
            XCTAssertThrowsError(try decode(DiscoveryTopicTemplate.self, "{\"id\":1,\"totalTime\":\(value)}"))
        }
    }
    func testBannerDestinationsAreTypedAndNeverOpenArbitraryH5() throws {
        let activity = try decode(DiscoveryBanner.self, #"{"id":1,"linkType":3,"dataId":"12"}"#)
        let topic = try decode(DiscoveryBanner.self, #"{"id":1,"linkType":4,"dataId":"13"}"#)
        XCTAssertEqual(activity.destination, .activity(12)); XCTAssertEqual(topic.destination, .topic(13))
        for json in [#"{"id":1,"linkType":2,"dataId":"https://example.com"}"#, #"{"id":1,"linkType":3,"dataId":"0"}"#, #"{"id":1,"linkType":4,"dataId":null}"#, #"{"id":1,"linkType":1,"contents":"html"}"#] {
            XCTAssertNil(try decode(DiscoveryBanner.self, json).destination)
        }
    }
    func testInvalidIDsAndNonscalarMetadataAreRejected() {
        XCTAssertThrowsError(try decode(DiscoveryPlayTemplate.self, #"{"id":-1}"#))
        XCTAssertThrowsError(try decode(DiscoveryPlayTemplate.self, #"{"id":1,"players":{}}"#))
        XCTAssertThrowsError(try decode(DiscoveryTopicTemplate.self, #"{"id":1,"totalTime":[]}"#))
        XCTAssertThrowsError(try decode(DiscoveryCategory.self, #"{"id":0,"name":"bad"}"#))
    }
}
