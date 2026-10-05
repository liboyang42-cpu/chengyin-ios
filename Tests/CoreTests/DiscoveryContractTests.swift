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
        XCTAssertEqual(DiscoveryPlayTemplatePresentation(item).storyText, "Creator")
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
        XCTAssertEqual(item.playersText, "6"); XCTAssertEqual(DiscoveryPlayTemplatePresentation(item).publisher, "42"); XCTAssertNil(DiscoveryPlayTemplatePresentation(item).storyText)
    }
    func testIndependentStoryAndUnknownCodes() throws {
        let item = try decode(DiscoveryPlayTemplate.self, #"{"id":1,"players":"--","duration":0,"storyText":" note ","publisher":"publisher","packType":99,"validationMethod":99}"#)
        XCTAssertEqual(DiscoveryPlayTemplatePresentation(item).storyText, "note")
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
    func testTopicNameSearchTrimsAndUsesCaseInsensitiveNameSubstring() throws {
        let rows = try decode([DiscoveryTopicTemplate].self, #"[{"id":8,"name":"A Neighborhood WALK"},{"id":9,"name":"A route"}]"#)
        let search = DiscoveryTopicTemplateNameSearch(" \tNeIgHbOrHoOd\n ")
        XCTAssertEqual(search.keyword, "NeIgHbOrHoOd"); XCTAssertTrue(search.isActive)
        XCTAssertEqual(search.filter(rows).map(\.id), [8])
    }
    func testTopicNameSearchIgnoresSubtitleAndUnrelatedFields() throws {
        let rows = try decode([DiscoveryTopicTemplate].self, #"[{"id":8,"name":"A route","subtitle":"secret","title":"secret","publisher":"secret"},{"id":9,"name":"Secret passage"},{"id":10,"name":null,"subtitle":"secret"}]"#)
        XCTAssertEqual(DiscoveryTopicTemplateNameSearch("SECRET").filter(rows).map(\.id), [9])
        XCTAssertEqual(DiscoveryTopicTemplateNameSearch(" ").filter(rows), rows)
    }
    func testTopicNameSearchPreservesSourceOrderCategoryPriorityAndPreviewFlags() throws {
        let rows = try decode([DiscoveryTopicTemplate].self, #"[{"id":9,"name":"Night route","categoryIds":"12","previewOnly":true},{"id":7,"name":"Day route","categoryIds":"11","templateStatus":"VERIFIED"},{"id":4,"name":"Unrelated","categoryIds":"11"},{"id":3,"name":"New route","categoryIds":"11,12","previewOnly":true}]"#)
        let filtered = DiscoveryTopicTemplateNameSearch("route").filter(rows)
        XCTAssertEqual(filtered.map(\.id), [9, 7, 3])
        XCTAssertEqual(filtered.filter { $0.matchesCategory(11) }.map(\.id), [7, 3])
        XCTAssertEqual(filtered.filter { !$0.matchesCategory(11) }.map(\.id), [9])
        XCTAssertEqual(filtered[0], rows[0]); XCTAssertTrue(filtered[0].previewOnly)
        XCTAssertEqual(filtered[1], rows[1]); XCTAssertTrue(filtered[1].isVerified)
        XCTAssertEqual(DiscoveryTopicTemplateNameSearch("").filter(rows), rows)
    }
    func testTopicNameSearchIsLiteralWithoutAccentOrWidthFolding() throws {
        let rows = try decode([DiscoveryTopicTemplate].self, #"[{"id":1,"name":"CAFÉ"},{"id":2,"name":"Cafe"},{"id":3,"name":"ＣＡＦＥ"},{"id":4,"name":"城市暗号"}]"#)
        XCTAssertEqual(DiscoveryTopicTemplateNameSearch("cafe").filter(rows).map(\.id), [2])
        XCTAssertEqual(DiscoveryTopicTemplateNameSearch("café").filter(rows).map(\.id), [1])
        XCTAssertTrue(DiscoveryTopicTemplateNameSearch("cafe\u{0301}").filter(rows).isEmpty)
        XCTAssertEqual(DiscoveryTopicTemplateNameSearch("暗号").filter(rows).map(\.id), [4])
    }
    func testTopicNameSearchUsesMiniTrimWhitespaceIncludingBOM() {
        let whitespace: [Unicode.Scalar] = ["\u{0009}", "\u{000A}", "\u{000B}", "\u{000C}", "\u{000D}", "\u{0020}", "\u{00A0}", "\u{1680}", "\u{2000}", "\u{2001}", "\u{2002}", "\u{2003}", "\u{2004}", "\u{2005}", "\u{2006}", "\u{2007}", "\u{2008}", "\u{2009}", "\u{200A}", "\u{2028}", "\u{2029}", "\u{202F}", "\u{205F}", "\u{3000}", "\u{FEFF}"]
        for scalar in whitespace {
            let edge = String(scalar)
            XCTAssertEqual(DiscoveryTopicTemplateNameSearch(edge + "Route" + edge).keyword, "Route")
            XCTAssertFalse(DiscoveryTopicTemplateNameSearch(edge).isActive)
        }
        XCTAssertEqual(DiscoveryTopicTemplateNameSearch("\u{0085}Route\u{0085}").keyword, "\u{0085}Route\u{0085}")
        XCTAssertEqual(DiscoveryTopicTemplateNameSearch("\u{200B}Route\u{200B}").keyword, "\u{200B}Route\u{200B}")
    }
    func testTopicNameSearchProjectsOnlyCurrentRowsAndDoesNotCacheMatches() throws {
        let old = try decode([DiscoveryTopicTemplate].self, #"[{"id":1,"name":"Night route"}]"#)
        let appended = try decode([DiscoveryTopicTemplate].self, #"[{"id":2,"name":"Another route"},{"id":3,"name":"Other"}]"#)
        let search = DiscoveryTopicTemplateNameSearch("route")
        XCTAssertEqual(search.filter(old + appended).map(\.id), [1, 2])
        XCTAssertEqual(search.filter(appended).map(\.id), [2])
        XCTAssertTrue(search.filter([]).isEmpty)
        XCTAssertTrue(DiscoveryTopicTemplateNameSearch("missing").filter(old).isEmpty)
        XCTAssertEqual(DiscoveryTopicTemplateNameSearch("").filter(appended), appended)
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
