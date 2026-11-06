import Foundation
import XCTest
@testable import QuestifyCore

@MainActor final class NativeFriendDirectoryFlowTests: XCTestCase {
    private final class Service: NativeFriendDirectoryServing {
        var viewerID: Int64 = 2
        var authorized = true
        var expiresAt: Date = .distantFuture
        var isCurrent: Bool { get { authorized && Date() < expiresAt } set { authorized = newValue } }
        var detailCalls = 0
        var calls: [(NativeFriendDirectoryFilter, String?)] = []
        var failure: Error?
        var missingOnce = false
        var version = String(repeating: "a", count: 64)
        var peers: [Int64] = [9, 7]
        var pageHandler: ((NativeFriendDirectoryFilter, String?) async throws -> NativeFriendDirectoryPage)?
        var detailHandler: ((Int64) async throws -> NativeFriendDirectoryDetail)?
        var groups = NativeFriendMetadataGroups(viewerID: 2, list: [.init(id: nil, name: "default", position: 0, version: 0, isDefault: 1), .init(id: 4, name: "riders", position: 1, version: 1, isDefault: 0)])
        func item(_ peer: Int64, group: Int64? = nil, star: Int = 0) -> NativeFriendItem {
            .init(peerID: peer, nickname: "friend", state: .friend, version: 3, message: "", expiresAtMS: 0, groupID: group, starred: star)
        }
        func answer(_ filter: NativeFriendDirectoryFilter, cursor: String?) -> NativeFriendDirectoryPage {
            .init(viewerID: viewerID, section: filter.section, groupID: filter.groupID, starredOnly: filter.starredOnly, revision: version,
                  groups: groups, counts: ["all": peers.count, "recent": peers.count, "together": peers.count], total: peers.count,
                  items: cursor == nil ? peers.prefix(1).map { item($0, group: filter.groupID, star: filter.starredOnly ? 1 : 0) } : peers.dropFirst().map { item($0) },
                  hasMore: cursor == nil && peers.count > 1, nextCursor: cursor == nil && peers.count > 1 ? "cursor" : nil)
        }
        func page(filter: NativeFriendDirectoryFilter, cursor: String?) async throws -> NativeFriendDirectoryPage {
            calls.append((filter, cursor))
            if missingOnce { missingOnce = false; throw NativeFriendDirectoryFailure.missingGroup }
            if let pageHandler { return try await pageHandler(filter, cursor) }
            if let failure { throw failure }; return answer(filter, cursor: cursor)
        }
        func detail(peerID: Int64) async throws -> NativeFriendDirectoryDetail {
            detailCalls += 1
            if let detailHandler { return try await detailHandler(peerID) }
            if let failure { throw failure }
            return .init(viewerID: viewerID, item: item(peerID), conversationID: 80)
        }
    }
    func testOrdinaryOrderAndPaginationAreServerOrderNotNicknameSort() async {
        let service = Service(), flow = NativeFriendDirectoryFlow(service: nil)
        await flow.load(); XCTAssertEqual(flow.phase, .closed)
        let live = NativeFriendDirectoryFlow(service: service); await live.load(); await live.loadMore()
        XCTAssertEqual(live.items.map(\.peerID), [9, 7]); XCTAssertNil(live.nextCursor)
        XCTAssertEqual(service.calls.map { $0.1 }, [nil, "cursor"])
    }
    func testFiltersSurviveMetadataReturnAndReenterWithoutLocalFallback() async {
        let service = Service()
        let live = NativeFriendDirectoryFlow(service: service)
        let selected = NativeFriendDirectoryFilter(section: .recent, groupID: 4, starredOnly: true)
        await live.select(selected); live.invalidate(); service.peers = []; await live.load()
        XCTAssertEqual(live.filter, selected); XCTAssertEqual(live.items, []); XCTAssertEqual(live.phase, .ready)
        XCTAssertEqual(service.calls.last?.0, selected)
    }
    func testDeletedGroupResetsOnlyGroupAndRereadsWithExplanation() async {
        let service = Service(); service.missingOnce = true
        let flow = NativeFriendDirectoryFlow(service: service)
        await flow.select(.init(section: .together, groupID: 4, starredOnly: true))
        XCTAssertEqual(service.calls.count, 2); XCTAssertNil(flow.filter.groupID)
        XCTAssertEqual(flow.filter.section, .together); XCTAssertTrue(flow.filter.starredOnly)
        XCTAssertEqual(flow.issue, "friendDirectory.groupGone")
    }
    func testChangedRevisionRetiresAllOldPagesRatherThanMerging() async {
        let service = Service()
        let live = NativeFriendDirectoryFlow(service: service); await live.load()
        service.version = String(repeating: "b", count: 64); await live.loadMore()
        XCTAssertTrue(live.items.isEmpty); XCTAssertNil(live.nextCursor); XCTAssertEqual(live.issue, "friendDirectory.changed")
    }
    func testServerChangedResponseRetiresRemovedOrReaddedRows() async {
        let service = Service(); let flow = NativeFriendDirectoryFlow(service: service); await flow.load()
        service.failure = NativeFriendDirectoryFailure.changed; await flow.loadMore()
        XCTAssertTrue(flow.items.isEmpty); XCTAssertNil(flow.revision)
        service.failure = nil; service.peers = [11]; await flow.load(); XCTAssertEqual(flow.items.map(\.peerID), [11])
    }
    func testLateOldFilterResponseCannotOverwriteNewSelection() async {
        let service = Service(); let flow = NativeFriendDirectoryFlow(service: service)
        var suspended: CheckedContinuation<NativeFriendDirectoryPage, Error>?
        service.pageHandler = { filter, cursor in
            if filter.section == .all { return try await withCheckedThrowingContinuation { suspended = $0 } }
            return service.answer(filter, cursor: cursor)
        }
        let old = Task { await flow.load() }
        for _ in 0..<100 where suspended == nil { await Task.yield() }
        await flow.select(.init(section: .recent)); suspended?.resume(returning: service.answer(.init(), cursor: nil)); await old.value
        XCTAssertEqual(flow.filter.section, .recent); XCTAssertEqual(flow.phase, .ready)
    }
    func testAccountWithdrawalDuringReadPurgesEvenLateSuccessfulPayload() async {
        let service = Service(); let flow = NativeFriendDirectoryFlow(service: service)
        service.pageHandler = { filter, cursor in service.isCurrent = false; return service.answer(filter, cursor: cursor) }
        await flow.load(); XCTAssertTrue(flow.items.isEmpty); XCTAssertTrue(flow.groups.isEmpty); XCTAssertEqual(flow.phase, .closed)
    }
    func testDetailReentryAfterRemoveOrBlockClearsActionsAndChat() async {
        let service = Service(); let flow = NativeFriendDirectoryDetailFlow(peerID: 9, service: service)
        await flow.load(); XCTAssertTrue(flow.canOpen)
        service.failure = NativeFriendDirectoryFailure.unavailablePeer
        await flow.load(); XCTAssertNil(flow.detail); XCTAssertFalse(flow.canOpen)
        let conversation = await flow.existingConversation(); XCTAssertNil(conversation)
    }
    func testDetailCannotUseOtherAccountOrWrongPeer() async {
        let service = Service(); let flow = NativeFriendDirectoryDetailFlow(peerID: 9, service: service)
        service.detailHandler = { _ in .init(viewerID: 3, item: service.item(7), conversationID: 80) }
        await flow.load(); XCTAssertNil(flow.detail); XCTAssertFalse(flow.canOpen)
    }
    func testLeavingDetailDropsLateResponseAndReentryReadsAgain() async {
        let service = Service(); let flow = NativeFriendDirectoryDetailFlow(peerID: 9, service: service)
        var suspended: CheckedContinuation<NativeFriendDirectoryDetail, Error>?
        service.detailHandler = { _ in try await withCheckedThrowingContinuation { suspended = $0 } }
        let pending = Task { await flow.load() }
        for _ in 0..<100 where suspended == nil { await Task.yield() }
        flow.invalidate(); suspended?.resume(returning: .init(viewerID: 2, item: service.item(9), conversationID: 80)); await pending.value
        XCTAssertNil(flow.detail); XCTAssertFalse(flow.canOpen)
        service.detailHandler = nil; await flow.load(); XCTAssertTrue(flow.canOpen)
    }
    func testReadyRevocationImmediatelyGatesRowsAndAutomaticallyPublishesWithoutRead() async throws {
        let service = Service()
        let live = NativeFriendDirectoryFlow(service: service); await live.load()
        var retired = false
        live.onChange = { if live.phase == .closed { retired = true } }
        let calls = service.calls.count
        service.authorized = false
        // No reload, action or manual invalidation is needed for immediate read isolation.
        XCTAssertTrue(live.items.isEmpty); XCTAssertTrue(live.groups.isEmpty); XCTAssertTrue(live.counts.isEmpty)
        XCTAssertNil(live.revision); XCTAssertNil(live.nextCursor); XCTAssertEqual(live.phase, .closed)
        for _ in 0..<100 where !retired { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertTrue(retired); XCTAssertEqual(service.calls.count, calls)
        service.authorized = true // A withdrawn issuance never revives, even if the callback changes back.
        await live.load(); XCTAssertEqual(live.phase, .closed); XCTAssertEqual(service.calls.count, calls)
        live.onChange = nil
    }
    func testReadyLeaseExpiryPurgesDirectoryAndDetailWithoutPollingServer() async throws {
        let service = Service()
        let live = NativeFriendDirectoryFlow(service: service), detail = NativeFriendDirectoryDetailFlow(peerID: 9, service: service)
        await live.load(); await detail.load()
        var changes = 0, detailChanges = 0
        live.onChange = { changes += 1 }; detail.onChange = { detailChanges += 1 }
        let calls = service.calls.count, detailCalls = service.detailCalls
        service.expiresAt = Date().addingTimeInterval(0.03)
        try await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertTrue(live.items.isEmpty); XCTAssertNil(detail.detail); XCTAssertFalse(detail.canOpen)
        for _ in 0..<100 where changes == 0 || detailChanges == 0 { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertGreaterThan(changes, 0); XCTAssertGreaterThan(detailChanges, 0)
        XCTAssertEqual(service.calls.count, calls); XCTAssertEqual(service.detailCalls, detailCalls)
    }
    func testRevokedLoadMoreClearsInsteadOfReturningWithCachedPrivateData() async {
        let service = Service()
        let live = NativeFriendDirectoryFlow(service: service); await live.load()
        let calls = service.calls.count; service.authorized = false; await live.loadMore()
        XCTAssertTrue(live.items.isEmpty); XCTAssertTrue(live.groups.isEmpty); XCTAssertEqual(live.phase, .closed)
        service.authorized = true
        XCTAssertTrue(live.items.isEmpty); XCTAssertEqual(service.calls.count, calls)
    }
    func testRevocationDuringHeldDetailCannotRestoreDataOrChatAfterAutomaticRetirement() async throws {
        let service = Service()
        let live = NativeFriendDirectoryDetailFlow(peerID: 9, service: service)
        var held: CheckedContinuation<NativeFriendDirectoryDetail, Error>?
        service.detailHandler = { _ in try await withCheckedThrowingContinuation { held = $0 } }
        let pending = Task { await live.load() }
        for _ in 0..<100 where held == nil { await Task.yield() }
        service.authorized = false
        try await Task.sleep(nanoseconds: 300_000_000)
        held?.resume(returning: .init(viewerID: 2, item: service.item(9), conversationID: 80))
        await pending.value; XCTAssertNil(live.detail); XCTAssertFalse(live.canOpen)
        let calls = service.detailCalls; let chat = await live.existingConversation()
        XCTAssertNil(chat); XCTAssertEqual(service.detailCalls, calls)
    }

    func testPageFailureRetriesSameCursorWithoutDroppingLoadedFriendsOrFilter() async {
        let service = Service(), flow = NativeFriendDirectoryFlow(service: nil)
        await flow.retry(); XCTAssertEqual(flow.phase, .closed)
        let live = NativeFriendDirectoryFlow(service: service)
        let filter = NativeFriendDirectoryFilter(section: .recent, groupID: 4, starredOnly: true)
        await live.select(filter)
        service.failure = URLError(.timedOut); await live.loadMore()
        XCTAssertEqual(live.items.map(\.peerID), [9]); XCTAssertEqual(live.nextCursor, "cursor")
        XCTAssertTrue(live.paginationFailed); XCTAssertEqual(live.phase, .ready)
        service.failure = nil; await live.retry()
        XCTAssertEqual(service.calls.map { $0.1 }, [nil, "cursor", "cursor"])
        XCTAssertEqual(live.items.map(\.peerID), [9, 7]); XCTAssertEqual(live.filter, filter)
        XCTAssertFalse(live.paginationFailed); XCTAssertNil(live.issue)
    }
    func testDirectoryReadUnavailableClearsPrivateSnapshotButDoesNotInferRelationshipDeletion() async {
        let service = Service(), live = NativeFriendDirectoryFlow(service: nil)
        await live.load()
        let flow = NativeFriendDirectoryFlow(service: service)
        let filter = NativeFriendDirectoryFilter(section: .recent, starredOnly: true)
        await flow.select(filter)
        service.failure = NativeFriendDirectoryFailure.readUnavailable; await flow.loadMore()
        XCTAssertTrue(flow.items.isEmpty); XCTAssertTrue(flow.groups.isEmpty); XCTAssertTrue(flow.counts.isEmpty)
        XCTAssertNil(flow.nextCursor); XCTAssertNil(flow.revision); XCTAssertEqual(flow.phase, .failed)
        XCTAssertFalse(flow.paginationFailed); XCTAssertTrue(flow.isCurrent); XCTAssertEqual(flow.filter, filter)
        XCTAssertEqual(flow.issue, "friendDirectory.readUnavailable")
        service.failure = nil; await flow.retry()
        XCTAssertNil(service.calls.last?.1); XCTAssertEqual(flow.items.map(\.peerID), [9]); XCTAssertEqual(flow.phase, .ready)
    }
    func testSupersededConversationReadCannotBorrowNewerSuccessfulDetail() async {
        let service = Service(), flow = NativeFriendDirectoryDetailFlow(peerID: 9, service: nil)
        let unavailable = await flow.currentFriend(); XCTAssertNil(unavailable)
        let detail = NativeFriendDirectoryDetailFlow(peerID: 9, service: service)
        var held: CheckedContinuation<NativeFriendDirectoryDetail, Error>?
        service.detailHandler = { _ in try await withCheckedThrowingContinuation { held = $0 } }
        let old = Task { await detail.existingConversation() }
        for _ in 0..<100 where held == nil { await Task.yield() }
        service.detailHandler = nil; await detail.load()
        held?.resume(returning: .init(viewerID: 2, item: service.item(9), conversationID: 90))
        let result = await old.value
        XCTAssertNil(result); XCTAssertEqual(detail.detail?.conversationID, 80)
    }
    func testCancelledProfileReadCannotReturnPeerAfterLeavingDetail() async {
        let service = Service(), detail = NativeFriendDirectoryDetailFlow(peerID: 9, service: nil)
        await detail.load()
        let flow = NativeFriendDirectoryDetailFlow(peerID: 9, service: service)
        var held: CheckedContinuation<NativeFriendDirectoryDetail, Error>?
        service.detailHandler = { _ in try await withCheckedThrowingContinuation { held = $0 } }
        let pending = Task { await flow.currentFriend() }
        for _ in 0..<100 where held == nil { await Task.yield() }
        flow.invalidate(); held?.resume(returning: .init(viewerID: 2, item: service.item(9), conversationID: 80))
        let result = await pending.value
        XCTAssertNil(result); XCTAssertNil(flow.detail)
    }

}
