import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class PlayPlayerSubmissionReadbackTests: XCTestCase {
    private func row(_ status: String, id: Int = 91, node: Int = 701, task: String = "OBSERVE", reason: PlayWireValue = .null) -> PlayWireValue {
        .object(["submissionId": .int(id), "nodeId": .int(node), "taskCode": .string(task), "status": .string(status), "reason": reason])
    }
    private func raw(_ rows: [PlayWireValue], sessionID: Int = 501, revision: Int = 2) throws -> PlayWireValue {
        var root = try XCTUnwrap(PlayExperienceSyntheticFixtures.wire(PlayExperienceSyntheticFixtures.player).object)
        var player = try XCTUnwrap(root["player"]?.object)
        player["mySubmissions"] = .array(rows); root["player"] = .object(player)
        root["sessionId"] = .int(sessionID); root["revision"] = .int(revision)
        return .object(root)
    }
    private func read(_ rows: [PlayWireValue], nodeID: Int = 701) throws -> PlayPlayerSubmissionState {
        PlayPlayerSubmissionRecord.read(projection: try .init(raw(rows)), nodeID: nodeID)
    }
    private func record(_ state: PlayPlayerSubmissionState) throws -> PlayPlayerSubmissionRecord {
        guard case .record(let record) = state else { XCTFail("Expected an exact server record"); throw APIError.invalidRequest }
        return record
    }
    func testFourStatesHaveSeparateCopyAndExactPlayerScope() throws {
        for status in PlayPlayerSubmissionRecord.Status.allCases {
            let value = try record(read([row(status.rawValue)]))
            XCTAssertEqual(value.status, status); XCTAssertEqual(value.sessionID, 501)
            XCTAssertEqual(value.activityID, 41); XCTAssertEqual(value.teamID, 61)
            XCTAssertEqual(value.revision, 2); XCTAssertEqual(value.nodeID, 701)
            XCTAssertEqual(value.taskCode, "OBSERVE"); XCTAssertEqual(value.submissionID, 91)
        }
        XCTAssertNotEqual(PlayPlayerSubmissionRecord.Status.recorded.titleKey, PlayPlayerSubmissionRecord.Status.approved.titleKey)
    }
    func testReasonAppearsOnlyForRejectedAndSupportsBothSourceAliases() throws {
        for status in ["PENDING", "APPROVED", "RECORDED"] {
            XCTAssertNil(try record(read([row(status, reason: .string("Private old reason"))])).rejectionReason)
        }
        XCTAssertEqual(try record(read([row("REJECTED", reason: .string(" Try another photo "))])).rejectionReason, "Try another photo")
        var alias = try XCTUnwrap(row("REJECTED").object)
        alias["decisionReason"] = .string("Synthetic rejection")
        XCTAssertEqual(try record(read([.object(alias)])).rejectionReason, "Synthetic rejection")
        XCTAssertNil(try record(read([row("REJECTED")])).rejectionReason)
    }
    func testMalformedNewestRecordNeverFallsBackToAnOldApproval() throws {
        for status in ["UNKNOWN", "", "approved"] {
            XCTAssertEqual(try read([row(status, id: 92), row("APPROVED")]), .unconfirmed)
        }
        XCTAssertEqual(try read([row("REJECTED", reason: .array([]))]), .unconfirmed)
        XCTAssertEqual(try read([row("REJECTED", reason: .string(String(repeating: "a", count: 301)))]), .unconfirmed)
        XCTAssertEqual(try read([row("APPROVED", id: 0)]), .unconfirmed)
    }
    func testDuplicateIdentityMissingNodeAndDifferentTaskAreUnconfirmed() throws {
        XCTAssertEqual(try read([row("APPROVED"), row("REJECTED")]), .unconfirmed)
        XCTAssertEqual(try read([row("APPROVED", node: 0)]), .unconfirmed)
        XCTAssertEqual(try read([row("APPROVED", task: "ANOTHER_TASK")]), .unconfirmed)
        XCTAssertEqual(try read([row("APPROVED")], nodeID: 999), .unconfirmed)
    }
    func testNoSubmissionAndOtherNodeDoNotBecomeApproval() throws {
        XCTAssertEqual(try read([]), .none)
        XCTAssertEqual(try read([row("APPROVED", node: 702)]), .none)
    }
    func testMissingArrayAndMalformedContainerRemainDistinctWithoutChangingLegacyRows() throws {
        let empty = try PlayPlayerGameProjection(raw([]))
        XCTAssertEqual(empty.submissionContainerShape, .array)
        XCTAssertEqual(PlayPlayerSubmissionRecord.read(projection: empty, nodeID: 701), .none)
        let replacements: [PlayWireValue?] = [nil, .null, .string("invalid"), .object([:]), .bool(false)]
        for replacement in replacements {
            var root = try XCTUnwrap(raw([]).object)
            var player = try XCTUnwrap(root["player"]?.object)
            player["mySubmissions"] = replacement; root["player"] = .object(player)
            let value = try PlayPlayerGameProjection(.object(root))
            XCTAssertEqual(value.submissionContainerShape, replacement == nil ? .missing : .malformed)
            XCTAssertTrue(value.submissions.isEmpty, "The legacy write-eligibility input stays unchanged")
            XCTAssertEqual(PlayPlayerSubmissionRecord.read(projection: value, nodeID: 701), .unconfirmed)
        }
    }
    func testUsesNewestServerOrderRatherThanMaximumStatusOrOldApproval() throws {
        let value = try record(read([row("REJECTED", id: 93), row("APPROVED", id: 92)]))
        XCTAssertEqual(value.submissionID, 93); XCTAssertEqual(value.status, .rejected)
        XCTAssertEqual(try read([row("APPROVED", id: 91), row("REJECTED", id: 92)]), .unconfirmed)
    }
    func testReadbackDoesNotAlterExistingSubmissionEligibility() throws {
        let projection = try PlayPlayerGameProjection(raw([row("RECORDED")]))
        let command = try PlayPlayerCommand(activityID: 41, nodeID: 701, expectedRevision: 2, action: .submit,
            payload: ["taskCode": .string("OBSERVE"), "evidenceUrls": .array([.string("text:synthetic")])])
        let before = projection.allows(command)
        _ = PlayPlayerSubmissionRecord.read(projection: projection, nodeID: 701)
        XCTAssertEqual(projection.allows(command), before); XCTAssertFalse(before)
    }
    private func setup(_ rows: [PlayWireValue]) throws -> (SubmissionOwner, SubmissionReadTransport, PlayPlayerGameCoordinator, PlayPlayerSubmissionReadback) {
        let owner = try SubmissionOwner(), transport = SubmissionReadTransport(response: try raw(rows))
        let service = PlayExperienceService(configuration: try .init(baseURL: URL(string: "https://example.test")!), transport: transport, enabled: [.reads])
        let model = PlayPlayerGameCoordinator(activityID: 41, service: service, currentSession: { owner.value })
        return (owner, transport, model, PlayPlayerSubmissionReadback(model: model))
    }
    func testLeaseUsesOnlyExistingPlayerReadAndDismissalBlocksQueuedRefresh() async throws {
        let (_, transport, _, readback) = try setup([row("PENDING")])
        await readback.open()
        XCTAssertEqual(try record(readback.state(nodeID: 701)).status, .pending)
        XCTAssertEqual(transport.requests.count, 1)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "GET"); XCTAssertEqual(request.url?.path, "/api/game/session/view")
        let fields = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertTrue(fields.contains(URLQueryItem(name: "activityId", value: "41")))
        XCTAssertTrue(fields.contains(URLQueryItem(name: "perspective", value: "PLAYER")))
        readback.dismiss(); await readback.refresh()
        XCTAssertEqual(readback.state(nodeID: 701), .unconfirmed); XCTAssertEqual(transport.requests.count, 1)
    }
    func testRefreshFailureImmediatelyRemovesOldApproval() async throws {
        let (_, transport, _, readback) = try setup([row("APPROVED")])
        await readback.open(); XCTAssertEqual(try record(readback.state(nodeID: 701)).status, .approved)
        transport.fail = true; await readback.refresh()
        XCTAssertEqual(readback.state(nodeID: 701), .unconfirmed)
        transport.fail = false; transport.response = try raw([row("REJECTED", id: 92)], revision: 3)
        await readback.refresh(); XCTAssertEqual(try record(readback.state(nodeID: 701)).status, .rejected)
    }
    func testAccountEpochNamespaceAndLogoutHideAllReadbackBeforeAnotherLoad() async throws {
        let (owner, transport, _, readback) = try setup([row("REJECTED", reason: .string("Synthetic private reason"))])
        await readback.open()
        for replacement in [
            try PlayExperienceSession(accountID: 2, epoch: 1, namespace: "synthetic", token: "synthetic-token"),
            try PlayExperienceSession(accountID: 1, epoch: 2, namespace: "synthetic", token: "synthetic-token"),
            try PlayExperienceSession(accountID: 1, epoch: 1, namespace: "different", token: "synthetic-token")
        ] {
            owner.value = replacement; XCTAssertEqual(readback.state(nodeID: 701), .unconfirmed)
            await readback.refresh()
        }
        owner.value = nil; XCTAssertEqual(readback.state(nodeID: 701), .unconfirmed)
        XCTAssertEqual(transport.requests.count, 1)
    }
    func testDifferentGameSessionWithSameNodeNumberCannotReplaceCurrentRecord() async throws {
        let (_, transport, _, readback) = try setup([row("PENDING")])
        await readback.open(); transport.response = try raw([row("APPROVED")], sessionID: 999, revision: 3)
        await readback.refresh(); XCTAssertEqual(readback.state(nodeID: 701), .unconfirmed)
    }
    func testLateResponseAfterDismissalDoesNotRestorePrivateReason() async throws {
        let (_, transport, _, readback) = try setup([row("REJECTED", reason: .string("Synthetic private reason"))])
        let started = expectation(description: "fake projection read started")
        transport.suspend = true; transport.onRead = { started.fulfill() }
        let task = Task { await readback.open() }
        await fulfillment(of: [started], timeout: 2)
        readback.dismiss(); transport.resume(); await task.value
        XCTAssertEqual(readback.state(nodeID: 701), .unconfirmed)
        await readback.refresh(); XCTAssertEqual(transport.requests.count, 1)
    }
    func testLateOldOwnerResponseAndCancelledReadCannotPublishStatus() async throws {
        let (owner, transport, _, readback) = try setup([row("APPROVED")])
        let started = expectation(description: "fake projection read started")
        transport.suspend = true; transport.onRead = { started.fulfill() }
        let task = Task { await readback.open() }
        await fulfillment(of: [started], timeout: 2)
        owner.value = nil; task.cancel(); transport.resume(); await task.value
        XCTAssertEqual(readback.state(nodeID: 701), .unconfirmed)
    }
    func testReopenRequiresFreshReadAndDoesNotRevealCachedApprovalWhileLoading() async throws {
        let (_, transport, model, original) = try setup([row("APPROVED")])
        await original.open(); original.dismiss()
        let reopened = PlayPlayerSubmissionReadback(model: model)
        XCTAssertEqual(reopened.state(nodeID: 701), .unconfirmed)
        let started = expectation(description: "reopen read started")
        transport.suspend = true; transport.onRead = { started.fulfill() }; transport.response = try raw([row("RECORDED")], revision: 3)
        let task = Task { await reopened.open() }
        await fulfillment(of: [started], timeout: 2)
        XCTAssertEqual(reopened.state(nodeID: 701), .unconfirmed)
        transport.resume(); await task.value
        XCTAssertEqual(try record(reopened.state(nodeID: 701)).status, .recorded)
        XCTAssertEqual(original.state(nodeID: 701), .unconfirmed)
    }
    func testDisabledReadGrantNeverDispatchesOrShowsStatus() async throws {
        let owner = try SubmissionOwner(), transport = SubmissionReadTransport(response: try raw([row("APPROVED")]))
        let service = PlayExperienceService(configuration: try .init(baseURL: URL(string: "https://example.test")!), transport: transport, enabled: [])
        let model = PlayPlayerGameCoordinator(activityID: 41, service: service, currentSession: { owner.value })
        let readback = PlayPlayerSubmissionReadback(model: model)
        await readback.open(); await readback.refresh()
        XCTAssertEqual(readback.state(nodeID: 701), .unconfirmed); XCTAssertFalse(readback.canRefresh)
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testOlderRefreshCannotReplaceNewerRejectedStateWithApproval() async throws {
        let (_, transport, _, readback) = try setup([row("PENDING")])
        await readback.open()
        let started = expectation(description: "older read started")
        transport.response = try raw([row("APPROVED")], revision: 3)
        transport.suspend = true; transport.onRead = { started.fulfill() }
        let older = Task { await readback.refresh() }
        await fulfillment(of: [started], timeout: 2)
        transport.onRead = nil; transport.suspend = false
        transport.response = try raw([row("REJECTED", id: 92)], revision: 4)
        await readback.refresh()
        transport.resume(); await older.value
        XCTAssertEqual(try record(readback.state(nodeID: 701)).status, .rejected)
        XCTAssertEqual(try record(readback.state(nodeID: 701)).revision, 4)
    }
}

@MainActor private final class SubmissionOwner {
    var value: PlayExperienceSession?
    init() throws { value = try .init(accountID: 1, epoch: 1, namespace: "synthetic", token: "synthetic-token") }
}
private final class SubmissionReadTransport: HTTPTransport {
    @MainActor var response: PlayWireValue
    @MainActor var requests: [URLRequest] = []
    @MainActor var fail = false
    @MainActor var suspend = false
    @MainActor var onRead: (() -> Void)?
    @MainActor private var continuation: CheckedContinuation<Void, Never>?
    @MainActor init(response: PlayWireValue) { self.response = response }
    func send(_ request: URLRequest) async throws -> (Data, Int) { try await execute(request) }
    @MainActor private func execute(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); let snapshot = response
        if suspend { await withCheckedContinuation { continuation = $0; onRead?() } }
        else { onRead?() }
        if fail { throw APIError.malformedResponse }
        return (try JSONEncoder().encode(PlayWireValue.object(["code": .int(200), "data": snapshot])), 200)
    }
    @MainActor func resume() { suspend = false; continuation?.resume(); continuation = nil }
}
