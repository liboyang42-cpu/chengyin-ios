import XCTest
@testable import QuestifyCore

/// Durable meeting intent. Authored for the Core test target; not executed in this environment.
@MainActor final class TeamMeetingRecoveryTests: XCTestCase {
    private let enabled = ReformWorldCapabilities.syntheticFixture([.teamFirstMeeting])

    func testIntentFileSurvivesANewJournalAndDropsSecrets() async throws {
        let root = try scratch()
        let owner = try TeamMeetingOwner(accountID: 901, namespace: "offline-team-fixture")
        let journal = TeamMeetingPendingJournal(root: root)
        let fake = MeetingRecoveryFake()
        let recovery = TeamMeetingRecovery(journal: journal, service: fake)
        let nonce = "PeerNonceValue0000000001"
        let token = "session-token-secret"
        var fields = try fields(teamID: 4101, requestId: "request-0001", nonce: nonce)
        fields["token"] = token
        let sent = try await recovery.claimAndSend(owner: owner, teamId: "4101", meetingId: "meet-4101", fields: fields)
        XCTAssertEqual(sent.phase, .confirmed)
        XCTAssertEqual(fake.confirmations.count, 1)
        let revived = TeamMeetingPendingJournal(root: root)
        let loaded = try XCTUnwrap(try revived.record(owner: owner, teamId: "4101", meetingId: "meet-4101"))
        XCTAssertEqual(loaded.requestId, "request-0001")
        XCTAssertEqual(loaded.phase, .confirmed)
        let bytes = try Data(contentsOf: try XCTUnwrap(try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).first))
        let text = String(decoding: bytes, as: UTF8.self)
        XCTAssertFalse(text.contains(nonce))
        XCTAssertFalse(text.contains(token))
        XCTAssertFalse(text.contains("OpaqueSignatureValue1"))
        var tampered = try XCTUnwrap(try JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        tampered["nonce"] = nonce
        let extra = try JSONSerialization.data(withJSONObject: tampered)
        XCTAssertThrowsError(try TeamMeetingIntentWire.decode(extra))
    }

    func testAccountAndTeamJournalsStayApart() async throws {
        let root = try scratch()
        let journal = TeamMeetingPendingJournal(root: root)
        let owner = try TeamMeetingOwner(accountID: 901, namespace: "offline-team-fixture")
        let other = try TeamMeetingOwner(accountID: 903, namespace: "offline-team-fixture")
        let fake = MeetingRecoveryFake()
        let recovery = TeamMeetingRecovery(journal: journal, service: fake)
        _ = try await recovery.claimAndSend(owner: owner, teamId: "4101", meetingId: "meet-4101", fields: try fields(teamID: 4101, requestId: "request-0001", nonce: "PeerNonceValue0000000001"))
        XCTAssertEqual(try journal.record(owner: owner, teamId: "4101", meetingId: "meet-4101")?.phase, .confirmed)
        XCTAssertNil(try journal.record(owner: other, teamId: "4101", meetingId: "meet-4101"))
        XCTAssertNil(journal.outstanding(owner: other, teamId: "4101"))
        XCTAssertNil(try journal.record(owner: owner, teamId: "9999", meetingId: "meet-9999"))
        XCTAssertNil(journal.outstanding(owner: owner, teamId: "9999"))
        XCTAssertNil(journal.outstanding(owner: owner, teamId: "4101"))
        let foreign = TeamMeetingFlow(teamID: 9999, service: fake, capabilities: enabled, journal: journal, owner: owner)
        await foreign.open()
        XCTAssertEqual(foreign.meeting?.phase, .readyToMeet)
        XCTAssertEqual(fake.confirmations.count, 1)
    }

    func testPreparedSendsOnceAndLaterPhasesDoNot() async throws {
        let root = try scratch()
        let owner = try TeamMeetingOwner(accountID: 901, namespace: "offline-team-fixture")
        let journal = TeamMeetingPendingJournal(root: root)
        let fake = MeetingRecoveryFake()
        let recovery = TeamMeetingRecovery(journal: journal, service: fake)
        _ = try journal.prepare(owner: owner, teamId: "4101", meetingId: "meet-4101", requestId: "request-0001")
        let first = try await recovery.claimAndSend(owner: owner, teamId: "4101", meetingId: "meet-4101", fields: try fields(teamID: 4101, requestId: "request-0001", nonce: "PeerNonceValue0000000001"))
        XCTAssertTrue(first.sentThisCall)
        XCTAssertEqual(first.phase, .confirmed)
        let second = try await recovery.claimAndSend(owner: owner, teamId: "4101", meetingId: "meet-4101", fields: try fields(teamID: 4101, requestId: "request-0001", nonce: "PeerNonceValue0000000001"))
        XCTAssertFalse(second.sentThisCall)
        XCTAssertEqual(fake.confirmations.count, 1)
        let looked = try await recovery.lookup(owner: owner, teamId: "4101", meetingId: "meet-4101")
        XCTAssertEqual(looked?.phase, .confirmed)
        XCTAssertEqual(fake.confirmations.count, 1)
    }

    func testLostResponseIsUnknownUntilReadback() async throws {
        let root = try scratch()
        let owner = try TeamMeetingOwner(accountID: 901, namespace: "offline-team-fixture")
        let journal = TeamMeetingPendingJournal(root: root)
        let fake = MeetingRecoveryFake()
        fake.decision = nil
        let recovery = TeamMeetingRecovery(journal: journal, service: fake)
        let lost = try await recovery.claimAndSend(owner: owner, teamId: "4101", meetingId: "meet-4101", fields: try fields(teamID: 4101, requestId: "request-0001", nonce: "PeerNonceValue0000000001"))
        XCTAssertEqual(lost.phase, .unknown)
        XCTAssertNil(lost.verified)
        XCTAssertEqual(journal.outstanding(owner: owner, teamId: "4101")?.requestId, "request-0001")
        let blocked = try await recovery.claimAndSend(owner: owner, teamId: "4101", meetingId: "meet-4101", fields: try fields(teamID: 4101, requestId: "request-0002", nonce: "PeerNonceValue0000000002"))
        XCTAssertFalse(blocked.sentThisCall)
        XCTAssertEqual(fake.confirmations.count, 1)
        let waiting = try await recovery.lookup(owner: owner, teamId: "4101", meetingId: "meet-4101")
        XCTAssertEqual(waiting?.phase, .unknown)
        fake.readback = true
        let found = try await recovery.lookup(owner: owner, teamId: "4101", meetingId: "meet-4101")
        XCTAssertEqual(found?.verified, true)
        XCTAssertEqual(found?.phase, .confirmed)
        XCTAssertEqual(fake.confirmations.count, 1)
    }

    func testCancelCasesDoNotResendOrUnconfirm() async throws {
        let prepared = try await cancelFixture()
        _ = try prepared.journal.prepare(owner: prepared.owner, teamId: "4101", meetingId: "meet-4101", requestId: "request-0001")
        XCTAssertEqual(try prepared.recovery.classifyCancel(owner: prepared.owner, teamId: "4101", meetingId: "meet-4101"), .notSent)
        XCTAssertEqual(try prepared.journal.record(owner: prepared.owner, teamId: "4101", meetingId: "meet-4101")?.phase, .cancelledBeforeSend)
        XCTAssertEqual(prepared.fake.confirmations.count, 0)
        let again = try await prepared.recovery.claimAndSend(owner: prepared.owner, teamId: "4101", meetingId: "meet-4101", fields: try fields(teamID: 4101, requestId: "request-0002", nonce: "PeerNonceValue0000000002"))
        XCTAssertFalse(again.sentThisCall)
        XCTAssertEqual(prepared.fake.confirmations.count, 0)

        let unknown = try await cancelFixture()
        unknown.fake.decision = nil
        _ = try await unknown.recovery.claimAndSend(owner: unknown.owner, teamId: "4101", meetingId: "meet-4101", fields: try fields(teamID: 4101, requestId: "request-0001", nonce: "PeerNonceValue0000000001"))
        XCTAssertEqual(try unknown.recovery.classifyCancel(owner: unknown.owner, teamId: "4101", meetingId: "meet-4101"), .sentUnknown)
        XCTAssertEqual(try unknown.journal.record(owner: unknown.owner, teamId: "4101", meetingId: "meet-4101")?.phase, .unknown)

        let confirmed = try await cancelFixture()
        _ = try await confirmed.recovery.claimAndSend(owner: confirmed.owner, teamId: "4101", meetingId: "meet-4101", fields: try fields(teamID: 4101, requestId: "request-0001", nonce: "PeerNonceValue0000000001"))
        XCTAssertEqual(try confirmed.recovery.classifyCancel(owner: confirmed.owner, teamId: "4101", meetingId: "meet-4101"), .confirmed)
        XCTAssertEqual(try confirmed.journal.record(owner: confirmed.owner, teamId: "4101", meetingId: "meet-4101")?.phase, .confirmed)
        XCTAssertEqual(confirmed.fake.cancelCount, 0)
    }

    func testRefusedReplacementUsesANewRequestOnly() async throws {
        let root = try scratch()
        let owner = try TeamMeetingOwner(accountID: 901, namespace: "offline-team-fixture")
        let journal = TeamMeetingPendingJournal(root: root)
        let fake = MeetingRecoveryFake()
        fake.decision = false
        let recovery = TeamMeetingRecovery(journal: journal, service: fake)
        _ = try await recovery.claimAndSend(owner: owner, teamId: "4101", meetingId: "meet-4101", fields: try fields(teamID: 4101, requestId: "request-0001", nonce: "PeerNonceValue0000000001"))
        let same = try await recovery.claimAndSend(owner: owner, teamId: "4101", meetingId: "meet-4101", fields: try fields(teamID: 4101, requestId: "request-0001", nonce: "PeerNonceValue0000000001"))
        XCTAssertFalse(same.sentThisCall)
        fake.decision = true
        let replaced = try await recovery.claimAndSend(owner: owner, teamId: "4101", meetingId: "meet-4101", fields: try fields(teamID: 4101, requestId: "request-0002", nonce: "PeerNonceValue0000000002"))
        XCTAssertTrue(replaced.sentThisCall)
        XCTAssertEqual(replaced.requestId, "request-0002")
        XCTAssertEqual(fake.confirmations.count, 2)
    }

    func testInMemoryMeetingStillConfirmsWithoutAJournal() async throws {
        let fake = MeetingRecoveryFake()
        let flow = TeamMeetingFlow(teamID: 4101, service: fake, capabilities: enabled)
        await flow.open(); await flow.startHandshake()
        await flow.submitScanned(try peer())
        XCTAssertEqual(flow.meeting?.phase, .met)
        XCTAssertEqual(fake.confirmations.count, 1)
        XCTAssertFalse(flow.blocksResend)
        XCTAssertNil(flow.cancelCase)
    }

    func testRestartLooksUpTheOriginalRequestAndDoesNotSendAgain() async throws {
        let root = try scratch()
        let owner = try TeamMeetingOwner(accountID: 901, namespace: "offline-team-fixture")
        let journal = TeamMeetingPendingJournal(root: root)
        let fake = MeetingRecoveryFake()
        fake.decision = nil
        let flow = TeamMeetingFlow(teamID: 4101, service: fake, capabilities: enabled, journal: journal, owner: owner)
        await flow.open(); await flow.startHandshake()
        await flow.submitScanned(try peer())
        XCTAssertEqual(flow.meeting?.phase, .confirmationPending)
        XCTAssertEqual(flow.scanIssue, .outcomeUnknown)
        XCTAssertTrue(flow.blocksResend)
        let restarted = TeamMeetingFlow(teamID: 4101, service: fake, capabilities: enabled, journal: TeamMeetingPendingJournal(root: root), owner: owner)
        await restarted.open()
        XCTAssertEqual(restarted.meeting?.phase, .confirmationPending)
        await restarted.submitScanned(try peer(nonce: "PeerNonceValue0000000002"))
        XCTAssertEqual(fake.confirmations.count, 1)
        fake.readback = true
        await restarted.readBackConfirmation()
        XCTAssertEqual(restarted.meeting?.phase, .met)
        XCTAssertEqual(fake.confirmations.count, 1)
    }

    func testFlowCancelDistinguishesNotSentUnknownAndConfirmed() async throws {
        let unsent = try await flowFixture()
        _ = try unsent.journal.prepare(owner: unsent.owner, teamId: "4101", meetingId: "meet-4101", requestId: "request-0001")
        await unsent.flow.open()
        XCTAssertEqual(unsent.flow.meeting?.phase, .confirmationPending)
        await unsent.flow.cancel()
        XCTAssertEqual(unsent.flow.cancelCase, .notSent)
        XCTAssertEqual(unsent.flow.meeting?.phase, .cancelled)
        XCTAssertEqual(unsent.fake.confirmations.count, 0)
        await unsent.flow.submitScanned(try peer())
        XCTAssertEqual(unsent.fake.confirmations.count, 0)

        let pending = try await flowFixture()
        pending.fake.decision = nil
        await pending.flow.open(); await pending.flow.startHandshake()
        await pending.flow.submitScanned(try peer())
        await pending.flow.cancel()
        XCTAssertEqual(pending.flow.cancelCase, .sentUnknown)
        XCTAssertEqual(pending.flow.meeting?.phase, .confirmationPending)
        XCTAssertNotNil(pending.flow.meeting?.pendingRequestId)
        XCTAssertEqual(try pending.journal.record(owner: pending.owner, teamId: "4101", meetingId: "meet-4101")?.phase, .unknown)
        XCTAssertEqual(pending.fake.cancelCount, 1)
        pending.fake.readback = true
        await pending.flow.readBackConfirmation()
        XCTAssertEqual(pending.flow.meeting?.phase, .met)
        XCTAssertEqual(pending.fake.confirmations.count, 1)

        let done = try await flowFixture()
        await done.flow.open(); await done.flow.startHandshake()
        await done.flow.submitScanned(try peer())
        XCTAssertEqual(done.flow.meeting?.phase, .met)
        await done.flow.cancel()
        XCTAssertEqual(done.flow.cancelCase, .confirmed)
        XCTAssertEqual(done.flow.meeting?.phase, .met)
        XCTAssertEqual(done.fake.cancelCount, 0)
        XCTAssertEqual(done.fake.confirmations.count, 1)
    }

    func testCloseDuringConfirmDoesNotDoubleConfirmOrCrossTeams() async throws {
        let root = try scratch()
        let owner = try TeamMeetingOwner(accountID: 901, namespace: "offline-team-fixture")
        let other = try TeamMeetingOwner(accountID: 903, namespace: "offline-team-fixture")
        let journal = TeamMeetingPendingJournal(root: root)
        let fake = MeetingRecoveryFake()
        let flow = TeamMeetingFlow(teamID: 4101, service: fake, capabilities: enabled, journal: journal, owner: owner)
        fake.onConfirm = { [weak flow] in await flow?.close() }
        await flow.open(); await flow.startHandshake()
        await flow.submitScanned(try peer())
        XCTAssertEqual(flow.phase, .closed)
        XCTAssertEqual(fake.confirmations.count, 1)
        let restarted = TeamMeetingFlow(teamID: 4101, service: fake, capabilities: enabled, journal: journal, owner: owner)
        await restarted.open()
        XCTAssertEqual(restarted.meeting?.phase, .met)
        await restarted.submitScanned(try peer(nonce: "PeerNonceValue0000000002"))
        XCTAssertEqual(fake.confirmations.count, 1)
        let switched = TeamMeetingFlow(teamID: 4101, service: MeetingRecoveryFake(), capabilities: enabled, journal: journal, owner: other)
        await switched.open()
        XCTAssertEqual(switched.meeting?.phase, .readyToMeet)
    }

    private func scratch() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("meeting-intent-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    private func fields(teamID: Int, requestId: String, nonce: String) throws -> [String: String] {
        ["meetingId": "meet-\(teamID)", "teamId": "\(teamID)", "nonce": nonce, "keyVersion": "k1", "signature": "OpaqueSignatureValue1", "purpose": TeamMeetingChallenge.purpose, "requestId": requestId]
    }
    private func peer(teamID: Int = 4101, nonce: String = "PeerNonceValue0000000001") throws -> TeamMeetingChallenge {
        let issued = Int64(Date().timeIntervalSince1970 * 1000)
        return try TeamMeetingChallenge(meetingId: "meet-\(teamID)", teamId: "\(teamID)", issuerMemberId: "902", receiverMemberId: "901",
                                        purpose: TeamMeetingChallenge.purpose, nonce: nonce, keyVersion: "k1", signature: "OpaqueSignatureValue1",
                                        issuedAtMillis: issued, expiresAtMillis: issued + 60_000)
    }
    private func cancelFixture() async throws -> (journal: TeamMeetingPendingJournal, owner: TeamMeetingOwner, recovery: TeamMeetingRecovery, fake: MeetingRecoveryFake) {
        let root = try scratch()
        let owner = try TeamMeetingOwner(accountID: 901, namespace: "offline-team-fixture")
        let journal = TeamMeetingPendingJournal(root: root)
        let fake = MeetingRecoveryFake()
        return (journal, owner, TeamMeetingRecovery(journal: journal, service: fake), fake)
    }
    private func flowFixture() async throws -> (flow: TeamMeetingFlow, journal: TeamMeetingPendingJournal, owner: TeamMeetingOwner, fake: MeetingRecoveryFake) {
        let root = try scratch()
        let owner = try TeamMeetingOwner(accountID: 901, namespace: "offline-team-fixture")
        let journal = TeamMeetingPendingJournal(root: root)
        let fake = MeetingRecoveryFake()
        let flow = TeamMeetingFlow(teamID: 4101, service: fake, capabilities: enabled, journal: journal, owner: owner)
        return (flow, journal, owner, fake)
    }
}

@MainActor private final class MeetingRecoveryFake: TeamMeetingServing {
    var decision: Bool? = true
    var readback: Bool?
    var confirmations: [[String: String]] = []
    var cancelCount = 0
    var onConfirm: (() async -> Void)?
    func eligibility(teamID: Int) async throws -> TeamMeetingEligibility? {
        try TeamMeetingEligibility(teamId: "\(teamID)", meetingId: "meet-\(teamID)", selfMemberId: "901", peerMemberId: "902", formation: "CONFIRMED", teamStatus: .full)
    }
    func realNameVerified(meetingId: String) async throws -> Bool { true }
    func issueChallenge(meetingId: String) async throws -> TeamMeetingChallenge {
        let issued = Int64(Date().timeIntervalSince1970 * 1000)
        return try TeamMeetingChallenge(meetingId: meetingId, teamId: "4101", issuerMemberId: "901", receiverMemberId: "902",
                                        purpose: TeamMeetingChallenge.purpose, nonce: "OwnNonceValue00000000001", keyVersion: "k1",
                                        signature: "OpaqueSignatureValue1", issuedAtMillis: issued, expiresAtMillis: issued + 60_000)
    }
    func serverClockOffset() async throws -> TimeInterval { 0 }
    func confirm(_ fields: [String: String]) async -> Bool? {
        confirmations.append(fields)
        if decision != nil { readback = decision }
        await onConfirm?()
        return decision
    }
    func confirmationReadback(meetingId: String, requestId: String) async throws -> Bool? { readback }
    func cancel(meetingId: String) async -> Bool { cancelCount += 1; return true }
}
