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
    public let handshakes: [TeamMeetingHandshake]
    private let service: (any TeamMeetingServing)?
    private let capabilities: ReformWorldCapabilities
    private var serverOffset: TimeInterval = 0
    private var generation: UInt64 = 0

    public init(teamID: Int, service: (any TeamMeetingServing)?, capabilities: ReformWorldCapabilities = .disabled, deviceReportsNFC: Bool = false) {
        self.teamID = teamID; self.service = service; self.capabilities = capabilities
        handshakes = TeamMeetingHandshake.available(capabilities: capabilities, deviceReportsNFC: deviceReportsNFC)
    }

    public var available: Bool { capabilities.allows(.teamFirstMeeting) && service != nil && teamID > 0 }
    /// U05: offered only for a full or in-progress team; the server still decides eligibility.
    public static func mayOffer(_ detail: TeamDetail?) -> Bool {
        guard let detail else { return false }
        return detail.joined == true && (detail.team.status == .full || detail.team.status == .inProgress)
    }

    public func open() async {
        guard available, let service, !busy else { phase = .closed; return }
        generation &+= 1; let stamp = generation; busy = true; phase = .loading; scanIssue = nil
        defer { if generation == stamp { busy = false } }
        do {
            guard let eligibility = try await service.eligibility(teamID: teamID) else {
                guard generation == stamp else { return }; phase = .notEligible; return
            }
            let verified = try await service.realNameVerified(meetingId: eligibility.meetingId)
            serverOffset = try await service.serverClockOffset()
            guard generation == stamp, !Task.isCancelled else { return }
            meeting = TeamFirstMeeting(eligibility: eligibility, realNameVerified: verified)
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
        if verified, (try? value.realNameConfirmedByServer()) != nil { meeting = value }
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
        guard let service, var value = meeting, value.phase == .confirmationPending, let requestId = value.pendingRequestId, !busy else { return }
        generation &+= 1; let stamp = generation; busy = true
        defer { if generation == stamp { busy = false } }
        guard let decision = try? await service.confirmationReadback(meetingId: value.eligibility.meetingId, requestId: requestId),
              generation == stamp else { return }
        if (try? value.serverDecision(requestId: requestId, verified: decision)) != nil { meeting = value; scanIssue = decision ? nil : .wrongCode }
    }

    /// U04: cancel is final locally at once; the server call is still made and an unknown is reported.
    public func cancel() async {
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
}
