import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor private final class NativeChannelProgressQueuedDispatcher: NativeChannelProgressDispatching {
    var forwarded = 0
    private var queued = false
    private var queuedWaiter: CheckedContinuation<Void,Never>?
    private var forwardWaiter: CheckedContinuation<Void,Never>?
    func send(_ request: URLRequest, fence: NativeChannelProgressDispatchFence) async throws -> (Data,Int) {
        queued = true; queuedWaiter?.resume(); queuedWaiter = nil
        await withCheckedContinuation { forwardWaiter = $0 }
        guard fence.isCurrent else { throw NativeChannelProgressError.closed }
        forwarded += 1
        return (Data(#"{"code":200,"data":{"visible":true,"list":[]}}"#.utf8),200)
    }
    func waitUntilQueued() async { if !queued { await withCheckedContinuation { queuedWaiter = $0 } } }
    func release() { forwardWaiter?.resume(); forwardWaiter = nil }
}
final class NativeChannelProgressAuthorityTests: XCTestCase {
    @MainActor func testRevocationAtActualForwardPreventsNetwork() async throws {
        let captured = try NativeChannelProgressFixtures.authority(), dispatcher = NativeChannelProgressQueuedDispatcher()
        var current: NativeChannelProgressAuthoritySnapshot? = captured
        let client = try NativeChannelProgressClient(captured: captured, dispatcher: dispatcher, current: { current }, token: { "test-token" }, onUnauthorized: {})
        let request = Task { try await client.definitions() }
        await dispatcher.waitUntilQueued(); current = nil; dispatcher.release()
        do { _ = try await request.value; XCTFail("A retired authority forwarded") } catch { XCTAssertEqual(error as? NativeChannelProgressError, .closed) }
        XCTAssertEqual(dispatcher.forwarded, 0)
    }
    @MainActor func testViewRetirementCancelsQueuedOriginalForward() async throws {
        let captured = try NativeChannelProgressFixtures.authority(), dispatcher = NativeChannelProgressQueuedDispatcher()
        let client = try NativeChannelProgressClient(captured: captured, dispatcher: dispatcher, current: { captured }, token: { "test-token" }, onUnauthorized: {})
        let request = Task { try await client.definitions() }
        await dispatcher.waitUntilQueued(); client.retireOperations(); dispatcher.release()
        do { _ = try await request.value; XCTFail("A retired operation forwarded") } catch { XCTAssertEqual(error as? NativeChannelProgressError, .closed) }
        XCTAssertEqual(dispatcher.forwarded, 0)
    }
    func testOwnPrivacyAuthorityCannotGrantBoardOperationsWithoutChannel() throws {
        XCTAssertThrowsError(try NativeChannelProgressAuthoritySnapshot(identity: NativeChannelProgressFixtures.identity(), channelID: nil,
            authorizationVersion: "own-privacy-v1", metadataVersion: nil, permissionVersion: nil, endpointApprovalRevision: UUID(), viewerRevision: 3, operations: [.top]))
    }
}
