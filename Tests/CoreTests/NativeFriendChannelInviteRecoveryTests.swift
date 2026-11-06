import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class NativeFriendChannelInviteRecoveryTests: XCTestCase {
    private func flow(_ wire: ChannelRecoveryWire, _ storage: ChannelRecoveryStorage, owner: String,
                      mode: NativeFriendChannelInviteMode = .mine, writes: Bool = false) throws -> NativeFriendChannelInviteFlow {
        let context = RuntimeDependencyContext(market: .china, baseURL: URL(string: "https://channel-invite.example.com/")!, role: "player",
            session: try .init(accountID: 2, epoch: 1, namespace: "fixture", token: "fixture-token", role: "player"))
        let approval = try NativeFriendChannelInviteApproval(endpoint: .init(baseURL: context.baseURL, namespace: "fixture", accountID: 2,
            paths: writes ? NativeFriendChannelInviteApproval.reads.union(NativeFriendChannelInviteApproval.writes) : NativeFriendChannelInviteApproval.reads),
            mode: mode, expiresAt: Date().addingTimeInterval(600))
        return NativeFriendChannelInviteFlow(service: try .init(context: context, approval: approval, transport: wire, current: { true }, unauthorized: {}),
            journal: .init(storage: storage, ownerKey: owner))
    }

    func testCorruptOriginalSurvivesRefreshAndReopensForExplicitReadOnlyRecovery() async throws {
        let storage = ChannelRecoveryStorage(), wire = ChannelRecoveryWire(), owner = UUID().uuidString
        let journal = NativeFriendChannelInviteJournal(storage: storage, ownerKey: owner)
        let command = try NativeFriendChannelInviteCommand(action: "REVOKE", objectID: 42)
        try journal.save(command)
        let original = storage.rows, key = try XCTUnwrap(storage.rows.keys.first)
        storage.rows[key] = Data("corrupt".utf8); let corrupt = storage.rows
        storage.writes = 0; storage.removes = 0
        let first = try flow(wire, storage, owner: owner, writes: true)
        await first.activate(); await first.refresh()
        XCTAssertEqual(first.issue, "原请求保护记录暂不可确认，不发送新操作。")
        XCTAssertFalse(first.canWrite); XCTAssertFalse(first.canRecover)
        await first.confirm(); await first.recover()
        XCTAssertEqual(storage.rows, corrupt); XCTAssertEqual(storage.writes, 0); XCTAssertEqual(storage.removes, 0)
        storage.rows = original; await first.refresh()
        XCTAssertFalse(first.canWrite); XCTAssertFalse(first.canRecover)
        first.deactivate(); XCTAssertNil(first.issue)
        let reopened = try flow(wire, storage, owner: owner)
        await reopened.activate()
        XCTAssertEqual(reopened.pending, command); XCTAssertTrue(reopened.canRecover); XCTAssertNil(reopened.issue)
        wire.receipt = ["viewer_id": 2, "request_id": command.requestID, "outcome": "UNKNOWN"]
        await reopened.recover(); XCTAssertEqual(storage.rows, original); XCTAssertEqual(reopened.pending, command)
        wire.receipt = ["viewer_id": 2, "request_id": command.requestID, "outcome": "REJECTED", "action": command.action,
                        "object_id": String(command.objectID), "payload_hash": command.proof, "error_code": "FRIEND_INVITE_REJECTED"]
        await reopened.recover()
        XCTAssertNil(reopened.pending); XCTAssertNil(try journal.restore()); XCTAssertEqual(storage.removes, 1)
        XCTAssertEqual(reopened.receipt?.outcome, "REJECTED"); XCTAssertFalse(reopened.canWrite)
        XCTAssertTrue(wire.requests.allSatisfy { $0.httpMethod == "GET" })
        let reads = wire.requests.filter { $0.url?.path.hasSuffix("/receipt") == true }
        XCTAssertEqual(reads.count, 2)
        XCTAssertTrue(reads.allSatisfy { URLComponents(url: $0.url!, resolvingAgainstBaseURL: false)?.queryItems == [.init(name: "request_id", value: command.requestID)] })
        reopened.deactivate()
    }

    func testFailedSaveKeepsAccurateNotSentWarningAfterSuccessfulPickerRefresh() async throws {
        let storage = ChannelRecoveryStorage(), wire = ChannelRecoveryWire()
        let current = try flow(wire, storage, owner: UUID().uuidString, mode: .channel(42), writes: true)
        await current.activate()
        current.toggle(try XCTUnwrap(current.items.first)); current.prepareCreate()
        XCTAssertNotNil(current.review)
        storage.failWrite = true; await current.confirm(); await current.refresh()
        XCTAssertEqual(current.issue, "原请求未能可靠保存，本次未发送。")
        XCTAssertFalse(current.items.isEmpty); XCTAssertFalse(current.canWrite); XCTAssertFalse(current.canRecover)
        XCTAssertNil(current.review); XCTAssertTrue(storage.rows.isEmpty); XCTAssertEqual(storage.removes, 0)
        XCTAssertTrue(wire.requests.allSatisfy { $0.httpMethod == "GET" })
        current.deactivate(); XCTAssertNil(current.issue)
    }
}

@MainActor private final class ChannelRecoveryStorage: ProjectEditDataStorage {
    var rows: [String: Data] = [:]
    var writes = 0, removes = 0
    var failWrite = false
    func read(_ key: String) throws -> Data? { rows[key] }
    func write(_ data: Data, key: String) throws {
        if failWrite { throw NativeFriendFailure.invalid }
        writes += 1; rows[key] = data
    }
    func remove(_ key: String) throws { removes += 1; rows[key] = nil }
}
@MainActor private final class ChannelRecoveryWire: HTTPTransport {
    var requests: [URLRequest] = []
    var receipt: [String: Any] = [:]
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        let data: [String: Any]
        if request.url?.path.hasSuffix("/mine") == true {
            data = ["viewer_id": 2, "items": [], "next_before": "0"]
        } else if request.url?.path.hasSuffix("/picker") == true {
            data = ["viewer_id": 2, "channel_id": "42", "guild_id": "7", "guild_kind": 1, "name": "Fixture channel",
                    "section": "all", "starred_only": false, "revision": String(repeating: "a", count: 64),
                    "total": 1, "has_more": false, "counts": ["all": 1],
                    "groups": ["viewer_id": 2, "list": [["id": 0, "name": "Default", "position": 0, "version": 0, "is_default": 1]]],
                    "items": [["peer_id": 9, "nickname": "Fixture friend", "state": 1, "version": 3, "msg": "", "expires_at_ms": 0, "already_member": false]]]
        } else { data = receipt }
        return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": data]), 200)
    }
}
