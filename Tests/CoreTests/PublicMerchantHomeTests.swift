import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class PublicMerchantFixtureTransport: HTTPTransport {
    var payload: String
    var status = 200
    var requests: [URLRequest] = []
    init(_ payload: String) { self.payload = payload }
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return (Data(payload.utf8), status) }
}
@MainActor final class PublicMerchantHomeTests: XCTestCase {
    private let owner = PublicMerchantOwnerID(41)!
    private let row = PublicMerchantRowID(73)!
    private func config() throws -> APIConfiguration { try .init(baseURL: URL(string: "https://example.com/")!) }
    private var target: PublicMerchantReviewTarget { .init(merchantRowID: row, ownerMemberID: owner) }
    func testIDsRejectInvalidAndRemainDiscriminated() {
        XCTAssertNil(PublicMerchantOwnerID(0)); XCTAssertNil(PublicMerchantRowID(-1))
        XCTAssertEqual(PublicMerchantHomeTarget.ownerMemberID(owner).fields, ["memberId": 41])
        XCTAssertEqual(PublicMerchantHomeTarget.legacyMerchantRowID(row).fields, ["id": 73])
    }
    func testExactAnonymousPostBothIdentityVariants() async throws {
        for (target, fields) in [(PublicMerchantHomeTarget.ownerMemberID(owner), ["memberId": 41]), (.legacyMerchantRowID(row), ["id": 73])] {
            let transport = PublicMerchantFixtureTransport(#"{"code":200,"data":{"name":"Fixture"}}"#)
            let reader = PublicMerchantHomeHTTPReader(configuration: try config(), transport: transport)
            _ = try await reader.home(target)
            let request = try XCTUnwrap(transport.requests.first)
            XCTAssertEqual(request.url?.path, "/api/merchant/public-home"); XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertNil(request.url?.query); XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertFalse(request.httpShouldHandleCookies)
            XCTAssertEqual(try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Int], fields)
        }
    }
    func testMissingReturnedIDsNeverBecomeReviewTarget() async throws {
        let transport = PublicMerchantFixtureTransport(#"{"code":200,"data":{"id":73}}"#)
        let value = try await PublicMerchantHomeHTTPReader(configuration: config(), transport: transport).home(.ownerMemberID(owner))
        XCTAssertNil(value.reviewTarget); XCTAssertNil(value.businessStatus)
    }
    func testUnavailableOnlyExactBusinessMessage() async throws {
        let transport = PublicMerchantFixtureTransport(#"{"code":500,"msg":"商家不存在或未开放"}"#)
        let reader = PublicMerchantHomeHTTPReader(configuration: try config(), transport: transport)
        do { _ = try await reader.home(.ownerMemberID(owner)); XCTFail() } catch { XCTAssertEqual(error as? PublicMerchantHomeFailure, .unavailable) }
        transport.status = 404
        do { _ = try await reader.home(.ownerMemberID(owner)); XCTFail() } catch { XCTAssertEqual(error as? PublicMerchantHomeFailure, .retryable) }
        transport.status = 200; transport.payload = #"{"code":500,"msg":"不存在"}"#
        do { _ = try await reader.home(.ownerMemberID(owner)); XCTFail() } catch { XCTAssertEqual(error as? PublicMerchantHomeFailure, .retryable) }
    }
    func testNullProfileMatchesSourceEmptyObject() async throws {
        let reader = PublicMerchantHomeHTTPReader(configuration: try config(), transport: PublicMerchantFixtureTransport(#"{"code":200,"data":null}"#))
        let value = try await reader.home(.legacyMerchantRowID(row)); XCTAssertNil(value.name); XCTAssertNil(value.reviewTarget)
    }
    func testProfileListsCooperationAndNPCGate() throws {
        let value = try JSONDecoder().decode(PublicMerchantHome.self, from: Data(#"{"id":73,"memberId":41,"gallery":" a ; ; b ","tags":"tag;","capacity":8,"npc":{"name":"Guide"}}"#.utf8))
        XCTAssertEqual(value.galleryItems, ["a", "b"]); XCTAssertEqual(value.tagItems, ["tag"])
        XCTAssertTrue(value.hasCooperation); XCTAssertTrue(value.hasNPCIdentity)
        XCTAssertFalse(value.canOfferNPCChat(shopNpcChat: false)); XCTAssertTrue(value.canOfferNPCChat(shopNpcChat: true))
        XCTAssertEqual(value.reviewTarget, target)
    }
    func testDisabledReaderCannotRead() async {
        do { _ = try await DisabledPublicMerchantHomeReader().home(.ownerMemberID(owner)); XCTFail() }
        catch { XCTAssertEqual(error as? PublicMerchantHomeFailure, .notConfigured) }
    }
    func testPublicReviewExactQueryNoBodyAndStrictMode() async throws {
        let transport = PublicMerchantFixtureTransport(Self.emptyPage)
        let reader = PublicMerchantReviewHTTPReader(configuration: try config(), transport: transport)
        let value = try await reader.page(target, page: 1); XCTAssertTrue(value.items.isEmpty)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "POST"); XCTAssertEqual(request.url?.path, "/api/merchant/reviews/public")
        XCTAssertNil(request.httpBody); XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: query.map { ($0.name, $0.value!) }), ["merchantRowId": "73", "pageNum": "1", "pageSize": "20"])
        transport.payload = Self.emptyPage.replacingOccurrences(of: "public", with: "manage")
        do { _ = try await reader.page(target, page: 1); XCTFail() } catch { XCTAssertEqual(error as? PublicMerchantHomeFailure, .retryable) }
    }
    func testReviewInvalidPageMakesNoRequest() async throws {
        let transport = PublicMerchantFixtureTransport(Self.emptyPage)
        do { _ = try await PublicMerchantReviewHTTPReader(configuration: config(), transport: transport).page(target, page: 0); XCTFail() } catch {}
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testReviewRejectsBadTotalsAndEligibility() async throws {
        for payload in [Self.emptyPage.replacingOccurrences(of: "\"total\":0", with: "\"total\":1"), Self.emptyPage.replacingOccurrences(of: "LOGIN_REQUIRED", with: "ELIGIBLE")] {
            do { _ = try await PublicMerchantReviewHTTPReader(configuration: config(), transport: PublicMerchantFixtureTransport(payload)).page(target, page: 1); XCTFail() } catch {}
        }
    }
    static let emptyPage = #"{"code":200,"data":{"mode":"public","pageNum":1,"pageSize":20,"total":0,"hasMore":false,"averageRating":null,"eligibility":{"canCreate":false,"reasonCode":"LOGIN_REQUIRED","registrationId":null},"items":[]}}"#
}

@MainActor final class PublicMerchantReviewHTTPWriteTests: XCTestCase {
    private let target = PublicMerchantReviewTarget(merchantRowID: PublicMerchantRowID(73)!, ownerMemberID: PublicMerchantOwnerID(41)!)
    func testInjectedCreateSendsOnlyExactSourceJSONAndRawAuthorization() async throws {
        let configuration = try APIConfiguration(baseURL: URL(string: "https://example.com/")!)
        let session = try PublicMerchantReviewSession(accountID: 8, scope: UUID(), realm: configuration.baseURL.absoluteString, token: "fixture-token")
        let transport = PublicMerchantFixtureTransport(#"{"code":200,"data":{"reviewId":9,"status":"PENDING_REVIEW","version":0,"replayed":false,"auditTaskId":2}}"#)
        let writer = PublicMerchantReviewHTTPWriter(configuration: configuration, transport: transport, currentSession: { session })
        let receipt = try await writer.execute(.create(registrationID: 19, rating: 5, content: " Fixture text "), target: target, requestID: "stable-fixture", session: session)
        XCTAssertEqual(receipt.status, "PENDING_REVIEW")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/api/merchant/reviews/create"); XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "fixture-token")
        XCTAssertNil(request.url?.query)
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        XCTAssertEqual(body["requestId"] as? String, "stable-fixture"); XCTAssertEqual(body["content"] as? String, "Fixture text")
        XCTAssertNil(body["memberId"]); XCTAssertNil(body["merchantMemberId"])
    }
    func testMalformedOrMismatchedWriteReceiptIsUnknown() async throws {
        let configuration = try APIConfiguration(baseURL: URL(string: "https://example.com/")!)
        let session = try PublicMerchantReviewSession(accountID: 8, scope: UUID(), realm: configuration.baseURL.absoluteString, token: "fixture-token")
        let transport = PublicMerchantFixtureTransport(#"{"code":200,"data":{"reviewId":99,"status":"PENDING_PLATFORM_REVIEW","replayed":false,"auditTaskId":2}}"#)
        let writer = PublicMerchantReviewHTTPWriter(configuration: configuration, transport: transport, currentSession: { session })
        do { _ = try await writer.execute(.report(reviewID: 9, expectedVersion: 1, reason: "Fixture reason"), target: target, requestID: "stable-fixture", session: session); XCTFail() }
        catch { XCTAssertEqual(error as? PublicMerchantReviewWriteFailure, .unknown) }
        XCTAssertEqual(transport.requests.first?.url?.path, "/api/merchant/reviews/report")
    }
    func testRealmMismatchNeverTransmitsSessionToken() async throws {
        let configuration = try APIConfiguration(baseURL: URL(string: "https://example.com/")!)
        let session = try PublicMerchantReviewSession(accountID: 8, scope: UUID(), realm: "other", token: "fixture-token")
        let transport = PublicMerchantFixtureTransport("{}")
        let writer = PublicMerchantReviewHTTPWriter(configuration: configuration, transport: transport, currentSession: { session })
        do { _ = try await writer.execute(.report(reviewID: 9, expectedVersion: 1, reason: "Fixture reason"), target: target, requestID: "stable-fixture", session: session); XCTFail() } catch {}
        XCTAssertTrue(transport.requests.isEmpty)
    }
}
