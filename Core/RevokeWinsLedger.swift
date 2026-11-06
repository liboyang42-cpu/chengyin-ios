import Foundation

/// Reform plan v9 decision U04 (revoke wins). When a revoke races an accept, a late
/// response, a retry or a restore, the revoke is final: an older success can never
/// bring a revoked invite, offer or meeting back. The server terminal state, the
/// local cache and notifications must agree, so every source of an update funnels
/// through `apply(_:)`. Only a server record with a NEW subject id (a fresh invite)
/// can follow a revoke; the same subject stays revoked.
public enum RevokeWinsIssue: Error, Equatable { case invalid, wrongSubject }

public struct RevokeWinsEvent: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case offered = "OFFERED", accepted = "ACCEPTED", declined = "DECLINED", revoked = "REVOKED", expired = "EXPIRED"
        var isTerminal: Bool { self != .offered }
    }
    public enum Source: String, Sendable { case serverReadback, serverPush, lateResponse, localRetry, restoredCache }
    public let subjectId: String
    public let kind: Kind
    /// Server version for server sources; nil for local or cached claims.
    public let serverVersion: Int64?
    public let source: Source
    public init(subjectId: String, kind: Kind, serverVersion: Int64?, source: Source) throws {
        guard ReformWire.id(subjectId) else { throw RevokeWinsIssue.invalid }
        if let serverVersion { guard ReformWire.version(serverVersion) else { throw RevokeWinsIssue.invalid } }
        // Only server sources carry authority to establish a terminal state.
        if source == .localRetry || source == .restoredCache { guard serverVersion == nil else { throw RevokeWinsIssue.invalid } }
        self.subjectId = subjectId; self.kind = kind; self.serverVersion = serverVersion; self.source = source
    }
    var isServerAuthoritative: Bool { [.serverReadback, .serverPush, .lateResponse].contains(source) && serverVersion != nil }
}

public struct RevokeWinsState: Equatable, Sendable {
    public enum Display: Equatable, Sendable { case pending, accepted, declined, revoked, expired, unknown }
    public let subjectId: String
    public private(set) var display: Display = .unknown
    public private(set) var version: Int64 = -1
    /// Notifications already shown for this subject; a revoke supersedes any "accepted" toast.
    public private(set) var notified: Display?

    public init(subjectId: String) throws { guard ReformWire.id(subjectId) else { throw RevokeWinsIssue.invalid }; self.subjectId = subjectId }

    /// Returns true when the visible state changed.
    @discardableResult
    public mutating func apply(_ event: RevokeWinsEvent) throws -> Bool {
        guard event.subjectId == subjectId else { throw RevokeWinsIssue.wrongSubject }
        if display == .revoked { return false } // revoke is final for this subject.
        guard event.isServerAuthoritative, let incoming = event.serverVersion else {
            // Local retries and restored caches only mark uncertainty; they never set a terminal state.
            if display == .unknown, event.kind == .offered { display = .pending; return true }
            return false
        }
        if event.kind == .revoked { display = .revoked; version = max(version, incoming); return true }
        guard incoming > version else { return false } // late or duplicate response.
        // Once any terminal state exists, only a revoke may replace it.
        if [.accepted, .declined, .expired].contains(display) { version = incoming; return false }
        version = incoming
        switch event.kind {
        case .offered: display = .pending
        case .accepted: display = .accepted
        case .declined: display = .declined
        case .expired: display = .expired
        case .revoked: display = .revoked
        }
        return true
    }

    /// Notification gate: show at most one terminal notice, and never "accepted" after "revoked".
    public mutating func notificationToShow() -> Display? {
        guard [.accepted, .declined, .revoked, .expired].contains(display), notified != display else { return nil }
        if notified == .revoked { return nil }
        notified = display
        return display
    }
}
