import XCTest
import Foundation
import CryptoKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

/// Synthetic original-request/secure-storage coverage; never sends business HTTP.
@MainActor final class NativeFriendTeamInviteRecoveryTests: XCTestCase {
    private let offerID = "01234567-89ab-cdef-0123-456789abcdef"

    private func command(_ action: String = "FRIEND_OFFER", team: Int64 = 42) throws -> NativeFriendTeamInviteCommand {
        if action == "FRIEND_OFFER" {
            return try .init(action: action, body: .init(teamId: team, peers: [.init(id: 9, version: 3)]))
        }
        return try .init(action: action, body: .init(teamId: team, offerId: offerID, joinMode: action == "FRIEND_CONFIRM" ? 2 : nil))
    }
    private func receipt(_ command: NativeFriendTeamInviteCommand, outcome: String = "APPLIED") -> [String: Any] {
        var value: [String: Any] = ["contract": "ORIGINAL_TEAM_REQUEST_V1", "outcome": outcome, "requestId": command.requestID]
        if outcome != "UNKNOWN" {
            value.merge(["action": command.action, "teamId": command.teamID, "targetKey": "friend-offer:\(command.teamID)",
                         "requestFingerprint": command.fingerprint]) { _, right in right }
            if outcome == "REJECTED" { value["errorCode"] = "TEAM_OFFER_UNAVAILABLE" }
        }
        return value
    }
    private func service(_ wire: InviteRecoveryWire, mode: NativeFriendTeamInviteMode = .mine,
                         writes: Bool = false, current: @escaping () -> Bool = { true }) throws -> NativeFriendTeamInviteService {
        let context = RuntimeDependencyContext(market: .china, baseURL: URL(string: "https://friend-invite.example.com/")!, role: "player",
            session: try .init(accountID: 2, epoch: 1, namespace: "fixture", token: "fixture-token", role: "player"))
        let approval = try NativeFriendTeamInviteApproval(endpoint: .init(baseURL: context.baseURL, namespace: "fixture", accountID: 2,
            paths: NativeFriendTeamInviteApproval.paths), mode: mode, allowWrites: writes, expiresAt: Date().addingTimeInterval(600))
        return try .init(context: context, approval: approval, transport: wire, current: current, unauthorized: {})
    }
    private func legacyStorage(_ command: NativeFriendTeamInviteCommand, owner: String) throws -> InviteRecoveryStorage {
        // Construct the shipped v1 envelope independently; do not migrate, rewrite or mint a request ID.
        let storage = InviteRecoveryStorage()
        let key = "friend-team-invite.intent.v1." + SHA256.hash(data: Data(owner.utf8)).map { String(format: "%02x", $0) }.joined()
        let encodedCommand = try JSONSerialization.jsonObject(with: JSONEncoder().encode(command))
        storage.rows[key] = try JSONSerialization.data(withJSONObject: ["schema": 1, "owner": owner,
            "proof": command.fingerprint, "command": encodedCommand], options: [.sortedKeys])
        return storage
    }

    func testExactOriginalTerminalReceiptsAcceptedForAllActionsOnWriteAndRead() async throws {
        for action in ["FRIEND_OFFER", "FRIEND_CONFIRM", "FRIEND_DECLINE", "FRIEND_REVOKE"] {
            for outcome in ["APPLIED", "REJECTED"] {
                let command = try command(action)
                let wire = InviteRecoveryWire(); wire.response = receipt(command, outcome: outcome)
                let mode: NativeFriendTeamInviteMode = action == "FRIEND_OFFER" ? .team(command.teamID) : .offer(offerID)
                let service = try service(wire, mode: mode, writes: true)
                let written = try await service.write(command)
                let recovered = try await service.recover(command)
                XCTAssertEqual(written.outcome, outcome); XCTAssertEqual(recovered.outcome, outcome)
                XCTAssertEqual(wire.requests.map(\.httpMethod), ["POST", "GET"])
                XCTAssertEqual(wire.requests.first?.httpBody, command.raw)
                XCTAssertNil(wire.requests.last?.httpBody)
                let query = URLComponents(url: try XCTUnwrap(wire.requests.last?.url), resolvingAgainstBaseURL: false)?.queryItems
                XCTAssertEqual(query, [URLQueryItem(name: "requestId", value: command.requestID)])
                XCTAssertEqual(recovered.targetKey, "friend-offer:42")
            }
        }
    }

    func testExistingV1PendingResolvesReadOnlyForEachOriginalTerminalOutcome() async throws {
        for action in ["FRIEND_OFFER", "FRIEND_CONFIRM", "FRIEND_DECLINE", "FRIEND_REVOKE"] {
            for outcome in ["APPLIED", "REJECTED"] {
                let command = try command(action), owner = UUID().uuidString
                let storage = try legacyStorage(command, owner: owner), originalBytes = storage.rows
                let journal = NativeFriendTeamInviteJournal(storage: storage, ownerKey: owner)
                let wire = InviteRecoveryWire(); wire.response = receipt(command, outcome: outcome)
                let flow = NativeFriendTeamInviteFlow(service: try service(wire), journal: journal)
                await flow.activate()
                XCTAssertEqual(flow.pending, command); XCTAssertTrue(flow.canRecover); XCTAssertFalse(flow.canWrite)
                XCTAssertEqual(storage.rows, originalBytes); XCTAssertEqual(storage.writes, 0)
                await flow.recover()
                XCTAssertNil(flow.pending); XCTAssertNil(try journal.restore()); XCTAssertEqual(storage.removes, 1)
                XCTAssertEqual(wire.requests.filter { $0.httpMethod == "POST" }.count, 0)
                XCTAssertEqual(wire.receiptReads.map(\.value), [command.requestID])
                flow.deactivate()
            }
        }
    }

    func testUnknownAndMisboundReceiptsKeepExactLegacyBytesAndNeverResend() async throws {
        let command = try command(), owner = UUID().uuidString
        let storage = try legacyStorage(command, owner: owner), originalBytes = storage.rows
        let journal = NativeFriendTeamInviteJournal(storage: storage, ownerKey: owner)
        let wire = InviteRecoveryWire()
        let flow = NativeFriendTeamInviteFlow(service: try service(wire), journal: journal)
        await flow.activate()
        var invalid = [receipt(command, outcome: "UNKNOWN")]
        let mismatches: [(String, Any)] = [
            ("contract", "OTHER"), ("requestId", UUID().uuidString.lowercased()),
            ("action", "FRIEND_REVOKE"), ("teamId", Int64(43)), ("targetKey", "friend-offer:43"),
            ("targetKey", "friend-offer:(c.teamID)"), ("requestFingerprint", String(repeating: "0", count: 64))
        ]
        for (field, value) in mismatches {
            var response = receipt(command); response[field] = value; invalid.append(response)
        }
        var rejectedWithoutReason = receipt(command, outcome: "REJECTED"); rejectedWithoutReason.removeValue(forKey: "errorCode")
        invalid.append(rejectedWithoutReason)
        for response in invalid {
            wire.response = response
            await flow.recover(); await flow.confirm()
            XCTAssertEqual(flow.pending, command); XCTAssertTrue(flow.canRecover); XCTAssertFalse(flow.canWrite)
            XCTAssertEqual(storage.rows, originalBytes); XCTAssertEqual(storage.writes, 0); XCTAssertEqual(storage.removes, 0)
        }
        XCTAssertTrue(wire.requests.allSatisfy { $0.httpMethod == "GET" })
        XCTAssertEqual(wire.receiptReads.count, invalid.count)
        XCTAssertTrue(wire.receiptReads.allSatisfy { $0.value == command.requestID })
        flow.deactivate()
    }

    func testNormalPickerConfirmationPersistsBeforeOneWriteAndReopensForOnlySameRequestRead() async throws {
        let owner = UUID().uuidString, storage = InviteRecoveryStorage(), wire = InviteRecoveryWire()
        let journal = NativeFriendTeamInviteJournal(storage: storage, ownerKey: owner)
        let first = NativeFriendTeamInviteFlow(service: try service(wire, mode: .team(42), writes: true), journal: journal)
        await first.activate()
        let selected = try XCTUnwrap(first.items.first)
        first.toggle(selected); first.prepareCreate()
        let reviewed = try XCTUnwrap(first.review)
        wire.response = receipt(reviewed, outcome: "UNKNOWN")
        wire.beforePost = { request in
            XCTAssertEqual(try journal.restore(), reviewed)
            XCTAssertEqual(request.httpBody, reviewed.raw)
        }
        await first.confirm()
        XCTAssertEqual(first.pending, reviewed); XCTAssertFalse(first.canWrite)
        first.prepareCreate(); await first.confirm()
        XCTAssertEqual(wire.requests.filter { $0.httpMethod == "POST" }.count, 1)
        let savedBytes = storage.rows
        first.deactivate()
        let reopened = NativeFriendTeamInviteFlow(service: try service(wire), journal: .init(storage: storage, ownerKey: owner))
        await reopened.activate()
        XCTAssertEqual(reopened.pending?.requestID, reviewed.requestID)
        XCTAssertEqual(reopened.pending?.raw, reviewed.raw); XCTAssertEqual(storage.rows, savedBytes)
        wire.response = receipt(reviewed)
        await reopened.recover()
        XCTAssertNil(reopened.pending); XCTAssertNil(try journal.restore())
        XCTAssertEqual(wire.requests.filter { $0.httpMethod == "POST" }.count, 1)
        XCTAssertEqual(wire.receiptReads.map(\.value), [reviewed.requestID])
        XCTAssertFalse(reopened.canWrite) // Read-only approval never becomes a write grant on recovery.
        reopened.deactivate()
    }

    func testRevokedAuthorityCannotReadOrClearPending() async throws {
        let command = try command(), owner = UUID().uuidString
        let storage = try legacyStorage(command, owner: owner), bytes = storage.rows
        let wire = InviteRecoveryWire(); wire.response = receipt(command)
        var live = true
        let flow = NativeFriendTeamInviteFlow(service: try service(wire, current: { live }),
            journal: .init(storage: storage, ownerKey: owner))
        await flow.activate(); let count = wire.requests.count
        live = false; await flow.recover()
        XCTAssertEqual(wire.requests.count, count); XCTAssertEqual(storage.rows, bytes)
        XCTAssertEqual(storage.removes, 0); XCTAssertFalse(flow.canRecover)
        flow.deactivate()
    }
}

@MainActor private final class InviteRecoveryStorage: ProjectEditDataStorage {
    var rows: [String: Data] = [:]
    var writes = 0, removes = 0
    func read(_ key: String) throws -> Data? { rows[key] }
    func write(_ data: Data, key: String) throws { writes += 1; rows[key] = data }
    func remove(_ key: String) throws { removes += 1; rows[key] = nil }
}
@MainActor private final class InviteRecoveryWire: HTTPTransport {
    var requests: [URLRequest] = []
    var response: [String: Any] = [:]
    var beforePost: ((URLRequest) throws -> Void)?
    var receiptReads: [URLQueryItem] {
        requests.filter { $0.httpMethod == "GET" && $0.url?.path.hasSuffix("original-request") == true }
            .flatMap { URLComponents(url: $0.url!, resolvingAgainstBaseURL: false)?.queryItems ?? [] }
    }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        if request.httpMethod == "POST" { try beforePost?(request) }
        let data: [String: Any]
        if request.url?.path.hasSuffix("/picker") == true {
            data = ["viewer_id": 2, "team_id": "42", "name": "Fixture team", "section": "all", "starred_only": false,
                    "revision": String(repeating: "a", count: 64), "total": 1, "has_more": false, "counts": ["all": 1],
                    "groups": ["viewer_id": 2, "list": [["id": 0, "name": "Default", "position": 0, "version": 0, "is_default": 1]]],
                    "items": [["peer_id": 9, "nickname": "Fixture friend", "state": 1, "version": 3, "msg": "", "expires_at_ms": 0, "already_member": false]]]
        } else if request.url?.path.hasSuffix("/mine") == true {
            data = ["viewer_id": 2, "items": [], "next_before": "0"]
        } else { data = response }
        return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": data]), 200)
    }
}
