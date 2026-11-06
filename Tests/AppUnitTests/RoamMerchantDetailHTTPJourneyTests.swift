import XCTest
import Combine
@testable import Questify

/// Supplementary merchant retry used by RoamItemDetailView; no device location or writes.
@MainActor final class RoamMerchantDetailHTTPJourneyTests: XCTestCase {
    @MainActor private final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        var status = 200, returnedID = 22
        var beforeReply: (() -> Void)?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            XCTAssertEqual(request.url?.path, "/native/api/merchant/public-detail")
            XCTAssertNil(request.url?.query); XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-roam-token")
            XCTAssertEqual(try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Int], ["id": 22])
            beforeReply?()
            return (Data("{\"code\":\(status),\"data\":{\"id\":\(returnedID),\"name\":\"Synthetic merchant\"}}".utf8), status)
        }
    }
    @MainActor private final class Harness {
        let wire = Wire(), model = RoamMerchantDetailRetryModel()
        var session: RoamReadSession?
        var expired: [RoamReadIdentity] = []
        let service: RoamService
        lazy var reader = RoamSessionReader(service: service, currentSession: { self.session },
            searchArea: { nil }, onUnauthorized: { self.expired.append($0.identity) })
        init() throws {
            session = try .init(accountID: 7, epoch: 1, token: "synthetic-roam-token", manualMapApprovalRevision: UUID())
            service = RoamService(configuration: try .init(baseURL: URL(string: "https://roam.example.test/native/")!), transport: wire)
        }
    }
    private func read(_ h: Harness) async -> Result<RoamMerchantDetail, Error>? {
        let finished = expectation(description: "Retry operation settled")
        let observation = h.model.$isLoading.dropFirst().filter { !$0 }.prefix(1).sink { _ in finished.fulfill() }
        var result: Result<RoamMerchantDetail, Error>?
        XCTAssertTrue(h.model.retry(merchantID: 22, reader: h.reader, isCurrent: { true }) { result = $0 })
        await fulfillment(of: [finished], timeout: 2)
        withExtendedLifetime(observation) {}
        return result
    }
    func testExactMerchantReadWorksWithoutAcquiringLocationOrReloadingNode() async throws {
        let h = try Harness()
        guard let result = await read(h), case .success(let detail) = result else { XCTFail("Expected merchant"); return }
        XCTAssertEqual(detail.merchant.id, 22); XCTAssertEqual(h.wire.requests.count, 1)
        XCTAssertNil(h.reader.searchArea); XCTAssertTrue(h.expired.isEmpty)
    }
    func test503ThenExplicitRetryReturnsOriginalMerchantWithIdenticalBody() async throws {
        let h = try Harness(); h.wire.status = 503
        guard let result = await read(h), case .failure(let error) = result else { XCTFail("Expected failure"); return }
        XCTAssertEqual(error as? APIError, .httpStatus(503)); XCTAssertFalse(h.model.isLoading)
        h.wire.status = 200
        guard let retried = await read(h), case .success(let detail) = retried else { XCTFail("Expected retry success"); return }
        XCTAssertEqual(detail.merchant.id, 22); XCTAssertEqual(h.wire.requests.count, 2)
        XCTAssertEqual(h.wire.requests.first?.httpBody, h.wire.requests.last?.httpBody)
        XCTAssertTrue(h.expired.isEmpty)
    }
    func testWrongReturnedMerchantCannotReplaceSelectedNodeMerchant() async throws {
        let h = try Harness(); h.wire.returnedID = 23
        guard let result = await read(h), case .failure(let error) = result else { XCTFail("Expected identity rejection"); return }
        XCTAssertEqual(error as? APIError, .malformedResponse); XCTAssertEqual(h.wire.requests.count, 1)
    }
    func testCurrent401SurfacesOriginalIdentityButLate401CannotExpireNewAccount() async throws {
        let h = try Harness(); h.wire.status = 401
        let original = try XCTUnwrap(h.session?.identity)
        guard let result = await read(h), case .failure(let error) = result else { XCTFail("Expected unauthorized"); return }
        XCTAssertEqual(error as? APIError, .unauthorized); XCTAssertEqual(h.expired, [original])
        let replacement = try RoamReadSession(accountID: 8, epoch: 2, token: "replacement-token")
        h.wire.beforeReply = { h.session = replacement }
        let late = await read(h)
        XCTAssertNil(late); XCTAssertEqual(h.expired, [original]); XCTAssertEqual(h.reader.identity?.accountID, 8)
        XCTAssertEqual(h.wire.requests.count, 2)
    }
    func testRepeatedTapWhileHTTPBeginsCannotStartSecondRequest() async throws {
        let h = try Harness()
        h.wire.beforeReply = {
            XCTAssertFalse(h.model.retry(merchantID: 22, reader: h.reader, isCurrent: { true }) { _ in XCTFail("Duplicate callback") })
        }
        guard let result = await read(h), case .success = result else { XCTFail("Expected original result"); return }
        XCTAssertEqual(h.wire.requests.count, 1)
    }
}
