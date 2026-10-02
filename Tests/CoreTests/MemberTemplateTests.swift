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
