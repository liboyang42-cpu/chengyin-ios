import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let rewardID = String(repeating: "a", count: 64)
private let rewardID2 = String(repeating: "b", count: 64)
private func rewardWire(_ overrides: [String: Any] = [:]) -> [String: Any] {
    var row: [String: Any] = ["awardId": rewardID, "contextType": "MAP", "contextId": "map & 1", "releaseId": "release",
        "instanceId": "season", "rulesVersion": "v1", "merchantId": "12", "storeId": "34", "rewardKind": "PHYSICAL",
        "rewardTitle": " Item ", "redemptionConditions": "Store only", "state": "AWARDED", "quantity": 1,
        "validFrom": 100_000, "validUntil": 200_000, "awardedAt": 100_000, "asOf": 150_000,
        "validityStatus": "IN_WINDOW", "fulfillmentStatus": "UNVERIFIED"]
    for (key, value) in overrides { row[key] = value }
    return row
}
private func rewardEnvelope(_ data: Any, code: Int = 200) throws -> Data {
    try JSONSerialization.data(withJSONObject: ["code": code, "msg": "ignored", "data": data])
}
private func rewardPageData(_ rows: [[String: Any]] = [rewardWire()], next: String? = nil, asOf: Int64 = 150_000) throws -> Data {
    try rewardEnvelope(["items": rows, "nextCursor": next as Any? ?? NSNull(), "asOf": asOf])
}
// Captured from backend MVC responses; fixture source SHA256 6a65210fb9a53b35d1df3c5395745f643968351a7fb04a8edd6f248cc18e8caa.
private let mvcRewardList = #"{"msg":"操作成功","code":200,"data":{"items":[{"awardId":"4c4d99d1d59013513ef9efd07ed1a537700d17430428bae07267f4c992976974","contextType":"MAP","contextId":"board","releaseId":"release","instanceId":"season","rulesVersion":"rules","merchantId":"7","storeId":"8","rewardKind":"PHYSICAL","rewardTitle":"Promised coffee","redemptionConditions":"Original store 8 conditions","state":"AWARDED","quantity":1,"validFrom":100,"validUntil":1000,"awardedAt":300,"asOf":300,"validityStatus":"IN_WINDOW","fulfillmentStatus":"UNVERIFIED"}],"nextCursor":null,"asOf":300}}"#
private let mvcRewardDetail = #"{"msg":"操作成功","code":200,"data":{"awardId":"4c4d99d1d59013513ef9efd07ed1a537700d17430428bae07267f4c992976974","contextType":"MAP","contextId":"board","releaseId":"release","instanceId":"season","rulesVersion":"rules","merchantId":"7","storeId":"8","rewardKind":"PHYSICAL","rewardTitle":"Promised coffee","redemptionConditions":"Original store 8 conditions","state":"AWARDED","quantity":1,"validFrom":100,"validUntil":1000,"awardedAt":300,"asOf":300,"validityStatus":"IN_WINDOW","fulfillmentStatus":"UNVERIFIED"}}"#
private let mvcRewardNotFound = #"{"msg":"未找到该奖励","code":404,"errorCode":"NOT_FOUND"}"#
private actor RewardWireTransport: HTTPTransport {
    var replies: [(Data, Int)]
    var requests: [URLRequest] = []
    init(_ replies: [(Data, Int)]) { self.replies = replies }
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return replies.removeFirst() }
}
private actor SuspendedRewardWire: HTTPTransport {
    var requests: [URLRequest] = []
    var continuations: [CheckedContinuation<(Data, Int), Error>] = []
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        return try await withCheckedThrowingContinuation { continuations.append($0) }
    }
    func waitForRequest() async { while requests.isEmpty { await Task.yield() } }
    func finish(_ data: Data, status: Int) { continuations.removeFirst().resume(returning: (data, status)) }
}
private func rewardService(_ transport: any HTTPTransport) throws -> NonCashRewardService {
    NonCashRewardService(configuration: try APIConfiguration(baseURL: URL(string: "https://example.test/native")!), transport: transport)
}

final class NonCashRewardServiceTests: XCTestCase {
    private func rejects(_ operation: () async throws -> Void, _ expected: APIError = .malformedResponse) async {
        do { try await operation(); XCTFail("Expected rejection") } catch { XCTAssertEqual(error as? APIError, expected) }
    }
    func testCapturedBackendMVCResponsesDecodeWithoutInventedFields() async throws {
        let wire = RewardWireTransport([(Data(mvcRewardList.utf8), 200), (Data(mvcRewardDetail.utf8), 200), (Data(mvcRewardNotFound.utf8), 404)])
        let service = try rewardService(wire), page = try await service.rewards(limit: 20, cursor: nil, token: "synthetic")
        XCTAssertEqual(page.items.count, 1); XCTAssertNil(page.nextCursor)
        let detail = try await service.reward(NonCashRewardReference(page.items[0]), token: "synthetic")
        XCTAssertEqual(detail, page.items[0]); XCTAssertEqual(detail.awardedAt.timeIntervalSince1970, 0.3, accuracy: 0.000001)
        do { _ = try await service.reward(NonCashRewardReference(detail), token: "synthetic"); XCTFail() }
        catch { XCTAssertEqual(error as? AccountCollectionReadFailure, .unavailable) }
    }
    func testExactReadRoutesProjectionAndNoOwnerParameter() async throws {
        let wire = RewardWireTransport([(try rewardPageData(), 200), (try rewardEnvelope(rewardWire(["state": "REDEEMED"])), 200)])
        let service = try rewardService(wire)
        let page = try await service.rewards(limit: 20, cursor: nil, token: "synthetic")
        let row = try XCTUnwrap(page.items.first)
        XCTAssertEqual(row.rewardTitle, " Item "); XCTAssertEqual(row.validUntil.timeIntervalSince1970, 200)
        XCTAssertEqual(row.fulfillmentStatus, .unverified)
        let fresh = try await service.reward(NonCashRewardReference(row), token: "synthetic")
        XCTAssertEqual(fresh.state, .redeemed)
        let requests = await wire.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].url?.path, "/native/api/rewards/noncash")
        XCTAssertEqual(requests[1].url?.path, "/native/api/rewards/noncash/" + rewardID)
        XCTAssertEqual(requests[0].httpMethod, "GET"); XCTAssertNil(requests[0].httpBody)
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Cache-Control"), "no-store")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "synthetic")
        let query = try XCTUnwrap(URLComponents(url: requests[1].url!, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(Set(query.map(\.name)), Set(["contextType", "contextId", "releaseId", "instanceId"]))
        XCTAssertEqual(query.first(where: { $0.name == "contextId" })?.value, "map & 1")
    }
    func testInvalidArgumentsNeverDispatch() async throws {
        let wire = RewardWireTransport([]), service = try rewardService(wire)
        for limit in [0, 51] { await rejects({ _ = try await service.rewards(limit: limit, cursor: nil, token: "x") }, .invalidRequest) }
        await rejects({ _ = try await service.rewards(limit: 20, cursor: "../foreign", token: "x") }, .invalidRequest)
        await rejects({ _ = try await service.rewards(limit: 20, cursor: nil, token: "\n") }, .invalidRequest)
        let requests = await wire.requests; XCTAssertTrue(requests.isEmpty)
    }
    func testMalformedAndUnsupportedProjectionFailsClosed() async throws {
        let cases: [[String: Any]] = [["rewardKind": "CASH"], ["quantity": 2], ["quantity": 1.5], ["state": "PENDING"],
            ["merchantId": "0012"], ["storeId": "9223372036854775808"], ["merchantId": 12], ["instanceId": ""],
            ["validUntil": 100_000], ["validFrom": -1], ["asOf": 150_000.5], ["asOf": Int64.max],
            ["validityStatus": "ELAPSED"], ["fulfillmentStatus": "AVAILABLE"], ["contextType": "CITY"],
            ["redemptionConditions": String(repeating: "😀", count: 257)], ["awardId": rewardID.uppercased()]]
        for fields in cases {
            let wire = RewardWireTransport([(try rewardPageData([rewardWire(fields)]), 200)])
            await rejects { _ = try await rewardService(wire).rewards(limit: 20, cursor: nil, token: "x") }
        }
    }
    func testDuplicatePageStaleTimestampAndLoopCursorAreRejected() async throws {
        let payloads = [try rewardPageData([rewardWire(), rewardWire()]),
                        try rewardPageData(asOf: 151_000), try rewardPageData(next: rewardID)]
        for data in payloads {
            let wire = RewardWireTransport([(data, 200)])
            await rejects { _ = try await rewardService(wire).rewards(limit: 20, cursor: nil, token: "x") }
        }
        let wire = RewardWireTransport([(try rewardPageData(next: rewardID), 200)])
        await rejects { _ = try await rewardService(wire).rewards(limit: 1, cursor: rewardID, token: "x") }
    }
    func testDetailScopeAndFrozenTermsCannotSilentlyChange() async throws {
        for fields in [["instanceId": "other"], ["merchantId": "99"], ["redemptionConditions": "changed"], ["storeId": "99"]] {
            let wire = RewardWireTransport([(try rewardPageData(), 200), (try rewardEnvelope(rewardWire(fields)), 200)])
            let service = try rewardService(wire), page = try await service.rewards(limit: 20, cursor: nil, token: "x")
            await rejects { _ = try await service.reward(NonCashRewardReference(page.items[0]), token: "x") }
        }
    }
    func testOlderDetailAndTerminalStateResurrectionAreRejected() async throws {
        let variants: [(String, [String: Any])] = [("AWARDED", ["asOf": 149_000]), ("REDEEMED", ["state": "AWARDED"]),
            ("EXPIRED", ["state": "REVERSED"]), ("REVERSED", ["state": "REDEEMED"])]
        for (initial, changes) in variants {
            let wire = RewardWireTransport([(try rewardPageData([rewardWire(["state": initial])]), 200),
                                            (try rewardEnvelope(rewardWire(changes)), 200)])
            let service = try rewardService(wire), page = try await service.rewards(limit: 20, cursor: nil, token: "x")
            await rejects { _ = try await service.reward(NonCashRewardReference(page.items[0]), token: "x") }
        }
    }
    func testElapsedWindowDoesNotRewriteAwardedStateOrEnableFulfillment() async throws {
        let wire = RewardWireTransport([(try rewardPageData([rewardWire(["asOf": 200_000, "validityStatus": "ELAPSED"])], asOf: 200_000), 200)])
        let page = try await rewardService(wire).rewards(limit: 20, cursor: nil, token: "x")
        XCTAssertEqual(page.items[0].state, .awarded); XCTAssertEqual(page.items[0].validityStatus, .elapsed)
        XCTAssertEqual(page.items[0].fulfillmentStatus, .unverified)
    }
    func testHTTPAndEnvelopeErrorsDoNotLeakServerMessage() async throws {
        for status in [400, 401, 503] {
            let wire = RewardWireTransport([(Data("not json".utf8), status)])
            await rejects({ _ = try await rewardService(wire).rewards(limit: 20, cursor: nil, token: "x") }, status == 401 ? .unauthorized : .httpStatus(status))
        }
        let wire = RewardWireTransport([(try rewardPageData(), 404)])
        do { _ = try await rewardService(wire).rewards(limit: 20, cursor: nil, token: "x"); XCTFail() }
        catch { XCTAssertEqual(error as? AccountCollectionReadFailure, .unavailable) }
        let envelope = RewardWireTransport([(try rewardEnvelope(NSNull(), code: 401), 200)])
        await rejects({ _ = try await rewardService(envelope).rewards(limit: 20, cursor: nil, token: "x") }, .unauthorized)
    }
}

@MainActor final class NonCashRewardSessionReaderTests: XCTestCase {
    func testDisabledReaderNeverDispatches() async throws {
        let session = try NonCashRewardReadSession(accountID: 7, epoch: 1, token: "x")
        let reader = NonCashRewardSessionReader(service: nil, currentSession: { session })
        XCTAssertTrue(reader.isAuthenticated); XCTAssertFalse(reader.isConfigured)
        do { _ = try await reader.rewards(cursor: nil); XCTFail() } catch { XCTAssertEqual(error as? APIError, .notConfigured) }
    }
    func testLateUnauthorizedFromOldEpochCannotExpireCurrentAccount() async throws {
        let wire = SuspendedRewardWire()
        var session: NonCashRewardReadSession? = try .init(accountID: 7, epoch: 1, token: "old")
        var unauthorized = 0
        let reader = NonCashRewardSessionReader(service: try rewardService(wire), currentSession: { session }, onUnauthorized: { _ in unauthorized += 1 })
        let oldScope = reader.scope
        let task = Task { try await reader.rewards(cursor: nil) }
        await wire.waitForRequest()
        session = try .init(accountID: 7, epoch: 2, token: "new")
        XCTAssertNotEqual(reader.scope, oldScope)
        await wire.finish(Data(), status: 401)
        do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(unauthorized, 0)
    }
    func testLateSuccessAfterLogoutIsDiscarded() async throws {
        let wire = SuspendedRewardWire()
        var session: NonCashRewardReadSession? = try .init(accountID: 7, epoch: 1, token: "x")
        let reader = NonCashRewardSessionReader(service: try rewardService(wire), currentSession: { session })
        let task = Task { try await reader.rewards(cursor: nil) }
        await wire.waitForRequest(); session = nil
        await wire.finish(try rewardPageData(), status: 200)
        do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(reader.isAuthenticated)
    }
}
