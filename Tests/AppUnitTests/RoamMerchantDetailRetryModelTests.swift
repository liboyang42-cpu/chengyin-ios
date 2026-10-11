import XCTest
@testable import Questify

@MainActor private final class MerchantRetryReaderFixture: RoamReading {
    let isConfigured = true
    let identity: RoamReadIdentity? = .init(accountID: 7, epoch: 1)
    let searchArea: RoamSearchArea? = .init(coordinate: .init(latitude: 1, longitude: 1)!, label: "Synthetic area")
    let isOfflineExample = true
    var merchantIDs: [Int] = []
    var nodeCalls = 0
    var requested: (() -> Void)?
    var pending: [CheckedContinuation<RoamMerchantDetail, Error>] = []
    func roamMerchantDetail(id: Int) async throws -> RoamMerchantDetail {
        merchantIDs.append(id)
        return try await withCheckedThrowingContinuation { pending.append($0); requested?() }
    }
    func roamNodeDetail(id: Int) async throws -> RoamNodeDetail { nodeCalls += 1; throw APIError.notConfigured }
    func roamPlaces(radiusM: Int) async throws -> [RoamPlace] { throw APIError.notConfigured }
    func roamRouteNodes(radiusM: Int) async throws -> [RoamRouteNode] { throw APIError.notConfigured }
    func roamEvents(radiusM: Int) async throws -> RoamEvents { throw APIError.notConfigured }
    func roamPlayers(radiusM: Int) async throws -> [RoamPlayer] { throw APIError.notConfigured }
    func roamExploreDay() async throws -> RoamExploreDay? { throw APIError.notConfigured }
}

@MainActor final class RoamMerchantDetailRetryModelTests: XCTestCase {
    private func detail(_ id: Int = 22) throws -> RoamMerchantDetail {
        try JSONDecoder().decode(RoamMerchantDetail.self, from: Data("{\"data\":{\"id\":\(id),\"name\":\"Synthetic merchant\"}}".utf8))
    }
    func testExplicitRetryReadsOnlyTheExactMerchantAndReturnsIt() async throws {
        let reader = MerchantRetryReaderFixture(), model = RoamMerchantDetailRetryModel()
        let requested = expectation(description: "Merchant requested"), done = expectation(description: "Merchant returned")
        reader.requested = { requested.fulfill() }; let expected = try detail()
        XCTAssertTrue(model.retry(merchantID: 22, reader: reader, isCurrent: { true }) { result in
            guard case .success(let value) = result else { XCTFail("Expected success"); done.fulfill(); return }
            XCTAssertEqual(value, expected); done.fulfill()
        })
        XCTAssertTrue(model.isLoading); await fulfillment(of: [requested], timeout: 1)
        XCTAssertEqual(reader.merchantIDs, [22]); XCTAssertEqual(reader.nodeCalls, 0)
        reader.pending[0].resume(returning: expected); await fulfillment(of: [done], timeout: 1)
        XCTAssertFalse(model.isLoading)
    }
    func testRepeatedTapDoesNotCreateAnotherRead() async throws {
        let reader = MerchantRetryReaderFixture(), model = RoamMerchantDetailRetryModel()
        let requested = expectation(description: "Merchant requested"), done = expectation(description: "Merchant returned")
        reader.requested = { requested.fulfill() }
        XCTAssertTrue(model.retry(merchantID: 22, reader: reader, isCurrent: { true }) { _ in done.fulfill() })
        XCTAssertFalse(model.retry(merchantID: 22, reader: reader, isCurrent: { true }) { _ in XCTFail("Duplicate callback") })
        await fulfillment(of: [requested], timeout: 1); XCTAssertEqual(reader.merchantIDs, [22])
        reader.pending[0].resume(returning: try detail()); await fulfillment(of: [done], timeout: 1)
    }
    func testFailureAllowsAnotherExplicitRetryWithoutReadingNode() async throws {
        let reader = MerchantRetryReaderFixture(), model = RoamMerchantDetailRetryModel()
        let request = expectation(description: "First request"), failed = expectation(description: "Failure surfaced")
        reader.requested = { request.fulfill() }
        model.retry(merchantID: 22, reader: reader, isCurrent: { true }) { result in
            guard case .failure(let error) = result else { XCTFail("Expected failure"); failed.fulfill(); return }
            XCTAssertEqual(error as? APIError, .httpStatus(503)); failed.fulfill()
        }
        await fulfillment(of: [request], timeout: 1); reader.pending[0].resume(throwing: APIError.httpStatus(503))
        await fulfillment(of: [failed], timeout: 1); XCTAssertFalse(model.isLoading)
        let retry = expectation(description: "Retry request"), done = expectation(description: "Retry result")
        reader.requested = { retry.fulfill() }
        XCTAssertTrue(model.retry(merchantID: 22, reader: reader, isCurrent: { true }) { _ in done.fulfill() })
        await fulfillment(of: [retry], timeout: 1); reader.pending[1].resume(returning: try detail())
        await fulfillment(of: [done], timeout: 1)
        XCTAssertEqual(reader.merchantIDs, [22, 22]); XCTAssertEqual(reader.nodeCalls, 0)
    }
    func testClosingBeforeQueuedWorkPreventsRequest() async {
        let reader = MerchantRetryReaderFixture(), model = RoamMerchantDetailRetryModel()
        let request = expectation(description: "No request after close"); request.isInverted = true
        reader.requested = { request.fulfill() }
        model.retry(merchantID: 22, reader: reader, isCurrent: { true }) { _ in XCTFail("Closed callback") }
        model.cancel(); await fulfillment(of: [request], timeout: 0.05)
        XCTAssertTrue(reader.merchantIDs.isEmpty); XCTAssertFalse(model.isLoading)
    }
    func testClosingDuringReadDropsLateResult() async throws {
        let reader = MerchantRetryReaderFixture(), model = RoamMerchantDetailRetryModel()
        let request = expectation(description: "Request"), result = expectation(description: "No late result")
        result.isInverted = true; reader.requested = { request.fulfill() }
        model.retry(merchantID: 22, reader: reader, isCurrent: { true }) { _ in result.fulfill() }
        await fulfillment(of: [request], timeout: 1); model.cancel()
        reader.pending[0].resume(returning: try detail()); await fulfillment(of: [result], timeout: 0.05)
        XCTAssertFalse(model.isLoading)
    }
    func testChangedOwnerNodeAreaOrSnapshotDropsResultBeforeViewCallback() async throws {
        let reader = MerchantRetryReaderFixture(), model = RoamMerchantDetailRetryModel()
        var current = true
        let request = expectation(description: "Request"), result = expectation(description: "No stale result")
        result.isInverted = true; reader.requested = { request.fulfill() }
        model.retry(merchantID: 22, reader: reader, isCurrent: { current }) { _ in result.fulfill() }
        await fulfillment(of: [request], timeout: 1); current = false
        reader.pending[0].resume(returning: try detail()); await fulfillment(of: [result], timeout: 0.05)
        XCTAssertFalse(model.isLoading)
    }
    func testWrongMerchantResponseIsFailure() async throws {
        let reader = MerchantRetryReaderFixture(), model = RoamMerchantDetailRetryModel()
        let request = expectation(description: "Request"), done = expectation(description: "Mismatch rejected")
        reader.requested = { request.fulfill() }
        model.retry(merchantID: 22, reader: reader, isCurrent: { true }) { result in
            guard case .failure(let error) = result else { XCTFail("Wrong merchant accepted"); done.fulfill(); return }
            XCTAssertEqual(error as? APIError, .malformedResponse); done.fulfill()
        }
        await fulfillment(of: [request], timeout: 1); reader.pending[0].resume(returning: try detail(23))
        await fulfillment(of: [done], timeout: 1)
    }
    func testOldCompletionCannotClearTheReplacementLoadingState() async throws {
        let reader = MerchantRetryReaderFixture(), model = RoamMerchantDetailRetryModel()
        let first = expectation(description: "First read"), stale = expectation(description: "No old callback")
        stale.isInverted = true; reader.requested = { first.fulfill() }
        model.retry(merchantID: 22, reader: reader, isCurrent: { true }) { _ in stale.fulfill() }
        await fulfillment(of: [first], timeout: 1); model.cancel()
        let second = expectation(description: "Second read"), done = expectation(description: "Second result")
        reader.requested = { second.fulfill() }
        model.retry(merchantID: 23, reader: reader, isCurrent: { true }) { _ in done.fulfill() }
        await fulfillment(of: [second], timeout: 1); reader.pending[0].resume(returning: try detail())
        await fulfillment(of: [stale], timeout: 0.05); XCTAssertTrue(model.isLoading)
        reader.pending[1].resume(returning: try detail(23)); await fulfillment(of: [done], timeout: 1)
        XCTAssertFalse(model.isLoading)
    }
    func testInvalidIDOrStaleSourceNeverQueuesARead() {
        let reader = MerchantRetryReaderFixture(), model = RoamMerchantDetailRetryModel()
        XCTAssertFalse(model.retry(merchantID: 0, reader: reader, isCurrent: { true }) { _ in XCTFail("Invalid read") })
        XCTAssertFalse(model.retry(merchantID: 22, reader: reader, isCurrent: { false }) { _ in XCTFail("Stale read") })
        XCTAssertTrue(reader.merchantIDs.isEmpty); XCTAssertFalse(model.isLoading)
    }
}
