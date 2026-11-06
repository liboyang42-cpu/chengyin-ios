import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class CityArrivalEvidenceRuntimeOwnerTests: XCTestCase {
    @MainActor final class Wire: HTTPTransport {
        var calls = 0
        var beforeReply: (() -> Void)?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            calls += 1; beforeReply?()
            return (Data(#"{"code":200,"data":{"contract":"CITY_ARRIVAL_EVIDENCE_V1","scope":"CITY","status":"JOIN_REQUIRED","writeApproved":false,"points":[]}}"#.utf8), 200)
        }
    }
    @MainActor final class Journal: OperationPendingJournal {
        var record: OperationPendingRecord?
        func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? {
            guard let record, record.ownerKey == ownerKey, record.targetKey == targetKey else { return nil }; return record
        }
        func write(_ value: OperationPendingRecord) throws { record = value }
        func clear(_ value: OperationPendingRecord) throws { XCTFail("Runtime owner must not clear unknown journal") }
    }
    @MainActor final class Fixture {
        let context: RuntimeDependencyContext
        let board: CityReadBoard
        var live: RuntimeDependencyContext?
        var revision: UInt64 = 1
        var approval: CityArrivalEvidenceApproval?
        let wire = Wire(), journal = Journal()
        init() throws {
            let base = URL(string: "https://city.example.test/native/")!
            context = .init(market: .china, baseURL: base, role: "player", session: try .init(accountID: 7, epoch: 1, namespace: "arrival", token: "fake-token", role: "player")); live = context
            board = .init(gameId: "game", boardId: "board", regionId: "region", seasonId: "season", rulesReleaseId: "rules", rulesHash: String(repeating: "a", count: 64), lifecycle: "FROZEN", title: "Fake board", revision: 1)
            approval = try makeApproval()
        }
        func makeApproval() throws -> CityArrivalEvidenceApproval { try .init(context: context, audience: .player(regionID: "region"), expiresAt: Date().addingTimeInterval(600)) }
        func owner() throws -> CityArrivalEvidenceRuntimeOwner {
            try .init(context: context, revision: 1, board: board, approval: approval, underlying: wire, journal: journal,
                current: { self.live }, currentRevision: { self.revision }, selected: { _ in self.approval })
        }
    }
    func testNilApprovalOrDefaultProviderCannotCreateRuntime() throws {
        let f = try Fixture(); f.approval = nil; XCTAssertThrowsError(try f.owner())
        f.approval = try f.makeApproval()
        XCTAssertThrowsError(try CityArrivalEvidenceRuntimeOwner(context: f.context, revision: 1, board: f.board, approval: f.approval,
            underlying: f.wire, journal: f.journal, current: { f.live }, currentRevision: { f.revision }))
        XCTAssertEqual(f.wire.calls, 0)
    }
    func testRealControllerReadAndRevisionRetirement() async throws {
        let f = try Fixture(), owner = try f.owner(), controller = try XCTUnwrap(owner.controller)
        await controller.load(); XCTAssertEqual(controller.player?.status, "JOIN_REQUIRED"); XCTAssertEqual(f.wire.calls, 1)
        f.revision = 2; owner.synchronize(); XCTAssertTrue(owner.isRetired); XCTAssertNil(controller.player)
        f.revision = 1; XCTAssertFalse(owner.isCurrent); await controller.load(); XCTAssertEqual(f.wire.calls, 1)
    }
    func testApprovalReplacementAndRoleChangeCannotReuseOwner() throws {
        let f = try Fixture(), owner = try f.owner(); f.approval = try f.makeApproval(); XCTAssertFalse(owner.isCurrent)
        let next = try f.owner()
        f.live = .init(market: .china, baseURL: f.context.baseURL, role: "merchant", session: try .init(accountID: 7, epoch: 1, namespace: "arrival", token: "fake-token", role: "merchant"))
        next.synchronize(); XCTAssertTrue(next.isRetired)
    }
    func testLateReadAfterRevocationIsNeverPresented() async throws {
        let f = try Fixture(), owner = try f.owner(), controller = try XCTUnwrap(owner.controller)
        f.wire.beforeReply = { f.approval?.revoke() }; await controller.load()
        XCTAssertNil(controller.player); XCTAssertFalse(owner.isCurrent); XCTAssertEqual(f.wire.calls, 1)
    }
    func testRetirementPreservesOriginalUnknownIdentityRecord() async throws {
        let f = try Fixture(), owner = try f.owner()
        let original = OperationPendingRecord(ownerKey: "city-arrival:arrival:https://city.example.test/native/:7", targetKey: "player:region")
        f.journal.record = original
        await owner.controller?.load(); XCTAssertEqual(owner.controller?.pendingRequestID, original.operationID)
        owner.retire(); XCTAssertEqual(f.journal.record, original); XCTAssertNil(owner.controller?.pendingRequestID)
    }
    func testAudienceAndBoardCannotBeInterchanged() throws {
        let f = try Fixture()
        let merchant = try CityArrivalEvidenceApproval(context: f.context, audience: .merchant(merchantID: 41), expiresAt: Date().addingTimeInterval(600))
        f.approval = merchant
        XCTAssertThrowsError(try f.owner())
        let owner = try CityArrivalEvidenceRuntimeOwner(context: f.context, revision: 1, board: nil, approval: merchant,
            underlying: f.wire, journal: f.journal, current: { f.live }, currentRevision: { f.revision }, selected: { _ in f.approval })
        XCTAssertTrue(owner.isCurrent); XCTAssertEqual(owner.controller?.audience, .merchant(merchantID: 41))
        f.approval = try f.makeApproval(); owner.synchronize(); XCTAssertFalse(owner.isCurrent)
    }
}
