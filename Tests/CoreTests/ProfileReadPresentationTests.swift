import XCTest
@testable import QuestifyCore

private final class ProfilePresentationSource {}
private enum ProfilePresentationTestError: Error { case failed }

@MainActor final class ProfileReadPresentationTests: XCTestCase {
    private func owner(_ source: ProfilePresentationSource, account: Int = 7, epoch: UInt64 = 1,
                       viewer: UInt64 = 1, approval: UUID? = nil, configured: Bool = true,
                       surface: String = "profile.order.detail", id: Int? = 1) -> ProfileReadPresentationOwner {
        .init(reader: source, identity: .init(accountID: account, epoch: epoch, viewerRevision: viewer, approvalRevision: approval),
              configured: configured, surface: surface, requestID: id)
    }
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<10_000 { if condition() { return }; await Task.yield() }
        throw ProfilePresentationTestError.failed
    }
    func testInactiveQueuedReadCannotDispatch() async throws {
        let source = ProfilePresentationSource(), model = ProfileReadPresentation<String>()
        let key = owner(source)
        var calls = 0
        await model.load(owner: key, currentOwner: { key }) { calls += 1; return "private" }
        XCTAssertEqual(calls, 0)
        let valid = owner(source); model.activate(owner: valid, source: source); model.suspend()
        await model.load(owner: valid, currentOwner: { valid }) { calls += 1; return "private" }
        XCTAssertEqual(calls, 0)
    }
    func testAcceptedListSurvivesPushButNewAppearanceReadsFreshValue() async throws {
        let source = ProfilePresentationSource(), model = ProfileReadPresentation<[Int]>()
        let list = owner(source, surface: "profile.orders", id: nil)
        model.activate(owner: list, source: source)
        await model.load(owner: list, currentOwner: { list }) { [1, 2] }
        model.suspend()
        XCTAssertEqual(model.snapshot(for: list).value, [1, 2]); XCTAssertFalse(model.snapshot(for: list).isLoading)
        model.activate(owner: list, source: source); XCTAssertNil(model.snapshot(for: list).value)
        await model.load(owner: list, currentOwner: { list }) { [3] }
        XCTAssertEqual(model.snapshot(for: list).value, [3])
    }
    func testEveryOwnerDimensionMasksContentErrorAndLoadingBeforeTask() async throws {
        let source = ProfilePresentationSource(), replacement = ProfilePresentationSource(), model = ProfileReadPresentation<String>()
        let approval = UUID(), key = owner(source, approval: approval)
        model.activate(owner: key, source: source)
        await model.load(owner: key, currentOwner: { key }) { "owned detail" }
        let others = [owner(replacement, approval: approval), owner(source, account: 8, approval: approval),
                      owner(source, epoch: 2, approval: approval), owner(source, viewer: 2, approval: approval),
                      owner(source, approval: UUID()), owner(source, approval: approval, configured: false),
                      owner(source, approval: approval, surface: "other"), owner(source, approval: approval, id: 2)]
        for current in others {
            let value = model.snapshot(for: current)
            XCTAssertNil(value.value); XCTAssertNil(value.error); XCTAssertFalse(value.isLoading); XCTAssertFalse(value.started)
        }
        await model.load(owner: key, currentOwner: { key }) { throw ProfilePresentationTestError.failed }
        for current in others { XCTAssertNil(model.snapshot(for: current).error) }
    }
    func testRequestIDChangesRejectOldSuccessBeforeNewActivation() async throws {
        let source = ProfilePresentationSource(), model = ProfileReadPresentation<String>()
        let first = owner(source, id: 1); var current = first
        var pending: CheckedContinuation<String, Error>?
        model.activate(owner: first, source: source)
        let old = Task { await model.load(owner: first, currentOwner: { current }) { try await withCheckedThrowingContinuation { pending = $0 } } }
        try await waitUntil { pending != nil }; current = owner(source, id: 2)
        pending!.resume(returning: "order one"); await old.value
        XCTAssertNil(model.snapshot(for: current).value)
        model.activate(owner: current, source: source)
        await model.load(owner: current, currentOwner: { current }) { "order two" }
        XCTAssertEqual(model.snapshot(for: current).value, "order two")
    }
    func testReaderReplacementSameIdentityRejectsLateError() async throws {
        let source = ProfilePresentationSource(), replacement = ProfilePresentationSource(), model = ProfileReadPresentation<String>()
        let first = owner(source), second = owner(replacement)
        var pending: CheckedContinuation<String, Error>?
        model.activate(owner: first, source: source)
        let old = Task { await model.load(owner: first, currentOwner: { first }) { try await withCheckedThrowingContinuation { pending = $0 } } }
        try await waitUntil { pending != nil }
        model.activate(owner: second, source: replacement)
        await model.load(owner: second, currentOwner: { second }) { "fresh" }
        pending!.resume(throwing: ProfilePresentationTestError.failed); await old.value
        XCTAssertEqual(model.snapshot(for: second).value, "fresh"); XCTAssertNil(model.snapshot(for: second).error)
    }
    func testRevocationDuringReadDiscardsResultAndDoesNotGrantAccess() async throws {
        let source = ProfilePresentationSource(), model = ProfileReadPresentation<String>()
        let first = owner(source); var current = first; var calls = 0
        model.activate(owner: first, source: source)
        await model.load(owner: first, currentOwner: { current }) {
            calls += 1; current = self.owner(source, configured: false); return "retired"
        }
        XCTAssertNil(model.snapshot(for: current).value)
        model.activate(owner: current, source: source)
        await model.load(owner: current, currentOwner: { current }) { calls += 1; return "forbidden" }
        XCTAssertEqual(calls, 1)
    }
    func testGuestAndInvalidOwnerNeverDispatchOperation() async throws {
        let source = ProfilePresentationSource(), model = ProfileReadPresentation<String>()
        let guest = ProfileReadPresentationOwner(reader: source, identity: nil, configured: true, surface: "profile.orders")
        var calls = 0
        for key in [guest, owner(source, account: 0), owner(source, configured: false)] {
            model.activate(owner: key, source: source)
            await model.load(owner: key, currentOwner: { key }) { calls += 1; return "private" }
            }
        XCTAssertEqual(calls, 0)
    }
    func testOverlappingRefreshLateSuccessDoesNotClearNewLoading() async throws {
        let source = ProfilePresentationSource(), model = ProfileReadPresentation<String>()
        let current = owner(source); var pending: [CheckedContinuation<String, Error>] = []
        model.activate(owner: current, source: source)
        let old = Task { await model.load(owner: current, currentOwner: { current }) { try await withCheckedThrowingContinuation { pending.append($0) } } }
        try await waitUntil { pending.count == 1 }
        let fresh = Task { await model.load(owner: current, currentOwner: { current }) { try await withCheckedThrowingContinuation { pending.append($0) } } }
        try await waitUntil { pending.count == 2 }
        pending[0].resume(returning: "old"); await old.value
        XCTAssertTrue(model.snapshot(for: current).isLoading)
        pending[1].resume(returning: "fresh"); await fresh.value
        XCTAssertEqual(model.snapshot(for: current).value, "fresh")
    }
    func testFailedRefreshClearsOldDetailAndRetryRecovers() async throws {
        let source = ProfilePresentationSource(), model = ProfileReadPresentation<String>()
        let current = owner(source); model.activate(owner: current, source: source)
        await model.load(owner: current, currentOwner: { current }) { "before" }
        await model.load(owner: current, currentOwner: { current }) { throw ProfilePresentationTestError.failed }
        XCTAssertNil(model.snapshot(for: current).value); XCTAssertNotNil(model.snapshot(for: current).error)
        await model.load(owner: current, currentOwner: { current }) { "after" }
        XCTAssertEqual(model.snapshot(for: current).value, "after"); XCTAssertNil(model.snapshot(for: current).error)
    }
    func testSuspensionAndReentryRejectOldCompletionWithoutRemovingAcceptedNewValue() async throws {
        let source = ProfilePresentationSource(), model = ProfileReadPresentation<String>()
        let key = owner(source); var pending: CheckedContinuation<String, Error>?
        model.activate(owner: key, source: source)
        let old = Task { await model.load(owner: key, currentOwner: { key }) { try await withCheckedThrowingContinuation { pending = $0 } } }
        try await waitUntil { pending != nil }; model.suspend()
        model.activate(owner: key, source: source)
        await model.load(owner: key, currentOwner: { key }) { "new" }
        pending!.resume(returning: "old"); await old.value
        XCTAssertEqual(model.snapshot(for: key).value, "new")
    }
    func testCancelledOperationDoesNotBecomeFailureAndExplicitRetryWorks() async throws {
        let source = ProfilePresentationSource(), model = ProfileReadPresentation<String>()
        let current = owner(source); var pending: CheckedContinuation<String, Error>?
        model.activate(owner: current, source: source)
        let task = Task { await model.load(owner: current, currentOwner: { current }) { try await withCheckedThrowingContinuation { pending = $0 } } }
        try await waitUntil { pending != nil }; task.cancel(); pending!.resume(returning: "cancelled"); await task.value
        XCTAssertFalse(model.snapshot(for: current).isLoading); XCTAssertNil(model.snapshot(for: current).error)
        await model.load(owner: current, currentOwner: { current }) { "retried" }
        XCTAssertEqual(model.snapshot(for: current).value, "retried")
    }
}
