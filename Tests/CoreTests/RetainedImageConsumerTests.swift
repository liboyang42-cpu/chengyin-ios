import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
private final class RetainedImageFakeTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var response = Data(#"{"code":200,"url":"https://media.example.com/approved.jpg"}"#.utf8)
    var status = 200
    var after: (() -> Void)?
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); after?(); return (response, status) }
}
@MainActor final class RetainedImageConsumerTests: XCTestCase {
    private let realm = "https://api.example.com"
    private let target = PublicMerchantReviewTarget(merchantRowID: PublicMerchantRowID(73)!, ownerMemberID: PublicMerchantOwnerID(41)!)
    private func scope(epoch: UUID = UUID(), field: MerchantImageField? = nil) throws -> RetainedImageScope {
        try .init(accountID: 8, epoch: epoch, realm: realm, destination: field.map { .merchant(merchantRowID: 73, field: $0) } ?? .publicReview(merchantRowID: 73, registrationID: 19), namespace: "test-deployment")
    }
    private func selection() throws -> RetainedSelectedImage { try .init(jpeg: Data([255,216,255,0]), width: 1, height: 1) }
    private func client(_ scope: RetainedImageScope, _ transport: RetainedImageFakeTransport, enabled: Bool = true) throws -> RetainedImageHTTPUploader {
        try .init(configuration: .init(baseURL: URL(string: realm)!), transport: transport, enabled: enabled,
                  approvedOrigins: ["https://media.example.com"], currentScope: { scope }, token: { "fixture-token" })
    }
    func testDefaultDisabledDoesNotDispatch() async throws {
        let s = try scope(), t = RetainedImageFakeTransport(), c = try client(s, t, enabled: false)
        do { _ = try await c.upload(.init(scope: s, selection: selection())); XCTFail() } catch { XCTAssertEqual(error as? RetainedImageFailure, .disabled) }
        XCTAssertTrue(t.requests.isEmpty)
    }
    func testScopedUploadExactMultipartAndTopLevelURL() async throws {
        let s = try scope(), t = RetainedImageFakeTransport(), c = try client(s, t)
        let review = try RetainedImageUploadReview(scope: s, selection: selection())
        let image = try await c.upload(review)
        XCTAssertEqual(image.scope, s); XCTAssertEqual(image.id, review.selection.id)
        let request = try XCTUnwrap(t.requests.first)
        XCTAssertEqual(request.url?.path, "/api/common/uploadOSS"); XCTAssertFalse(request.httpShouldHandleCookies)
        let body = String(decoding: request.httpBody!, as: UTF8.self)
        XCTAssertTrue(body.contains("name=\"file\"")); XCTAssertTrue(body.contains("image/jpeg"))
        XCTAssertFalse(body.contains("registrationId")); XCTAssertFalse(body.contains("community"))
    }
    func testMissingURLAndUnapprovedOriginFailClosed() async throws {
        for raw in [#"{"code":200,"data":{"url":"https://media.example.com/a.jpg"}}"#,
                    #"{"code":200,"url":"https://evil.example.com/a.jpg"}"#] {
            let s = try scope(), t = RetainedImageFakeTransport(); t.response = Data(raw.utf8)
            do { _ = try await client(s,t).upload(.init(scope: s, selection: selection())); XCTFail() } catch { XCTAssertEqual(error as? RetainedImageFailure, .unknown) }
        }
    }
    func testBusinessRejectionPreservesMessage() async throws {
        let s = try scope(), t = RetainedImageFakeTransport(); t.response = Data(#"{"code":409,"msg":"审核未通过"}"#.utf8)
        do { _ = try await client(s,t).upload(.init(scope: s, selection: selection())); XCTFail() }
        catch { XCTAssertEqual(error as? RetainedImageFailure, .rejected(409, "审核未通过")) }
    }
    func testSessionChangedAfterDispatchHasNoProof() async throws {
        let s = try scope(), t = RetainedImageFakeTransport(); var current: RetainedImageScope? = s
        let c = try RetainedImageHTTPUploader(configuration: .init(baseURL: URL(string: realm)!), transport: t, enabled: true,
            approvedOrigins: ["https://media.example.com"], currentScope: { current }, token: { "fixture-token" })
        t.after = { current = nil }
        do { _ = try await c.upload(.init(scope: s, selection: selection())); XCTFail() } catch { XCTAssertEqual(error as? RetainedImageFailure, .unknown) }
    }
    func testReviewImagesCarryRegistrationAndAccountEpoch() async throws {
        let s = try scope(), t = RetainedImageFakeTransport()
        let image = try await client(s,t).upload(.init(scope: s, selection: selection()))
        let session = try PublicMerchantReviewSession(accountID: 8, scope: s.epoch, realm: realm, token: "fixture-token")
        let command = PublicMerchantReviewCommand.create(registrationID: 19, rating: 5, content: "Good place", images: [image])
        XCTAssertNoThrow(try command.validateImages(target: target, session: session))
        let body = try command.body(target: target, requestID: "request-1")
        XCTAssertEqual(body["imageUrls"] as? [String], [image.url.absoluteString])
        let stale = try PublicMerchantReviewSession(accountID: 8, scope: UUID(), realm: realm, token: "fixture-token")
        XCTAssertThrowsError(try command.validateImages(target: target, session: stale))
        XCTAssertThrowsError(try PublicMerchantReviewCommand.create(registrationID: 20, rating: 5, content: "Good place", images: [image]).body(target: target, requestID: "request-1"))
        XCTAssertThrowsError(try PublicMerchantReviewCommand.create(registrationID: 19, rating: 5, content: "Good place", images: [image,image]).body(target: target, requestID: "request-1"))
    }
    func testMerchantFieldCannotCrossIntoAnotherDomain() async throws {
        let s = try scope(field: .avatar), t = RetainedImageFakeTransport()
        let image = try await client(s,t).upload(.init(scope: s, selection: selection()))
        let session = try PublicMerchantReviewSession(accountID: 8, scope: s.epoch, realm: realm, token: "fixture-token")
        XCTAssertThrowsError(try image.validateReview(target: target, registrationID: 19, session: session))
        let updated = try image.applying(to: .character(.init()), expectedScope: s)
        guard case .character(let character) = updated else { return XCTFail() }
        XCTAssertEqual(character.avatar, image.url.absoluteString)
        XCTAssertThrowsError(try image.applying(to: .character(.init()), expectedScope: scope(field: .logo)))
    }
    func testUnknownRemainsLockedOnDismissAndReprepare() async throws {
        let s = try scope(), t = RetainedImageFakeTransport(); t.response = Data("broken".utf8)
        let owner = RetainedImageUploadCoordinator(uploader: try client(s,t), journal: ImageJournalTestStorage().journal())
        owner.prepare(try selection(), scope: s)
        guard case .reviewing(let review) = owner.state else { return XCTFail() }
        await owner.confirm(review); XCTAssertTrue(owner.locked)
        owner.clear(); owner.prepare(try selection(), scope: s)
        XCTAssertEqual(owner.state, .unknown); XCTAssertEqual(t.requests.count, 1)
    }
    func testChangedReviewCannotBeConfirmed() async throws {
        let s = try scope(), t = RetainedImageFakeTransport(), owner = RetainedImageUploadCoordinator(uploader: try client(s,t), journal: ImageJournalTestStorage().journal())
        owner.prepare(try selection(), scope: s)
        guard case .reviewing(let review) = owner.state else { return XCTFail() }
        owner.clear(); await owner.confirm(review); XCTAssertTrue(t.requests.isEmpty)
    }
    func testBoundsAndURLPolicy() throws {
        XCTAssertThrowsError(try RetainedSelectedImage(jpeg: Data(), width: 1, height: 1))
        XCTAssertThrowsError(try RetainedSelectedImage(jpeg: Data([255,216,255]), width: 4097, height: 1))
        for raw in ["http://media.example.com/a", "https://user@media.example.com/a", "https://media.example.com/a#x", "https://media.example.com:444/a"] {
            XCTAssertFalse(RetainedImageOrigin.accepts(URL(string: raw)!, origins: ["https://media.example.com"]))
        }
    }
}
