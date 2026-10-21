import Foundation

/// Short-lived permission to hand one completed export file to the system.
///
/// The coordinator issues a lease only for a fully read, non-empty file. The view checks
/// the lease again at the actual hand-off moment, and revokes it when the scene leaves the
/// foreground or the page goes away; an expired, revoked, foreign-identity or backgrounded
/// lease delivers nothing. Revocation is one-way: returning to the foreground never revives
/// this lease or the file it covered. A later completed read gets a new lease.
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

/// Live hand-off readers. Delivery calls them at the write. It does not keep the
/// time, identity, or foreground from the last view refresh, and it does not
/// substitute the lease's own identity or a constant foreground.
public final class RoamExportDeliveryContext: @unchecked Sendable {
    private let lock = NSLock()
    private var clock: @MainActor () -> Date
    private var identity: @MainActor () -> RoamExperienceIdentity?
    private var foreground: @MainActor () -> Bool
    private var temporaryURL: URL?
    private var tokens: [UUID: URL] = [:]

    public init() {
        clock = { @MainActor in Date() }
        identity = { @MainActor in nil }
        foreground = { @MainActor in false }
    }

    /// Install the readers. Their results at this moment are not the delivery decision.
    public func bind(clock: @escaping @MainActor () -> Date,
                     identity: @escaping @MainActor () -> RoamExperienceIdentity?,
                     foreground: @escaping @MainActor () -> Bool) {
        lock.lock(); defer { lock.unlock() }
        self.clock = clock; self.identity = identity; self.foreground = foreground
    }

    public func snapshot() -> (now: Date, identity: RoamExperienceIdentity?, foreground: Bool) {
        lock.lock()
        let clock = self.clock, identity = self.identity, foreground = self.foreground
        lock.unlock()
        let read = { MainActor.assumeIsolated { (clock(), identity(), foreground()) } }
        if Thread.isMainThread { return read() }
        // ponytail: main.sync, hangs if the main thread is already waiting on this write
        return DispatchQueue.main.sync(execute: read)
    }

    public func rememberTemporary(_ url: URL) {
        lock.lock(); temporaryURL = url; lock.unlock()
    }

    /// One hand-off, one file. A later hand-off keeps its own token, so releasing the
    /// earlier one cannot delete the file a newer lease is about to deliver.
    public func rememberTemporary(_ url: URL, token: UUID) {
        lock.lock()
        let previous = tokens.updateValue(url, forKey: token)
        temporaryURL = url
        lock.unlock()
        if let previous, previous != url { Self.removeExportedCopy(previous) }
    }

    public func releaseTemporary(token: UUID) {
        lock.lock()
        let url = tokens.removeValue(forKey: token)
        if let url, temporaryURL == url { temporaryURL = nil }
        lock.unlock()
        if let url { Self.removeExportedCopy(url) }
    }

    /// Cancel, completion, background and leaving the page all drop temporary copies.
    /// A second call is a no-op. This removes every hand-off still remembered.
    public func cleanupTemporary() {
        lock.lock()
        let urls = Array(tokens.values)
        let latest = temporaryURL
        tokens.removeAll()
        temporaryURL = nil
        lock.unlock()
        var removed: [URL] = []
        for url in urls where !removed.contains(url) {
            removed.append(url)
            Self.removeExportedCopy(url)
        }
        if let latest, !removed.contains(latest) { Self.removeExportedCopy(latest) }
    }

    /// Deletes the copy and its unique parent folder when this hand-off created one.
    private static func removeExportedCopy(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        let parent = url.deletingLastPathComponent()
        guard parent.lastPathComponent.hasPrefix("roam-export-") else { return }
        try? FileManager.default.removeItem(at: parent)
    }
}

public enum RoamExportHandoff {
    /// Bytes to write only while the lease still matches the readers at this call.
    /// Nil means deliver nothing: revoked, expired, backgrounded, or a different identity.
    public static func contents(file: RoamExportFile, lease: RoamExportDeliveryLease, context: RoamExportDeliveryContext) -> Data? {
        let shot = context.snapshot()
        guard lease.validatedFile(file, now: shot.now, currentIdentity: shot.identity, foreground: shot.foreground) != nil else { return nil }
        return Data(file.content.utf8)
    }

    /// System share success is only a finished activity with no error. Cancel is not a save.
    public static func recordsSave(completed: Bool, errorIsSet: Bool) -> Bool {
        completed && !errorIsSet
    }

    /// An older share's callback may change delivery only while its lease is still current.
    public static func callbackMatches(_ callback: RoamExportDeliveryLease, current: RoamExportDeliveryLease?) -> Bool {
        callback === current
    }
}
