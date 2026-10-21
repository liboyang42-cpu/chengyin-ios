import Foundation

/// Reform plan v9 §24 / W16 with U05–U07 and U04 as a dormant client flow on top of
/// `TeamFirstMeeting`. Nothing here exists in the mini-program; no meeting endpoint is reviewed,
/// so there is no production port. Closed unless `ReformWorldCapabilities.teamFirstMeeting` is on
/// (DEBUG fixtures only). The flow never holds coordinates, never matches by interest, asks for
/// real-name status only inside this meeting, and never decides that a handshake succeeded.
@MainActor public protocol TeamMeetingServing: AnyObject {
    /// Server readback for a confirmed team. nil means the team is not eligible for a meeting.
    func eligibility(teamID: Int) async throws -> TeamMeetingEligibility?
    /// Real-name status scoped to this meeting only (U06).
    func realNameVerified(meetingId: String) async throws -> Bool
    /// This member's rotating code to show the peer (U07). The payload is opaque to the client.
    func issueChallenge(meetingId: String) async throws -> TeamMeetingChallenge
    /// Server offset (server minus device) used to judge expiry; a changed phone clock does not move it.
    func serverClockOffset() async throws -> TimeInterval
    /// Submits a scanned peer code. nil means the response was lost and must be read back.
    func confirm(_ fields: [String: String]) async -> Bool?
    /// Readback for a lost confirmation. nil means the server has not decided yet.
    func confirmationReadback(meetingId: String, requestId: String) async throws -> Bool?
    /// Either side may cancel; the server outcome is final (U04).
    func cancel(meetingId: String) async -> Bool
}

@MainActor public final class TeamMeetingFlow {
    public enum Phase: Equatable { case closed, loading, notEligible, failed, active }
    public enum ScanIssue: Equatable { case wrongCode, expired, replayed, malformed, outcomeUnknown }
    public let teamID: Int
    public private(set) var phase: Phase = .closed
    public private(set) var meeting: TeamFirstMeeting?
    public private(set) var myChallenge: TeamMeetingChallenge?
    public private(set) var scanIssue: ScanIssue?
    public private(set) var busy = false
    public private(set) var cancelUnknown = false
    public private(set) var cancelCase: TeamMeetingCancelCase?
    public let handshakes: [TeamMeetingHandshake]
    private let service: (any TeamMeetingServing)?
    private let capabilities: ReformWorldCapabilities
    private let journal: TeamMeetingPendingJournal?
    private let owner: TeamMeetingOwner?
    private var serverOffset: TimeInterval = 0
    private var generation: UInt64 = 0

    public init(teamID: Int, service: (any TeamMeetingServing)?, capabilities: ReformWorldCapabilities = .disabled, deviceReportsNFC: Bool = false, journal: TeamMeetingPendingJournal? = nil, owner: TeamMeetingOwner? = nil) {
        self.teamID = teamID; self.service = service; self.capabilities = capabilities
        self.journal = journal; self.owner = owner
        handshakes = TeamMeetingHandshake.available(capabilities: capabilities, deviceReportsNFC: deviceReportsNFC)
    }

    /// True when a stored intent must not be scanned again. A missing journal keeps the in-memory path.
    public var blocksResend: Bool {
        guard let journal, let owner, let meeting else { return false }
        do {
            guard let row = try journal.record(owner: owner, teamId: meeting.eligibility.teamId, meetingId: meeting.eligibility.meetingId) else { return false }
            return row.blocksNewSend
        } catch { return true }
    }

    public var available: Bool { capabilities.allows(.teamFirstMeeting) && service != nil && teamID > 0 }
    /// U05: offered only for a full or in-progress team; the server still decides eligibility.
    public static func mayOffer(_ detail: TeamDetail?) -> Bool {
        guard let detail else { return false }
        return detail.joined == true && (detail.team.status == .full || detail.team.status == .inProgress)
    }

    public func open() async {
        guard available, let service, !busy else { phase = .closed; return }
        generation &+= 1; let stamp = generation; busy = true; phase = .loading; scanIssue = nil; cancelCase = nil
        defer { if generation == stamp { busy = false } }
        do {
            guard let eligibility = try await service.eligibility(teamID: teamID) else {
                guard generation == stamp else { return }; phase = .notEligible; return
            }
            let verified = try await service.realNameVerified(meetingId: eligibility.meetingId)
            serverOffset = try await service.serverClockOffset()
            guard generation == stamp, !Task.isCancelled else { return }
            meeting = TeamFirstMeeting(eligibility: eligibility, realNameVerified: verified)
            restoreDurable()
            phase = .active
        } catch {
            guard generation == stamp else { return }
            meeting = nil; phase = .failed
        }
    }

    /// U06: re-reads the server status; the client never marks itself verified.
    public func recheckRealName() async {
        guard let service, var value = meeting, value.phase == .realNameRequired, !busy else { return }
        generation &+= 1; let stamp = generation; busy = true
        defer { if generation == stamp { busy = false } }
        guard let verified = try? await service.realNameVerified(meetingId: value.eligibility.meetingId), generation == stamp else { return }
        if verified, (try? value.realNameConfirmedByServer()) != nil { meeting = value; restoreDurable() }
    }

    /// Starts the handshake and fetches this member's rotating code.
    public func startHandshake() async {
        guard let service, var value = meeting, !busy else { return }
        guard (try? value.beginHandshake()) != nil else { return }
        meeting = value
        await refreshMyCode(service)
    }

    public func refreshMyCode() async { if let service, meeting?.phase == .handshaking { await refreshMyCode(service) } }

    private func refreshMyCode(_ service: any TeamMeetingServing) async {
        guard let value = meeting else { return }
        generation &+= 1; let stamp = generation; busy = true
        defer { if generation == stamp { busy = false } }
        let challenge = try? await service.issueChallenge(meetingId: value.eligibility.meetingId)
        guard generation == stamp else { return }
        // Only a code bound to this meeting and issued by this member is shown.
        if let challenge, challenge.meetingId == value.eligibility.meetingId, challenge.teamId == value.eligibility.teamId,
           challenge.issuerMemberId == value.eligibility.selfMemberId, challenge.receiverMemberId == value.eligibility.peerMemberId {
            myChallenge = challenge
        } else { myChallenge = nil }
    }

    public func myCodeExpired(now: Date = Date()) -> Bool {
        guard let myChallenge else { return true }
        return now.addingTimeInterval(serverOffset) >= myChallenge.expiresAt
    }

    /// A scanned peer code. Camera capture is not wired; fixtures inject the decoded challenge.
    public func submitScanned(_ challenge: TeamMeetingChallenge, now: Date = Date()) async {
        guard journal == nil || owner == nil else { await submitDurable(challenge, now: now); return }
        guard let service, var value = meeting, !busy else { return }
        let fields: [String: String]
        do { fields = try value.scanned(challenge, deviceNow: now, serverOffset: serverOffset) }
        catch let issue as TeamMeetingIssue {
            switch issue {
            case .expired: scanIssue = .expired
            case .replayed: scanIssue = .replayed
            case .wrongBinding: scanIssue = .wrongCode
            default: scanIssue = .malformed
            }
            return
        } catch { scanIssue = .malformed; return }
        meeting = value; scanIssue = nil
        generation &+= 1; let stamp = generation; busy = true
        defer { if generation == stamp { busy = false } }
        let decision = await service.confirm(fields)
        guard generation == stamp, var current = meeting, let requestId = fields["requestId"] else { return }
        guard let decision else { scanIssue = .outcomeUnknown; return }
        // A cancel that landed first makes this a no-op (U04).
        if (try? current.serverDecision(requestId: requestId, verified: decision)) != nil { meeting = current }
        if !decision { scanIssue = .wrongCode }
    }

    /// Lost confirmation: read back by the same request id; never re-submit the nonce.
    public func readBackConfirmation() async {
        guard journal == nil || owner == nil else { await readBackDurable(); return }
        guard let service, var value = meeting, value.phase == .confirmationPending, let requestId = value.pendingRequestId, !busy else { return }
        generation &+= 1; let stamp = generation; busy = true
        defer { if generation == stamp { busy = false } }
        guard let decision = try? await service.confirmationReadback(meetingId: value.eligibility.meetingId, requestId: requestId),
              generation == stamp else { return }
        if (try? value.serverDecision(requestId: requestId, verified: decision)) != nil { meeting = value; scanIssue = decision ? nil : .wrongCode }
    }

    /// U04: cancel is final locally at once; the server call is still made and an unknown is reported.
    public func cancel() async {
        guard journal == nil || owner == nil else { await cancelDurable(); return }
        guard var value = meeting else { return }
        value.cancel(); meeting = value; myChallenge = nil
        guard let service else { return }
        generation &+= 1; let stamp = generation; busy = true
        defer { if generation == stamp { busy = false } }
        let confirmed = await service.cancel(meetingId: value.eligibility.meetingId)
        guard generation == stamp else { return }
        cancelUnknown = !confirmed
    }

    public func close() { generation &+= 1; busy = false; phase = .closed; myChallenge = nil; scanIssue = nil }

    private func recovery() -> TeamMeetingRecovery? {
        guard let journal, let service else { return nil }
        return TeamMeetingRecovery(journal: journal, service: service)
    }

    private func restoreDurable() {
        guard let journal, let owner, var value = meeting else { return }
        guard let record = try? journal.record(owner: owner, teamId: value.eligibility.teamId, meetingId: value.eligibility.meetingId) else { return }
        switch record.phase {
        case .prepared, .unknown:
            if (try? value.restorePending(requestId: record.requestId)) != nil { meeting = value }
        case .confirmed:
            if (try? value.restorePending(requestId: record.requestId)) != nil,
               (try? value.serverDecision(requestId: record.requestId, verified: true)) != nil { meeting = value }
        case .refused:
            if (try? value.restorePending(requestId: record.requestId)) != nil,
               (try? value.serverDecision(requestId: record.requestId, verified: false)) != nil { meeting = value }
        case .cancelledBeforeSend:
            value.cancel(); meeting = value
        }
    }

    private func submitDurable(_ challenge: TeamMeetingChallenge, now: Date) async {
        guard let journal, let owner, let service, var value = meeting, !busy else { return }
        let teamId = value.eligibility.teamId, meetingId = value.eligibility.meetingId
        let existing: TeamMeetingIntentRecord?
        do { existing = try journal.record(owner: owner, teamId: teamId, meetingId: meetingId) }
        catch { scanIssue = .outcomeUnknown; return }
        if let existing, existing.blocksNewSend {
            if existing.phase == .cancelledBeforeSend { value.cancel(); meeting = value; myChallenge = nil; cancelCase = .notSent; return }
            apply(TeamMeetingSubmitResult(requestId: existing.requestId, teamId: existing.teamId, meetingId: existing.meetingId, phase: existing.phase, verified: existing.phase == .confirmed ? true : nil, sentThisCall: false))
            return
        }
        let fields: [String: String]
        do { fields = try value.scanned(challenge, deviceNow: now, serverOffset: serverOffset) }
        catch let issue as TeamMeetingIssue {
            switch issue {
            case .expired: scanIssue = .expired
            case .replayed: scanIssue = .replayed
            case .wrongBinding: scanIssue = .wrongCode
            default: scanIssue = .malformed
            }
            return
        } catch { scanIssue = .malformed; return }
        guard fields["teamId"] == teamId, fields["meetingId"] == meetingId, let requestId = fields["requestId"] else { scanIssue = .malformed; return }
        meeting = value; scanIssue = nil
        generation &+= 1; let stamp = generation; busy = true
        defer { if generation == stamp { busy = false } }
        let result: TeamMeetingSubmitResult
        do { result = try await TeamMeetingRecovery(journal: journal, service: service).claimAndSend(owner: owner, teamId: teamId, meetingId: meetingId, fields: fields) }
        catch { scanIssue = .outcomeUnknown; return }
        guard generation == stamp, var current = meeting, result.teamId == teamId, result.meetingId == meetingId else { return }
        if result.requestId != requestId, let nonce = fields["nonce"], (try? current.abandonUnsent(requestId: requestId, nonce: nonce)) != nil { meeting = current }
        apply(result)
    }

    private func readBackDurable() async {
        guard let owner, let recovery = recovery(), let value = meeting, !busy else { return }
        let teamId = value.eligibility.teamId, meetingId = value.eligibility.meetingId
        generation &+= 1; let stamp = generation; busy = true
        defer { if generation == stamp { busy = false } }
        guard let result = try? await recovery.lookup(owner: owner, teamId: teamId, meetingId: meetingId), generation == stamp else { return }
        guard result.teamId == teamId, result.meetingId == meetingId else { return }
        apply(result)
    }

    /// Refused is an answered confirm, so it keeps the ordinary local cancel. The other phases stay distinct.
    private func cancelDurable() async {
        guard let journal, let owner, let recovery = recovery(), var value = meeting else { return }
        let teamId = value.eligibility.teamId, meetingId = value.eligibility.meetingId
        let prior = try? journal.record(owner: owner, teamId: teamId, meetingId: meetingId)
        let kind = (try? recovery.classifyCancel(owner: owner, teamId: teamId, meetingId: meetingId)) ?? .notSent
        if prior?.phase == .refused {
            cancelCase = nil; value.cancel(); meeting = value; myChallenge = nil
            await serverCancel(meetingId); return
        }
        cancelCase = kind
        switch kind {
        case .confirmed:
            return
        case .sentUnknown:
            await serverCancel(meetingId)
        case .notSent:
            value.cancel(); meeting = value; myChallenge = nil
            await serverCancel(meetingId)
        }
    }

    private func serverCancel(_ meetingId: String) async {
        guard let service else { cancelUnknown = true; return }
        generation &+= 1; let stamp = generation; busy = true
        defer { if generation == stamp { busy = false } }
        let confirmed = await service.cancel(meetingId: meetingId)
        guard generation == stamp else { return }
        cancelUnknown = !confirmed
    }

    private func apply(_ result: TeamMeetingSubmitResult) {
        guard var current = meeting, result.teamId == current.eligibility.teamId, result.meetingId == current.eligibility.meetingId else { return }
        if result.phase == .cancelledBeforeSend {
            if !current.phase.isTerminal { current.cancel(); meeting = current; myChallenge = nil; cancelCase = .notSent }
            return
        }
        if current.phase.isTerminal { return }
        if current.phase != .confirmationPending || current.pendingRequestId != result.requestId {
            guard (try? current.restorePending(requestId: result.requestId)) != nil else { return }
            meeting = current
        }
        guard let verified = result.verified else { scanIssue = .outcomeUnknown; return }
        if (try? current.serverDecision(requestId: result.requestId, verified: verified)) != nil {
            meeting = current; scanIssue = verified ? nil : .wrongCode
        }
    }
}
