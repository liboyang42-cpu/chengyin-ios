import XCTest
@testable import QuestifyCore

/// Source-only regressions; uses the unchanged synthetic fixture, never real declarations.
@MainActor final class WorkshopCreatorConsentBackgroundRecoveryTests: XCTestCase {
    typealias Fixture = WorkshopCreatorConsentTests.Fixture

    func testBackgroundClearsReviewAndRequiresThreeFreshAcknowledgments() async throws {
        let f = try Fixture(), a = WorkshopCreatorConsentAppearance()
        try await f.load(a); try f.consent(a)
        XCTAssertTrue(f.controller.canConfirm)
        f.controller.suspend(a)
        XCTAssertNil(f.controller.preview)
        XCTAssertNil(f.controller.selected)
        XCTAssertTrue(f.controller.targets.isEmpty)
        XCTAssertTrue(f.controller.acknowledgments.isEmpty)
        XCTAssertFalse(f.controller.canConfirm)
        XCTAssertNil(f.controller.offerLoad(a))
        XCTAssertNil(f.controller.offerConfirm(a))
        XCTAssertTrue(f.lease.isCurrent)
        await (try XCTUnwrap(f.controller.resume(a)))()
        XCTAssertEqual(f.controller.phase, .reviewing)
        XCTAssertNotNil(f.controller.preview)
        XCTAssertTrue(f.controller.acknowledgments.isEmpty)
        XCTAssertFalse(f.controller.canConfirm)
        XCTAssertEqual(f.wire.writes, 0)
    }

    func testQueuedDeclarationNeverDispatchesAndNotFoundRemainsOriginalUnknown() async throws {
        let f = try Fixture(), a = WorkshopCreatorConsentAppearance()
        try await f.load(a); try f.consent(a)
        let queued = try XCTUnwrap(f.controller.offerConfirm(a))
        let original = try XCTUnwrap(f.store.load()), bytes = f.memory.values
        f.controller.suspend(a)
        await queued()
        XCTAssertEqual(f.wire.writes, 0)
        XCTAssertEqual(f.memory.values, bytes)
        let count = f.wire.requests.count
        await (try XCTUnwrap(f.controller.resume(a)))()
        XCTAssertEqual(f.wire.requests.dropFirst(count).map { $0.url?.lastPathComponent }, ["status"])
        XCTAssertEqual(f.controller.phase, .failed)
        XCTAssertEqual(f.controller.issue, .unknown)
        XCTAssertNil(f.controller.preview)
        XCTAssertFalse(f.controller.canConfirm)
        XCTAssertEqual(try f.store.load()?.data(), try original.data())
        XCTAssertEqual(f.memory.values, bytes)
        XCTAssertEqual(f.wire.writes, 0)
        await queued()
        XCTAssertEqual(f.wire.writes, 0)
    }

    func testDispatchedOriginalRecoversReadOnlyAndLate401CannotRetireNewForeground() async throws {
        let f = try Fixture(), a = WorkshopCreatorConsentAppearance()
        try await f.load(a); try f.consent(a)
        f.wire.delay = true
        let action = try XCTUnwrap(f.controller.offerConfirm(a))
        let task = Task { await action() }; await f.wire.wait()
        let original = try XCTUnwrap(f.store.load()), bytes = f.memory.values
        XCTAssertEqual(f.wire.committed?.requestId, original.requestId)
        f.controller.suspend(a); f.write = nil
        let count = f.wire.requests.count
        await (try XCTUnwrap(f.controller.resume(a)))()
        XCTAssertEqual(f.wire.requests.dropFirst(count).map { $0.url?.lastPathComponent }, ["status"])
        XCTAssertEqual(f.controller.phase, .recorded)
        XCTAssertEqual(f.controller.pending?.requestId, original.requestId)
        XCTAssertNotNil(f.controller.receipt)
        f.wire.resume401(); await task.value
        XCTAssertEqual(f.controller.phase, .recorded)
        XCTAssertTrue(f.lease.isCurrent)
        XCTAssertEqual(f.unauthorized, 0)
        XCTAssertEqual(f.memory.values, bytes)
        XCTAssertEqual(f.wire.writes, 1)
    }

    func testRevokedSessionCannotResumeOrReadAndKeepsJournal() async throws {
        let f = try Fixture(), a = WorkshopCreatorConsentAppearance()
        try await f.load(a); try f.consent(a)
        _ = try XCTUnwrap(f.controller.offerConfirm(a))
        let bytes = f.memory.values, count = f.wire.requests.count
        f.controller.suspend(a); f.current = nil
        XCTAssertNil(f.controller.resume(a))
        XCTAssertEqual(f.controller.phase, .invalidated)
        XCTAssertEqual(f.memory.values, bytes)
        XCTAssertEqual(f.wire.requests.count, count)
        XCTAssertEqual(f.wire.writes, 0)
    }

    func testCloseAndOldAppearanceCannotResumeReplacement() async throws {
        let f = try Fixture(), old = WorkshopCreatorConsentAppearance()
        try await f.load(old); f.controller.suspend(old); f.controller.close(old)
        XCTAssertNil(f.controller.resume(old))
        let fresh = WorkshopCreatorConsentAppearance(); try await f.load(fresh)
        f.controller.suspend(old)
        XCTAssertNil(f.controller.resume(old))
        XCTAssertEqual(f.controller.phase, .reviewing)
        XCTAssertNotNil(f.controller.preview)
        XCTAssertEqual(f.wire.writes, 0)
    }

    func testInitiallyInactiveAppearanceCannotRunQueuedPreview() async throws {
        let f = try Fixture(), a = WorkshopCreatorConsentAppearance()
        let queued = try XCTUnwrap(f.controller.appear(a))
        f.controller.suspend(a); await queued()
        XCTAssertTrue(f.wire.requests.isEmpty)
        await (try XCTUnwrap(f.controller.resume(a)))()
        XCTAssertEqual(f.wire.requests.map { $0.url?.lastPathComponent }, ["preview"])
        XCTAssertEqual(f.controller.phase, .reviewing)
        XCTAssertNil(f.controller.resume(a))
        XCTAssertEqual(f.wire.writes, 0)
    }
}
