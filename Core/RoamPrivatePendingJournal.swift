import Foundation

/// Minimal cross-restart identity for one unconfirmed private-tool create.
///
/// Only the request identity and its owner scope are durable. The capsule body, any photo
/// reference and every credential stay out of this record by construction: the type has no
/// field that could carry them, and decoding rejects any record that smuggles extra keys in.
public enum RoamPrivatePendingKind: String, Codable, Equatable {
    case capsuleCreate
    case goalCreate
}

public struct RoamPrivatePendingEntry: Codable, Equatable {
    public let version: Int
    public let kind: RoamPrivatePendingKind
    public let requestID: String
    public let market: String
    public let deployment: String
    public let namespace: String
    public let accountID: Int
    public let recordedAtMs: Int64
    /// Set once an attempt's outcome was UNKNOWN. A later refusal is not an
    /// authoritative receipt, so the slot stays until a matching receipt agrees.
    public let receiptRequired: Bool

    public init(kind: RoamPrivatePendingKind, requestID: String, scope: RoamHistoryScope, recordedAtMs: Int64, receiptRequired: Bool = false) {
        version = 1
        self.kind = kind
        self.requestID = requestID
        market = scope.market
        deployment = scope.deployment
        self.namespace = scope.namespace
        accountID = scope.accountID
        self.recordedAtMs = recordedAtMs
        self.receiptRequired = receiptRequired
    }

    func matches(scope: RoamHistoryScope) -> Bool {
        market == scope.market && deployment == scope.deployment && namespace == scope.namespace && accountID == scope.accountID
    }
}

public enum RoamPrivatePendingJournalError: Error, Equatable {
    /// The identity record could not be made durable; the caller must not dispatch.
    case saveFailed
    case removalFailed
    /// Stored bytes are unreadable, oversized, out of version or carry unexpected fields.
    case corrupted
    /// A different request already holds this kind's slot for the scope.
    case locked
    /// No durable storage is available on this device at all.
    case unavailable
}

/// Raw byte storage for the journal. Implementations must replace atomically.
@MainActor public protocol RoamPrivatePendingJournalStoring: AnyObject {
    func read(key: String) throws -> Data?
    func store(_ data: Data, key: String) throws
    func remove(key: String) throws
}

@MainActor public final class RoamPrivatePendingInMemoryJournalStorage: RoamPrivatePendingJournalStoring {
    public var values: [String: Data] = [:]
    public var storeError: Error?
    public init() {}
    public func read(key: String) throws -> Data? { values[key] }
    public func store(_ data: Data, key: String) throws {
        if let storeError { throw storeError }
        values[key] = data
    }
    public func remove(key: String) throws { values[key] = nil }
}

/// Device-local file storage in Application Support. The file name is the hex of the
/// journal key, so account, deployment and namespace never appear as path text either.
@MainActor public final class RoamPrivatePendingFileJournalStorage: RoamPrivatePendingJournalStoring {
    private let directory: () -> URL?
    public init(directory: URL) { self.directory = { directory } }
    public init() {
        directory = {
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("Questify/roam-private-pending-v1", isDirectory: true)
        }
    }
    private func fileURL(_ key: String) throws -> URL {
        guard let directory = directory() else { throw RoamPrivatePendingJournalError.unavailable }
        let hex = key.utf8.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hex + ".json")
    }
    public func read(key: String) throws -> Data? {
        let url = try fileURL(key)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do { return try Data(contentsOf: url) } catch { throw RoamPrivatePendingJournalError.corrupted }
    }
    public func store(_ data: Data, key: String) throws {
        let url = try fileURL(key)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic])
        } catch { throw RoamPrivatePendingJournalError.saveFailed }
    }
    public func remove(key: String) throws {
        let url = try fileURL(key)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do { try FileManager.default.removeItem(at: url) } catch { throw RoamPrivatePendingJournalError.removalFailed }
    }
}

/// One durable slot per (scope, kind). A slot is written before dispatch, survives relaunch
/// as a lock holding only the original request ID, and is removed only by an explicit
/// confirmation path (a matching receipt, or a refusal that proves nothing was applied).
@MainActor public final class RoamPrivatePendingJournal {
    private let storage: any RoamPrivatePendingJournalStoring
    public init(storage: any RoamPrivatePendingJournalStoring) { self.storage = storage }

    /// Production storage: device-local files, created lazily on first record.
    public static func live() -> RoamPrivatePendingJournal {
        RoamPrivatePendingJournal(storage: RoamPrivatePendingFileJournalStorage())
    }

    static func key(kind: RoamPrivatePendingKind, scope: RoamHistoryScope) -> String {
        let raw = [scope.namespace, scope.market, scope.deployment, String(scope.accountID), kind.rawValue]
            .map { "\($0.utf8.count):\($0)" }.joined()
        return "roam-private-pending-v1-" + Data(raw.utf8).base64EncodedString()
    }

    private static let allowedKeys: Set<String> = ["version", "kind", "requestId", "market", "deployment", "namespace", "accountId", "recordedAtMs", "receiptRequired"]
    private struct Wire: Codable {
        let version: Int
        let kind: RoamPrivatePendingKind
        let requestId: String
        let market: String
        let deployment: String
        let namespace: String
        let accountId: Int
        let recordedAtMs: Int64
        /// Omitted when false so a first, still-unsent record stays minimal.
        let receiptRequired: Bool?
    }

    public func entry(kind: RoamPrivatePendingKind, scope: RoamHistoryScope) throws -> RoamPrivatePendingEntry? {
        let data: Data?
        do { data = try storage.read(key: Self.key(kind: kind, scope: scope)) }
        catch { throw RoamPrivatePendingJournalError.corrupted }
        guard let data else { return nil }
        guard data.count <= 2048,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys).isSubset(of: Self.allowedKeys),
              let wire = try? JSONDecoder().decode(Wire.self, from: data),
              wire.version == 1, wire.kind == kind, wire.recordedAtMs > 0,
              RoamPrivateRequestID.isValid(wire.requestId) else { throw RoamPrivatePendingJournalError.corrupted }
        let entry = RoamPrivatePendingEntry(kind: wire.kind, requestID: wire.requestId, scope: scope, recordedAtMs: wire.recordedAtMs, receiptRequired: wire.receiptRequired == true)
        guard entry.market == wire.market, entry.deployment == wire.deployment,
              entry.namespace == wire.namespace, entry.accountID == wire.accountId,
              entry.matches(scope: scope) else { throw RoamPrivatePendingJournalError.corrupted }
        return entry
    }

    /// Persist the minimal identity before any dispatch. Re-recording the same request is
    /// idempotent; a different request for the same slot is refused, never overwritten.
    @discardableResult
    public func record(kind: RoamPrivatePendingKind, requestID: String, scope: RoamHistoryScope, now: Date) throws -> RoamPrivatePendingEntry {
        guard RoamPrivateRequestID.isValid(requestID) else { throw RoamPrivatePendingJournalError.corrupted }
        if let existing = try entry(kind: kind, scope: scope) {
            guard existing.requestID == requestID else { throw RoamPrivatePendingJournalError.locked }
            return existing
        }
        let entry = RoamPrivatePendingEntry(kind: kind, requestID: requestID, scope: scope,
                                            recordedAtMs: Int64((now.timeIntervalSince1970 * 1000).rounded(.down)))
        try write(entry, scope: scope)
        return entry
    }

    /// Mark a slot that has already left the device with an unknown outcome.
    /// Idempotent for the same request; never replaces a different request's lock.
    public func requireReceipt(kind: RoamPrivatePendingKind, requestID: String, scope: RoamHistoryScope) throws {
        guard let existing = try entry(kind: kind, scope: scope) else { return }
        guard existing.requestID == requestID else { throw RoamPrivatePendingJournalError.locked }
        guard !existing.receiptRequired else { return }
        let marked = RoamPrivatePendingEntry(kind: existing.kind, requestID: existing.requestID, scope: scope,
                                             recordedAtMs: existing.recordedAtMs, receiptRequired: true)
        try write(marked, scope: scope)
    }

    private func write(_ entry: RoamPrivatePendingEntry, scope: RoamHistoryScope) throws {
        let wire = Wire(version: entry.version, kind: entry.kind, requestId: entry.requestID, market: entry.market,
                        deployment: entry.deployment, namespace: entry.namespace, accountId: entry.accountID,
                        recordedAtMs: entry.recordedAtMs, receiptRequired: entry.receiptRequired ? true : nil)
        do {
            let data = try JSONEncoder().encode(wire)
            try storage.store(data, key: Self.key(kind: entry.kind, scope: scope))
        } catch let error as RoamPrivatePendingJournalError { throw error }
        catch { throw RoamPrivatePendingJournalError.saveFailed }
        // Read back what actually landed; a store that cannot be read back has not saved.
        guard let landed = try self.entry(kind: entry.kind, scope: scope), landed == entry else { throw RoamPrivatePendingJournalError.saveFailed }
    }

    /// Confirmation-only cleanup: removes the slot only when it still names this request.
    public func clear(kind: RoamPrivatePendingKind, requestID: String, scope: RoamHistoryScope) throws {
        guard let existing = try entry(kind: kind, scope: scope) else { return }
        guard existing.requestID == requestID else { throw RoamPrivatePendingJournalError.locked }
        do { try storage.remove(key: Self.key(kind: kind, scope: scope)) }
        catch let error as RoamPrivatePendingJournalError { throw error }
        catch { throw RoamPrivatePendingJournalError.removalFailed }
    }
}
