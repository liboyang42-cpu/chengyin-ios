import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class DiscoveryPlayTemplatePresentationTests: XCTestCase {
    private func decode(_ json: String) throws -> DiscoveryPlayTemplate {
        try JSONDecoder().decode(DiscoveryPlayTemplate.self, from: Data(json.utf8))
    }
    func testPublisherStoryAndKnownUseCountStayIndependent() throws {
        let value = DiscoveryPlayTemplatePresentation(try decode(#"{"id":7,"publisher":"  Example author  ","storyText":"  Narrative  ","useNum":12}"#))
        XCTAssertEqual(value.publisher, "Example author")
        XCTAssertEqual(value.storyText, "Narrative")
        XCTAssertEqual(value.useCount, 12)
        XCTAssertTrue(value.hasStory)
    }
    func testPublisherOnlyNeverBecomesStoryAndMissingAuthorNeverBecomesOfficial() throws {
        let publisher = DiscoveryPlayTemplatePresentation(try decode(#"{"id":7,"publisher":"Name"}"#))
        XCTAssertEqual(publisher.publisher, "Name"); XCTAssertNil(publisher.storyText); XCTAssertFalse(publisher.hasStory)
        let story = DiscoveryPlayTemplatePresentation(try decode(#"{"id":7,"storyText":"Story","memberId":91,"collaborators":[{"name":"Someone else"}]}"#))
        XCTAssertNil(story.publisher); XCTAssertEqual(story.storyText, "Story")
        XCTAssertFalse(String(describing: story).contains("Someone else"))
    }
    func testOnlyCurrentDTOCoverThenStoryFormTheBoundedGallery() throws {
        let value = DiscoveryPlayTemplatePresentation(try decode(#"{"id":7,"imgUrl":"https://example.invalid/cover.jpg","storyImg":"https://example.invalid/story.jpg","imgUrls":["https://example.invalid/speculative.jpg"],"storyJson":"private narrative","questionImg":"https://example.invalid/answer.jpg"}"#))
        XCTAssertEqual(value.gallerySources, ["https://example.invalid/cover.jpg", "https://example.invalid/story.jpg"])
        XCTAssertEqual(value.storyImage, "https://example.invalid/story.jpg")
        XCTAssertTrue(value.hasStory); XCTAssertNil(value.storyText)
    }
    func testDuplicateAndWhitespaceImagesKeepFirstPositionWithoutLosingImageOnlyStory() throws {
        let value = DiscoveryPlayTemplatePresentation(try decode(#"{"id":7,"imgUrl":" https://example.invalid/shared.jpg ","storyImg":"https://example.invalid/shared.jpg"}"#))
        XCTAssertEqual(value.gallerySources, ["https://example.invalid/shared.jpg"])
        XCTAssertTrue(value.hasStory)
    }
    func testMissingNullAndBlankContentRemainUnknownWithoutFabricatedZero() throws {
        for json in [#"{"id":7}"#, #"{"id":7,"publisher":null,"storyText":null,"storyImg":null,"imgUrl":null,"useNum":null}"#, #"{"id":7,"publisher":"  ","storyText":" \n ","storyImg":" ","imgUrl":" "}"#] {
            let value = DiscoveryPlayTemplatePresentation(try decode(json))
            XCTAssertNil(value.publisher); XCTAssertNil(value.storyText); XCTAssertNil(value.useCount)
            XCTAssertTrue(value.gallerySources.isEmpty); XCTAssertFalse(value.hasStory)
        }
        XCTAssertEqual(DiscoveryPlayTemplatePresentation(try decode(#"{"id":7,"useNum":0}"#)).useCount, 0)
    }
    func testMalformedImageShapesAndCountsAreNotSilentlyCoerced() {
        for field in [#""imgUrl":[]"#, #""imgUrl":42"#, #""storyImg":{}"#, #""storyImg":true"#, #""storyText":[]"#, #""publisher":{}"#, #""useNum":-1"#, #""useNum":1.5"#, #""useNum":"2""#, #""useNum":false"#] {
            XCTAssertThrowsError(try decode("{\"id\":7,\(field)}"), field)
        }
    }
    func testUnsafeImagesAreOmittedWithoutOriginOrNetworkAuthority() throws {
        for source in ["http://example.invalid/a.jpg", "file:///a.jpg", "data:image/png;base64,abc", "javascript:alert(1)", "//example.invalid/a.jpg", "https://user:secret@example.invalid/a.jpg", "https:///", "https://example.invalid/%ZZ", "https://example.invalid/a\nb.jpg", String(repeating: "a", count: 8193)] {
            let data = try JSONSerialization.data(withJSONObject: ["id":7, "storyImg":source, "storyText":"Still readable"])
            let value = DiscoveryPlayTemplatePresentation(try JSONDecoder().decode(DiscoveryPlayTemplate.self, from: data))
            XCTAssertTrue(value.gallerySources.isEmpty, source); XCTAssertNil(value.storyImage)
            XCTAssertEqual(value.storyText, "Still readable")
        }
        // HTTPS is only screened; the separate image reader still must approve the origin.
        let value = DiscoveryPlayTemplatePresentation(try decode(#"{"id":7,"imgUrl":"https://unapproved.invalid/image"}"#))
        XCTAssertEqual(value.gallerySources.count, 1)
        let encoded = DiscoveryPlayTemplatePresentation(try decode(#"{"id":7,"imgUrl":"https://example.invalid/a%20%E4%B8%AD.jpg"}"#))
        XCTAssertEqual(encoded.gallerySources, ["https://example.invalid/a%20%E4%B8%AD.jpg"])
    }
    func testReadOnlyProjectionNeverImportsSecretsOwnerOrPurchaseAuthority() throws {
        let value = try decode(#"{"id":7,"publisher":"Name","questionAnswer":"SECRET_ANSWER","hint1":"SECRET_HINT","correctAnswer":"SECRET_CHOICE","merchantGuide":"SECRET_GUIDE","storyJson":"SECRET_NODES","isOwner":true,"isPurchased":true,"isUnlocked":true,"memberTemplateId":999}"#)
        for marker in ["SECRET_ANSWER", "SECRET_HINT", "SECRET_CHOICE", "SECRET_GUIDE", "SECRET_NODES"] {
            XCTAssertFalse(String(describing: value).contains(marker))
        }
        XCTAssertNil(DiscoveryPlayTemplatePresentation(value).storyText)
    }
    func testPublicReadRejectsMismatchedAndMalformedIdentityWithoutOwnerNamespace() async throws {
        let transport = PresentationTransport()
        let service = try DiscoveryService(configuration: APIConfiguration(baseURL: URL(string: "https://api.example.invalid/prod-api")!), transport: transport)
        for identity in ["8", "0", "-1", "\"7\"", "null"] {
            transport.response = "{\"code\":200,\"data\":{\"id\":\(identity)}}"
            do { _ = try await service.playTemplate(id: 7); XCTFail(identity) }
            catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        }
        transport.response = #"{"code":200,"data":{"id":7}}"#
        let accepted = try await service.playTemplate(id: 7)
        XCTAssertEqual(accepted.id, 7)
        let request = try XCTUnwrap(transport.requests.last)
        XCTAssertEqual(request.httpMethod, "POST"); XCTAssertEqual(request.url?.path, "/prod-api/api/template/info")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        let body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
        XCTAssertTrue(body.contains("name=\"id\"")); XCTAssertFalse(body.contains("scope")); XCTAssertFalse(body.contains("memberId"))
        let before = transport.requests.count
        do { _ = try await service.playTemplate(id: 0); XCTFail() } catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        XCTAssertEqual(transport.requests.count, before)
    }
}

private final class PresentationTransport: HTTPTransport {
    var response = "{}"
    var requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); return (Data(response.utf8), 200)
    }
}
