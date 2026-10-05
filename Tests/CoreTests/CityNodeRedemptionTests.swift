import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private actor CityNodeRedemptionTransport: MerchantBusinessTestTransport {
    var response = #"{"code":200,"msg":"已发放测试券"}"#
    var access = #"{"code":200,"data":{"active":true,"merchant":{"id":19},"roleCode":"MERCHANT_CHECKIN","permissions":["merchant:verify"]}}"#
    var throwAfterSend = false
    var suspendMutation = false
    var continuation: CheckedContinuation<(Data, Int), Error>?
    var pending: Bool { continuation != nil }
    private(set) var requests: [URLRequest] = []
    func setResponse(_ response: String) { self.response = response }
    func setAccess(_ access: String) { self.access = access }
    func fail() { throwAfterSend = true }
    func suspend() { suspendMutation = true }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        if request.url!.path.hasSuffix("access/me") { return (Data(access.utf8), 200) }
        if throwAfterSend { throw URLError(.timedOut) }
        if suspendMutation { return try await withCheckedThrowingContinuation { continuation = $0 } }
        return (Data(response.utf8), 200)
    }
    func finish() { continuation?.resume(returning: (Data(response.utf8), 200)); continuation = nil }
}
final class CityNodeRedemptionTests: XCTestCase {
    private func service(_ t: CityNodeRedemptionTransport, enabled: Bool = true) throws -> MerchantBusinessService {
        .init(configuration: try .init(baseURL: URL(string: "https://example.com/test/")!), readTransport: t, testingMutationTransport: enabled ? t : nil)
    }
    private func body(_ json: String) throws -> MerchantBusinessObject {
        try XCTUnwrap(JSONDecoder().decode(MerchantBusinessValue.self, from: Data(json.utf8)).object)
    }
    func testExactMultipartEndpointOneCodeFieldNoInventedIds() throws {
        let t = CityNodeRedemptionTransport()
        let code = try CityNodeRedemptionCode("  opaque & + 城\n")
        let request = try service(t).makeRequest(code.request, token: "synthetic")
        XCTAssertEqual(request.url?.path, "/test/api/verify/citynode/redeem")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic")
        XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")!.hasPrefix("multipart/form-data; boundary="))
        XCTAssertEqual(code.request.body, .form(["code": "opaque & + 城"]))
        let payload = String(decoding: request.httpBody!, as: UTF8.self)
        XCTAssertTrue(payload.contains("name=\"code\"\r\n\r\nopaque & + 城\r\n"))
        for absent in ["poiId", "merchantId", "memberId", "requestId", "lat", "lng"] { XCTAssertFalse(payload.contains("name=\"\(absent)\"")) }
    }
    func testSuccessAndRejectionMessagesRemainByteExact() throws {
        for code in [200, 400, 403, 500] {
            let message = "  玩家未到店打卡,或该券已核销\n库存耗尽，补货后可重扫  "
            let data = try JSONSerialization.data(withJSONObject: ["code": code, "msg": message])
            let result = try CityNodeRedemptionResult(body: XCTUnwrap(JSONDecoder().decode(MerchantBusinessValue.self, from: data).object))
            XCTAssertEqual(result.message, message); XCTAssertEqual(result.redeemed, code == 200)
        }
        XCTAssertEqual(try CityNodeRedemptionResult(body: body(#"{"code":200}"#)).message, "核销成功")
        XCTAssertEqual(try CityNodeRedemptionResult(body: body(#"{"code":500}"#)).message, "核销失败")
        XCTAssertThrowsError(try CityNodeRedemptionResult(body: body(#"{"code":200,"msg":42}"#)))
        XCTAssertThrowsError(try CityNodeRedemptionResult(body: body(#"{"msg":"not a result"}"#)))
    }
    func testCodeIsOpaqueButEmptyOrOversizedRejected() throws {
        XCTAssertThrowsError(try CityNodeRedemptionCode(" \n "))
        XCTAssertThrowsError(try CityNodeRedemptionCode(String(repeating: "a", count: 16_385)))
        // This value stays in the code field. It is never parsed/opened as a navigation URL.
        XCTAssertEqual(try CityNodeRedemptionCode("https://example.com/code").request.body, .form(["code": "https://example.com/code"]))
    }
    @MainActor func testDefaultDisabledStopsBeforeSessionPermissionOrTransport() async throws {
        let t = CityNodeRedemptionTransport(); var sessionCalls = 0
        let c = CityNodeRedemptionCoordinator(service: try service(t, enabled: false), journal: MerchantBusinessMemoryIntentStore(), currentSession: { sessionCalls += 1; return nil })
        XCTAssertFalse(c.isAvailable)
        await c.prepare("synthetic")
        XCTAssertEqual(c.failure, "merchant.cityRedeem.disabled"); XCTAssertNil(c.review)
        XCTAssertEqual(sessionCalls, 0)
        let requests = await t.requests; XCTAssertTrue(requests.isEmpty)
    }
    @MainActor func testReviewCancellationHasNoMutationAndConfirmationRechecksAccess() async throws {
        let t = CityNodeRedemptionTransport(), journal = MerchantBusinessMemoryIntentStore()
        let session = try MerchantBusinessSession(accountID: 8, epoch: 1, token: "synthetic")
        let c = CityNodeRedemptionCoordinator(service: try service(t), journal: journal, currentSession: { session })
        await c.prepare("synthetic-code")
        let cancelled = try XCTUnwrap(c.review).id
        c.cancelReview(); await c.confirm(cancelled)
        var requests = await t.requests; XCTAssertEqual(requests.count, 1)
        await c.prepare("synthetic-code")
        let id = try XCTUnwrap(c.review).id
        await c.confirm(id); await c.confirm(id)
        requests = await t.requests
        XCTAssertEqual(requests.filter { $0.url!.path.hasSuffix("access/me") }.count, 3)
        XCTAssertEqual(requests.filter { $0.url!.path.hasSuffix("citynode/redeem") }.count, 1)
        XCTAssertEqual(c.result?.message, "已发放测试券"); XCTAssertTrue(try journal.intents().isEmpty)
    }
    @MainActor func testKnownBusinessRejectionShowsExactMessageAndNextCanStartFresh() async throws {
        let t = CityNodeRedemptionTransport(), journal = MerchantBusinessMemoryIntentStore()
        await t.setResponse(#"{"code":400,"msg":"玩家未到店打卡,或该券已核销"}"#)
        let session = try MerchantBusinessSession(accountID: 8, epoch: 1, token: "synthetic")
        let c = CityNodeRedemptionCoordinator(service: try service(t), journal: journal, currentSession: { session })
        await c.prepare("synthetic-code"); await c.confirm(try XCTUnwrap(c.review).id)
        XCTAssertEqual(c.result?.redeemed, false); XCTAssertEqual(c.result?.message, "玩家未到店打卡,或该券已核销")
        XCTAssertNil(c.failure); XCTAssertTrue(try journal.intents().isEmpty)
        c.next(); XCTAssertNil(c.result)
        await c.prepare("next-synthetic-code"); XCTAssertNotNil(c.review)
    }
    @MainActor func testPermissionRevocationOrMerchantChangeBeforeConfirmationNeverDispatches() async throws {
        for changed in [#"{"code":200,"data":{"active":true,"merchant":{"id":19},"roleCode":"MERCHANT_CHECKIN","permissions":[]}}"#,
                        #"{"code":200,"data":{"active":true,"merchant":{"id":20},"roleCode":"MERCHANT_CHECKIN","permissions":["merchant:verify"]}}"#] {
            let t = CityNodeRedemptionTransport(), journal = MerchantBusinessMemoryIntentStore()
            let session = try MerchantBusinessSession(accountID: 8, epoch: 1, token: "synthetic")
            let c = CityNodeRedemptionCoordinator(service: try service(t), journal: journal, currentSession: { session })
            await c.prepare("synthetic"); let id = try XCTUnwrap(c.review).id
            await t.setAccess(changed); await c.confirm(id)
            XCTAssertNil(c.result); XCTAssertTrue(try journal.intents().isEmpty)
            let requests = await t.requests; XCTAssertTrue(requests.allSatisfy { $0.url!.path.hasSuffix("access/me") })
        }
    }
    @MainActor func testTimeoutLeavesDurableCoarseLockAcrossNextAndNewEpoch() async throws {
        let t = CityNodeRedemptionTransport(), journal = MerchantBusinessMemoryIntentStore()
        var session = try MerchantBusinessSession(accountID: 8, epoch: 1, token: "synthetic")
        let c = CityNodeRedemptionCoordinator(service: try service(t), journal: journal, currentSession: { session })
        await c.prepare("never-persist-this-code"); let id = try XCTUnwrap(c.review).id
        await t.fail(); await c.confirm(id)
        XCTAssertEqual(c.failure, "merchant.cityRedeem.unknown"); XCTAssertEqual(try journal.intents().count, 1)
        let saved = try String(decoding: JSONEncoder().encode(journal.intents()), as: UTF8.self)
        XCTAssertFalse(saved.contains("never-persist-this-code")); XCTAssertFalse(saved.contains("synthetic"))
        c.next(); c.invalidate(); session = try .init(accountID: 8, epoch: 2, token: "new-synthetic")
        let reopened = CityNodeRedemptionCoordinator(service: try service(t), journal: journal, currentSession: { session })
        await reopened.prepare("another-code"); XCTAssertNil(reopened.review); XCTAssertEqual(reopened.failure, "merchant.cityRedeem.pending")
        let requests = await t.requests; XCTAssertEqual(requests.filter { $0.url!.path.hasSuffix("citynode/redeem") }.count, 1)
    }
    @MainActor func testDismissedInFlightResponseCannotShowResultOrClearJournal() async throws {
        let t = CityNodeRedemptionTransport(), journal = MerchantBusinessMemoryIntentStore()
        let session = try MerchantBusinessSession(accountID: 8, epoch: 1, token: "synthetic")
        let c = CityNodeRedemptionCoordinator(service: try service(t), journal: journal, currentSession: { session })
        await c.prepare("synthetic"); let id = try XCTUnwrap(c.review).id; await t.suspend()
        let task = Task { await c.confirm(id) }
        while !(await t.pending) { await Task.yield() }
        c.invalidate(); await t.finish(); await task.value
        XCTAssertNil(c.result); XCTAssertNil(c.failure); XCTAssertEqual(try journal.intents().count, 1)
    }
    @MainActor func testLogoutBeforeConfirmInvalidatesConsentWithoutMutation() async throws {
        let t = CityNodeRedemptionTransport(), journal = MerchantBusinessMemoryIntentStore()
        var session: MerchantBusinessSession? = try .init(accountID: 8, epoch: 1, token: "synthetic")
        let c = CityNodeRedemptionCoordinator(service: try service(t), journal: journal, currentSession: { session })
        await c.prepare("synthetic"); let id = try XCTUnwrap(c.review).id; session = nil
        await c.confirm(id); XCTAssertEqual(c.failure, "merchant.cityRedeem.stale")
        let requests = await t.requests; XCTAssertEqual(requests.count, 1); XCTAssertTrue(try journal.intents().isEmpty)
    }
    @MainActor func testAccountChangeDuringMutationDoesNotPublishOrExpireNewAccount() async throws {
        let t = CityNodeRedemptionTransport(), journal = MerchantBusinessMemoryIntentStore()
        var session = try MerchantBusinessSession(accountID: 8, epoch: 1, token: "synthetic")
        var expired = false
        let c = CityNodeRedemptionCoordinator(service: try service(t), journal: journal, currentSession: { session }, onUnauthorized: { _ in expired = true })
        await c.prepare("synthetic"); let id = try XCTUnwrap(c.review).id
        await t.setResponse(#"{"code":401,"msg":"Expired old account"}"#); await t.suspend()
        let task = Task { await c.confirm(id) }
        while !(await t.pending) { await Task.yield() }
        session = try .init(accountID: 9, epoch: 2, token: "new-synthetic")
        await t.finish(); await task.value
        XCTAssertNil(c.result); XCTAssertNil(c.failure); XCTAssertFalse(expired)
        XCTAssertEqual(try journal.intents().count, 1)
    }
    @MainActor func testMalformedMutationResponseRetainsUnknownLock() async throws {
        let t = CityNodeRedemptionTransport(), journal = MerchantBusinessMemoryIntentStore()
        let session = try MerchantBusinessSession(accountID: 8, epoch: 1, token: "synthetic")
        await t.setResponse(#"{"msg":"missing required status"}"#)
        let c = CityNodeRedemptionCoordinator(service: try service(t), journal: journal, currentSession: { session })
        await c.prepare("synthetic"); await c.confirm(try XCTUnwrap(c.review).id)
        XCTAssertNil(c.result); XCTAssertEqual(c.failure, "merchant.cityRedeem.unknown")
        XCTAssertEqual(try journal.intents().count, 1)
    }
    @MainActor func testFileJournalSurvivesNewCoordinatorAndContainsNoCode() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("intents.json")
        let t = CityNodeRedemptionTransport()
        let session = try MerchantBusinessSession(accountID: 8, epoch: 1, token: "synthetic")
        let first = CityNodeRedemptionCoordinator(service: try service(t), journal: MerchantBusinessFileIntentStore(url: url), currentSession: { session })
        await first.prepare("private-payload"); await t.fail(); await first.confirm(try XCTUnwrap(first.review).id)
        let stored = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(stored.contains("private-payload")); XCTAssertFalse(stored.contains("synthetic"))
        let reopened = CityNodeRedemptionCoordinator(service: try service(t), journal: MerchantBusinessFileIntentStore(url: url), currentSession: { session })
        await reopened.prepare("another-code")
        XCTAssertNil(reopened.review); XCTAssertEqual(reopened.failure, "merchant.cityRedeem.pending")
    }

}
