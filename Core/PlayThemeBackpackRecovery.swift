import Foundation
import CryptoKit

/// One exact personal inventory request, never credentials or a reconstructed retry.
public struct PlayThemeBackpackPending: Codable, Equatable {
    public enum State: String, Codable { case prepared, dispatching, unknown, acknowledged }
    public let intent: PlayThemeBackpackIntent
    public let state: State
    public let dispatchProcess: UUID?
    /// The original POST response data, not a later GET projection or a fabricated receipt ID.
    public let receipt: Data?
}

public struct PlayThemeBackpackRecoverySnapshot: Equatable {
    public let value: PlayThemeBackpackPending
    public let generation: Data
    let persistedBytes: Data?
    init(value: PlayThemeBackpackPending, generation: Data, persistedBytes: Data? = nil) {
        self.value = value; self.generation = generation; self.persistedBytes = persistedBytes
    }
}

/// Final concrete storage. Neither injected primitive conformance nor a UI flag can
/// confer production dispatch authority. All mutations use the exact persisted generation.
@MainActor public final class PlayThemeBackpackRecoveryStore {
    private static let liveProcessID = UUID()
    public let processID: UUID
    private let owner: PlayRecoveryOwner
    private let scope: PlaySessionScope
    private let topicID: Int
    private let key: String
    private let slot: PlayThemeBackpackEncryptedSlot
    private struct SystemSeal { let baseURL: URL }
    private var systemSeal: SystemSeal?

    /// Synthetic/offline injection only, even if callers inject actual OS primitives.
    public convenience init(session: PlayExperienceSession, scope: PlaySessionScope, topicID: Int,
                            anchors: any ContentDraftAnchorStore, ciphertexts: any ContentDraftCiphertextStore) throws {
        try self.init(session: session, scope: scope, topicID: topicID, anchors: anchors,
                      ciphertexts: ciphertexts, processID: Self.liveProcessID)
    }
    /// A distinct nonce is available only to internal synthetic process-restart tests.
    init(session: PlayExperienceSession, scope: PlaySessionScope, topicID: Int,
         anchors: any ContentDraftAnchorStore, ciphertexts: any ContentDraftCiphertextStore, processID: UUID) throws {
        let owner = PlayRecoveryOwner(session: session)
        guard owner.accountID > 0, !owner.namespace.isEmpty, !owner.role.isEmpty,
              scope.isValid, topicID > 0 else { throw PlayExperienceError.persistenceUnavailable }
        if case .topic(let id) = scope, id != topicID { throw PlayExperienceError.persistenceUnavailable }
        let scopeKey: String
        switch scope {
        case .activity(let id): scopeKey = "activity-" + String(id)
        case .topic(let id): scopeKey = "topic-" + String(id)
        }
        // Epoch, role and run never create a fresh slot around an unresolved command.
        let key = "theme-backpack:v1:" + Data(owner.namespace.utf8).base64EncodedString() + ":" +
            String(owner.accountID) + ":" + scopeKey + ":" + String(topicID)
        self.owner = owner; self.scope = scope; self.topicID = topicID; self.key = key
        self.processID = processID; systemSeal = nil
        slot = try PlayThemeBackpackEncryptedSlot(binding: key, anchors: anchors, ciphertexts: ciphertexts)
    }

    /// The sole production provenance factory. Constructing it does not read/write storage
    /// and does not enable any writer capability or inject itself into an App session.
    public static func make(session: PlayExperienceSession, scope: PlaySessionScope, topicID: Int,
                            regionalConfiguration: RegionalConfiguration,
                            storageScope: RegionalSessionStorageScope) throws -> PlayThemeBackpackRecoveryStore {
        #if canImport(Security) && canImport(Darwin)
        guard storageScope.matches(configuration: regionalConfiguration),
              session.namespace.utf8.elementsEqual(storageScope.service.utf8),
              let baseURL = regionalConfiguration.apiConfiguration?.baseURL else { throw PlayExperienceError.persistenceUnavailable }
        // Only the OS-supplied home prefix is canonicalized. Existing OS primitives
        // validate the fixed tail using no-follow descriptors and durability barriers.
        let root = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).resolvingSymlinksInPath()
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("PlayThemeBackpackRecovery-v1", isDirectory: true)
        let store = try PlayThemeBackpackRecoveryStore(session: session, scope: scope, topicID: topicID,
            anchors: ContentDraftSystemAnchors(service: "questify.play.theme-backpack-recovery.v1"),
            ciphertexts: ContentDraftSystemCiphertexts(root: root, createApplicationSupport: true))
        store.systemSeal = SystemSeal(baseURL: baseURL)
        return store
        #else
        throw PlayExperienceError.persistenceUnavailable
        #endif
    }
    func permitsSystemDispatch(to endpoint: URL) -> Bool {
        systemSeal?.baseURL.absoluteString.utf8.elementsEqual(endpoint.absoluteString.utf8) == true
    }
    private func encode(_ value: PlayThemeBackpackPending) throws -> Data {
        let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
        return try encoder.encode(value)
    }
    private func validate(_ intent: PlayThemeBackpackIntent) throws {
        try intent.validate()
        guard intent.owner == owner, intent.scope == scope, intent.topicID == topicID,
              intent.storageKey.utf8.elementsEqual(key.utf8) else { throw PlayExperienceError.persistenceUnavailable }
    }
    private func validateReceipt(_ bytes: Data, intent: PlayThemeBackpackIntent) throws {
        // Re-encoding a <=512 KiB wire response can expand escaping. Leave bounded
        // headroom while the complete encrypted record remains below one MiB.
        guard !bytes.isEmpty, bytes.count <= 768 * 1024 else { throw PlayExperienceError.persistenceUnavailable }
        let raw = try JSONDecoder().decode(PlayWireValue.self, from: bytes)
        let facts = try PlayThemeBackpackActionFacts(raw, scope: intent.scope, topicID: intent.topicID,
                                                   sessionID: intent.command.sessionId)
        // The saved original response is exactly the submitted version plus one.
        // A higher-version GET is not a substitute for the original POST's response.
        guard facts.version == intent.command.expectedVersion + 1 else { throw PlayExperienceError.persistenceUnavailable }
    }
    private func validate(_ value: PlayThemeBackpackPending) throws {
        try validate(value.intent)
        switch value.state {
        case .prepared:
            guard value.dispatchProcess == nil, value.receipt == nil else { throw PlayExperienceError.persistenceUnavailable }
        case .dispatching, .unknown:
            guard value.dispatchProcess != nil, value.receipt == nil else { throw PlayExperienceError.persistenceUnavailable }
        case .acknowledged:
            guard value.dispatchProcess != nil, let receipt = value.receipt else { throw PlayExperienceError.persistenceUnavailable }
            try validateReceipt(receipt, intent: value.intent)
        }
    }
    private func pending(_ raw: PlayThemeBackpackEncryptedSnapshot) throws -> PlayThemeBackpackRecoverySnapshot? {
        guard let bytes = raw.data else { return nil }
        let value = try PropertyListDecoder().decode(PlayThemeBackpackPending.self, from: bytes)
        try validate(value)
        guard let generation = raw.generation, generation.count == 32 else { throw PlayExperienceError.persistenceUnavailable }
        return .init(value: value, generation: generation, persistedBytes: bytes)
    }
    private func original(_ snapshot: PlayThemeBackpackRecoverySnapshot) throws -> Data {
        try validate(snapshot.value)
        guard snapshot.generation.count == 32, let bytes = snapshot.persistedBytes,
              bytes.count <= 1_048_576,
              try PropertyListDecoder().decode(PlayThemeBackpackPending.self, from: bytes) == snapshot.value else {
            throw PlayExperienceError.persistenceUnavailable
        }
        return bytes
    }
    public func read() async throws -> PlayThemeBackpackRecoverySnapshot? {
        do { return try pending(await slot.read()) }
        catch { throw PlayExperienceError.persistenceUnavailable }
    }
    public func prepare(_ intent: PlayThemeBackpackIntent) async throws -> PlayThemeBackpackRecoverySnapshot {
        do {
            try validate(intent)
            let old = try await slot.read()
            guard old.data == nil else { throw PlayExperienceError.persistenceUnavailable }
            let value = PlayThemeBackpackPending(intent: intent, state: .prepared, dispatchProcess: nil, receipt: nil)
            let written = try await slot.write(encode(value), replacing: old)
            guard let result = try pending(written) else { throw PlayExperienceError.persistenceUnavailable }
            return result
        } catch { throw PlayExperienceError.persistenceUnavailable }
    }
    public func transition(_ snapshot: PlayThemeBackpackRecoverySnapshot, to state: PlayThemeBackpackPending.State,
                           receipt: Data? = nil) async throws -> PlayThemeBackpackRecoverySnapshot {
        do {
            let bytes = try original(snapshot), value = snapshot.value
            let allowed: Bool
            switch (value.state, state) {
            case (.prepared, .dispatching), (.unknown, .dispatching): allowed = true
            case (.dispatching, .dispatching): allowed = value.dispatchProcess != processID
            case (.dispatching, .unknown), (.dispatching, .acknowledged): allowed = value.dispatchProcess == processID
            default: allowed = false
            }
            guard allowed, (state == .acknowledged) == (receipt != nil) else { throw PlayExperienceError.persistenceUnavailable }
            let next = PlayThemeBackpackPending(intent: value.intent, state: state,
                dispatchProcess: state == .dispatching ? processID : value.dispatchProcess, receipt: receipt)
            try validate(next)
            let written = try await slot.write(encode(next), replacing: .init(data: bytes, generation: snapshot.generation))
            guard let result = try pending(written) else { throw PlayExperienceError.persistenceUnavailable }
            return result
        } catch { throw PlayExperienceError.persistenceUnavailable }
    }
    public func clear(_ snapshot: PlayThemeBackpackRecoverySnapshot) async throws {
        do {
            let bytes = try original(snapshot)
            guard snapshot.value.state == .acknowledged else { throw PlayExperienceError.persistenceUnavailable }
            _ = try await slot.write(nil, replacing: .init(data: bytes, generation: snapshot.generation))
        } catch { throw PlayExperienceError.persistenceUnavailable }
    }
}

// Private byte algorithm copied from public PlayDurableRecovery.swift blob
// f839a09b49c2173bb8f1bf7d7865b1b1251ddef5; independent slot names and a 1 MiB
// bound accommodate the immutable body plus a bounded 768 KiB stored receipt.
private struct PlayThemeBackpackEncryptedSnapshot: Equatable {
    let data: Data?
    let generation: Data?
}
/// Bounded immutable encrypted generations. A reservation precedes file I/O. No failed update
/// rolls back to an old generation. Successful clear retains an empty anchor and presence marker.
private actor PlayThemeBackpackEncryptedSlot {
    private static let limit = 1_048_576
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
    private func finishClear(_ value: Anchor, current: ContentDraftAnchorItem) async throws -> PlayThemeBackpackEncryptedSnapshot {
        try await ciphertexts.removeDurably(name: value.blob)
        let empty = Anchor(schema: 1, binding: binding, blob: "", key: Data(), digest: Data(), generation: random(), state: .empty)
        guard try await anchors.exchange(slot: slot, matchingTag: current.tag, item: item(empty)) else { throw PlayExperienceError.persistenceUnavailable }
        return .init(data: nil, generation: empty.generation)
    }
    private func readRecord() async throws -> PlayThemeBackpackEncryptedSnapshot {
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
    func read() async throws -> PlayThemeBackpackEncryptedSnapshot {
        try enter(); defer { busy = false }
        do { return try await readRecord() } catch { throw PlayExperienceError.persistenceUnavailable }
    }
    func write(_ data: Data?, replacing expected: PlayThemeBackpackEncryptedSnapshot) async throws -> PlayThemeBackpackEncryptedSnapshot {
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
