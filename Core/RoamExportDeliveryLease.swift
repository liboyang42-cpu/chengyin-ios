import Foundation

/// Short-lived permission to hand one completed export file to the system.
///
/// The coordinator issues a lease only for a fully read, non-empty file. The view checks
/// the lease again at the actual hand-off moment, and revokes it when the scene leaves the
/// foreground or the page goes away; an expired, revoked, foreign-identity or backgrounded
/// lease delivers nothing. Revocation is one-way for the lease instance: returning to the
/// foreground never revives it, so a revoked file must be re-validated by the coordinator
/// issuing a fresh lease.
public final class RoamExportDeliveryLease: @unchecked Sendable {
    public let fileName: String
    public let rows: Int
    public let expiresAtMs: Int64
    public let identity: RoamExperienceIdentity?
    private let lock = NSLock()
    private var revoked = false

    public init?(file: RoamExportFile, identity: RoamExperienceIdentity?) {
        guard file.rows > 0, !file.fileName.isEmpty else { return nil }
        fileName = file.fileName
        rows = file.rows
        expiresAtMs = file.expiresAtMs
        self.identity = identity
    }

    public var isRevoked: Bool {
        lock.lock(); defer { lock.unlock() }
        return revoked
    }

    public func revoke() {
        lock.lock(); defer { lock.unlock() }
        revoked = true
    }

    /// Hand-off gate: current identity, foreground and unexpired, all at delivery time.
    public func canDeliver(now: Date, currentIdentity: RoamExperienceIdentity?, foreground: Bool) -> Bool {
        guard foreground, currentIdentity == identity else { return false }
        let file = RoamExportFile(fileName: fileName, content: "", expiresAtMs: expiresAtMs, rows: rows)
        guard !file.isExpired(now: now) else { return false }
        return !isRevoked
    }

    /// The file only when this lease still authorises its delivery; otherwise nothing.
    public func validatedFile(_ file: RoamExportFile, now: Date, currentIdentity: RoamExperienceIdentity?, foreground: Bool) -> RoamExportFile? {
        guard file.fileName == fileName, file.rows == rows, file.expiresAtMs == expiresAtMs,
              canDeliver(now: now, currentIdentity: currentIdentity, foreground: foreground) else { return nil }
        return file
    }
}
