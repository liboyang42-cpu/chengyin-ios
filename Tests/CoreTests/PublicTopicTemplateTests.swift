import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class PublicTemplateTransport: HTTPTransport {
    var response: String
    var status = 200
    var requests: [URLRequest] = []
    init(_ response: String) { self.response = response }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); return (Data(response.utf8), status)
    }
}

final class PublicTopicTemplateTests: XCTestCase {
    private func decode(_ json: String) throws -> PublicTopicTemplateDetail {
        try JSONDecoder().decode(PublicTopicTemplateDetail.self, from: Data(json.utf8))
    }
    func testShelfAndDetailShareUnknownZeroAndInt64TotalSemantics() throws {
        for field in ["", ",\"locationCount\":null"] {
            let bytes = Data("{\"id\":801\(field)}".utf8)
            XCTAssertNil(try JSONDecoder().decode(DiscoveryTopicTemplate.self, from: bytes).locationCount)
            XCTAssertNil(try JSONDecoder().decode(PublicTopicTemplateDetail.self, from: bytes).locationCount)
        }
        for count in [0, 9, 3_000_000_000, Int.max] {
            let bytes = Data("{\"id\":801,\"locationCount\":\(count),\"templateStatus\":\"VERIFIED\",\"chapters\":[{\"id\":1,\"nodes\":[{\"name\":\"Public preview\"}]}]}".utf8)
            let shelf = try JSONDecoder().decode(DiscoveryTopicTemplate.self, from: bytes)
            let detail = try JSONDecoder().decode(PublicTopicTemplateDetail.self, from: bytes)
            XCTAssertEqual(shelf.locationCount, count)
            XCTAssertEqual(detail.locationCount, count)
            XCTAssertEqual(detail.chapters.flatMap(\.nodes).count, 1)
            XCTAssertTrue(shelf.isVerified)
            XCTAssertFalse(detail.viewerIsMerchant)
            XCTAssertFalse(detail.viewerIsPublisher)
        }
    }
    func testShelfAndDetailRejectMalformedTotalsInsteadOfInventingZero() {
        for value in ["-1", "1.5", "\"9\"", "true", "{}", "9223372036854775808"] {
            let bytes = Data("{\"id\":801,\"locationCount\":\(value)}".utf8)
            XCTAssertThrowsError(try JSONDecoder().decode(DiscoveryTopicTemplate.self, from: bytes))
            XCTAssertThrowsError(try JSONDecoder().decode(PublicTopicTemplateDetail.self, from: bytes))
        }
    }
    private func service(_ transport: PublicTemplateTransport) throws -> DiscoveryService {
        try DiscoveryService(configuration: APIConfiguration(baseURL: URL(string: "https://api.example.com/prod-api")!), transport: transport)
    }
    func testRealDecoderPreservesAuthoritativeCountsAndPublicIdentity() throws {
        let detail = try decode(PublicTopicTemplateFixtures.content())
        XCTAssertEqual(detail.id, 801); XCTAssertEqual(detail.chapters.first?.id, 901)
        XCTAssertEqual(detail.games.first?.id, 701)
        XCTAssertEqual(detail.locationCount, 6) // deliberately greater than public preview rows
        XCTAssertEqual(detail.templateCount, 3) // never recompute from public games
        XCTAssertEqual(detail.totalTime, 5400)
        XCTAssertEqual(detail.chapters.first?.nodeCount, 6)
        XCTAssertEqual(detail.chapters.first?.nodes.count, 1)
        XCTAssertEqual(detail.chapters.first?.routeShape.count, 3)
    }
    func testAbsentAndNullAggregatesDoNotInventCounts() throws {
        let detail = try decode(#"{"id":801,"chapters":null,"games":null}"#)
        XCTAssertNil(detail.locationCount); XCTAssertNil(detail.templateCount)
        XCTAssertTrue(detail.chapters.isEmpty); XCTAssertTrue(detail.games.isEmpty)
    }
    func testExplicitZeroCountsStayZeroAndLargeOpaqueIDsStayExact() throws {
        let detail = try decode(#"{"id":9223372036854775806,"locationCount":0,"templateCount":0,"chapters":[{"id":9223372036854775805,"nodeCount":0}],"games":[{"id":9223372036854775804}]}"#)
        XCTAssertEqual(detail.id, 9223372036854775806)
        XCTAssertEqual(detail.chapters.first?.id, 9223372036854775805)
        XCTAssertEqual(detail.games.first?.id, 9223372036854775804)
        XCTAssertEqual(detail.locationCount, 0); XCTAssertEqual(detail.templateCount, 0)
        XCTAssertEqual(detail.chapters.first?.nodeCount, 0)
    }
    func testHiddenFieldsAreIgnoredAndRecruitmentNeedsServerRole() throws {
        let detail = try decode(PublicTopicTemplateFixtures.content().replacingOccurrences(of: "\"hookTeaser\":", with: "\"questionAnswer\":\"SECRET\",\"longitude\":120,\"storyJson\":{\"secret\":1},\"hookTeaser\":"))
        XCTAssertNil(detail.chapters.first?.recruitStatus)
        XCTAssertFalse(String(describing: detail).contains("SECRET"))
        let merchant = try decode(PublicTopicTemplateFixtures.content(merchant: true))
        XCTAssertEqual(merchant.chapters.first?.recruitStatus?.remainingMerchantCount, 2)
        let publisher = try decode(PublicTopicTemplateFixtures.content().replacingOccurrences(of: "\"viewerIsPublisher\":false", with: "\"viewerIsPublisher\":true"))
        XCTAssertNotNil(publisher.chapters.first?.recruitStatus)
    }
    func testRejectsMalformedIdentityCountsAndAbsoluteCoordinates() throws {
        for json in [#"{"id":0}"#, #"{"id":801,"locationCount":-1}"#,
                     #"{"id":801,"chapters":[{"id":1},{"id":1}]}"#,
                     #"{"id":801,"games":[{"id":0}]}"#,
                     #"{"id":801,"chapters":[{"id":1,"routeShape":[{"x":120,"y":30}]}]}"#] {
            XCTAssertThrowsError(try decode(json))
        }
    }
    func testExactReadOnlyFormRequestAndIDReadback() async throws {
        let transport = PublicTemplateTransport("{\"code\":200,\"data\":\(PublicTopicTemplateFixtures.content())}")
        let detail = try await service(transport).publicTopicTemplate(id: 801)
        XCTAssertEqual(detail.id, 801)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/prod-api/api/template/topic-template/info")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        let body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
        XCTAssertTrue(body.contains("name=\"id\"")); XCTAssertTrue(body.contains("801"))
        XCTAssertFalse(body.contains("scope")); XCTAssertFalse(body.contains("memberId"))
        do { _ = try await service(transport).publicTopicTemplate(id: 802); XCTFail("Mismatched source identity accepted") }
        catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
    }
    func testAuthAndBusinessFailurePrecedePayloadDecodeAndInvalidIDDoesNotSend() async throws {
        let transport = PublicTemplateTransport(#"{"code":401,"data":"bad","msg":42}"#)
        do { _ = try await service(transport).publicTopicTemplate(id: 801); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        transport.response = #"{"code":500,"msg":"模板不存在","data":"bad"}"#
        do { _ = try await service(transport).publicTopicTemplate(id: 801); XCTFail() }
        catch { XCTAssertNotNil(error as? DiscoveryTemplateUnavailable) }
        let count = transport.requests.count
        do { _ = try await service(transport).publicTopicTemplate(id: -1); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        XCTAssertEqual(transport.requests.count, count)
    }

    @MainActor func testNewerCompletionWinsAndOldFailureCannotEraseIt() async throws {
        let started = expectation(description: "first request suspended")
        var continuation: CheckedContinuation<PublicTopicTemplateDetail, Error>?
        let fresh = try decode(#"{"id":801,"name":"Fresh"}"#)
        var calls = 0
        var unauthorizedCallbacks = 0
        let coordinator = PublicTopicTemplateCoordinator(id: 801, onUnauthorized: { unauthorizedCallbacks += 1 }) { _ in
            calls += 1
            if calls == 1 {
                return try await withCheckedThrowingContinuation { continuation = $0; started.fulfill() }
            }
            return fresh
        }
        let old = Task { await coordinator.load() }
        await fulfillment(of: [started], timeout: 2)
        await coordinator.load()
        continuation?.resume(throwing: APIError.unauthorized)
        await old.value
        XCTAssertEqual(coordinator.value?.name, "Fresh"); XCTAssertNil(coordinator.error)
        XCTAssertEqual(unauthorizedCallbacks, 0)
        XCTAssertFalse(coordinator.isLoading)
    }
    @MainActor func testRoleLogoutAccountAndRealmTransitionsInvalidateCachedDetail() async throws {
        let owner = PublicTemplateDetailOwner()
        let contexts = [
            PublicTemplateViewerContext(accountID: 1, role: "merchant", realm: "CN", revision: 1),
            PublicTemplateViewerContext(accountID: 1, role: "player", realm: "CN", revision: 1),
            PublicTemplateViewerContext(accountID: 2, role: "player", realm: "CN", revision: 1),
            PublicTemplateViewerContext(accountID: nil, role: nil, realm: "CN", revision: 2),
            PublicTemplateViewerContext(accountID: nil, role: nil, realm: "US", revision: 2),
            PublicTemplateViewerContext(accountID: nil, role: nil, realm: "US", revision: 3)]
        let payload = try decode(PublicTopicTemplateFixtures.content(merchant: true))
        var previous: PublicTopicTemplateCoordinator?
        for context in contexts {
            owner.synchronize(context)
            if let previous { XCTAssertTrue(previous.isInvalidated); XCTAssertNil(previous.value) }
            let next = owner.coordinator(id: 801) { _ in payload }
            await next.load(); XCTAssertNotNil(next.value)
            owner.synchronize(context)
            XCTAssertTrue(next === owner.coordinator(id: 801) { _ in payload })
            previous = next
        }
        owner.invalidate(); XCTAssertNil(previous?.value)
    }
    @MainActor func testLogoutWhileSuspendedRejectsOldSuccessAndNeverReadsAgain() async throws {
        let started = expectation(description: "suspended")
        var continuation: CheckedContinuation<PublicTopicTemplateDetail, Error>?
        let coordinator = PublicTopicTemplateCoordinator(id: 801) { _ in
            try await withCheckedThrowingContinuation { continuation = $0; started.fulfill() }
        }
        let task = Task { await coordinator.load() }
        await fulfillment(of: [started], timeout: 2)
        coordinator.invalidate()
        continuation?.resume(returning: try decode(PublicTopicTemplateFixtures.content(merchant: true)))
        await task.value; await coordinator.load()
        XCTAssertNil(coordinator.value); XCTAssertNil(coordinator.error); XCTAssertFalse(coordinator.isLoading)
    }
    @MainActor func testDismissalClearRejectsLateResponseAndAllowsReopen() async throws {
        let started = expectation(description: "suspended")
        var continuation: CheckedContinuation<PublicTopicTemplateDetail, Error>?
        var first = true
        let payload = try decode(#"{"id":801}"#)
        let coordinator = PublicTopicTemplateCoordinator(id: 801) { _ in
            if first { first = false; return try await withCheckedThrowingContinuation { continuation = $0; started.fulfill() } }
            return payload
        }
        let task = Task { await coordinator.load() }
        await fulfillment(of: [started], timeout: 2)
        coordinator.clear(); continuation?.resume(returning: payload); await task.value
        XCTAssertNil(coordinator.value)
        await coordinator.load(); XCTAssertEqual(coordinator.value?.id, 801)
    }
}
