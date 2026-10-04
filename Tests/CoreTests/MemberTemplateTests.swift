import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class MemberTemplateTests: XCTestCase {
    func testMemberIdentityCannotBeMissingOrNonpositive() {
        XCTAssertNil(MemberPlayTemplateID(rawValue: 0)); XCTAssertNil(MemberPlayTemplateID(rawValue: -1))
        XCTAssertEqual(MemberPlayTemplateID(rawValue: 3)?.rawValue, 3)
    }
    func testExactPrivateNamespaceEndpointNotPublicInfo() async throws {
        let transport = MemberTemplateTestTransport(response: Data(#"{"code":"200","data":{"id":17,"title":"Synthetic draft","draftStatus":0,"memberId":9}}"#.utf8))
        let service = PlayerJourneyService(configuration: try APIConfiguration(baseURL: URL(string: "https://member-template.test")!), transport: transport, readsEnabled: true)
        let detail = try await service.memberTemplate(id: XCTUnwrap(MemberPlayTemplateID(rawValue: 17)), token: "synthetic-token")
        XCTAssertEqual(detail.id.rawValue, 17); XCTAssertEqual(detail.memberID, 9); XCTAssertEqual(detail.draftStatus, 0)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1); XCTAssertEqual(requests[0].url?.path, "/api/template/myinfo"); XCTAssertEqual(requests[0].httpMethod, "POST")
        let body = String(decoding: try XCTUnwrap(requests[0].httpBody), as: UTF8.self)
        XCTAssertTrue(body.contains("name=\"id\"\r\n\r\n17\r\n")); XCTAssertFalse(body.contains("name=\"scope\""))
    }
    func testWrongMemberTemplateIDCannotBindToRequestedTemplate() async throws {
        let transport = MemberTemplateTestTransport(response: Data(#"{"code":200,"data":{"id":18}}"#.utf8))
        let service = PlayerJourneyService(configuration: try APIConfiguration(baseURL: URL(string: "https://member-template.test")!), transport: transport, readsEnabled: true)
        do { _ = try await service.memberTemplate(id: XCTUnwrap(MemberPlayTemplateID(rawValue: 17)), token: "synthetic-token"); XCTFail("Wrong identity") }
        catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
    }
    func testBackendUnavailableReasonIsRetainedWithoutPublicFallback() async throws {
        let transport = MemberTemplateTestTransport(response: Data(#"{"code":500,"msg":"模版不存在"}"#.utf8))
        let service = PlayerJourneyService(configuration: try APIConfiguration(baseURL: URL(string: "https://member-template.test")!), transport: transport, readsEnabled: true)
        do { _ = try await service.memberTemplate(id: XCTUnwrap(MemberPlayTemplateID(rawValue: 17)), token: "synthetic-token"); XCTFail("Expected refusal") }
        catch { XCTAssertEqual((error as? PlayerJourneyFailure)?.message, "模版不存在") }
        let count = await transport.requests.count; XCTAssertEqual(count, 1)
    }
    func testDefaultGateNeverDispatchesPrivateRead() async throws {
        let transport = MemberTemplateTestTransport(response: Data())
        let service = PlayerJourneyService(configuration: try APIConfiguration(baseURL: URL(string: "https://member-template.test")!), transport: transport)
        do { _ = try await service.memberTemplate(id: XCTUnwrap(MemberPlayTemplateID(rawValue: 17)), token: "synthetic-token"); XCTFail("Expected disabled") }
        catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        let count = await transport.requests.count; XCTAssertEqual(count, 0)
    }
    private func storyDetail(_ rows: [[String: Any]]) throws -> MemberTemplateDetail {
        // CmsMemberTemplate serializes storyJson as a JSON string, not a nested array.
        let story = String(decoding: try JSONSerialization.data(withJSONObject: rows), as: UTF8.self)
        let data = try JSONSerialization.data(withJSONObject: ["id": 17, "memberId": 9, "storyJson": story])
        return try JSONDecoder().decode(MemberTemplateDetail.self, from: data)
    }
    func testLegacyDTOStoryImageMissingAndNullArrayHydrateWithoutLosingText() throws {
        let detail = try storyDetail([
            ["text": "Legacy story", "tag": "Opening", "img": "https://images.test/old.jpg"],
            ["text": "Null array", "imgs": NSNull(), "img": "https://images.test/null.jpg"]
        ])
        XCTAssertEqual(detail.story.map(\.images), [["https://images.test/old.jpg"], ["https://images.test/null.jpg"]])
        XCTAssertEqual(detail.story.first?.text, "Legacy story"); XCTAssertEqual(detail.story.first?.tag, "Opening")
        XCTAssertEqual(detail.memberID, 9)
    }
    func testCurrentArrayIncludingExplicitEmptyAlwaysWinsOverLegacyImage() throws {
        let detail = try storyDetail([
            ["imgs": [], "img": "https://images.test/must-not-return.jpg"],
            ["imgs": ["https://images.test/new.jpg"], "img": "https://images.test/old.jpg"],
            ["imgs": [], "img": ["not": "a string"]]
        ])
        XCTAssertEqual(detail.story.map(\.images), [[], ["https://images.test/new.jpg"], []])
    }
    func testMalformedNewImageFieldCannotActivateLegacyFallback() throws {
        let detail = try storyDetail([
            ["imgs": "malformed", "img": "https://images.test/old.jpg"],
            ["imgs": false, "img": "https://images.test/old.jpg"],
            ["imgs": ["wrong": "shape"], "img": "https://images.test/old.jpg"],
            ["img": 123], ["img": NSNull()], ["img": ""], [:]
        ])
        XCTAssertTrue(detail.story.allSatisfy { $0.images.isEmpty })
        for story in ["not JSON", "{}", "[1]", "[null]"] {
            let data = try JSONSerialization.data(withJSONObject: ["id": 17, "storyJson": story])
            XCTAssertThrowsError(try JSONDecoder().decode(MemberTemplateDetail.self, from: data))
        }
    }
    func testLegacyProjectionDoesNotApproveMediaOriginsOrUnsafeSchemes() throws {
        for raw in ["javascript:alert(1)", "file:///private/photo.jpg", "http://images.test/a.jpg", "https://other.test/a.jpg"] {
            let detail = try storyDetail([["img": raw]])
            let projected = try XCTUnwrap(detail.story.first?.images.first)
            XCTAssertEqual(projected, raw)
            XCTAssertFalse(RetainedImageOrigin.accepts(try XCTUnwrap(URL(string: projected)), origins: ["https://images.test"]))
        }
        let safe = try storyDetail([["img": "https://images.test/a.jpg"]])
        let url = try XCTUnwrap(URL(string: XCTUnwrap(safe.story.first?.images.first)))
        XCTAssertFalse(RetainedImageOrigin.accepts(url, origins: []))
        XCTAssertTrue(RetainedImageOrigin.accepts(url, origins: ["https://images.test"]))
    }
    func testWhitelistProjectionKeepsStoryAndGalleryWithoutAnswerFields() throws {
        let raw = #"{"id":17,"title":"Synthetic","imgUrl":"https://image.test/a, https://image.test/b","questionAnswer":"private answer","storyJson":"[{\"text\":\"Hello\",\"tag\":\"Opening\",\"imgs\":[]}]"}"#
        let detail = try JSONDecoder().decode(MemberTemplateDetail.self, from: Data(raw.utf8))
        XCTAssertEqual(detail.gallery.count, 2); XCTAssertEqual(detail.story.first?.text, "Hello")
        XCTAssertFalse(Mirror(reflecting: detail).children.contains { $0.label == "questionAnswer" })
    }
}
private actor MemberTemplateTestTransport: HTTPTransport {
    let response: Data
    private(set) var requests: [URLRequest] = []
    init(response: Data) { self.response = response }
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return (response, 200) }
}
