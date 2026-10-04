import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class SocialMediaTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var data = Data([137, 80, 78, 71, 13, 10, 26, 10])
    var status = 200
    var operation: (@MainActor () -> Void)?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); await operation?(); return (data, status)
    }
}
@MainActor final class SocialMessageMediaTests: XCTestCase {
    private func message(_ url: String, type: Int = 2) throws -> MessagingMessage {
        let data = try JSONSerialization.data(withJSONObject: ["id": 1, "conversationId": 9, "status":0,"msgType": type, "content": url])
        return try JSONDecoder().decode(MessagingMessage.self, from: data)
    }
    func testSharedAccountMediaFixtureHasExplicitNormalStatusAndValidProjection() throws {
        // The same fixture drives SocialAccountFlowTests' explicit-load/account-switch flow.
        let message = try SocialAccountSyntheticFixtures.imageMessage()
        XCTAssertEqual(message.status, .normal)
        XCTAssertTrue(message.isPayloadVisible)
        let media = try SocialMessageMedia(message: message)
        XCTAssertEqual(media.messageID, 90)
        XCTAssertEqual(media.conversationID, 901)
        XCTAssertEqual(media.url.absoluteString, "https://media.example.test/synthetic.png")
    }
    func testImageContentURLIsUsedWithoutInventingMessageInfoEndpoint() throws {
        let media = try SocialMessageMedia(message: message("https://media.example.com/image.png?signature=synthetic"))
        XCTAssertEqual(media.messageID, 1); XCTAssertEqual(media.conversationID, 9)
        XCTAssertEqual(media.url.query, "signature=synthetic")
        XCTAssertEqual(SocialMessageMediaService.origin(media.url), "https://media.example.com")
    }
    func testMalformedInsecureCredentialsAndPrivateURLsAreRejected() throws {
        for url in ["http://example.com/a.png", "file:///tmp/a.png", "data:image/png,a", "https://user:secret@example.com/a.png", "https://localhost/a", "https://127.0.0.1/a", "https://[::1]/a", "https://host.local/a", "https://example.com/a#fragment", "not a url"] {
            XCTAssertThrowsError(try SocialMessageMedia(message: message(url)), url)
        }
        XCTAssertThrowsError(try SocialMessageMedia(message: message("https://example.com/a.png", type: 1)))
    }
    func testUnapprovedOriginNeverSends() async throws {
        let t = SocialMediaTransport(), service = SocialMessageMediaService(approvedOrigins: [], transport: SocialMediaTransport())
        _ = service
        let reader = SocialMessageMediaService(approvedOrigins: ["https://different.example.com"], transport: t)
        do { _ = try await reader.image(.init(message: message("https://media.example.com/a.png"))); XCTFail() }
        catch { XCTAssertEqual(error as? SocialMediaFailure, .originNotApproved) }
        XCTAssertTrue(t.requests.isEmpty)
    }
    func testApprovedRequestSendsNoAuthCookiesOrUploadBody() async throws {
        let t = SocialMediaTransport(), service: SocialMessageMediaService
        service = .init(approvedOrigins: ["https://media.example.com"], transport: t)
        _ = try await service.image(.init(message: message("https://media.example.com/a.png")))
        let request = try XCTUnwrap(t.requests.first)
        XCTAssertEqual(request.httpMethod, "GET"); XCTAssertNil(request.httpBody)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization")); XCTAssertFalse(request.httpShouldHandleCookies)
    }
    func testNonImageAndOversizeResponsesFailClosed() async throws {
        let t = SocialMediaTransport(), media = try SocialMessageMedia(message: message("https://media.example.com/a.png"))
        let service = SocialMessageMediaService(approvedOrigins: ["https://media.example.com"], transport: t)
        t.data = Data("<script>bad content</script>".utf8)
        do { _ = try await service.image(media); XCTFail() } catch { XCTAssertEqual(error as? SocialMediaFailure, .notImage) }
        t.data = Data(repeating: 0, count: SocialMessageMediaService.maximumBytes + 1)
        do { _ = try await service.image(media); XCTFail() } catch { XCTAssertEqual(error as? SocialMediaFailure, .tooLarge) }
    }
    func testRedirectResponseIsNotTreatedAsAnImage() async throws {
        let t = SocialMediaTransport(); t.status = 302
        let service = SocialMessageMediaService(approvedOrigins: ["https://media.example.com"], transport: t)
        do { _ = try await service.image(.init(message: message("https://media.example.com/a.png"))); XCTFail() }
        catch { XCTAssertEqual(error as? SocialMediaFailure, .unavailable) }
        XCTAssertEqual(t.requests.count, 1)
    }
    func testSameAccountReloginDiscardsCompletedImageBytes() async throws {
        let t = SocialMediaTransport()
        var identity: MessagingReadIdentity? = .init(accountID: 81, epoch: 1)
        let old = try XCTUnwrap(identity)
        t.operation = { identity = .init(accountID: 81, epoch: 2) }
        let reader = SocialMessageMediaReader(service: .init(approvedOrigins: ["https://media.example.com"], transport: t), currentIdentity: { identity })
        do { _ = try await reader.image(.init(message: message("https://media.example.com/a.png")), expectedIdentity: old); XCTFail() }
        catch { XCTAssertTrue(error is CancellationError) }
    }
    func testUnconfiguredAndWrongIdentityDoNotFetch() async throws {
        let current = MessagingReadIdentity(accountID: 81, epoch: 1)
        let reader = SocialMessageMediaReader(service: nil, currentIdentity: { current })
        let media = try SocialMessageMedia(message: message("https://media.example.com/a.png"))
        do { _ = try await reader.image(media, expectedIdentity: current); XCTFail() } catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        do { _ = try await reader.image(media, expectedIdentity: .init(accountID: 82, epoch: 1)); XCTFail() } catch { XCTAssertEqual(error as? APIError, .unauthorized) }
    }
}
