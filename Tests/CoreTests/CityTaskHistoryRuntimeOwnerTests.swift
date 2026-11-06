import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class CityTaskHistoryRuntimeOwnerTests: XCTestCase {
    @MainActor final class Wire: HTTPTransport {
        var calls = 0
        var beforeReply: (() -> Void)?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            calls += 1; beforeReply?()
            return (Data(#"{"code":200,"data":{"contract":"CITY_PERSONAL_TASK_HISTORY_V1","scope":"OWN_ONSITE_TASKS_ONLY","regionId":"region","readAt":"2026-10-21T00:00:00Z","currentQualification":"NOT_EVALUATED","memberId":7,"readOnly":true,"pageSize":20,"items":[]}}"#.utf8), 200)
        }
    }
    @MainActor final class Fixture {
        let context: RuntimeDependencyContext
        var live: RuntimeDependencyContext?
        var revision: UInt64 = 1
        var approval: CityTaskHistoryApproval?
        let wire = Wire()
        init() throws {
            let base = URL(string: "https://city.example.test/native/")!
            context = .init(market: .china, baseURL: base, role: "player", session: try .init(accountID: 7, epoch: 1, namespace: "neutral", token: "fake-token", role: "player")); live = context
            approval = try makeApproval()
        }
        func makeApproval() throws -> CityTaskHistoryApproval { try .init(context: context, regionID: "region", expiresAt: Date().addingTimeInterval(600)) }
        func owner() throws -> CityTaskHistoryRuntimeOwner {
            try .init(context: context, revision: 1, regionID: "region", approval: approval, underlying: wire,
                current: { self.live }, currentRevision: { self.revision }, selected: { _ in self.approval })
        }
    }
    func testNilApprovalOrDefaultProviderCannotCreateRuntime() throws {
        let f = try Fixture(); f.approval = nil; XCTAssertThrowsError(try f.owner())
        f.approval = try f.makeApproval()
        XCTAssertThrowsError(try CityTaskHistoryRuntimeOwner(context: f.context, revision: 1, regionID: "region", approval: f.approval,
            underlying: f.wire, current: { f.live }, currentRevision: { f.revision }))
        XCTAssertEqual(f.wire.calls, 0)
    }
    func testRealControllerReadAndRevisionRetirement() async throws {
        let f = try Fixture(), owner = try f.owner(), controller = try XCTUnwrap(owner.controller)
        await controller.load(); XCTAssertTrue(controller.loaded); XCTAssertEqual(f.wire.calls, 1)
        f.revision = 2; owner.synchronize(); XCTAssertTrue(owner.isRetired); XCTAssertTrue(controller.items.isEmpty)
        f.revision = 1; XCTAssertFalse(owner.isCurrent); await controller.load(); XCTAssertEqual(f.wire.calls, 1)
    }
    func testApprovalReplacementAndRoleChangeCannotReuseOwner() throws {
        let f = try Fixture(), owner = try f.owner(); f.approval = try f.makeApproval(); XCTAssertFalse(owner.isCurrent)
        let next = try f.owner()
        f.live = .init(market: .china, baseURL: f.context.baseURL, role: "merchant", session: try .init(accountID: 7, epoch: 1, namespace: "neutral", token: "fake-token", role: "merchant"))
        next.synchronize(); XCTAssertTrue(next.isRetired)
    }
    func testLateReadAfterRevocationIsNeverPresented() async throws {
        let f = try Fixture(), owner = try f.owner(), controller = try XCTUnwrap(owner.controller)
        f.wire.beforeReply = { f.approval?.revoke() }; await controller.load()
        XCTAssertTrue(controller.items.isEmpty); XCTAssertFalse(owner.isCurrent); XCTAssertEqual(f.wire.calls, 1)
    }
    func testBackgroundInvalidationAllowsFreshReadButNotOldReview() async throws {
        let f = try Fixture(), owner = try f.owner(), controller = try XCTUnwrap(owner.controller)
        let old = try XCTUnwrap(controller.captureRead(.refresh)); controller.invalidate()
        await controller.perform(old); XCTAssertEqual(f.wire.calls, 0)
        await controller.load(); XCTAssertTrue(controller.loaded); XCTAssertEqual(f.wire.calls, 1)
        XCTAssertTrue(owner.isCurrent)
    }
}
