import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Exercises the actual model -> session reader -> HTTP service path, not a reader stub.
private actor DetailSuspendedTransport: HTTPTransport {
    private var requests: [URLRequest] = []
    private var pending: [Int: CheckedContinuation<(Data, Int), Error>] = [:]
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let index = requests.count; requests.append(request)
        return try await withCheckedThrowingContinuation { pending[index] = $0 }
    }
    func waitFor(_ count: Int) async { while requests.count < count { await Task.yield() } }
    func count() -> Int { requests.count }
    func finish(_ index: Int, status: Int) {
        let body = #"{"code":200,"data":{"awardId":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","contextType":"MAP","contextId":"map","releaseId":"release","instanceId":"season","rulesVersion":"rules","merchantId":"7","storeId":"8","rewardKind":"PHYSICAL","rewardTitle":"Item","redemptionConditions":"Store only","state":"AWARDED","quantity":1,"validFrom":100000,"validUntil":200000,"awardedAt":100000,"asOf":150000,"validityStatus":"IN_WINDOW","fulfillmentStatus":"UNVERIFIED"}}"#
        pending.removeValue(forKey: index)?.resume(returning: (Data(body.utf8), status))
    }
}
@MainActor private final class DetailSessionHarness {
    var session: NonCashRewardReadSession? = try! .init(accountID: 7, epoch: 1, token: "synthetic")
    var unauthorized = 0
    let transport = DetailSuspendedTransport()
    lazy var reader = NonCashRewardSessionReader(service: NonCashRewardService(
        configuration: try! APIConfiguration(baseURL: URL(string: "https://example.test")!), transport: transport),
        currentSession: { [unowned self] in session }, onUnauthorized: { [unowned self] _ in unauthorized += 1 })
    func model() -> NonCashRewardDetailModel { .init(selection: .init(reference: .init(reward), ownerScope: reader.scope)) }
    var reward: NonCashReward {
        NonCashReward(awardId: String(repeating: "a", count: 64), contextType: .map, contextId: "map", releaseId: "release", instanceId: "season",
            rulesVersion: "rules", merchantId: "7", storeId: "8", rewardTitle: "Item", quantity: 1,
            validFrom: Date(timeIntervalSince1970: 100), validUntil: Date(timeIntervalSince1970: 200), redemptionConditions: "Store only",
            state: .awarded, awardedAt: Date(timeIntervalSince1970: 100), asOf: Date(timeIntervalSince1970: 150))
    }
}
@MainActor final class NonCashRewardDetailLifetimeTests: XCTestCase {
    func testBackOrCloseInvalidatesLate401BeforeSessionCallback() async {
        let h = DetailSessionHarness(), model = h.model()
        let read = Task { await model.refresh(reader: h.reader) }; await h.transport.waitFor(1)
        model.cancelPending(); await h.transport.finish(0, status: 401); await read.value
        XCTAssertEqual(h.unauthorized, 0); XCTAssertNil(model.visibleValue(scope: h.reader.scope)); XCTAssertNil(model.visibleIssue(scope: h.reader.scope))
    }
    func testNewRefreshInvalidatesOlder401AndAcceptsOnlyCurrentResult() async {
        let h = DetailSessionHarness(), model = h.model()
        let old = Task { await model.refresh(reader: h.reader) }; await h.transport.waitFor(1)
        let fresh = Task { await model.refresh(reader: h.reader) }; await h.transport.waitFor(2)
        await h.transport.finish(0, status: 401); await old.value
        XCTAssertEqual(h.unauthorized, 0); XCTAssertTrue(model.isLoading)
        await h.transport.finish(1, status: 200); await fresh.value
        XCTAssertEqual(model.visibleValue(scope: h.reader.scope)?.reward, h.reward)
    }
    func testTaskCancellationSuppressesLate401AndStopsLoading() async {
        let h = DetailSessionHarness(), model = h.model()
        let read = Task { await model.refresh(reader: h.reader) }; await h.transport.waitFor(1)
        read.cancel(); await h.transport.finish(0, status: 401); await read.value
        XCTAssertEqual(h.unauthorized, 0); XCTAssertFalse(model.isLoading); XCTAssertNil(model.loadedScope)
    }
    func testCurrent401StillExpiresOnlyTheCurrentSession() async {
        let h = DetailSessionHarness(), model = h.model()
        let read = Task { await model.refresh(reader: h.reader) }; await h.transport.waitFor(1)
        await h.transport.finish(0, status: 401); await read.value
        XCTAssertEqual(h.unauthorized, 1); XCTAssertEqual(model.visibleIssue(scope: h.reader.scope), .login)
    }
    func testInvalidatedReadDoesNotDispatchAndCollectionCallbackRemainsCompatible() async {
        let h = DetailSessionHarness(), lifetime = NonCashRewardReadLifetime(); lifetime.invalidate()
        do { _ = try await h.reader.reward(.init(h.reward), lifetime: lifetime); XCTFail("Invalidated detail dispatched") }
        catch { XCTAssertTrue(error is CancellationError) }
        let before = await h.transport.count(); XCTAssertEqual(before, 0)
        let collection = Task { try await h.reader.rewards(cursor: nil) }; await h.transport.waitFor(1)
        await h.transport.finish(0, status: 401)
        do { _ = try await collection.value; XCTFail() } catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        XCTAssertEqual(h.unauthorized, 1)
    }
    func testSessionSwitchWhilePushedSuppressesOld401WithoutNewDispatch() async throws {
        let h = DetailSessionHarness(), model = h.model(), oldScope = h.reader.scope
        let read = Task { await model.refresh(reader: h.reader) }; await h.transport.waitFor(1)
        h.session = try .init(accountID: 8, epoch: 2, token: "next")
        XCTAssertNotEqual(h.reader.scope, oldScope); await h.transport.finish(0, status: 401); await read.value
        await model.refresh(reader: h.reader)
        let count = await h.transport.count(); XCTAssertEqual(count, 1); XCTAssertEqual(h.unauthorized, 0)
        XCTAssertNil(model.visibleValue(scope: h.reader.scope))
    }
    func testRevokedOfferCannotStartActualSessionReaderAfterQueuedModelHandoff() async {
        let h = DetailSessionHarness(), model = h.model(), offered = NonCashRewardReadLifetime()
        offered.invalidate()
        await model.refresh(reader: h.reader, offeredLifetime: offered)
        let count = await h.transport.count()
        XCTAssertEqual(count, 0); XCTAssertEqual(h.unauthorized, 0); XCTAssertNil(model.loadedScope)
    }
    func testObsoleteOfferCannotInvalidateAReopenedCurrentRead() async {
        let h = DetailSessionHarness(), model = h.model()
        let old = NonCashRewardReadLifetime(); old.invalidate()
        let current = NonCashRewardReadLifetime()
        let read = Task { await model.refresh(reader: h.reader, offeredLifetime: current) }
        await h.transport.waitFor(1)
        await model.refresh(reader: h.reader, offeredLifetime: old)
        XCTAssertTrue(current.isActive); XCTAssertTrue(model.isLoading)
        await h.transport.finish(0, status: 200); await read.value
        XCTAssertEqual(model.visibleValue(scope: h.reader.scope)?.reward, h.reward)
        XCTAssertEqual(h.unauthorized, 0)
    }

}
