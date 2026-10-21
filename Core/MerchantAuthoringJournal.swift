import Foundation
import CryptoKit

/// Persistent authoring job marker. Keyed by owner + requestId. Stores the payload
/// fingerprint and intent, never a prompt, draft body, credential, order, customer or cost.
public enum MerchantAuthoringJobState: String, Codable, Sendable {
    case unknown = "UNKNOWN"
    case cancelled = "CANCELLED"
    /// An authoritative readback was applied. This is not a published stage.
    case read = "READ"
}

public enum MerchantAuthoringIntent: String, Codable, Sendable {
    case create = "CREATE"
    case generate = "GENERATE"
    case save = "SAVE"
    case publish = "PUBLISH"
}

public enum MerchantAuthoringAdmit: Equatable, Sendable {
    case claim, replay, conflict
}

public enum MerchantAuthoringJournalRules {
    public static func admit(existingFingerprint: String?, fingerprint: String) -> MerchantAuthoringAdmit {
        guard let existingFingerprint else { return .claim }
        return existingFingerprint == fingerprint ? .replay : .conflict
    }
}

public struct MerchantAuthoringJobRecord: Codable, Equatable, Sendable {
    public let ownerKey: String
    public let requestID: String
    public let fingerprint: String
    public var state: MerchantAuthoringJobState
    public let draftID: String
    public let storeID: String
    public let intent: MerchantAuthoringIntent
    public init(ownerKey: String, requestID: String, fingerprint: String, state: MerchantAuthoringJobState,
                draftID: String, storeID: String, intent: MerchantAuthoringIntent) {
        self.ownerKey = ownerKey; self.requestID = requestID; self.fingerprint = fingerprint; self.state = state
        self.draftID = draftID; self.storeID = storeID; self.intent = intent
    }
}

public struct MerchantAuthoringClaim: Equatable, Sendable {
    public let record: MerchantAuthoringJobRecord
    public let fresh: Bool
}

public enum MerchantAuthoringFingerprint {
    /// Digest only. The caller discards the prompt after this returns.
    public static func make(_ parts: [String]) -> String {
        let digest = SHA256.hash(data: Data(parts.joined(separator: "\u{1e}").utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor public protocol MerchantAuthoringJobJournal: AnyObject {
    func lookup(ownerKey: String, requestID: String) throws -> MerchantAuthoringJobRecord?
    func claim(ownerKey: String, requestID: String, fingerprint: String, draftID: String, storeID: String, intent: MerchantAuthoringIntent) throws -> MerchantAuthoringClaim
    func cancel(ownerKey: String, requestID: String) throws -> MerchantAuthoringJobRecord
    func acknowledge(ownerKey: String, requestID: String) throws
    func pendingUnknown(ownerKey: String) throws -> MerchantAuthoringJobRecord?
    func unknownCount(ownerKey: String) throws -> Int
}

/// ponytail: one UserDefaults store, no cross-process lock. The server owner+requestId key is the real guard.
@MainActor public final class MerchantAuthoringDefaultsJournal: MerchantAuthoringJobJournal {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults) { self.defaults = defaults }

    public func lookup(ownerKey: String, requestID: String) throws -> MerchantAuthoringJobRecord? {
        guard let raw = defaults.object(forKey: recordKey(ownerKey, requestID)) else { return nil }
        guard let data = raw as? Data, let record = try? JSONDecoder().decode(MerchantAuthoringJobRecord.self, from: data),
              record.ownerKey == ownerKey, record.requestID == requestID, !record.fingerprint.isEmpty else { throw APIError.malformedResponse }
        return record
    }

    public func claim(ownerKey: String, requestID: String, fingerprint: String, draftID: String, storeID: String, intent: MerchantAuthoringIntent) throws -> MerchantAuthoringClaim {
        guard !ownerKey.isEmpty, !requestID.isEmpty, !fingerprint.isEmpty, !draftID.isEmpty, !storeID.isEmpty else { throw APIError.invalidRequest }
        let existing = try lookup(ownerKey: ownerKey, requestID: requestID)
        switch MerchantAuthoringJournalRules.admit(existingFingerprint: existing?.fingerprint, fingerprint: fingerprint) {
        case .conflict: throw APIError.invalidRequest
        case .replay: return MerchantAuthoringClaim(record: existing!, fresh: false)
        case .claim:
            let record = MerchantAuthoringJobRecord(ownerKey: ownerKey, requestID: requestID, fingerprint: fingerprint,
                                                    state: .unknown, draftID: draftID, storeID: storeID, intent: intent)
            try store(record)
            return MerchantAuthoringClaim(record: record, fresh: true)
        }
    }

    public func cancel(ownerKey: String, requestID: String) throws -> MerchantAuthoringJobRecord {
        guard var record = try lookup(ownerKey: ownerKey, requestID: requestID) else { throw APIError.invalidRequest }
        record.state = .cancelled
        try store(record)
        return record
    }

    public func acknowledge(ownerKey: String, requestID: String) throws {
        guard var record = try lookup(ownerKey: ownerKey, requestID: requestID), record.state == .unknown else { throw APIError.invalidRequest }
        record.state = .read
        try store(record)
    }

    public func pendingUnknown(ownerKey: String) throws -> MerchantAuthoringJobRecord? {
        try identifiers(ownerKey).compactMap { try lookup(ownerKey: ownerKey, requestID: $0) }.first { $0.state == .unknown }
    }

    public func unknownCount(ownerKey: String) throws -> Int {
        try identifiers(ownerKey).compactMap { try lookup(ownerKey: ownerKey, requestID: $0) }.filter { $0.state == .unknown }.count
    }

    private func store(_ record: MerchantAuthoringJobRecord) throws {
        let data = try JSONEncoder().encode(record)
        let name = recordKey(record.ownerKey, record.requestID)
        defaults.set(data, forKey: name)
        guard defaults.data(forKey: name) == data else { throw APIError.malformedResponse }
        var ids = try identifiers(record.ownerKey)
        if !ids.contains(record.requestID) {
            ids.append(record.requestID)
            let indexData = try JSONEncoder().encode(ids)
            let index = indexKey(record.ownerKey)
            defaults.set(indexData, forKey: index)
            guard defaults.data(forKey: index) == indexData else { throw APIError.malformedResponse }
        }
    }

    private func identifiers(_ ownerKey: String) throws -> [String] {
        guard let raw = defaults.object(forKey: indexKey(ownerKey)) else { return [] }
        guard let data = raw as? Data, let ids = try? JSONDecoder().decode([String].self, from: data) else { throw APIError.malformedResponse }
        return ids
    }

    private func recordKey(_ owner: String, _ requestID: String) -> String {
        "questify.merchantAuthoring.job.v1." + Data("\(owner.utf8.count):\(owner):\(requestID.utf8.count):\(requestID)".utf8).base64EncodedString()
    }
    private func indexKey(_ owner: String) -> String {
        "questify.merchantAuthoring.index.v1." + Data("\(owner.utf8.count):\(owner)".utf8).base64EncodedString()
    }
}
