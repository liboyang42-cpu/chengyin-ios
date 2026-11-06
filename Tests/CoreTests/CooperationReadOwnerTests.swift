import XCTest
@testable import QuestifyCore

@MainActor final class CooperationReadOwnerTests: XCTestCase {
    private final class Reader: CooperationReading {
        var isConfigured = true
        var isAuthenticated = true
        var isOfflineExample = false
        var scope = UUID()
        func inbox(direction: CooperationDirection) async throws -> CooperationInbox { throw APIError.invalidRequest }
        func detail(key: CooperationInviteKey) async throws -> CooperationInviteDetail { throw APIError.invalidRequest }
        func pool() async throws -> CooperationPool { throw APIError.invalidRequest }
        func candidates(topicID: Int) async throws -> CooperationCandidates { throw APIError.invalidRequest }
    }
    private func owner(_ reader: Reader, _ resource: String = "inbox.received") -> CooperationReadOwner {
        CooperationReadOwner(reader: reader, resource: resource)
    }
    func testDirectionAndReaderReplacementHideRowsBeforeNextLoad() async throws {
        let reader = Reader(), other = Reader(), model = CooperationReadModel<String>()
        other.scope = reader.scope
        let received = owner(reader), sent = owner(reader, "inbox.sent")
        let permit = try XCTUnwrap(model.beginPresentation(owner: received))
        await model.load(presentation: permit, currentOwner: { received }) { "received-only" }
        XCTAssertEqual(model.visibleValue(owner: received), "received-only")
        XCTAssertNil(model.visibleValue(owner: sent))
        XCTAssertNil(model.visibleValue(owner: owner(other)))
        XCTAssertFalse(model.accepts(permit, currentOwner: sent))
    }
    func testRetiredQueuedLoadCannotDispatchOrEraseNewResult() async throws {
        let reader = Reader(), model = CooperationReadModel<String>()
        let current = owner(reader)
        let old = try XCTUnwrap(model.beginPresentation(owner: current))
        model.endPresentation()
        let fresh = try XCTUnwrap(model.beginPresentation(owner: current))
        await model.load(presentation: fresh, currentOwner: { current }) { "new" }
        var dispatched = false
        await model.load(presentation: old, currentOwner: { current }) { dispatched = true; return "old" }
        XCTAssertFalse(dispatched)
        XCTAssertEqual(model.visibleValue(owner: current), "new")
    }
    func testInFlightOldDirectionCannotReplaceNewDirection() async throws {
        let reader = Reader(), model = CooperationReadModel<String>()
        var current = owner(reader)
        let old = try XCTUnwrap(model.beginPresentation(owner: current))
        var pending: CheckedContinuation<String, Never>?
        let task = Task { await model.load(presentation: old, currentOwner: { current }) {
            await withCheckedContinuation { pending = $0 }
        } }
        for _ in 0..<2000 { if pending != nil { break }; await Task.yield() }
        let continuation = try XCTUnwrap(pending)
        current = owner(reader, "inbox.sent")
        let next = try XCTUnwrap(model.beginPresentation(owner: current))
        await model.load(presentation: next, currentOwner: { current }) { "sent" }
        continuation.resume(returning: "received"); await task.value
        XCTAssertEqual(model.visibleValue(owner: current), "sent")
        XCTAssertFalse(model.isLoading)
    }
    func testRetiredFailureCannotExposeIssueOnNewTarget() async throws {
        let reader = Reader(), model = CooperationReadModel<String>()
        let current = owner(reader)
        let old = try XCTUnwrap(model.beginPresentation(owner: current))
        model.endPresentation(preservingValues: false)
        let fresh = try XCTUnwrap(model.beginPresentation(owner: current))
        await model.load(presentation: fresh, currentOwner: { current }) { "new" }
        var called = false
        await model.load(presentation: old, currentOwner: { current }) {
            called = true; throw CooperationReadFailure.forbidden(message: "old")
        }
        XCTAssertFalse(called); XCTAssertNil(model.visibleIssue(owner: current))
        XCTAssertEqual(model.visibleValue(owner: current), "new")
    }
    func testGuestAndUnavailableOwnersNeverDispatch() async {
        let reader = Reader(), model = CooperationReadModel<String>()
        reader.isAuthenticated = false
        XCTAssertNil(model.beginPresentation(owner: owner(reader)))
        reader.isAuthenticated = true; reader.isConfigured = false
        XCTAssertNil(model.beginPresentation(owner: owner(reader)))
        reader.isConfigured = true
        XCTAssertNil(model.beginPresentation(owner: owner(reader, "")))
    }
    func testRevocationMasksRowsAndRejectsOldPermit() async throws {
        let reader = Reader(), model = CooperationReadModel<String>()
        let granted = owner(reader)
        let permit = try XCTUnwrap(model.beginPresentation(owner: granted))
        await model.load(presentation: permit, currentOwner: { self.owner(reader) }) { "private" }
        reader.isAuthenticated = false
        XCTAssertNil(model.visibleValue(owner: owner(reader)))
        XCTAssertFalse(model.accepts(permit, currentOwner: owner(reader)))
        model.endPresentation(preservingValues: false)
        XCTAssertNil(model.value)
    }
    func testSameOwnerNavigationPreservesRowsButRetiresPendingPermit() async throws {
        let reader = Reader(), model = CooperationReadModel<String>()
        let key = owner(reader)
        let permit = try XCTUnwrap(model.beginPresentation(owner: key))
        await model.load(presentation: permit, currentOwner: { key }) { "rows" }
        model.endPresentation()
        XCTAssertEqual(model.visibleValue(owner: key), "rows")
        XCTAssertFalse(model.accepts(permit, currentOwner: key))
        let returned = try XCTUnwrap(model.beginPresentation(owner: key))
        XCTAssertNotEqual(returned, permit)
    }
    func testCurrentForbiddenClearsRowsWithoutChangingReaderAuthority() async throws {
        let reader = Reader(), model = CooperationReadModel<String>()
        let key = owner(reader), permit = try XCTUnwrap(model.beginPresentation(owner: owner(reader)))
        await model.load(presentation: permit, currentOwner: { key }) { "private" }
        await model.load(presentation: permit, currentOwner: { key }) { throw CooperationReadFailure.forbidden(message: "Denied") }
        XCTAssertEqual(model.visibleIssue(owner: key), .forbidden("Denied"))
        XCTAssertTrue(reader.isAuthenticated)
    }
}
