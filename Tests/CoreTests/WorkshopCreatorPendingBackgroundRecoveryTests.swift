import XCTest
@testable import QuestifyCore

/// Unexecuted source regressions using unchanged synthetic fixtures only.
@MainActor final class WorkshopCreatorPendingBackgroundRecoveryTests: XCTestCase {
    typealias Harness = WorkshopCreatorPendingControllerTests.Harness

    func testBackgroundHidesUnsubmittedFormThenRestoresOnlyLocalInput() async throws {
        let h = try Harness(), a = WorkshopCreatorPendingAppearance()
        try await h.load(a); h.fill(); let form = h.controller.form
        h.controller.suspend(a); h.controller.suspend(a)
        XCTAssertEqual(h.controller.form, WorkshopCreatorPendingForm())
        XCTAssertNil(h.controller.preview); XCTAssertTrue(h.controller.items.isEmpty)
        XCTAssertFalse(h.controller.canSubmit); XCTAssertFalse(h.controller.canRetry)
        XCTAssertNil(h.controller.offerLoad(a)); XCTAssertNil(h.controller.offerAuthor(a))
        XCTAssertNil(try h.store.load())
        await (try XCTUnwrap(h.controller.resume(a)))()
        XCTAssertEqual(h.controller.form, form)
        XCTAssertEqual(h.controller.phase, .editing)
        XCTAssertTrue(h.pending.commands.isEmpty)
        XCTAssertNil(h.controller.receipt); XCTAssertNil(h.controller.declaration)
    }

    func testQueuedAuthorIsBlockedAndOriginalJournalStaysUnknownWithoutAutomaticRetry() async throws {
        let h = try Harness(), a = WorkshopCreatorPendingAppearance()
        try await h.load(a); h.fill()
        let queued = try XCTUnwrap(h.controller.offerAuthor(a))
        let original = try XCTUnwrap(h.store.load()), bytes = h.memory.values
        h.controller.suspend(a); await queued()
        XCTAssertTrue(h.pending.commands.isEmpty); XCTAssertEqual(h.memory.values, bytes)
        await (try XCTUnwrap(h.controller.resume(a)))()
        XCTAssertEqual(h.controller.pending, original)
        XCTAssertEqual(h.controller.issue, .unknown)
        XCTAssertNil(h.controller.receipt); XCTAssertTrue(h.pending.commands.isEmpty)
        XCTAssertEqual(h.memory.values, bytes)
        XCTAssertFalse(h.controller.canSubmit)
        await queued(); XCTAssertTrue(h.pending.commands.isEmpty)
        await (try XCTUnwrap(h.controller.offerRetry(a)))()
        XCTAssertEqual(h.pending.commands, [original])
    }

    func testNestedReviewRetiresAndDeclarationJournalSurvivesForegroundRecovery() async throws {
        let h = try Harness(), a = WorkshopCreatorPendingAppearance()
        try await h.load(a)
        await (try XCTUnwrap(h.controller.offerReview(try XCTUnwrap(h.controller.items.first), a)))()
        let child = try XCTUnwrap(h.controller.declaration), childAppearance = WorkshopCreatorConsentAppearance()
        await (try XCTUnwrap(child.appear(childAppearance)))()
        child.select(try XCTUnwrap(child.targets.first), appearance: childAppearance)
        for index in 0..<3 { child.acknowledge(index, value: true, appearance: childAppearance) }
        let queued = try XCTUnwrap(child.offerConfirm(childAppearance))
        let original = try XCTUnwrap(h.declarationStore.load()), bytes = h.memory.values
        h.controller.suspend(a); await queued()
        XCTAssertEqual(child.phase, .invalidated)
        XCTAssertNil(h.controller.declaration); XCTAssertNil(h.controller.selectedDetail)
        h.proposalReads = false; h.writing = false
        await (try XCTUnwrap(h.controller.resume(a)))()
        XCTAssertEqual(h.source.statusReads, 1)
        XCTAssertEqual(h.controller.declarationRequestId, original.requestId)
        XCTAssertNil(h.controller.declarationReceipt)
        XCTAssertNil(h.controller.declaration)
        XCTAssertEqual(h.memory.values, bytes)
        XCTAssertTrue(h.pending.commands.isEmpty)
    }

    func testLateDispatched401CannotReplaceForegroundUnknownOrEraseAuthorJournal() async throws {
        let f = try WorkshopCreatorPendingRejectionRecoveryTests.Fixture()
        let a = WorkshopCreatorPendingAppearance(), command = try WorkshopCreatorPendingCoreTests.command()
        try f.store.retain(command); try await f.load(a); f.wire.delayWrite = true
        let action = try XCTUnwrap(f.controller.offerRetry(a))
        let task = Task { await action() }; await f.wire.wait()
        let bytes = f.memory.values
        f.controller.suspend(a)
        await (try XCTUnwrap(f.controller.resume(a)))()
        f.wire.reject(); await task.value
        XCTAssertEqual(f.controller.phase, .editing)
        XCTAssertEqual(f.controller.issue, .unknown)
        XCTAssertEqual(f.controller.pending, command); XCTAssertNil(f.controller.receipt)
        XCTAssertEqual(f.base.unauthorized, 0); XCTAssertTrue(f.base.lease.isCurrent)
        XCTAssertEqual(f.base.wire.writes, 1); XCTAssertEqual(f.memory.values, bytes)
    }

    func testOwnerChangeCannotRestorePrivateFormAndOriginalAuthorJournalRemains() async throws {
        let h = try Harness(), a = WorkshopCreatorPendingAppearance()
        try await h.load(a); h.fill(); _ = try XCTUnwrap(h.controller.offerAuthor(a))
        let bytes = h.memory.values
        h.controller.suspend(a); h.current = nil
        XCTAssertNil(h.controller.resume(a))
        XCTAssertEqual(h.controller.phase, .invalidated)
        XCTAssertEqual(h.controller.form, WorkshopCreatorPendingForm())
        XCTAssertEqual(h.memory.values, bytes); XCTAssertTrue(h.pending.commands.isEmpty)
        XCTAssertNil(h.controller.appear(.init()))
    }

    func testInitiallyInactiveAndClosedAppearancesCannotRunQueuedLoad() async throws {
        let h = try Harness(), a = WorkshopCreatorPendingAppearance()
        let queued = try XCTUnwrap(h.controller.appear(a))
        h.controller.suspend(a); await queued()
        XCTAssertEqual(h.source.reads, 0); XCTAssertEqual(h.pending.listReads, 0)
        h.controller.close(a); XCTAssertNil(h.controller.resume(a))
        let fresh = WorkshopCreatorPendingAppearance(); try await h.load(fresh)
        h.controller.suspend(a)
        XCTAssertEqual(h.controller.phase, .editing)
        XCTAssertNotNil(h.controller.preview)
        XCTAssertTrue(h.pending.commands.isEmpty)
    }
}
