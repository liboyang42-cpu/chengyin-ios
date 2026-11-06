import Foundation

/// Local uncertainty marker for the original tag-revocation request, not an idempotency key.
/// There is deliberately no request builder or retry operation. Credentials and tag values
/// are never stored; a restarted viewer may only read back the original topic and tag IDs.
public struct PlayTagRevocationIntent: Codable, Equatable {
    public let id: UUID
    public let owner: PlayRecoveryOwner
    public let originEpoch: UInt64
    public let topicID: Int
    public let tagID: Int

    public init(session: PlayExperienceSession, topicID: Int, tagID: Int) throws {
        id = UUID(); owner = .init(session: session); originEpoch = session.epoch
        self.topicID = topicID; self.tagID = tagID
        try validateShape()
        try validate(key: PlayRunStorageKey.make(session: session, scope: .topic(topicID)))
    }
    /// A refreshed epoch/token does not create another lock or authorize another POST.
    public func validate(session: PlayExperienceSession, topicID: Int) throws {
        try validateShape()
        guard owner.matches(session), self.topicID == topicID else { throw PlayExperienceError.persistenceUnavailable }
        try validate(key: PlayRunStorageKey.make(session: session, scope: .topic(topicID)))
    }
    private func validateShape() throws {
        guard owner.accountID > 0, !owner.namespace.isEmpty, !owner.role.isEmpty,
              owner.role.utf8.count <= 128, topicID > 0, tagID > 0 else { throw PlayExperienceError.persistenceUnavailable }
    }
    /// Check the existing length-prefixed PlayRunStorageKey representation without constructing
    /// a credential-bearing session. Role stays in the owner check, never in a new slot key.
    func validate(key: String) throws {
        try validateShape()
        let scope = PlaySessionScope.topic(topicID)
        let parts = [owner.namespace, String(owner.accountID), scope.fields.keys.first!, String(scope.id)]
        let expected = "play.run.v2:" + parts.map { "\($0.utf8.count):\($0)" }.joined()
        guard expected.utf8.elementsEqual(key.utf8) else { throw PlayExperienceError.persistenceUnavailable }
    }
    private enum CodingKeys: String, CodingKey { case schema, id, owner, originEpoch, topicID, tagID }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schema) == 1 else { throw PlayExperienceError.persistenceUnavailable }
        id = try c.decode(UUID.self, forKey: .id); owner = try c.decode(PlayRecoveryOwner.self, forKey: .owner)
        originEpoch = try c.decode(UInt64.self, forKey: .originEpoch)
        topicID = try c.decode(Int.self, forKey: .topicID); tagID = try c.decode(Int.self, forKey: .tagID)
        try validateShape()
    }
    public func encode(to encoder: Encoder) throws {
        try validateShape()
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(1, forKey: .schema); try c.encode(id, forKey: .id); try c.encode(owner, forKey: .owner)
        try c.encode(originEpoch, forKey: .originEpoch); try c.encode(topicID, forKey: .topicID); try c.encode(tagID, forKey: .tagID)
    }
}

public struct PlayTagRevocationRecoverySnapshot: Equatable {
    public let value: PlayTagRevocationIntent
    public let generation: Data
    let persistedBytes: Data?
    init(value: PlayTagRevocationIntent, generation: Data, persistedBytes: Data? = nil) {
        self.value = value; self.generation = generation; self.persistedBytes = persistedBytes
    }
}

/// Record must finish durably before dispatch. An existing marker is never replaced or retried.
/// Only authoritative reconciliation of the original tag permits exact-generation clear;
/// UNKNOWN, ACTIVE, read errors, cancellation and page exit retain the marker.
@MainActor public protocol PlayTagRevocationRecovery: AnyObject {
    func readTagRevocation(_ key: String) async throws -> PlayTagRevocationRecoverySnapshot?
    func recordTagRevocation(_ intent: PlayTagRevocationIntent, key: String) async throws -> PlayTagRevocationRecoverySnapshot
    func clearTagRevocation(_ snapshot: PlayTagRevocationRecoverySnapshot, key: String) async throws
}

/// Normal composition uses this on durable construction failure, never the memory fixture.
@MainActor public final class PlayUnavailableTagRevocationRecovery: PlayTagRevocationRecovery {
    public init() {}
    public func readTagRevocation(_ key: String) async throws -> PlayTagRevocationRecoverySnapshot? {
        throw PlayExperienceError.persistenceUnavailable
    }
    public func recordTagRevocation(_ intent: PlayTagRevocationIntent, key: String) async throws -> PlayTagRevocationRecoverySnapshot {
        throw PlayExperienceError.persistenceUnavailable
    }
    public func clearTagRevocation(_ snapshot: PlayTagRevocationRecoverySnapshot, key: String) async throws {
        throw PlayExperienceError.persistenceUnavailable
    }
}

/// Synthetic-only compatibility adapter. This does not establish durable storage provenance.
@MainActor public final class PlayMemoryTagRevocationRecovery: PlayTagRevocationRecovery {
    private var values: [String: PlayTagRevocationRecoverySnapshot] = [:]
    public init() {}
    public func readTagRevocation(_ key: String) async throws -> PlayTagRevocationRecoverySnapshot? {
        if let stored = values[key] { try stored.value.validate(key: key) }
        return values[key]
    }
    public func recordTagRevocation(_ intent: PlayTagRevocationIntent, key: String) async throws -> PlayTagRevocationRecoverySnapshot {
        try intent.validate(key: key)
        guard values[key] == nil else { throw PlayExperienceError.persistenceUnavailable }
        let next = PlayTagRevocationRecoverySnapshot(value: intent, generation: Data(UUID().uuidString.utf8))
        values[key] = next; return next
    }
    public func clearTagRevocation(_ snapshot: PlayTagRevocationRecoverySnapshot, key: String) async throws {
        try snapshot.value.validate(key: key)
        guard values[key] == snapshot else { throw PlayExperienceError.persistenceUnavailable }
        values[key] = nil
    }
}
