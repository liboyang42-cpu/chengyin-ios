import Foundation
import CryptoKit

/// Durable normal-Play prerequisite only. Uses the unchanged reviewed OS storage primitives;
/// neither arbitrary conformance nor this injectable initializer grants network authority.
@MainActor public final class PlayDurableRecovery: PlayCompletionRecoveryStore, PlayPausedStorage {
    private static let liveProcessID = UUID()
    public let processID: UUID
    private let key: String
    private let owner: PlayRecoveryOwner
    private let completion: PlayEncryptedSlot
    private let paused: PlayEncryptedSlot
    #if canImport(Security) && canImport(Darwin)
    private var systemStorage: PlayRecoverySystemStorage?
    var isSystemBacked: Bool { systemStorage != nil }
    func permitsSystemDispatch(to endpoint: URL) -> Bool {
        systemStorage?.baseURL.absoluteString.utf8.elementsEqual(endpoint.absoluteString.utf8) == true
    }
    convenience init(owner: PlayRecoveryOwner, key: String, system: PlayRecoverySystemStorage) throws {
        try self.init(owner: owner, key: key, anchors: system.anchors, ciphertexts: system.ciphertexts, processID: Self.liveProcessID)
        systemStorage = system
    }
    #else
    var isSystemBacked: Bool { false }
    func permitsSystemDispatch(to endpoint: URL) -> Bool { false }
    #endif
    public convenience init(owner: PlayRecoveryOwner, key: String, anchors: any ContentDraftAnchorStore,
                            ciphertexts: any ContentDraftCiphertextStore) throws {
        try self.init(owner: owner, key: key, anchors: anchors, ciphertexts: ciphertexts, processID: Self.liveProcessID)
    }
    /// Internal synthetic tests may model a process restart without any real app storage.
    init(owner: PlayRecoveryOwner, key: String, anchors: any ContentDraftAnchorStore,
         ciphertexts: any ContentDraftCiphertextStore, processID: UUID) throws {
        guard owner.accountID > 0, !owner.namespace.isEmpty, !owner.role.isEmpty else { throw PlayExperienceError.persistenceUnavailable }
        self.owner = owner; self.key = key; self.processID = processID
        completion = try PlayEncryptedSlot(binding: key + ":completion", anchors: anchors, ciphertexts: ciphertexts)
        paused = try PlayEncryptedSlot(binding: key + ":paused", anchors: anchors, ciphertexts: ciphertexts)
    }
    private func check(_ key: String) throws {
        guard self.key.utf8.elementsEqual(key.utf8) else { throw PlayExperienceError.persistenceUnavailable }
    }
    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = PropertyListEncoder(); encoder.outputFormat = .binary; return try encoder.encode(value)
    }
    private func pending(_ raw: PlayEncryptedSnapshot) throws -> PlayCompletionRecoverySnapshot? {
        guard let data = raw.data else { return nil }
        let value = try PropertyListDecoder().decode(PlayPendingCompletion.self, from: data)
        guard value.intent.owner == owner, value.intent.nodeID > 0, let generation = raw.generation,
              (value.state == .prepared) == (value.dispatchProcess == nil) else { throw PlayExperienceError.persistenceUnavailable }
        return .init(value: value, generation: generation, persistedBytes: data)
    }
    public func read(_ key: String) async throws -> PlayCompletionRecoverySnapshot? {
        try check(key)
        do { return try pending(await completion.read()) } catch { throw PlayExperienceError.persistenceUnavailable }
    }
    public func prepare(_ intent: PlayCompletionIntent, key: String) async throws -> PlayCompletionRecoverySnapshot {
        try check(key)
        guard intent.owner == owner, intent.nodeID > 0 else { throw PlayExperienceError.persistenceUnavailable }
        let old = try await completion.read()
        guard old.data == nil else { throw PlayExperienceError.persistenceUnavailable }
        let value = PlayPendingCompletion(intent: intent, state: .prepared, dispatchProcess: nil)
        let next = try await completion.write(encode(value), replacing: old)
        guard let result = try pending(next) else { throw PlayExperienceError.persistenceUnavailable }; return result
    }
    public func transition(_ snapshot: PlayCompletionRecoverySnapshot, to state: PlayPendingCompletion.State, key: String) async throws -> PlayCompletionRecoverySnapshot {
        try check(key)
        guard snapshot.value.intent.owner == owner else { throw PlayExperienceError.persistenceUnavailable }
        let stored = try PropertyListDecoder().decode(PlayPendingCompletion.self, from: original(snapshot))
        let next = try PlayRecoveryTransition.next(stored, to: state, processID: processID)
        let written = try await completion.write(encode(next), replacing: .init(data: try original(snapshot), generation: snapshot.generation))
        guard let result = try pending(written) else { throw PlayExperienceError.persistenceUnavailable }; return result
    }
    private func original(_ snapshot: PlayCompletionRecoverySnapshot) throws -> Data {
        guard let bytes = snapshot.persistedBytes,
              try PropertyListDecoder().decode(PlayPendingCompletion.self, from: bytes) == snapshot.value else { throw PlayExperienceError.persistenceUnavailable }
        return bytes
    }
    public func clear(_ snapshot: PlayCompletionRecoverySnapshot, key: String) async throws {
        try check(key)
        guard snapshot.value.intent.owner == owner else { throw PlayExperienceError.persistenceUnavailable }
        _ = try await completion.write(nil, replacing: .init(data: try original(snapshot), generation: snapshot.generation))
    }
    public func read(key: String) async throws -> PlayPausedStorageSnapshot {
        try check(key)
        do {
            let raw = try await paused.read()
            let value = try raw.data.map { try PropertyListDecoder().decode(PlayPausedSnapshot.self, from: $0) }
            if let value {
                guard value.owner == owner else { throw PlayExperienceError.persistenceUnavailable }
                try PlayRecoveryTransition.validatePaused(value, previous: nil)
            }
            return .init(value: value, generation: raw.generation, persistedBytes: raw.data)
        } catch { throw PlayExperienceError.persistenceUnavailable }
    }
    public func write(_ value: PlayPausedSnapshot, replacing snapshot: PlayPausedStorageSnapshot, key: String) async throws -> PlayPausedStorageSnapshot {
        try check(key)
        guard value.owner == owner else { throw PlayExperienceError.persistenceUnavailable }
        try PlayRecoveryTransition.validatePaused(value, previous: snapshot.value)
        if let previous = snapshot.value {
            guard let bytes = snapshot.persistedBytes,
                  try PropertyListDecoder().decode(PlayPausedSnapshot.self, from: bytes) == previous else { throw PlayExperienceError.persistenceUnavailable }
        } else { guard snapshot.persistedBytes == nil else { throw PlayExperienceError.persistenceUnavailable } }
        let old = PlayEncryptedSnapshot(data: snapshot.persistedBytes, generation: snapshot.generation)
        let written = try await paused.write(encode(value), replacing: old)
        return .init(value: value, generation: written.generation, persistedBytes: written.data)
    }
}
private struct PlayEncryptedSnapshot: Equatable {
    let data: Data?
    let generation: Data?
}
/// Bounded immutable encrypted generations. A reservation precedes file I/O. No failed update
/// rolls back to an old generation. Successful clear retains an empty anchor and presence marker.
private actor PlayEncryptedSlot {
    private static let limit = 262_144
    private struct Anchor: Codable {
        enum State: String, Codable { case reserved, ready, clearing, empty }
        let schema: Int
        let binding: Data
        let blob: String
        let key: Data
        let digest: Data
        var generation: Data
        var state: State
    }
    private let binding: Data
    private let slot: String
    private let anchors: any ContentDraftAnchorStore
    private let ciphertexts: any ContentDraftCiphertextStore
    private var busy = false
    init(binding: String, anchors: any ContentDraftAnchorStore, ciphertexts: any ContentDraftCiphertextStore) throws {
        let bytes = Data(binding.utf8)
        guard !bytes.isEmpty, bytes.count <= 4_096 else { throw PlayExperienceError.persistenceUnavailable }
        self.binding = bytes; slot = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        self.anchors = anchors; self.ciphertexts = ciphertexts
    }
    private func enter() throws { guard !busy else { throw PlayExperienceError.persistenceUnavailable }; busy = true }
    private func random() -> Data { SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) } }
    private func item(_ value: Anchor) throws -> ContentDraftAnchorItem {
        let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
        let bytes = try encoder.encode(value)
        guard bytes.count <= 8_192 else { throw PlayExperienceError.persistenceUnavailable }
        return .init(bytes: bytes, tag: value.generation)
    }
    private func decode(_ item: ContentDraftAnchorItem) throws -> Anchor {
        guard item.bytes.count <= 8_192, item.tag.count == 32 else { throw PlayExperienceError.persistenceUnavailable }
        let value = try PropertyListDecoder().decode(Anchor.self, from: item.bytes)
        guard value.schema == 1, value.binding == binding, value.generation == item.tag else { throw PlayExperienceError.persistenceUnavailable }
        if value.state == .empty {
            guard value.blob.isEmpty, value.key.isEmpty, value.digest.isEmpty else { throw PlayExperienceError.persistenceUnavailable }
        } else {
            guard value.key.count == 32, value.digest.count == 32, UUID(uuidString: value.blob)?.uuidString == value.blob else { throw PlayExperienceError.persistenceUnavailable }
        }
        return value
    }
    private func load(_ value: Anchor) async throws -> Data {
        let bytes = try await ciphertexts.readDurably(name: value.blob, limit: Self.limit)
        guard bytes.count <= Self.limit else { throw PlayExperienceError.persistenceUnavailable }
        let plaintext = try AES.GCM.open(AES.GCM.SealedBox(combined: bytes), using: SymmetricKey(data: value.key), authenticating: binding + Data(value.blob.utf8))
        guard Data(SHA256.hash(data: plaintext)) == value.digest else { throw PlayExperienceError.persistenceUnavailable }; return plaintext
    }
    private func finishClear(_ value: Anchor, current: ContentDraftAnchorItem) async throws -> PlayEncryptedSnapshot {
        try await ciphertexts.removeDurably(name: value.blob)
        let empty = Anchor(schema: 1, binding: binding, blob: "", key: Data(), digest: Data(), generation: random(), state: .empty)
        guard try await anchors.exchange(slot: slot, matchingTag: current.tag, item: item(empty)) else { throw PlayExperienceError.persistenceUnavailable }
        return .init(data: nil, generation: empty.generation)
    }
    private func readRecord() async throws -> PlayEncryptedSnapshot {
        guard let current = try await anchors.read(slot: slot) else {
            guard try await ciphertexts.hasPresence(slot: slot) == false else { throw PlayExperienceError.persistenceUnavailable }
            return .init(data: nil, generation: nil)
        }
        guard try await ciphertexts.hasPresence(slot: slot) else { throw PlayExperienceError.persistenceUnavailable }
        var value = try decode(current)
        if value.state == .empty { return .init(data: nil, generation: value.generation) }
        if value.state == .clearing { return try await finishClear(value, current: current) }
        let plaintext = try await load(value)
        var published = current
        if value.state == .reserved {
            value.state = .ready; value.generation = random(); published = try item(value)
            guard try await anchors.exchange(slot: slot, matchingTag: current.tag, item: published) else { throw PlayExperienceError.persistenceUnavailable }
        }
        guard try await ciphertexts.hasPresence(slot: slot), try await anchors.read(slot: slot) == published else { throw PlayExperienceError.persistenceUnavailable }
        return .init(data: plaintext, generation: published.tag)
    }
    func read() async throws -> PlayEncryptedSnapshot {
        try enter(); defer { busy = false }
        do { return try await readRecord() } catch { throw PlayExperienceError.persistenceUnavailable }
    }
    func write(_ data: Data?, replacing expected: PlayEncryptedSnapshot) async throws -> PlayEncryptedSnapshot {
        try enter(); defer { busy = false }
        do {
            let observed = try await readRecord()
            guard observed == expected else { throw PlayExperienceError.persistenceUnavailable }
            let current = try await anchors.read(slot: slot)
            guard current?.tag == expected.generation else { throw PlayExperienceError.persistenceUnavailable }
            if data == nil {
                guard let current, expected.data != nil else { throw PlayExperienceError.persistenceUnavailable }
                var value = try decode(current); value.state = .clearing; value.generation = random()
                let clearing = try item(value)
                guard try await anchors.exchange(slot: slot, matchingTag: current.tag, item: clearing) else { throw PlayExperienceError.persistenceUnavailable }
                return try await finishClear(value, current: clearing)
            }
            guard let data, data.count <= Self.limit - 28 else { throw PlayExperienceError.persistenceUnavailable }
            let key = random(), blob = UUID().uuidString
            var value = Anchor(schema: 1, binding: binding, blob: blob, key: key, digest: Data(SHA256.hash(data: data)), generation: random(), state: .reserved)
            let sealed = try AES.GCM.seal(data, using: SymmetricKey(data: key), authenticating: binding + Data(blob.utf8))
            guard let bytes = sealed.combined, bytes.count <= Self.limit else { throw PlayExperienceError.persistenceUnavailable }
            let reservation = try item(value)
            if let current {
                guard try await anchors.exchange(slot: slot, matchingTag: current.tag, item: reservation) else { throw PlayExperienceError.persistenceUnavailable }
            } else {
                guard try await ciphertexts.createPresence(slot: slot), try await anchors.insert(slot: slot, item: reservation) else { throw PlayExperienceError.persistenceUnavailable }
            }
            try await ciphertexts.insert(name: blob, bytes: bytes)
            value.state = .ready; value.generation = random()
            let ready = try item(value)
            guard try await anchors.exchange(slot: slot, matchingTag: reservation.tag, item: ready) else { throw PlayExperienceError.persistenceUnavailable }
            // Cleanup follows commit and never removes a newer blob. A crash here can leave
            // an unreachable encrypted orphan; no scanning or automatic fallback is attempted.
            if let current { let old = try decode(current); if !old.blob.isEmpty { try await ciphertexts.removeDurably(name: old.blob) } }
            guard try await anchors.read(slot: slot) == ready else { throw PlayExperienceError.persistenceUnavailable }
            return .init(data: data, generation: value.generation)
        } catch { throw PlayExperienceError.persistenceUnavailable }
    }
}
