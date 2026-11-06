import Foundation

/// Reform plan v9 §24 / W16 with decisions U05–U07 and U04:
/// - U05: strangers meet offline only inside a theme or a team that has ALREADY been
///   confirmed by the server; there is no interest matching and no matching entry.
/// - U06: real-name verification applies to this stranger-meeting flow only, never to
///   the App, ordinary play, friend invites or map reads.
/// - U07: the handshake is a rotating server-issued QR or phone NFC. NFC is not
///   verified on any device, so QR is always offered and NFC never replaces it.
/// - U04: a cancel/revoke by either side is final for this meeting.
/// Client contract only. No exact coordinates exist in this type by design (MV38).
public enum TeamMeetingIssue: Error, Equatable {
    case invalid, teamNotConfirmed, notMember, realNameRequired, illegalTransition, expired, replayed, wrongBinding, unsupported
}

/// The only flow in which real-name verification may be requested.
public enum RealNameScope: Sendable {
    public enum Flow: Sendable { case strangerTeamMeeting, ordinaryPlay, friendInvite, mapRead, teamJoin, publish }
    public static func requiresRealName(_ flow: Flow) -> Bool { flow == .strangerTeamMeeting }
}

/// Server facts that open the meeting step. Built from a team readback, never from local state.
public struct TeamMeetingEligibility: Equatable, Sendable {
    public let teamId: String
    public let meetingId: String
    public let selfMemberId: String
    public let peerMemberId: String
    public init(teamId: String, meetingId: String, selfMemberId: String, peerMemberId: String, formation: String, teamStatus: TeamStatus) throws {
        guard [teamId, meetingId, selfMemberId, peerMemberId].allSatisfy(ReformWire.id), selfMemberId != peerMemberId else { throw TeamMeetingIssue.invalid }
        // U05: only a server-confirmed team success opens the meeting step.
        guard formation == "CONFIRMED", teamStatus == .full || teamStatus == .inProgress else { throw TeamMeetingIssue.teamNotConfirmed }
        self.teamId = teamId; self.meetingId = meetingId; self.selfMemberId = selfMemberId; self.peerMemberId = peerMemberId
    }
}

public enum TeamMeetingHandshake: Equatable, Sendable {
    case dynamicQR
    /// Offered only when enabled AND the device reports support; still unverified end to end.
    case nfcUnverified
    public static func available(capabilities: ReformWorldCapabilities, deviceReportsNFC: Bool) -> [TeamMeetingHandshake] {
        capabilities.allows(.meetingNFC) && deviceReportsNFC ? [.dynamicQR, .nfcUnverified] : [.dynamicQR]
    }
}

/// One server-issued rotating QR challenge. The signature is opaque: the client never
/// holds a signing key and never decides that a handshake succeeded.
public struct TeamMeetingChallenge: Equatable, Sendable {
    public static let purpose = "TEAM_MEETING_HANDSHAKE"
    public let meetingId, teamId, issuerMemberId, receiverMemberId, nonce, keyVersion, signature: String
    public let issuedAt, expiresAt: Date
    public init(meetingId: String, teamId: String, issuerMemberId: String, receiverMemberId: String, purpose: String, nonce: String, keyVersion: String, signature: String, issuedAtMillis: Int64, expiresAtMillis: Int64) throws {
        guard purpose == Self.purpose, [meetingId, teamId, issuerMemberId, receiverMemberId, keyVersion].allSatisfy(ReformWire.id), issuerMemberId != receiverMemberId,
              nonce.range(of: "\\A[A-Za-z0-9_-]{22,128}\\z", options: .regularExpression) != nil,
              signature.range(of: "\\A[A-Za-z0-9_-]{16,512}\\z", options: .regularExpression) != nil,
              issuedAtMillis > 0, expiresAtMillis > issuedAtMillis,
              // Sanity bound against malformed payloads only; the real rotation window is a server fact.
              expiresAtMillis - issuedAtMillis <= 600_000 else { throw TeamMeetingIssue.invalid }
        self.meetingId = meetingId; self.teamId = teamId; self.issuerMemberId = issuerMemberId; self.receiverMemberId = receiverMemberId
        self.nonce = nonce; self.keyVersion = keyVersion; self.signature = signature
        issuedAt = Date(timeIntervalSince1970: Double(issuedAtMillis) / 1000); expiresAt = Date(timeIntervalSince1970: Double(expiresAtMillis) / 1000)
    }
}

public struct TeamFirstMeeting: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case realNameRequired, readyToMeet, handshaking, confirmationPending, met, cancelled, expired
        var isTerminal: Bool { [.met, .cancelled, .expired].contains(self) }
    }
    public let eligibility: TeamMeetingEligibility
    public private(set) var phase: Phase
    /// Nonces this device already submitted; a repeated scan never re-submits.
    public private(set) var submittedNonces: Set<String> = []
    public private(set) var pendingRequestId: String?

    public init(eligibility: TeamMeetingEligibility, realNameVerified: Bool) {
        self.eligibility = eligibility; phase = realNameVerified ? .readyToMeet : .realNameRequired
    }

    public mutating func realNameConfirmedByServer() throws {
        guard phase == .realNameRequired else { throw TeamMeetingIssue.illegalTransition }
        phase = .readyToMeet
    }

    public mutating func beginHandshake() throws {
        guard phase != .realNameRequired else { throw TeamMeetingIssue.realNameRequired }
        guard phase == .readyToMeet else { throw TeamMeetingIssue.illegalTransition }
        phase = .handshaking
    }

    /// Validates a scanned peer challenge and returns the confirm body fields. The server
    /// verifies the signature, one-time use and evidence; this only rejects obvious misuse.
    public mutating func scanned(_ challenge: TeamMeetingChallenge, deviceNow: Date, serverOffset: TimeInterval, requestId: String = UUID().uuidString) throws -> [String: String] {
        guard phase == .handshaking else { throw TeamMeetingIssue.illegalTransition }
        guard challenge.meetingId == eligibility.meetingId, challenge.teamId == eligibility.teamId,
              challenge.issuerMemberId == eligibility.peerMemberId, challenge.receiverMemberId == eligibility.selfMemberId else { throw TeamMeetingIssue.wrongBinding }
        guard deviceNow.addingTimeInterval(serverOffset) < challenge.expiresAt else { throw TeamMeetingIssue.expired }
        guard !submittedNonces.contains(challenge.nonce) else { throw TeamMeetingIssue.replayed }
        guard ReformWire.requestID(requestId) else { throw TeamMeetingIssue.invalid }
        submittedNonces.insert(challenge.nonce); pendingRequestId = requestId; phase = .confirmationPending
        return ["meetingId": challenge.meetingId, "teamId": challenge.teamId, "nonce": challenge.nonce, "keyVersion": challenge.keyVersion,
                "signature": challenge.signature, "purpose": TeamMeetingChallenge.purpose, "requestId": requestId]
    }

    /// Server decision for the pending confirmation. Rejection returns to handshaking for a fresh code.
    public mutating func serverDecision(requestId: String, verified: Bool) throws {
        guard phase == .confirmationPending, requestId == pendingRequestId else { throw TeamMeetingIssue.illegalTransition }
        pendingRequestId = nil; phase = verified ? .met : .handshaking
    }

    /// Restores a request that was persisted before this process. Does not invent a nonce.
    public mutating func restorePending(requestId: String) throws {
        guard !phase.isTerminal, phase != .realNameRequired, ReformWire.requestID(requestId) else { throw TeamMeetingIssue.illegalTransition }
        pendingRequestId = requestId; phase = .confirmationPending
    }

    /// Drops a scan that never became the stored request, so a late body cannot confirm it.
    public mutating func abandonUnsent(requestId: String, nonce: String) throws {
        guard phase == .confirmationPending, pendingRequestId == requestId, submittedNonces.contains(nonce) else { throw TeamMeetingIssue.illegalTransition }
        submittedNonces.remove(nonce); pendingRequestId = nil; phase = .handshaking
    }

    /// U04: cancel/revoke by either side, block or report ends the meeting permanently.
    /// A late "verified" for the old request is then refused by `serverDecision`.
    public mutating func cancel() { guard !phase.isTerminal else { return }; phase = .cancelled; pendingRequestId = nil }
    public mutating func expire() { if !phase.isTerminal { phase = .expired; pendingRequestId = nil } }
}
