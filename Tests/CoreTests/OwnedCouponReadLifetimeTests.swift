import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private actor OwnedCouponSuspendedHTTP: HTTPTransport {
    private(set) var requests: [URLRequest] = []
    private var pending: [Int: CheckedContinuation<(Data, Int), Error>] = [:]
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let index = requests.count; requests.append(request)
        return try await withCheckedThrowingContinuation { pending[index] = $0 }
    }
    func waitFor(_ count: Int) async { while requests.count < count { await Task.yield() } }
    func finish(_ index: Int, status: Int = 200) {
        let body = #"{"code":200,"data":[{"id":71,"couponId":9,"useStatus":0,"couponName":"Owned coupon","couponDescription":"Current server terms","endTime":"2026-10-30 16:00:00","couponCode":"IGNORED-SECRET"}]}"#
        pending.removeValue(forKey: index)?.resume(returning: (Data(body.utf8), status))
    }
}
@MainActor private final class OwnedCouponReadHarness {
    let http = OwnedCouponSuspendedHTTP()
    var session: AccountCollectionReadSession? = try! .init(accountID: 1, epoch: 1, token: "synthetic-owner")
    var unauthorized = 0
    lazy var reader = AccountCollectionSessionReader(service: AccountCollectionService(
        configuration: try! APIConfiguration(baseURL: URL(string: "https://example.test")!), transport: http),
        currentSession: { [unowned self] in session }, onUnauthorized: { [unowned self] _ in unauthorized += 1 })
}
@MainActor final class OwnedCouponReadLifetimeTests: XCTestCase {
    func testClosedCouponReadNeverDispatches() async {
        let h = OwnedCouponReadHarness(), life = OwnedCouponReadLifetime(); life.invalidate()
        do { _ = try await h.reader.ownedCoupon(id: 71, lifetime: life); XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        let requests = await h.http.requests; XCTAssertTrue(requests.isEmpty)
    }
    func testCapturedOwnerScopeCannotReadListOrDetailAfterSessionSwitch() async throws {
        let h = OwnedCouponReadHarness(), life = OwnedCouponReadLifetime(ownerScope: h.reader.scope)
        h.session = try .init(accountID: 2, epoch: 2, token: "other-owner")
        do { _ = try await h.reader.ownedCoupons(keyword: nil, lifetime: life); XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        do { _ = try await h.reader.ownedCoupon(id: 71, lifetime: life); XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        let requests = await h.http.requests; XCTAssertTrue(requests.isEmpty); XCTAssertEqual(h.unauthorized, 0)
    }
    func testBackWhileDetailReadWaitsSuppressesLate401BeforeCallback() async {
        let h = OwnedCouponReadHarness(), life = OwnedCouponReadLifetime(ownerScope: h.reader.scope)
        let read = Task { try await h.reader.ownedCoupon(id: 71, lifetime: life) }
        await h.http.waitFor(1); life.invalidate(); await h.http.finish(0, status: 401)
        do { _ = try await read.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(h.unauthorized, 0)
    }
    func testNewReadKeepsOld401FromExpiringTheSameCurrentOwner() async throws {
        let h = OwnedCouponReadHarness(), oldLife = OwnedCouponReadLifetime(ownerScope: h.reader.scope)
        let old = Task { try await h.reader.ownedCoupons(keyword: "old", lifetime: oldLife) }; await h.http.waitFor(1)
        oldLife.invalidate(); let freshLife = OwnedCouponReadLifetime(ownerScope: h.reader.scope)
        let fresh = Task { try await h.reader.ownedCoupon(id: 71, lifetime: freshLife) }; await h.http.waitFor(2)
        await h.http.finish(0, status: 401)
        do { _ = try await old.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        await h.http.finish(1); let coupon = try await fresh.value
        XCTAssertEqual(coupon.id, 71); XCTAssertEqual(h.unauthorized, 0)
    }
    func testCurrent401StillCallsCurrentSessionUnauthorizedOnce() async {
        let h = OwnedCouponReadHarness(), life = OwnedCouponReadLifetime(ownerScope: h.reader.scope)
        let read = Task { try await h.reader.ownedCoupons(keyword: nil, lifetime: life) }; await h.http.waitFor(1)
        await h.http.finish(0, status: 401)
        do { _ = try await read.value; XCTFail() } catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        XCTAssertEqual(h.unauthorized, 1)
    }
    func testCanceledReadSuppressesCurrentOwnerLate401() async {
        let h = OwnedCouponReadHarness(), life = OwnedCouponReadLifetime(ownerScope: h.reader.scope)
        let read = Task { try await h.reader.ownedCoupon(id: 71, lifetime: life) }; await h.http.waitFor(1)
        read.cancel(); await h.http.finish(0, status: 401)
        do { _ = try await read.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(h.unauthorized, 0)
    }
    func testMetadataDetailUsesOwnedListOnlyWithoutCredentialIssuance() async throws {
        let h = OwnedCouponReadHarness(), life = OwnedCouponReadLifetime(ownerScope: h.reader.scope)
        let read = Task { try await h.reader.ownedCoupon(id: 71, lifetime: life) }; await h.http.waitFor(1); await h.http.finish(0)
        let coupon = try await read.value; XCTAssertEqual(coupon.description, "Current server terms")
        let requests = await h.http.requests; XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].url?.path, "/api/coupon/myrecvlist"); XCTAssertEqual(requests[0].httpMethod, "POST")
        XCTAssertFalse(requests.contains { $0.url?.path.contains("qr-token") == true })
    }
    func testLegacyOwnedCollectionRetainsCurrentUnauthorizedBehavior() async {
        let h = OwnedCouponReadHarness()
        let read = Task { try await h.reader.ownedCoupons(keyword: nil) }; await h.http.waitFor(1)
        await h.http.finish(0, status: 401)
        do { _ = try await read.value; XCTFail() } catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        XCTAssertEqual(h.unauthorized, 1)
    }
}
