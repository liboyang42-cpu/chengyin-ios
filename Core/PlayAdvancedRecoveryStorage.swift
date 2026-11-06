import Foundation
import CryptoKit

/// Independent advanced slot using the existing reviewed ciphertext/anchor
/// primitives. No classic, paused, game-command or tag slot is read or changed.
@MainActor public final class PlayAdvancedDurableRecovery: PlayAdvancedRecovery {
    private static let liveProcessID = UUID()
    public let processID: UUID
    private let owner: PlayRecoveryOwner
    private let scope: PlayAdvancedRecoveryScope
    private let slot: PlayAdvancedEncryptedSlot
    public convenience init(owner: PlayRecoveryOwner, scope: PlayAdvancedRecoveryScope,
                            anchors: any ContentDraftAnchorStore, ciphertexts: any ContentDraftCiphertextStore) throws {
        try self.init(owner: owner, scope: scope, anchors: anchors, ciphertexts: ciphertexts, processID: Self.liveProcessID)
    }
    /// Internal process override is for reconstruction regressions, not authority.
    init(owner: PlayRecoveryOwner, scope: PlayAdvancedRecoveryScope,
         anchors: any ContentDraftAnchorStore, ciphertexts: any ContentDraftCiphertextStore, processID: UUID) throws {
        self.owner = owner; self.scope = scope; self.processID = processID
        slot = try .init(binding: scope.key(owner: owner), anchors: anchors, ciphertexts: ciphertexts)
    }
    private func validate(_ value: PlayAdvancedRecoveryRecord) throws {
        try value.validate()
        guard value.owner == owner, value.scope == scope else { throw PlayExperienceError.persistenceUnavailable }
    }
    private func encode(_ value: PlayAdvancedRecoveryRecord) throws -> Data {
        try validate(value)
        let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
        return try encoder.encode(value)
    }
    private func decode(_ raw: PlayAdvancedEncryptedSnapshot) throws -> PlayAdvancedRecoverySnapshot? {
        guard let data = raw.data else { return nil }
        let value = try PropertyListDecoder().decode(PlayAdvancedRecoveryRecord.self, from: data)
        try validate(value)
        guard let generation = raw.generation else { throw PlayExperienceError.persistenceUnavailable }
        return .init(value: value, generation: generation, persistedBytes: data)
    }
    private func original(_ snapshot: PlayAdvancedRecoverySnapshot) throws -> PlayAdvancedEncryptedSnapshot {
        try validate(snapshot.value)
        guard let bytes = snapshot.persistedBytes,
              try PropertyListDecoder().decode(PlayAdvancedRecoveryRecord.self, from: bytes) == snapshot.value else { throw PlayExperienceError.persistenceUnavailable }
        return .init(data: bytes, generation: snapshot.generation)
    }
    public func read() async throws -> PlayAdvancedRecoverySnapshot? {
        do { return try decode(await slot.read()) } catch { throw PlayExperienceError.persistenceUnavailable }
    }
    public func prepare(_ value: PlayAdvancedRecoveryRecord) async throws -> PlayAdvancedRecoverySnapshot {
        do {
            try validate(value)
            guard value.phase == .prepared || value.phase == .starting && value.dispatchProcess == processID else { throw PlayExperienceError.persistenceUnavailable }
            let before = try await slot.read()
            if let prior = try decode(before) {
                guard value.canPrepareReplacing(prior.value) else { throw PlayExperienceError.persistenceUnavailable }
            }
            let after = try await slot.write(encode(value), replacing: before)
            guard let result = try decode(after) else { throw PlayExperienceError.persistenceUnavailable }; return result
        } catch { throw PlayExperienceError.persistenceUnavailable }
    }
    public func transition(_ snapshot: PlayAdvancedRecoverySnapshot, to phase: PlayAdvancedRecoveryRecord.Phase, startedSessionID: Int?) async throws -> PlayAdvancedRecoverySnapshot {
        do {
            let before = try original(snapshot)
            let value = try snapshot.value.next(phase, process: processID, startedSessionID: startedSessionID)
            let after = try await slot.write(encode(value), replacing: before)
            guard let result = try decode(after) else { throw PlayExperienceError.persistenceUnavailable }; return result
        } catch { throw PlayExperienceError.persistenceUnavailable }
    }
    public func clear(_ snapshot: PlayAdvancedRecoverySnapshot) async throws {
        do {
            guard snapshot.value.canClear else { throw PlayExperienceError.persistenceUnavailable }
            _ = try await slot.write(nil, replacing: original(snapshot))
        } catch { throw PlayExperienceError.persistenceUnavailable }
    }
}

#if canImport(Security) && canImport(Darwin)
/// Fixed OS roots only. This factory supplies persistence, not permission to play.
@MainActor public enum PlayAdvancedRecoverySystemFactory {
    public static func make(session: PlayExperienceSession, scope: PlayAdvancedRecoveryScope,
                            regionalConfiguration: RegionalConfiguration, storageScope: RegionalSessionStorageScope) throws -> PlayAdvancedDurableRecovery {
        guard storageScope.matches(configuration: regionalConfiguration),
              session.namespace.utf8.elementsEqual(storageScope.service.utf8),
              regionalConfiguration.apiConfiguration != nil else { throw PlayExperienceError.persistenceUnavailable }
        let root = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).resolvingSymlinksInPath()
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("PlayAdvancedRecovery-v1", isDirectory: true)
        return try .init(owner: .init(session: session), scope: scope,
            anchors: ContentDraftSystemAnchors(service: "questify.play.advanced-recovery.v1"),
            ciphertexts: ContentDraftSystemCiphertexts(root: root, createApplicationSupport: true))
    }
}
#endif
private struct PlayAdvancedEncryptedSnapshot: Equatable {
    let data: Data?
    let generation: Data?
}
/// Bounded immutable encrypted generations. A reservation precedes file I/O. No failed update
/// rolls back to an old generation. Successful clear retains an empty anchor and presence marker.
private actor PlayAdvancedEncryptedSlot {
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
    private func finishClear(_ value: Anchor, current: ContentDraftAnchorItem) async throws -> PlayAdvancedEncryptedSnapshot {
        try await ciphertexts.removeDurably(name: value.blob)
        let empty = Anchor(schema: 1, binding: binding, blob: "", key: Data(), digest: Data(), generation: random(), state: .empty)
        guard try await anchors.exchange(slot: slot, matchingTag: current.tag, item: item(empty)) else { throw PlayExperienceError.persistenceUnavailable }
        return .init(data: nil, generation: empty.generation)
    }
    private func readRecord() async throws -> PlayAdvancedEncryptedSnapshot {
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
    func read() async throws -> PlayAdvancedEncryptedSnapshot {
        try enter(); defer { busy = false }
        do { return try await readRecord() } catch { throw PlayExperienceError.persistenceUnavailable }
    }
    func write(_ data: Data?, replacing expected: PlayAdvancedEncryptedSnapshot) async throws -> PlayAdvancedEncryptedSnapshot {
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
