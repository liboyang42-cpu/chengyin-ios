import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import QuestifyCore

/// Presentation-only coverage over the original service/flow; this wire never uses a network session.
@MainActor final class NativeProgressPrivacyWriteAuthorityPresentationTests: XCTestCase {
    func testIndependentReadOnlyIssuanceExplainsWritableServerSnapshotForBothTargets() async throws {
        for channelID in [nil, Int64(77)] as [Int64?] {
            let h = try PrivacyWriteAuthorityHarness(independentWrite: false, serverWrite: true, channelID: channelID)
            let flow = try h.makeFlow(); defer { flow.deactivate() }
            await flow.activate()
            let value = try XCTUnwrap(flow.writeAuthorityPresentation)
            XCTAssertFalse(value.independentWriteAllowed); XCTAssertTrue(value.snapshotWriteAllowed)
            XCTAssertTrue(value.isReadOnly); XCTAssertEqual(flow.phase, .ready)
            XCTAssertFalse(flow.canEdit); XCTAssertFalse(flow.canConfirm)
            flow.prepare(.onlySelf); XCTAssertNil(flow.reviewedCommand); XCTAssertTrue(h.journal.rows.isEmpty)
            let requests = await h.wire.history()
            XCTAssertEqual(requests.map { $0.httpMethod ?? "" }, ["GET"])
        }
    }

    func testServerReadOnlyIsNotMistakenForIndependentGrantDenial() async throws {
        let h = try PrivacyWriteAuthorityHarness(independentWrite: true, serverWrite: false)
        let flow = try h.makeFlow(); defer { flow.deactivate() }; await flow.activate()
        let value = try XCTUnwrap(flow.writeAuthorityPresentation)
        XCTAssertTrue(value.independentWriteAllowed); XCTAssertFalse(value.snapshotWriteAllowed)
        XCTAssertTrue(value.isReadOnly); XCTAssertFalse(flow.canEdit)
        flow.prepare(.onlySelf); XCTAssertNil(flow.reviewedCommand)
        XCTAssertTrue(h.journal.rows.isEmpty)
    }

    func testBothWritePermissionsCanBeIndependentlyAbsent() async throws {
        let h = try PrivacyWriteAuthorityHarness(independentWrite: false, serverWrite: false)
        let flow = try h.makeFlow(); defer { flow.deactivate() }; await flow.activate()
        let value = try XCTUnwrap(flow.writeAuthorityPresentation)
        XCTAssertFalse(value.independentWriteAllowed); XCTAssertFalse(value.snapshotWriteAllowed)
        XCTAssertTrue(value.isReadOnly); XCTAssertFalse(flow.canEdit)
    }

    func testBothWritePermissionsAllowOriginalPrepareWithoutInventingAnAction() async throws {
        let h = try PrivacyWriteAuthorityHarness(independentWrite: true, serverWrite: true)
        let flow = try h.makeFlow(); defer { flow.deactivate() }; await flow.activate()
        let value = try XCTUnwrap(flow.writeAuthorityPresentation)
        XCTAssertTrue(value.independentWriteAllowed); XCTAssertTrue(value.snapshotWriteAllowed)
        XCTAssertFalse(value.isReadOnly); XCTAssertTrue(flow.canEdit)
        XCTAssertNil(flow.reviewedCommand); XCTAssertTrue(h.journal.rows.isEmpty)
        let requests = await h.wire.history(); XCTAssertEqual(requests.map { $0.httpMethod ?? "" }, ["GET"])
    }

    func testReviewLockIsNotReportedAsMissingWriteAuthority() async throws {
        let h = try PrivacyWriteAuthorityHarness(independentWrite: true, serverWrite: true)
        let flow = try h.makeFlow(); defer { flow.deactivate() }; await flow.activate()
        flow.prepare(.onlySelf); let displayed = try XCTUnwrap(flow.reviewedCommand)
        XCTAssertEqual(flow.phase, .reviewing); XCTAssertFalse(flow.canEdit); XCTAssertTrue(flow.canConfirm)
        XCTAssertEqual(flow.writeAuthorityPresentation?.isReadOnly, false)
        XCTAssertEqual(flow.reviewedCommand?.requestID, displayed.requestID)
        flow.cancelReview(); XCTAssertTrue(flow.canEdit)
        XCTAssertEqual(flow.writeAuthorityPresentation?.isReadOnly, false)
        XCTAssertTrue(h.journal.rows.isEmpty)
    }

    func testUnknownPendingAndRestartKeepAuthoritySeparateFromOperationLock() async throws {
        let h = try PrivacyWriteAuthorityHarness(independentWrite: true, serverWrite: true)
        let flow = try h.makeFlow(); defer { flow.deactivate() }; await flow.activate()
        flow.prepare(.onlySelf); let command = try XCTUnwrap(flow.reviewedCommand)
        await h.wire.setLosePostResponse(true)
        await flow.confirm(expected: command)
        XCTAssertEqual(flow.phase, .unknown); XCTAssertNil(flow.writeAuthorityPresentation)
        XCTAssertEqual(flow.requestID, command.requestID.uuidString)
        flow.deactivate()
        let restored = try h.makeFlow(); defer { restored.deactivate() }; await restored.activate()
        XCTAssertEqual(restored.phase, .unknown); XCTAssertFalse(restored.canEdit); XCTAssertTrue(restored.canRecover)
        let value = try XCTUnwrap(restored.writeAuthorityPresentation)
        XCTAssertTrue(value.independentWriteAllowed); XCTAssertTrue(value.snapshotWriteAllowed)
        XCTAssertFalse(value.isReadOnly); XCTAssertEqual(restored.requestID, command.requestID.uuidString)
        XCTAssertEqual(h.journal.rows.count, 1)
        await restored.confirm(expected: command)
        let requests = await h.wire.history()
        XCTAssertEqual(requests.filter { $0.httpMethod == "POST" }.count, 1)
    }

    func testRefreshClearsCurrentAuthorityWhileOriginalReadIsBusy() async throws {
        let h = try PrivacyWriteAuthorityHarness(independentWrite: true, serverWrite: true)
        let flow = try h.makeFlow(); defer { flow.deactivate() }; await flow.activate()
        await h.wire.holdNextCurrentRead()
        let refresh = Task { await flow.refresh() }; await h.wire.waitForHeldRead()
        XCTAssertEqual(flow.phase, .loading); XCTAssertFalse(flow.canEdit)
        XCTAssertNil(flow.writeAuthorityPresentation) // No current snapshot, not a permission-denial fact.
        await h.wire.releaseRead(); await refresh.value
        XCTAssertEqual(flow.phase, .ready); XCTAssertEqual(flow.writeAuthorityPresentation?.isReadOnly, false)
    }

    func testAppliedReceiptDoesNotOverrideNewReadOnlyCurrent() async throws {
        let h = try PrivacyWriteAuthorityHarness(independentWrite: true, serverWrite: true)
        let flow = try h.makeFlow(); defer { flow.deactivate() }; await flow.activate()
        flow.prepare(.onlySelf); let command = try XCTUnwrap(flow.reviewedCommand)
        await h.wire.setProof(try privacyWriteAuthorityProof(command))
        await h.wire.setCurrent(try privacyWriteAuthoritySnapshot(target: h.target, canWrite: false, aggregate: .everyone))
        await flow.confirm(expected: command)
        XCTAssertEqual(flow.resultPresentation, .applied); XCTAssertEqual(flow.snapshot?.aggregate, .everyone)
        let value = try XCTUnwrap(flow.writeAuthorityPresentation)
        XCTAssertTrue(value.independentWriteAllowed); XCTAssertFalse(value.snapshotWriteAllowed)
        XCTAssertTrue(value.isReadOnly); XCTAssertFalse(flow.canEdit); XCTAssertTrue(h.journal.rows.isEmpty)
        let requests = await h.wire.history(); XCTAssertEqual(requests.map { $0.httpMethod ?? "" }, ["GET", "POST", "GET"])
    }

    func testHistoricalAppliedWithCurrentReadFailureHasNoAuthorityProjection() async throws {
        let h = try PrivacyWriteAuthorityHarness(independentWrite: true, serverWrite: true)
        let flow = try h.makeFlow(); defer { flow.deactivate() }; await flow.activate()
        flow.prepare(.onlySelf); let command = try XCTUnwrap(flow.reviewedCommand)
        await h.wire.setProof(try privacyWriteAuthorityProof(command)); await h.wire.setFailCurrentRead(true)
        await flow.confirm(expected: command)
        XCTAssertEqual(flow.resultPresentation, .applied); XCTAssertEqual(flow.phase, .unavailable)
        XCTAssertNil(flow.snapshot); XCTAssertNil(flow.writeAuthorityPresentation)
        XCTAssertFalse(flow.canEdit); XCTAssertTrue(h.journal.rows.isEmpty)
    }

    func testRevocationOrChangedAccountHidesProjectionAndCannotReviveOldService() async throws {
        for revokeApproval in [true, false] {
            let h = try PrivacyWriteAuthorityHarness(independentWrite: true, serverWrite: true)
            let flow = try h.makeFlow(); defer { flow.deactivate() }; await flow.activate()
            XCTAssertNotNil(flow.writeAuthorityPresentation)
            if revokeApproval { h.approval = nil } else { h.current = nil }
            XCTAssertNil(flow.writeAuthorityPresentation); XCTAssertEqual(flow.phase, .closed)
            h.approval = h.initialApproval; h.current = h.context
            XCTAssertNil(flow.writeAuthorityPresentation); XCTAssertFalse(flow.canEdit)
            XCTAssertTrue(h.journal.rows.isEmpty)
        }
    }

    func testBackgroundClearsProjectionUntilFreshCurrentRead() async throws {
        let h = try PrivacyWriteAuthorityHarness(independentWrite: false, serverWrite: true)
        let flow = try h.makeFlow(); defer { flow.deactivate() }; await flow.activate()
        XCTAssertEqual(flow.writeAuthorityPresentation?.isReadOnly, true)
        flow.deactivate(); XCTAssertNil(flow.writeAuthorityPresentation)
        await h.wire.setCurrent(try privacyWriteAuthoritySnapshot(target: h.target, canWrite: false))
        await flow.activate()
        let value = try XCTUnwrap(flow.writeAuthorityPresentation)
        XCTAssertFalse(value.independentWriteAllowed); XCTAssertFalse(value.snapshotWriteAllowed)
        XCTAssertTrue(value.isReadOnly)
        let requests = await h.wire.history(); XCTAssertEqual(requests.map { $0.httpMethod ?? "" }, ["GET", "GET"])
    }

    func testPresentationGetterDoesNotReadWriteOrClearJournal() async throws {
        let closedJournal = PrivacyWriteAuthorityJournal()
        let closed = NativeProgressPrivacyFlow(service: nil, journal: closedJournal, ownerKey: "presentation-closed")
        defer { closed.deactivate() }
        for _ in 0..<3 { XCTAssertNil(closed.writeAuthorityPresentation) }
        XCTAssertEqual(closedJournal.calls, 0)
        let h = try PrivacyWriteAuthorityHarness(independentWrite: false, serverWrite: true)
        let flow = try h.makeFlow(); defer { flow.deactivate() }; await flow.activate()
        let calls = h.journal.calls
        for _ in 0..<3 { XCTAssertEqual(flow.writeAuthorityPresentation?.isReadOnly, true) }
        XCTAssertEqual(h.journal.calls, calls); XCTAssertTrue(h.journal.rows.isEmpty)
        let requests = await h.wire.history(); XCTAssertEqual(requests.count, 1)
    }
}

@MainActor private final class PrivacyWriteAuthorityJournal: OperationPendingListing {
    var rows: [OperationPendingRecord] = []
    var calls = 0
    func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? {
        calls += 1; return rows.first { $0.ownerKey == ownerKey && $0.targetKey == targetKey }
    }
    func pendingRecords(ownerKey: String) throws -> [OperationPendingRecord] {
        calls += 1; return rows.filter { $0.ownerKey == ownerKey }
    }
    func write(_ record: OperationPendingRecord) throws { calls += 1; rows.append(record) }
    func clear(_ record: OperationPendingRecord) throws { calls += 1; rows.removeAll { $0 == record } }
}

private actor PrivacyWriteAuthorityWire: HTTPTransport {
    private var current: Data
    private var proof: Data?
    private var requests: [URLRequest] = []
    private var losePostResponse = false
    private var failCurrentRead = false
    private var holdRead = false
    private var heldRead: CheckedContinuation<(Data, Int), Error>?
    private var heldWaiters: [CheckedContinuation<Void, Never>] = []
    init(current: Data) { self.current = current }
    func history() -> [URLRequest] { requests }
    func setCurrent(_ value: Data) { current = value }
    func setProof(_ value: Data) { proof = value }
    func setLosePostResponse(_ value: Bool) { losePostResponse = value }
    func setFailCurrentRead(_ value: Bool) { failCurrentRead = value }
    func holdNextCurrentRead() { holdRead = true }
    func waitForHeldRead() async {
        if heldRead != nil { return }
        await withCheckedContinuation { heldWaiters.append($0) }
    }
    func releaseRead() { let old = heldRead; heldRead = nil; old?.resume(returning: (current, 200)) }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        if request.httpMethod == "POST" {
            if losePostResponse { throw URLError(.timedOut) }
            guard let proof else { throw APIError.malformedResponse }; return (proof, 200)
        }
        if request.url?.path == "/api/progress/requests" {
            guard let proof else { throw APIError.malformedResponse }; return (proof, 200)
        }
        if failCurrentRead { throw URLError(.timedOut) }
        if holdRead {
            holdRead = false
            return try await withCheckedThrowingContinuation { continuation in
                heldRead = continuation
                let waiters = heldWaiters; heldWaiters.removeAll(); waiters.forEach { $0.resume() }
            }
        }
        return (current, 200)
    }
}

@MainActor private final class PrivacyWriteAuthorityHarness {
    let context: RuntimeDependencyContext
    let target: NativeProgressPrivacyTarget
    let initialApproval: NativeProgressPrivacyApproval
    var current: RuntimeDependencyContext?
    var approval: NativeProgressPrivacyApproval?
    let journal = PrivacyWriteAuthorityJournal()
    let wire: PrivacyWriteAuthorityWire
    let owner: String
    init(independentWrite: Bool, serverWrite: Bool, channelID: Int64? = nil) throws {
        let base = URL(string: "https://privacy.example.com/")!
        context = .init(market: .china, baseURL: base, role: "player",
            session: try .init(accountID: 101, epoch: 1, namespace: "p31-presentation-" + UUID().uuidString,
                               token: "fixture-not-live", role: "player"))
        target = try .init(kind: channelID == nil ? .user : .channel, id: channelID ?? 101)
        initialApproval = try .init(endpoint: .init(baseURL: base, namespace: context.session.namespace,
            accountID: 101, paths: [target.path, NativeProgressPrivacyApproval.receiptPath]),
            target: target, expiresAt: Date().addingTimeInterval(600), allowsWrite: independentWrite)
        current = context; approval = initialApproval
        wire = PrivacyWriteAuthorityWire(current: try privacyWriteAuthoritySnapshot(target: target, canWrite: serverWrite))
        owner = NativeProgressPrivacyInvalidation.owner(origin: base, namespace: context.session.namespace, actor: 101)
    }
    func makeFlow() throws -> NativeProgressPrivacyFlow {
        let service = try NativeProgressPrivacyService(context: context, approval: initialApproval, target: target,
            transport: wire, current: { [weak self] in self?.current }, currentApproval: { [weak self] in self?.approval },
            channelCurrent: { true }, onUnauthorized: { _ in })
        return NativeProgressPrivacyFlow(service: service, journal: journal, ownerKey: owner)
    }
}

private func privacyWriteAuthoritySnapshot(target: NativeProgressPrivacyTarget, canWrite: Bool,
                                           aggregate: NativeProgressPrivacyScope = .friend) throws -> Data {
    var value: [String: Any] = ["actor_id": 101, "scope_type": target.kind.rawValue, "scope_id": target.id,
        "aggregate_scope": aggregate.rawValue, "detail_scope": "TEAM", "updated_at": "2026-10-31 11:00:00.000001",
        "is_default": false, "applies_to": "ALL", "editable_fields": ["aggregate_scope"],
        "can_write": canWrite, "aggregate_verified": true]
    if target.kind == .user { value["photo_scope"] = "TEAM"; value["leaderboard_scope"] = "IN" }
    else { value["board_enabled"] = 1; value["revision"] = 3 }
    return try JSONSerialization.data(withJSONObject: ["code": 200, "data": value])
}

private func privacyWriteAuthorityProof(_ command: NativeProgressPrivacyCommand) throws -> Data {
    var value: [String: Any] = ["actor_id": 101, "request_id": command.requestID.uuidString,
        "scope_type": command.target.kind.rawValue, "scope_id": command.target.id,
        "payload_hash": try command.fingerprint(), "outcome": "APPLIED", "reason": "AGGREGATE_PRIVACY_SAVED",
        "applied_updated_at": "2026-10-31 11:00:00.000002"]
    if command.target.kind == .channel { value["applied_revision"] = (command.expectedRevision ?? 0) + 1 }
    return try JSONSerialization.data(withJSONObject: ["code": 200, "data": value])
}
