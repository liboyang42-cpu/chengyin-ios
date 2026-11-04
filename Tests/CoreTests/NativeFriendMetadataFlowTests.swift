import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class NativeFriendMetadataFlowTests: XCTestCase {
    private final class Journal: OperationPendingListing {
        var rows: [OperationPendingRecord] = []; var fail = false
        func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? { rows.first { $0.ownerKey == ownerKey && $0.targetKey == targetKey } }
        func pendingRecords(ownerKey: String) throws -> [OperationPendingRecord] { rows.filter { $0.ownerKey == ownerKey } }
        func write(_ record: OperationPendingRecord) throws { if fail { throw NativeFriendFailure.unavailable }; rows.append(record) }
        func clear(_ record: OperationPendingRecord) throws { rows.removeAll { $0 == record } }
    }
    private final class Service: NativeFriendMetadataServing {
        // Local-only explicit capabilities; protocol defaults and production grants stay closed.
        var viewerID: Int64 = 2; var canWrite = true; var canSettle = false; var isCurrent = true
        var canStarWrite = true; var canReadGroups = true; var canManageGroups = true; var canAssignGroup = true
        var writes: [NativeFriendMetadataCommand] = []; var lookups: [UUID] = []; var settlements: [UUID] = []
        var rejected: Set<UUID> = []; var wrongHash = false
        var failure: NativeFriendFailure?; var unknown = false; var wrongOwner = false; var retireDuringWrite = false; var readsFail = false
        var current = NativeFriendMetadata(viewerID: 2, peerID: 9, friendVersion: 3, version: 0, remark: nil, groupID: nil, starred: 0, notificationEffect: "NOT_CONNECTED")
        var page = NativeFriendMetadataGroups(viewerID: 2, list: [.init(id: nil, name: "默认分组", position: 0, version: 0, isDefault: 1), .init(id: 4, name: "Bikes", position: 1, version: 2, isDefault: 0)])
        func read(peerID: Int64) async throws -> NativeFriendMetadata { if readsFail { throw NativeFriendFailure.unknown }; return current }
        func groups() async throws -> NativeFriendMetadataGroups { page }
        func write(_ command: NativeFriendMetadataCommand) async throws -> NativeFriendMetadataReceipt {
            writes.append(command); if retireDuringWrite { isCurrent = false }
            if let failure, case .rejected = failure { rejected.insert(command.requestID) }
            if command.action == .remark, !rejected.contains(command.requestID) {
                // F-11 patch semantics: omission preserves each independently controlled field.
                current = .init(viewerID: viewerID, peerID: command.targetID, friendVersion: 3, version: current.version + 1,
                    remark: command.updatesRemark ? command.remark : current.remark,
                    groupID: command.updatesGroup ? command.groupID : current.groupID,
                    starred: command.starred ?? current.starred, notificationEffect: "NOT_CONNECTED")
            }
            if let failure { throw failure }
            return answer(command.action, command.targetID, command.requestID)
        }
        func receipt(action: NativeFriendMetadataAction, targetID: Int64, requestID: UUID) async throws -> NativeFriendMetadataReceipt {
            lookups.append(requestID); return answer(action, targetID, requestID)
        }
        func settle(action: NativeFriendMetadataAction, targetID: Int64, requestID: UUID, payloadHash: String) async throws -> NativeFriendMetadataReceipt {
            settlements.append(requestID)
            throw NativeFriendFailure.notSent // No formal backend settlement writer exists.
        }
        private func answer(_ action: NativeFriendMetadataAction, _ target: Int64, _ identity: UUID) -> NativeFriendMetadataReceipt {
            let outcome = unknown || !writes.contains(where: { $0.requestID == identity }) ? "UNKNOWN" : (rejected.contains(identity) ? "REJECTED" : "APPLIED")
            return .init(viewerID: wrongOwner ? 3 : viewerID, requestID: identity.uuidString, action: action, targetID: target,
                  outcome: outcome, current: action == .remark && outcome == "APPLIED" ? current : nil,
                  groups: action != .remark && outcome == "APPLIED" ? page : nil,
                  payloadHash: wrongHash ? String(repeating: "0", count: 64) : (try? writes.first(where: { $0.requestID == identity })?.fingerprint()))
        }
    }
    private func setup() async -> (NativeFriendMetadataFlow, Service, Journal) {
        let service = Service(), journal = Journal(), flow = NativeFriendMetadataFlow(peerID: 9, service: service, journal: journal, ownerKey: "owner-2")
        await flow.load(); return (flow, service, journal)
    }
    func testReviewAndCancelNeverDispatchAndConfirmedRemarkReentersAuthoritativeState() async throws {
        let (flow, service, journal) = await setup()
        flow.reviewMetadata(remark: "Biking friend", groupID: 4, starred: true)
        XCTAssertTrue(service.writes.isEmpty); XCTAssertEqual(flow.phase, .reviewing)
        flow.cancelReview(); XCTAssertTrue(journal.rows.isEmpty)
        flow.reviewMetadata(remark: "Biking friend", groupID: 4, starred: true)
        await flow.confirm(); XCTAssertEqual(service.writes.count, 1); XCTAssertEqual(flow.metadata?.remark, "Biking friend")
        XCTAssertEqual(flow.metadata?.starred, 0); XCTAssertNil(flow.metadata?.groupID)
        let remark = try XCTUnwrap(service.writes.first)
        XCTAssertNil(remark.starred); XCTAssertFalse(remark.updatesGroup)
        XCTAssertEqual(flow.phase, .ready); XCTAssertTrue(journal.rows.isEmpty)
        // The current UI has separate star/group reviews, not implicit writes with a remark.
        flow.reviewStar(true); await flow.confirm()
        XCTAssertEqual(flow.metadata?.starred, 1); XCTAssertEqual(flow.metadata?.remark, "Biking friend")
        let star = try XCTUnwrap(service.writes.last); XCTAssertEqual(service.writes.count, 2)
        XCTAssertFalse(star.updatesRemark); XCTAssertFalse(star.updatesGroup)
        flow.reviewAssignment(4); await flow.confirm()
        let assignment = try XCTUnwrap(service.writes.last)
        XCTAssertFalse(assignment.updatesRemark); XCTAssertNil(assignment.starred)
        XCTAssertEqual(service.writes.count, 3); XCTAssertTrue(journal.rows.isEmpty)
        await flow.load(); XCTAssertEqual(flow.metadata?.groupID, 4)
        XCTAssertEqual(flow.metadata?.starred, 1); XCTAssertEqual(flow.metadata?.remark, "Biking friend")
    }
    func testIndependentFieldCapabilitiesCannotPiggybackOnRemarkOrSurviveRevocation() async throws {
        let (flow, service, journal) = await setup()
        service.canStarWrite = false; service.canAssignGroup = false; service.canManageGroups = false
        flow.reviewStar(true); XCTAssertNil(flow.review)
        flow.reviewAssignment(4); XCTAssertNil(flow.review)
        flow.reviewDeleteGroup(id: 4, moveTo: nil); XCTAssertNil(flow.review)
        flow.reviewMetadata(remark: "Private", groupID: 4, starred: true)
        let remark = try XCTUnwrap(flow.review)
        XCTAssertNil(remark.starred); XCTAssertFalse(remark.updatesGroup)
        await flow.confirm(); XCTAssertEqual(service.writes, [remark]); XCTAssertTrue(journal.rows.isEmpty)
        XCTAssertEqual(flow.metadata?.starred, 0); XCTAssertNil(flow.metadata?.groupID)
        service.canStarWrite = true; flow.reviewStar(true)
        let star = try XCTUnwrap(flow.review)
        service.canStarWrite = false; await flow.confirm(expected: star)
        XCTAssertEqual(service.writes, [remark]); XCTAssertFalse(flow.canConfirm); XCTAssertTrue(journal.rows.isEmpty)
    }
    func testUnknownSurvivesNavigationAndOnlyOriginalReceiptCanUnlockWithoutResend() async throws {
        let (flow, service, journal) = await setup(); service.failure = .unknown
        flow.reviewMetadata(remark: "Private", groupID: nil, starred: false); let identity = try XCTUnwrap(flow.review?.requestID)
        await flow.confirm(); flow.invalidate()
        let recreated = NativeFriendMetadataFlow(peerID: 9, service: service, journal: journal, ownerKey: "owner-2")
        await recreated.load(); XCTAssertEqual(recreated.pending?.operationID, identity)
        service.unknown = true; await recreated.recover(); XCTAssertNotNil(recreated.pending)
        recreated.reviewMetadata(remark: "duplicate", groupID: nil, starred: true); await recreated.confirm(); XCTAssertEqual(service.writes.count, 1)
        service.unknown = false; await recreated.recover(); XCTAssertNil(recreated.pending); XCTAssertEqual(service.lookups, [identity, identity])
        XCTAssertEqual(service.writes.count, 1); XCTAssertTrue(journal.rows.isEmpty)
    }
    func testWriteStorageFailureAndClosedApprovalDoNotSend() async {
        let (flow, service, journal) = await setup(); journal.fail = true
        flow.reviewMetadata(remark: "Private", groupID: nil, starred: false); await flow.confirm(); XCTAssertTrue(service.writes.isEmpty)
        journal.fail = false; service.canWrite = false; await flow.confirm(); XCTAssertTrue(service.writes.isEmpty)
    }
    func testWrongOwnerReceiptAndAccountChangeRetainOriginalRecoveryIdentity() async {
        for wrongOwner in [true, false] {
            let (flow, service, journal) = await setup(); service.wrongOwner = wrongOwner; service.retireDuringWrite = !wrongOwner
            flow.reviewMetadata(remark: "Private", groupID: nil, starred: false); await flow.confirm()
            XCTAssertEqual(journal.rows.count, 1); XCTAssertFalse(flow.canEdit)
            if !wrongOwner { XCTAssertNil(flow.metadata) }
        }
    }
    func testOwnerWideFencePreventsSecondNavigationStackFromSending() async {
        let (first, service, journal) = await setup()
        let second = NativeFriendMetadataFlow(peerID: 9, service: service, journal: journal, ownerKey: "owner-2"); await second.load()
        first.reviewMetadata(remark: "one", groupID: nil, starred: false); second.reviewMetadata(remark: "two", groupID: nil, starred: false)
        service.failure = .unknown; await first.confirm(); await second.confirm(); XCTAssertEqual(service.writes.count, 1)
        let other = NativeFriendMetadataFlow(peerID: 9, service: nil, journal: journal, ownerKey: "owner-3"); await other.load(); XCTAssertNil(other.pending)
    }
    func testDefaultGroupCannotBeRenamedDeletedOrRepresentedByZero() async throws {
        let (flow, service, _) = await setup()
        flow.reviewGroup(id: 0, name: "illegal", position: 1); XCTAssertNil(flow.review)
        flow.reviewDeleteGroup(id: 0, moveTo: 4); XCTAssertNil(flow.review)
        flow.reviewDeleteGroup(id: 4, moveTo: nil); let command = try XCTUnwrap(flow.review)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: command.body()) as? [String: Any])
        XCTAssertTrue(body["move_to_group_id"] is NSNull); XCTAssertTrue(service.writes.isEmpty)
    }
    func testDefiniteConflictRequiresFreshReadAndNeverSaysSaved() async {
        let (flow, service, journal) = await setup(); service.failure = .rejected(409)
        flow.reviewMetadata(remark: "Private", groupID: nil, starred: false); await flow.confirm()
        XCTAssertEqual(flow.phase, .unknown); XCTAssertFalse(flow.didApply); XCTAssertEqual(journal.rows.count, 1)
        await flow.load(); XCTAssertEqual(flow.phase, .unknown); XCTAssertTrue(service.settlements.isEmpty)
        // An HTTP rejection is not a durable receipt and cannot authorize cancellation.
        XCTAssertFalse(flow.canSettle); await flow.settleOriginal()
        XCTAssertEqual(flow.phase, .unknown); XCTAssertTrue(service.settlements.isEmpty); XCTAssertFalse(journal.rows.isEmpty)
        await flow.recover() // Only the original server REJECTED receipt clears the fence.
        XCTAssertEqual(flow.phase, .ready); XCTAssertFalse(flow.didApply); XCTAssertTrue(journal.rows.isEmpty)
        XCTAssertEqual(service.lookups, service.writes.map(\.requestID)); XCTAssertEqual(service.writes.count, 1)
    }
    func testLostRejectionNeedsOriginalTerminalReceiptAndRestartRecoversWithoutResend() async throws {
        let (flow, service, journal) = await setup(); service.failure = .unknown; service.unknown = true
        flow.reviewMetadata(remark: "Private", groupID: nil, starred: false); let id = try XCTUnwrap(flow.review?.requestID)
        service.rejected.insert(id) // The original write rejects, but its response is lost.
        await flow.confirm(); await flow.recover(); XCTAssertTrue(service.settlements.isEmpty); XCTAssertNotNil(flow.pending)
        service.canSettle = false; await flow.settleOriginal(); XCTAssertTrue(service.settlements.isEmpty)
        // Even a stale fake-provider claim must not revive the removed settlement route.
        service.canSettle = true; XCTAssertFalse(flow.canSettle)
        await flow.settleOriginal(); XCTAssertNotNil(flow.pending); XCTAssertTrue(service.settlements.isEmpty)
        flow.invalidate(); let again = NativeFriendMetadataFlow(peerID: 9, service: service, journal: journal, ownerKey: "owner-2")
        await again.load(); await again.recover(); XCTAssertNotNil(again.pending)
        XCTAssertEqual(service.writes.count, 1); XCTAssertTrue(service.settlements.isEmpty)
        // The server subsequently exposes a terminal rejection for this same original UUID/hash.
        service.unknown = false
        await again.recover(); XCTAssertNil(again.pending); XCTAssertFalse(again.didApply)
        XCTAssertEqual(again.issue, "friendMeta.finalized"); XCTAssertTrue(journal.rows.isEmpty)
        XCTAssertEqual(service.lookups, [id, id, id]); XCTAssertTrue(service.settlements.isEmpty); XCTAssertEqual(service.writes.count, 1)
    }
    func testWrongFingerprintAndLegacyPendingNeverUnlockOrGuess() async {
        let (flow, service, journal) = await setup(); service.failure = .unknown
        flow.reviewMetadata(remark: "Private", groupID: nil, starred: false); await flow.confirm()
        service.wrongHash = true; await flow.recover(); XCTAssertNotNil(flow.pending)
        await flow.settleOriginal(); XCTAssertNotNil(flow.pending)
        journal.rows = [.init(ownerKey: "owner-2", targetKey: "native-friend-metadata.v1.remark.9")]
        let legacy = NativeFriendMetadataFlow(peerID: 9, service: service, journal: journal, ownerKey: "owner-2")
        await legacy.load(); XCTAssertFalse(legacy.canSettle); let sent = service.settlements.count
        await legacy.settleOriginal(); await legacy.recover(); XCTAssertEqual(service.settlements.count, sent); XCTAssertNotNil(legacy.pending)
    }
    func testRecoveryIdentityUsesOriginalFriendNotCurrentEditor() async throws {
        let (first, service, journal) = await setup(); service.failure = .unknown
        first.reviewMetadata(remark: "Private", groupID: nil, starred: false); let id = try XCTUnwrap(first.review?.requestID)
        await first.confirm(); first.invalidate()
        service.current = .init(viewerID: 2, peerID: 17, friendVersion: 3, version: 0, remark: nil, groupID: nil, starred: 0, notificationEffect: "NOT_CONNECTED")
        let other = NativeFriendMetadataFlow(peerID: 17, service: service, journal: journal, ownerKey: "owner-2")
        await other.load(); let identity = try XCTUnwrap(other.pendingIdentity)
        XCTAssertEqual(other.peerID, 17); XCTAssertEqual(identity.targetID, 9); XCTAssertEqual(identity.action, .remark)
        XCTAssertEqual(identity.actionLabelKey, "friendMeta.pendingRemark"); XCTAssertEqual(identity.targetLabelKey, "friendMeta.pendingFriendTarget")
        XCTAssertEqual(identity.requestID, id); XCTAssertEqual(identity.shortRequestID, String(id.uuidString.prefix(8)))
        XCTAssertEqual(service.writes.count, 1); XCTAssertTrue(service.settlements.isEmpty)
    }
    func testRecoveryIdentityDistinguishesExistingAndUncreatedGroups() async throws {
        for (action, target, label) in [(NativeFriendMetadataAction.groupSave, Int64(4), "friendMeta.pendingGroupEdit"),
                                       (.groupDelete, Int64(4), "friendMeta.pendingGroupDelete"),
                                       (.groupSave, Int64(0), "friendMeta.pendingGroupCreate")] {
            let (flow, service, journal) = await setup(); let id = UUID()
            journal.rows = [.init(operationID: id, ownerKey: "owner-2", targetKey: "native-friend-metadata.v1.\(action.rawValue).\(target)." + String(repeating: "a", count: 64))]
            await flow.load(); let identity = try XCTUnwrap(flow.pendingIdentity)
            XCTAssertEqual(identity.action, action); XCTAssertEqual(identity.targetID, target); XCTAssertEqual(identity.actionLabelKey, label)
            XCTAssertEqual(identity.targetLabelKey, target == 0 ? "friendMeta.pendingNewGroupTarget" : "friendMeta.pendingGroupTarget")
            XCTAssertEqual(identity.requestID, id); XCTAssertTrue(service.writes.isEmpty); XCTAssertTrue(service.settlements.isEmpty)
        }
    }
    func testFingerprintMatchesServerUnicodeNullVector() throws {
        let command = NativeFriendMetadataCommand(requestID: UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!,
            action: .remark, targetID: 9, expectedVersion: 0, expectedFriendVersion: 3, remark: "小林😀/é", starred: 1, updatesGroup: true)
        // Original Java vector includes an explicit group_id:null; absence is a different command.
        XCTAssertEqual(try command.fingerprint(), "b5c0c064daf47afac3d32cc48a55f3f09f6f80c615c5481d8c4f63a9b971bbcf")
        let omitted = NativeFriendMetadataCommand(requestID: command.requestID, action: .remark, targetID: 9,
            expectedVersion: 0, expectedFriendVersion: 3, remark: "小林😀/é", starred: 1)
        XCTAssertEqual(try omitted.fingerprint(), "cc8a29aebe3d6775b4b6c509db426e522de42bd0311ac36e91f5f47c70b85bd4")
        XCTAssertNotEqual(try omitted.fingerprint(), try command.fingerprint())
    }
    func testClearRemarkWireAndDisplayedNamePreserveNicknameAndPeerIdentity() throws {
        let command = NativeFriendMetadataCommand(action: .remark, targetID: 9, expectedVersion: 1, expectedFriendVersion: 3, starred: 0, updatesGroup: true)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: command.body()) as? [String: Any])
        XCTAssertTrue(body["remark"] is NSNull); XCTAssertTrue(body["group_id"] is NSNull)
        let item = NativeFriendItem(peerID: 9, nickname: "Original", state: .friend, version: 3, message: "", expiresAtMS: 0, friendRemark: "Private", groupID: 4, starred: 1)
        XCTAssertEqual(item.displayName, "Private"); XCTAssertEqual(item.nickname, "Original"); XCTAssertEqual(item.peerID, 9)
        for text in ["😀", "👨‍👩‍👧‍👦", "🇨🇳", "1️⃣"] { XCTAssertFalse(NativeFriendMetadataValidation.validRemark(text)) }
        XCTAssertTrue(NativeFriendMetadataValidation.validRemark("123")); XCTAssertTrue(NativeFriendMetadataValidation.validRemark("---"))
    }
    func testMetadataTransportRejectsOtherOwnerCookieAndRelationshipPaths() throws {
        let context = RuntimeDependencyContext(market: .china, baseURL: URL(string: "https://friend.example.com/")!, role: "player",
            session: try .init(accountID: 2, epoch: 1, namespace: "test", token: "test-token", role: "player"))
        let paths = NativeFriendMetadataApproval.readPaths.union(NativeFriendMetadataApproval.writePaths)
        let grant = try NativeFriendMetadataApproval(endpoint: .init(baseURL: context.baseURL, namespace: "test", accountID: 2,
            paths: paths), expiresAt: Date().addingTimeInterval(60), allowsStarChanges: true)
        var request = URLRequest(url: context.baseURL.appendingPathComponent("api/friend/remark")); request.httpShouldHandleCookies = false; request.httpMethod = "POST"
        request.setValue("test-token", forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try NativeFriendMetadataCommand(action: .remark, targetID: 9, expectedVersion: 0, expectedFriendVersion: 1, remark: "Name", starred: 1).body()
        XCTAssertTrue(NativeFriendMetadataTransportPolicy.accepts(request, context: context, approval: grant))
        var settlement = request; settlement.url = context.baseURL.appendingPathComponent(NativeFriendMetadataApproval.settlePath)
        settlement.httpBody = try JSONSerialization.data(withJSONObject: ["action": "remark", "target_id": 9,
            "request_id": UUID().uuidString, "payload_hash": String(repeating: "a", count: 64)])
        let ordinaryGrant = try NativeFriendMetadataApproval(endpoint: .init(baseURL: context.baseURL, namespace: "test", accountID: 2,
            paths: paths), expiresAt: Date().addingTimeInterval(60))
        XCTAssertFalse(NativeFriendMetadataTransportPolicy.accepts(settlement, context: context, approval: ordinaryGrant))
        XCTAssertFalse(NativeFriendMetadataTransportPolicy.accepts(settlement, context: context, approval: grant))
        XCTAssertFalse(NativeFriendMetadataTransportPolicy.accepts(request, context: context, approval: ordinaryGrant))
        // r493 has no /metadata/settle mapping. It cannot be issued even with ordinary read/write paths.
        for requestedPaths in [NativeFriendMetadataApproval.readPaths, paths] {
            XCTAssertThrowsError(try NativeFriendMetadataApproval(endpoint: .init(baseURL: context.baseURL, namespace: "test", accountID: 2,
                paths: requestedPaths.union([NativeFriendMetadataApproval.settlePath])), expiresAt: Date().addingTimeInterval(60)))
        }
        var remarkOnly = request
        remarkOnly.httpBody = try NativeFriendMetadataCommand(action: .remark, targetID: 9, expectedVersion: 0, expectedFriendVersion: 1, remark: "Name").body()
        XCTAssertTrue(NativeFriendMetadataTransportPolicy.accepts(remarkOnly, context: context, approval: ordinaryGrant))
        var unapprovedGroup = request
        unapprovedGroup.httpBody = try NativeFriendMetadataCommand(action: .remark, targetID: 9, expectedVersion: 0, expectedFriendVersion: 1, updatesRemark: false, updatesGroup: true).body()
        XCTAssertFalse(NativeFriendMetadataTransportPolicy.accepts(unapprovedGroup, context: context, approval: grant))
        var bad = request; bad.setValue("a=b", forHTTPHeaderField: "Cookie"); XCTAssertFalse(NativeFriendMetadataTransportPolicy.accepts(bad, context: context, approval: grant))
        bad = request; bad.url = context.baseURL.appendingPathComponent("api/im/start"); XCTAssertFalse(NativeFriendMetadataTransportPolicy.accepts(bad, context: context, approval: grant))
        var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any]); fields["viewer_id"] = 3
        bad = request; bad.httpBody = try JSONSerialization.data(withJSONObject: fields); XCTAssertFalse(NativeFriendMetadataTransportPolicy.accepts(bad, context: context, approval: grant))
    }
}
