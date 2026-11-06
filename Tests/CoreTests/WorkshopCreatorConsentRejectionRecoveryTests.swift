import XCTest
@testable import QuestifyCore

/// New source-only regressions. Existing synthetic fixture reused without modifying it.
/// No real creator declaration, license, purchase, payment, approval or server request occurs.
@MainActor final class WorkshopCreatorConsentRejectionRecoveryTests: XCTestCase {
    typealias Fixture = WorkshopCreatorConsentTests.Fixture

    func testCurrentPreview401RetiresTheRejectedPresentation() async throws {
        let f = try Fixture(), appearance = WorkshopCreatorConsentAppearance()
        f.wire.delay = true
        let action = try XCTUnwrap(f.controller.appear(appearance))
        let task = Task { await action() }; await f.wire.wait()
        f.wire.resume401(); await task.value
        XCTAssertEqual(f.unauthorized, 1)
        XCTAssertEqual(f.controller.phase, .invalidated)
        XCTAssertEqual(f.controller.issue, .unauthorized)
        XCTAssertFalse(f.lease.isCurrent)
        XCTAssertNil(f.controller.preview)
        XCTAssertTrue(f.controller.targets.isEmpty)
        XCTAssertNil(f.controller.offerLoad(appearance))
        XCTAssertNil(f.controller.appear(.init()))
        XCTAssertEqual(f.wire.writes, 0)
    }

    func testOriginalStatus401RetainsExactJournalRatherThanClearingUnknown() async throws {
        let f = try Fixture(), appearance = WorkshopCreatorConsentAppearance()
        let original = try WorkshopCreatorDeclarationCommand(preview: WorkshopCreatorConsentTests.preview(), target: WorkshopCreatorConsentTests.target())
        try f.store.retain(original)
        let bytes = f.memory.values
        f.wire.delay = true
        let action = try XCTUnwrap(f.controller.appear(appearance))
        let task = Task { await action() }; await f.wire.wait()
        f.wire.resume401(); await task.value
        XCTAssertEqual(f.controller.phase, .invalidated)
        XCTAssertEqual(f.controller.issue, .unauthorized)
        XCTAssertEqual(f.memory.values, bytes)
        XCTAssertEqual(try f.store.load()?.data(), try original.data())
        XCTAssertNil(f.controller.receipt)
        XCTAssertNil(f.controller.offerConfirm(appearance))
        XCTAssertEqual(f.wire.writes, 0)
        XCTAssertEqual(f.wire.requests.map { $0.url?.lastPathComponent }, ["status"])
    }

    func testDispatched401PreservesPossiblyCommittedRequestAndLocksOldPage() async throws {
        let f = try Fixture(), appearance = WorkshopCreatorConsentAppearance()
        try await f.load(appearance); try f.consent(appearance)
        f.wire.delay = true
        let action = try XCTUnwrap(f.controller.offerConfirm(appearance))
        let original = try XCTUnwrap(f.store.load()), bytes = f.memory.values
        let task = Task { await action() }; await f.wire.wait()
        // The original fixture records the command before delaying its response.
        XCTAssertEqual(f.wire.committed?.requestId, original.requestId)
        f.wire.resume401(); await task.value
        XCTAssertEqual(f.controller.phase, .invalidated)
        XCTAssertEqual(f.controller.issue, .unauthorized)
        XCTAssertEqual(f.unauthorized, 1)
        XCTAssertNil(f.controller.preview)
        XCTAssertNil(f.controller.selected)
        XCTAssertTrue(f.controller.targets.isEmpty)
        XCTAssertTrue(f.controller.acknowledgments.isEmpty)
        XCTAssertNil(f.controller.receipt)
        XCTAssertEqual(f.memory.values, bytes)
        XCTAssertEqual(try f.store.load()?.data(), try original.data())
        XCTAssertFalse(f.controller.canConfirm)
        XCTAssertNil(f.controller.offerConfirm(appearance))
        XCTAssertNil(f.controller.offerAnotherReview(appearance))
        XCTAssertEqual(f.wire.writes, 1)
    }

    func testFreshReadOnlySessionRecoversSameRequestWithoutSecondDeclaration() async throws {
        let old = try Fixture(), appearance = WorkshopCreatorConsentAppearance()
        try await old.load(appearance); try old.consent(appearance)
        old.wire.delay = true
        let action = try XCTUnwrap(old.controller.offerConfirm(appearance))
        let original = try XCTUnwrap(old.store.load()), bytes = old.memory.values
        let task = Task { await action() }; await old.wire.wait()
        old.wire.resume401(); await task.value
        let fresh = try Fixture(reading: true, writing: false, memory: old.memory)
        fresh.wire.committed = original // synthetic server retained original receipt, not client success synthesis
        try await fresh.load(.init())
        XCTAssertEqual(fresh.controller.phase, .recorded)
        XCTAssertNotNil(fresh.controller.receipt)
        XCTAssertEqual(fresh.controller.pending?.requestId, original.requestId)
        XCTAssertEqual(fresh.memory.values, bytes)
        XCTAssertEqual(fresh.wire.requests.map { $0.url?.lastPathComponent }, ["status"])
        XCTAssertEqual(fresh.wire.writes, 0)
        XCTAssertFalse(fresh.controller.canConfirm)
        XCTAssertNil(old.controller.offerLoad(appearance))
    }

    func testWriteApprovalWithdrawalDoesNotRevokeIndependentStatusRead() async throws {
        let f = try Fixture(), appearance = WorkshopCreatorConsentAppearance()
        try await f.load(appearance); try f.consent(appearance)
        f.wire.delay = true
        let action = try XCTUnwrap(f.controller.offerConfirm(appearance))
        let original = try XCTUnwrap(f.store.load())
        let task = Task { await action() }; await f.wire.wait()
        f.write = nil
        f.wire.resume401(); await task.value
        // The original write-specific lifetime becomes stale when canWrite becomes false.
        // This is not revocation of the independent read grant or owner session.
        XCTAssertEqual(f.controller.issue, .stale)
        XCTAssertEqual(f.controller.phase, .reviewing)
        XCTAssertTrue(f.lease.isCurrent)
        XCTAssertFalse(f.controller.canConfirm)
        XCTAssertEqual(f.unauthorized, 0)
        XCTAssertEqual(try f.store.load()?.requestId, original.requestId)
        await (try XCTUnwrap(f.controller.offerLoad(appearance)))()
        XCTAssertEqual(f.controller.phase, .recorded)
        XCTAssertEqual(f.controller.pending?.requestId, original.requestId)
        XCTAssertEqual(f.wire.writes, 1)
    }

    func testUnknownTransportResultStillRecoversWithoutRetiringOrRepeatingWrite() async throws {
        let f = try Fixture(), appearance = WorkshopCreatorConsentAppearance()
        try await f.load(appearance); try f.consent(appearance)
        f.wire.commitThenThrow = true
        await (try XCTUnwrap(f.controller.offerConfirm(appearance)))()
        let original = try XCTUnwrap(f.store.load())
        XCTAssertEqual(f.controller.issue, .unknown)
        XCTAssertEqual(f.controller.phase, .reviewing)
        XCTAssertTrue(f.lease.isCurrent)
        XCTAssertEqual(f.unauthorized, 0)
        await (try XCTUnwrap(f.controller.offerLoad(appearance)))()
        XCTAssertEqual(f.controller.phase, .recorded)
        XCTAssertEqual(f.controller.pending?.requestId, original.requestId)
        XCTAssertEqual(f.wire.writes, 1)
    }

    func testOld401CannotRetireNewerReviewPresentation() async throws {
        let f = try Fixture(), old = WorkshopCreatorConsentAppearance()
        f.wire.delay = true
        let action = try XCTUnwrap(f.controller.appear(old))
        let task = Task { await action() }; await f.wire.wait()
        f.controller.close(old)
        let fresh = WorkshopCreatorConsentAppearance(); try await f.load(fresh)
        f.wire.resume401(); await task.value
        XCTAssertEqual(f.controller.phase, .reviewing)
        XCTAssertNotNil(f.controller.preview)
        XCTAssertTrue(f.lease.isCurrent)
        XCTAssertEqual(f.unauthorized, 0)
        XCTAssertEqual(f.wire.writes, 0)
    }
}
