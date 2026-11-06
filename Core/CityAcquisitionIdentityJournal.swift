import Foundation

/// A local identity to query again, never a cached receipt or proof of success.
@MainActor public protocol CityAcquisitionOriginalJournal: OperationPendingJournal {
    func original(ownerKey: String, targetKey: String) throws -> OperationPendingRecord?
}

/// Acquisition-only compatibility boundary for the original region-scoped pending key.
/// Persists only UUID/owner/target/zero steps. No quote, evidence, token or payment facts.
/// Writes use the existing UserDefaults write/read-back boundary, not cross-process CAS or fsync.
@MainActor public final class CityAcquisitionIdentityJournal: CityAcquisitionOriginalJournal {
    private let defaults: UserDefaults
    private let backing: OperationDefaultsJournal
    private let ownerKey: String
    private let targetKey: String
    private var observedPendingBytes: Data?
    private static let identityKeys: Set<String> = ["operationID", "ownerKey", "targetKey", "acknowledgedSteps"]
    private static let knownMetadataKeys: Set<String> = [
        "nativeWebhook", "merchantNPCSave", "themeItemUse", "sideQuestPlayer", "merchantSideQuestPublishing"
    ]

    public init(defaults: UserDefaults, ownerKey: String, targetKey: String) {
        self.defaults = defaults
        self.backing = OperationDefaultsJournal(defaults: defaults)
        self.ownerKey = ownerKey
        self.targetKey = targetKey
    }

    private var encodedScope: String {
        Data("\(ownerKey.utf8.count):\(ownerKey):\(targetKey)".utf8).base64EncodedString()
    }
    private var pendingKey: String { "questify.operations.pending.v1." + encodedScope }
    private var originalKey: String { "questify.city.acquisition.original.v1." + encodedScope }

    private func checkScope(owner: String, target: String) throws {
        guard ownerKey.hasPrefix("city-acquisition:"), !targetKey.isEmpty,
              owner.utf8.elementsEqual(ownerKey.utf8), target.utf8.elementsEqual(targetKey.utf8) else {
            throw APIError.invalidRequest
        }
    }
    private func checkRecord(_ record: OperationPendingRecord) throws {
        try checkScope(owner: record.ownerKey, target: record.targetKey)
        guard record.acknowledgedSteps == 0, record.nativeWebhook == nil else { throw APIError.malformedResponse }
    }

    /// Always inspects the raw schema before decoding, including legacy explicit-null fields.
    /// Unknown keys (even null), non-Data values and malformed records are never repaired/deleted.
    private func read(_ key: String) throws -> (record: OperationPendingRecord, bytes: Data)? {
        guard let raw = defaults.object(forKey: key) else { return nil }
        guard let data = raw as? Data,
              let object = try? JSONSerialization.jsonObject(with: data),
              let fields = object as? [String: Any],
              Self.identityKeys.isSubset(of: Set(fields.keys)),
              Set(fields.keys).isSubset(of: Self.identityKeys.union(Self.knownMetadataKeys)),
              Self.knownMetadataKeys.allSatisfy({ fields[$0] == nil || fields[$0] is NSNull }),
              let record = try? JSONDecoder().decode(OperationPendingRecord.self, from: data) else {
            throw APIError.malformedResponse
        }
        try checkRecord(record)
        return (record, data)
    }

    public func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? {
        try checkScope(owner: ownerKey, target: targetKey)
        let value = try read(pendingKey)
        observedPendingBytes = value?.bytes
        return value?.record
    }

    public func original(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? {
        try checkScope(owner: ownerKey, target: targetKey)
        return try read(originalKey)?.record
    }

    public func write(_ record: OperationPendingRecord) throws {
        try checkRecord(record)
        // Re-read both raw slots at mutation time. A damaged original anchor cannot be replaced.
        let previous = try read(pendingKey)
        _ = try read(originalKey)
        if let previous {
            guard previous.record == record else { throw APIError.invalidRequest }
            // Idempotent identity writes must not strip recognized legacy null metadata.
            observedPendingBytes = previous.bytes
            return
        }
        try backing.write(record)
        guard let stored = try read(pendingKey), stored.record == record else { throw APIError.malformedResponse }
        observedPendingBytes = stored.bytes
    }

    /// Call only after a real original-request receipt has been verified by the controller.
    /// Save and verify its identity first; only then remove the matching pending lock.
    /// An interruption may leave both slots at the same UUID: recovery must prefer pending.
    public func clear(_ record: OperationPendingRecord) throws {
        try checkRecord(record)
        guard let pending = try read(pendingKey), pending.record == record else { throw APIError.invalidRequest }
        if let observedPendingBytes, observedPendingBytes != pending.bytes { throw APIError.malformedResponse }
        let previousOriginal = try read(originalKey)
        let markerBytes: Data
        if let previousOriginal, previousOriginal.record == record {
            markerBytes = previousOriginal.bytes
        } else {
            markerBytes = try JSONEncoder().encode(record)
            // Preserve an unknown/changed original slot instead of blindly replacing it.
            if let previousOriginal {
                guard defaults.data(forKey: originalKey) == previousOriginal.bytes else { throw APIError.malformedResponse }
            } else {
                guard defaults.object(forKey: originalKey) == nil else { throw APIError.malformedResponse }
            }
            guard defaults.data(forKey: pendingKey) == pending.bytes else { throw APIError.malformedResponse }
            defaults.set(markerBytes, forKey: originalKey)
        }
        guard defaults.data(forKey: originalKey) == markerBytes,
              try read(originalKey)?.record == record,
              defaults.data(forKey: pendingKey) == pending.bytes else { throw APIError.malformedResponse }
        try backing.clear(record)
        observedPendingBytes = nil
    }
}
