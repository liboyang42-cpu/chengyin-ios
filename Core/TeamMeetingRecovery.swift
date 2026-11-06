import Foundation

/// Confirm and lookup for an already-confirmed team's meeting.
/// Calls the injected `TeamMeetingServing` with the existing meetingId/teamId/nonce body.
/// Does not open a URL and does not map that body onto an R9 ticket or challenge.
@MainActor public final class TeamMeetingRecovery {
    private let journal: TeamMeetingPendingJournal
    private let service: any TeamMeetingServing
    public init(journal: TeamMeetingPendingJournal, service: any TeamMeetingServing) {
        self.journal = journal
        self.service = service
    }

    /// First send of this request, or the one replacement allowed after a refusal.
    /// A prepared row is the send that has not reached the server yet. Anything else returns the stored row and does not call confirm.
    public func claimAndSend(owner: TeamMeetingOwner, teamId: String, meetingId: String, fields: [String: String]) async throws -> TeamMeetingSubmitResult {
        guard fields["meetingId"] == meetingId, fields["teamId"] == teamId, let requestId = fields["requestId"], ReformWire.requestID(requestId) else { throw TeamMeetingJournalIssue.invalid }
        if let existing = try journal.record(owner: owner, teamId: teamId, meetingId: meetingId) {
            let firstSend = existing.phase == .prepared && existing.requestId == requestId
            let replacement = existing.phase == .refused && existing.requestId != requestId
            if !firstSend && !replacement { return Self.make(existing, sentThisCall: false) }
        }
        _ = try journal.prepare(owner: owner, teamId: teamId, meetingId: meetingId, requestId: requestId)
        _ = try journal.markUnknown(owner: owner, teamId: teamId, meetingId: meetingId, requestId: requestId)
        let decision = await service.confirm(fields)
        guard let decision else {
            guard let stored = try journal.record(owner: owner, teamId: teamId, meetingId: meetingId) else { throw TeamMeetingJournalIssue.saveFailed }
            return Self.make(stored, sentThisCall: true)
        }
        let finished = try journal.finish(owner: owner, teamId: teamId, meetingId: meetingId, requestId: requestId, verified: decision)
        return Self.make(finished, sentThisCall: true)
    }

    /// Authoritative readback. Never calls confirm.
    public func lookup(owner: TeamMeetingOwner, teamId: String, meetingId: String) async throws -> TeamMeetingSubmitResult? {
        guard let existing = try journal.record(owner: owner, teamId: teamId, meetingId: meetingId) else { return nil }
        if existing.phase == .confirmed || existing.phase == .refused || existing.phase == .cancelledBeforeSend {
            return Self.make(existing, sentThisCall: false)
        }
        let decision = try await service.confirmationReadback(meetingId: meetingId, requestId: existing.requestId)
        guard let decision else { return Self.make(existing, sentThisCall: false) }
        let finished = try journal.finish(owner: owner, teamId: teamId, meetingId: meetingId, requestId: existing.requestId, verified: decision)
        return Self.make(finished, sentThisCall: false)
    }

    /// Not sent, sent but unknown, or already confirmed. Unknown and confirmed stay as stored.
    public func classifyCancel(owner: TeamMeetingOwner, teamId: String, meetingId: String) throws -> TeamMeetingCancelCase {
        guard let existing = try journal.record(owner: owner, teamId: teamId, meetingId: meetingId) else { return .notSent }
        switch existing.phase {
        case .prepared:
            _ = try journal.markCancelledBeforeSend(owner: owner, teamId: teamId, meetingId: meetingId, requestId: existing.requestId)
            return .notSent
        case .cancelledBeforeSend, .refused:
            return .notSent
        case .unknown:
            return .sentUnknown
        case .confirmed:
            return .confirmed
        }
    }

    private static func make(_ record: TeamMeetingIntentRecord, sentThisCall: Bool) -> TeamMeetingSubmitResult {
        let verified: Bool?
        switch record.phase {
        case .confirmed: verified = true
        case .refused: verified = false
        case .prepared, .unknown, .cancelledBeforeSend: verified = nil
        }
        return TeamMeetingSubmitResult(requestId: record.requestId, teamId: record.teamId, meetingId: record.meetingId, phase: record.phase, verified: verified, sentThisCall: sentThisCall)
    }
}

public enum TeamMeetingCancelCase: Equatable, Sendable {
    case notSent, sentUnknown, confirmed
}

public struct TeamMeetingSubmitResult: Equatable, Sendable {
    public let requestId, teamId, meetingId: String
    public let phase: TeamMeetingIntentPhase
    public let verified: Bool?
    public let sentThisCall: Bool
}
