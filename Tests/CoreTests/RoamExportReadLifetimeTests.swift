import XCTest
import Observation
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Adapted from the original three read recovery cases, extended for the current delivery lease.
@MainActor final class RoamExportReadLifetimeTests: XCTestCase {
    private func prepare(_ model: RoamExportCoordinator) async {
        let range = model.presets[0]
        await model.prepare(startDate: range.startDate, endDateExclusive: range.endDateExclusive)
    }
    private func held(_ check: () -> Bool) async {
        for _ in 0..<100 { if check() { return }; await Task.yield() }
        XCTFail("Synthetic suspended read was not entered")
    }
    func testLateFinalChunkCannotMintLeaseAfterSuspendEvenIfForegroundAlreadyReturned() async throws {
        let tools = ExportReadTools(), model = RoamExportCoordinator(tools: tools, pageSize: 2)
        await prepare(model); await model.readNext()
        let original = try XCTUnwrap(model.checkpoint)
        tools.holdPage = true
        let late = Task { await model.readNext() }
        await held { tools.heldPage != nil }
        model.suspend(); model.resume()
        XCTAssertEqual(model.phase, .prepared)
        XCTAssertEqual(tools.pages.count, 2, "Resume does not dispatch")
        tools.releasePage(); await late.value
        XCTAssertEqual(model.checkpoint, original); XCTAssertNil(model.file); XCTAssertNil(model.deliveryLease)
        await model.readNext()
        XCTAssertEqual(tools.prepareCalls, 1); XCTAssertEqual(tools.pages[1], tools.pages[2])
        XCTAssertEqual(model.shareableFile?.rows, 3)
        XCTAssertEqual(model.shareableFile?.content.split(separator: "\n").count, 7)
    }
    func testSuspendedPrepareCannotCommitAndOnlyExplicitFreshPrepareCanRecover() async {
        let tools = ExportReadTools(), model = RoamExportCoordinator(tools: tools, pageSize: 2)
        tools.holdPrepare = true
        let late = Task { await self.prepare(model) }
        await held { tools.heldPrepare != nil }
        model.suspend(); tools.releasePrepare(); await late.value
        XCTAssertNil(model.checkpoint); XCTAssertNil(model.file)
        await prepare(model); XCTAssertEqual(tools.prepareCalls, 1)
        model.resume(); XCTAssertEqual(model.phase, .choosing); XCTAssertEqual(tools.prepareCalls, 1)
        await prepare(model); XCTAssertEqual(tools.prepareCalls, 2); XCTAssertEqual(model.phase, .prepared)
    }
    func testFailedChunkBackgroundReturnKeepsExactOriginalSnapshotAndCursor() async throws {
        let tools = ExportReadTools(), model = RoamExportCoordinator(tools: tools, pageSize: 2)
        await prepare(model); await model.readNext(); let checkpoint = model.checkpoint
        tools.failNextPage = true; await model.readNext()
        XCTAssertEqual(model.phase, .failed); XCTAssertEqual(model.checkpoint, checkpoint)
        model.suspend(); model.resume(); await model.readNext()
        XCTAssertEqual(tools.pages[1], tools.pages[2]); XCTAssertEqual(tools.prepareCalls, 1)
        XCTAssertEqual(model.shareableFile?.rows, 3)
    }
    func testResumeRejectsExpiredRevokedAndChangedOwnerCheckpointWithoutRequest() async throws {
        for reason in 0..<3 {
            let tools = ExportReadTools(), model = RoamExportCoordinator(tools: tools, pageSize: 2)
            await prepare(model); await model.readNext(); model.suspend()
            if reason == 0 { tools.now = Date(timeIntervalSince1970: Double(try XCTUnwrap(model.checkpoint).snapshot.expiresAtMs) / 1000) }
            else if reason == 1 { tools.isConfigured = false }
            else { tools.identity = nil }
            model.resume()
            XCTAssertNil(model.checkpoint); XCTAssertNil(model.file); XCTAssertNil(model.deliveryLease)
            XCTAssertEqual(model.issue, reason == 0 ? .expired : (reason == 1 ? .notConfigured : .changedContext))
            XCTAssertEqual(tools.pages.count, 1); XCTAssertEqual(tools.prepareCalls, 1)
        }
    }
    func testCompletedLeaseNeverRevivesOnResumeOrRenewButExplicitNewSnapshotGetsNewLease() async throws {
        let tools = ExportReadTools(), model = RoamExportCoordinator(tools: tools, pageSize: 2)
        await prepare(model); await model.readNext(); await model.readNext()
        let old = try XCTUnwrap(model.deliveryLease)
        XCTAssertNotNil(model.shareableFile)
        model.suspend(); XCTAssertTrue(old.isRevoked)
        model.resume(); model.renewDelivery()
        XCTAssertTrue(model.deliveryLease === old); XCTAssertNil(model.shareableFile)
        XCTAssertEqual(tools.prepareCalls, 1); XCTAssertEqual(tools.pages.count, 2)
        model.restart(); await prepare(model); await model.readNext(); await model.readNext()
        XCTAssertFalse(model.deliveryLease === old); XCTAssertTrue(old.isRevoked)
        XCTAssertNotNil(model.shareableFile)
    }
    func testSuspendDoesNotPublishObservedCoordinatorValuesDuringNativeTeardown() async {
        let tools = ExportReadTools(), model = RoamExportCoordinator(tools: tools, pageSize: 2)
        await prepare(model); await model.readNext(); await model.readNext()
        let notice = ExportReadObservationCount()
        withObservationTracking {
            _ = model.phase; _ = model.checkpoint; _ = model.file; _ = model.issue; _ = model.deliveryLease
            _ = model.shareableFile; _ = model.isBusy; _ = model.percent
        } onChange: { notice.count += 1 }
        model.suspend()
        XCTAssertEqual(notice.count, 0)
        XCTAssertEqual(model.phase, .complete); XCTAssertNil(model.shareableFile)
    }
    func testCancelledQueuedReadAndUnconfiguredScopeNeverDispatch() async {
        let tools = ExportReadTools(), model = RoamExportCoordinator(tools: tools, pageSize: 2)
        await prepare(model)
        let queued = Task { await model.readNext() }; queued.cancel(); await queued.value
        XCTAssertTrue(tools.pages.isEmpty)
        tools.isConfigured = false
        await model.readNext(); await prepare(model)
        XCTAssertTrue(tools.pages.isEmpty); XCTAssertEqual(tools.prepareCalls, 1)
        XCTAssertEqual(model.issue, .notConfigured)
    }
    func testRealSessionReaderStillRequiresOriginalReadApprovalAndDoesNotOpenJournalOrWire() async throws {
        let base = URL(string: "https://example.test/export-scope")!
        let session = try PlayExperienceSession(accountID: 7, epoch: 1, namespace: "export-read", token: "synthetic-export")
        let context = RuntimeDependencyContext(market: .china, baseURL: base, role: "player", session: session)
        let wire = ExportReadForbiddenWire()
        let reader = RoamPrivateToolsSessionReader(service: .init(configuration: try APIConfiguration(baseURL: base), transport: wire),
                                                  current: { context }, access: { _ in nil }, journal: nil)
        let model = RoamExportCoordinator(tools: reader)
        XCTAssertFalse(reader.isConfigured); XCTAssertFalse(reader.allowsWrites)
        await prepare(model); model.suspend(); model.resume(); await model.readNext()
        XCTAssertEqual(model.issue, .notConfigured); XCTAssertNil(model.file)
        let calls = await wire.calls; XCTAssertEqual(calls, 0)
    }
}
private final class ExportReadObservationCount: @unchecked Sendable { var count = 0 }
private actor ExportReadForbiddenWire: HTTPTransport {
    private(set) var calls = 0
    func send(_ request: URLRequest) async throws -> (Data, Int) { calls += 1; throw APIError.notConfigured }
}

@MainActor private final class ExportReadTools: RoamPrivateToolsServing {
    let fixture = RoamPrivateToolsFixture()
    var identity: RoamExperienceIdentity?
    var isConfigured = true
    var now: Date
    let allowsWrites = false, isOfflineExample = true
    var pendingCapsule: RoamCapsuleDraft?
    var pendingGoal: RoamGoalDraft?
    var confirmedCancelledGoals: Set<String> = []
    var prepareCalls = 0
    var pages: [RoamExportCheckpoint] = []
    var holdPrepare = false
    var heldPrepare: CheckedContinuation<Void, Never>?
    var holdPage = false
    var heldPage: CheckedContinuation<Void, Never>?
    var failNextPage = false
    init() { identity = fixture.identity; now = fixture.now }
    func prepareExport(_ request: RoamExportRequest) async throws -> RoamExportCheckpoint {
        prepareCalls += 1
        if holdPrepare { await withCheckedContinuation { heldPrepare = $0 } }
        return try await fixture.prepareExport(request)
    }
    func exportPage(_ checkpoint: RoamExportCheckpoint) async throws -> RoamExportChunk {
        pages.append(checkpoint)
        if holdPage { await withCheckedContinuation { heldPage = $0 } }
        if failNextPage { failNextPage = false; throw APIError.httpStatus(503) }
        return try await fixture.exportPage(checkpoint)
    }
    func releasePrepare() { holdPrepare = false; heldPrepare?.resume(); heldPrepare = nil }
    func releasePage() { holdPage = false; heldPage?.resume(); heldPage = nil }
    func capsules(beforeID: String?) async throws -> RoamCapsulePage { throw APIError.notConfigured }
    func capsule(id: String) async throws -> RoamCapsule { throw APIError.notConfigured }
    func capsuleReceipt(requestID: String) async throws -> RoamCapsule { throw APIError.notConfigured }
    func createCapsule(_ draft: RoamCapsuleDraft) async throws -> RoamCapsule { throw APIError.notConfigured }
    func deleteCapsule(id: String) async throws -> RoamCapsule { throw APIError.notConfigured }
    func goals(beforeID: String?) async throws -> RoamGoalPage { throw APIError.notConfigured }
    func goal(id: String) async throws -> RoamExplorationGoal { throw APIError.notConfigured }
    func goalReceipt(requestID: String) async throws -> RoamExplorationGoal { throw APIError.notConfigured }
    func createGoal(_ draft: RoamGoalDraft) async throws -> RoamExplorationGoal { throw APIError.notConfigured }
    func cancelGoal(id: String) async throws -> RoamExplorationGoal { throw APIError.notConfigured }
}
