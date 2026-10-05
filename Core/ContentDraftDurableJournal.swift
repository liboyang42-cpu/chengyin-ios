import Foundation
import CryptoKit

/// The anchor is small Keychain secret data, never a payload-sized Keychain item.
public struct ContentDraftAnchorItem: Sendable, Equatable {
    public let bytes: Data
    public let tag: Data
    public init(bytes: Data, tag: Data) { self.bytes = bytes; self.tag = tag }
}
public protocol ContentDraftAnchorStore: Sendable {
    func read(slot: String) async throws -> ContentDraftAnchorItem?
    func insert(slot: String, item: ContentDraftAnchorItem) async throws -> Bool
    /// One atomic compare-and-swap on the opaque generation; never read followed by blind overwrite.
    func exchange(slot: String, matchingTag: Data, item: ContentDraftAnchorItem) async throws -> Bool
}
public protocol ContentDraftCiphertextStore: Sendable {
    /// Durable, permanent, empty presence marker. Existing means false; never overwrite/remove.
    /// Marker-before-anchor makes lost device-only Keychain state distinguishable from a fresh slot.
    func createPresence(slot: String) async throws -> Bool
    func hasPresence(slot: String) async throws -> Bool
    /// Exclusive immutable creation; success means file AND directory durability barriers succeeded.
    func insert(name: String, bytes: Data) async throws
    /// Bounded regular-file read. Reestablish durability before returning a recovered staged file.
    func readDurably(name: String, limit: Int) async throws -> Data
    /// Missing is accepted only for an already committed clear tombstone.
    func removeDurably(name: String) async throws
}

/// Explicit injection only. Session/UI factories do not construct this adapter by default.
@MainActor public final class ContentDraftDurableJournal: ContentDraftSecureJournal {
    public let scope: ContentDraftJournalScope
    private let engine: ContentDraftJournalEngine
    #if canImport(Security) && canImport(Darwin)
    private let systemStorage: ContentDraftSystemStorage?
    var isSystemBacked: Bool { systemStorage != nil }
    /// The sealed handle is available only from the fixed OS factory, never from injected stores.
    init(scope: ContentDraftJournalScope, system: ContentDraftSystemStorage) throws {
        self.scope = scope; systemStorage = system
        engine = try ContentDraftJournalEngine(scope: scope, anchors: system.anchors, ciphertexts: system.ciphertexts)
    }
    #else
    var isSystemBacked: Bool { false }
    #endif
    /// Injectable stores support synthetic/offline execution only. Their conformance cannot
    /// assert production durability or authorize a network-capable ContentDraftService.
    public init(scope: ContentDraftJournalScope, anchors: any ContentDraftAnchorStore,
                ciphertexts: any ContentDraftCiphertextStore) throws {
        self.scope = scope
        #if canImport(Security) && canImport(Darwin)
        systemStorage = nil
        #endif
        engine = try ContentDraftJournalEngine(scope: scope, anchors: anchors, ciphertexts: ciphertexts)
    }
    public func read() async throws -> ContentDraftJournalSnapshot? { try await engine.read() }
    public func insert(_ value: ContentDraftPending) async throws -> ContentDraftJournalSnapshot { try await engine.insert(value) }
    public func replace(_ old: ContentDraftJournalSnapshot, with new: ContentDraftPending) async throws -> ContentDraftJournalSnapshot { try await engine.replace(old, with: new) }
    public func clear(matching value: ContentDraftJournalSnapshot) async throws { try await engine.clear(matching: value) }
}

/// Crypto/serialization and storage calls run away from MainActor. Actor isolation alone is
/// NOT the cross-instance lock; unique insertion and generation-CAS in the primitive are mandatory.
private actor ContentDraftJournalEngine {
    // Two 512 KiB UTF-8 payloads can occupy 2 MiB as UTF-16 in a binary plist.
    // Four MiB also bounds structure/escaping overhead. Oversize never reaches transport.
    static let maximumBlobBytes = 4_194_304
    private struct Anchor: Codable {
        enum State: String, Codable { case empty, reserved, ready, clearing }
        let schema: Int
        let binding: Data
        let blob: String
        let key: Data
        let digest: Data
        var generation: Data
        var state: State
        var dispatched: Bool
    }
    private let scope: ContentDraftJournalScope
    private let binding: Data
    private let slot: String
    private let anchors: any ContentDraftAnchorStore
    private let ciphertexts: any ContentDraftCiphertextStore
    private var busy = false
    init(scope: ContentDraftJournalScope, anchors: any ContentDraftAnchorStore,
         ciphertexts: any ContentDraftCiphertextStore) throws {
        guard scope.accountID > 0, scope.ownerMemberID > 0,
              ContentDraftIdentity.validKey(scope.clientDraftKey) else { throw ContentDraftIssue.storageUnavailable }
        var binding = Data()
        // Length-delimited UTF-8, not Swift canonical-equivalence comparison or delimiter concatenation.
        for field in [scope.market.rawValue, scope.baseURL.absoluteString, scope.namespace,
                      String(scope.accountID), String(scope.ownerMemberID), scope.businessType.rawValue, scope.clientDraftKey] {
            let bytes = Data(field.utf8)
            guard bytes.count <= 2_048 else { throw ContentDraftIssue.storageUnavailable }
            var length = UInt32(bytes.count).bigEndian
            withUnsafeBytes(of: &length) { binding.append(contentsOf: $0) }; binding.append(bytes)
        }
        guard binding.count <= 4_096 else { throw ContentDraftIssue.storageUnavailable }
        self.scope = scope; self.binding = binding
        slot = SHA256.hash(data: binding).map { String(format: "%02x", $0) }.joined()
        self.anchors = anchors; self.ciphertexts = ciphertexts
    }
    private func enter() throws { guard !busy else { throw ContentDraftIssue.storageUnavailable }; busy = true }
    private func random() -> Data { SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) } }
    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
        return try encoder.encode(value)
    }
    private func item(_ anchor: Anchor) throws -> ContentDraftAnchorItem {
        let bytes = try encode(anchor)
        guard bytes.count <= 8_192 else { throw ContentDraftIssue.storageUnavailable }
        return .init(bytes: bytes, tag: anchor.generation)
    }
    private func anchor(_ item: ContentDraftAnchorItem) throws -> Anchor {
        guard item.bytes.count <= 8_192, item.tag.count == 32 else { throw ContentDraftIssue.storageUnavailable }
        let value = try PropertyListDecoder().decode(Anchor.self, from: item.bytes)
        guard value.schema == 1, value.binding == binding, value.generation == item.tag else { throw ContentDraftIssue.storageUnavailable }
        if value.state == .empty {
            guard value.key.isEmpty, value.digest.isEmpty, value.blob.isEmpty, !value.dispatched else { throw ContentDraftIssue.storageUnavailable }
        } else {
            guard value.key.count == 32, value.digest.count == 32,
                  value.state != .reserved || !value.dispatched,
                  UUID(uuidString: value.blob)?.uuidString == value.blob else { throw ContentDraftIssue.storageUnavailable }
        }
        return value
    }
    private func validate(_ mutation: ContentDraftMutation) throws {
        try mutation.validate()
        let identity = mutation.identity
        guard identity.ownerMemberID == scope.ownerMemberID, identity.businessType == scope.businessType,
              identity.clientDraftKey.utf8.elementsEqual(scope.clientDraftKey.utf8) else { throw ContentDraftIssue.storageUnavailable }
    }
    private func load(_ anchor: Anchor) async throws -> ContentDraftPending {
        let bytes = try await ciphertexts.readDurably(name: anchor.blob, limit: Self.maximumBlobBytes)
        guard bytes.count <= Self.maximumBlobBytes else { throw ContentDraftIssue.storageUnavailable }
        let plaintext = try AES.GCM.open(AES.GCM.SealedBox(combined: bytes), using: SymmetricKey(data: anchor.key),
                                         authenticating: binding + Data(anchor.blob.utf8))
        guard Data(SHA256.hash(data: plaintext)) == anchor.digest else { throw ContentDraftIssue.storageUnavailable }
        let mutation = try PropertyListDecoder().decode(ContentDraftMutation.self, from: plaintext)
        try validate(mutation)
        return .init(mutation: mutation, dispatched: anchor.dispatched)
    }
    private func finishClear(_ value: Anchor, _ item: ContentDraftAnchorItem) async throws {
        try await ciphertexts.removeDurably(name: value.blob)
        // Keep a small authenticated empty anchor and its permanent presence marker. A restore
        // missing this device-only anchor must fail closed, never mistake it for a fresh slot.
        let empty = Anchor(schema: 1, binding: binding, blob: "", key: Data(), digest: Data(),
                           generation: random(), state: .empty, dispatched: false)
        guard try await anchors.exchange(slot: slot, matchingTag: item.tag, item: self.item(empty)) else { throw ContentDraftIssue.storageUnavailable }
    }
    private func readRecord() async throws -> ContentDraftJournalSnapshot? {
        guard let current = try await anchors.read(slot: slot) else {
            let present = try await ciphertexts.hasPresence(slot: slot)
            guard !present else { throw ContentDraftIssue.storageUnavailable }
            return nil
        }
        guard try await ciphertexts.hasPresence(slot: slot) else { throw ContentDraftIssue.storageUnavailable }
        var value = try anchor(current)
        if value.state == .empty { return nil }
        if value.state == .clearing { try await finishClear(value, current); return nil }
        let pending = try await load(value)
        var published = current
        if value.state == .reserved {
            // A complete durable authenticated blob is recoverable. Missing/partial/corrupt blobs
            // throw and retain the reservation; no scan, replacement, or automatic unlock.
            value.state = .ready; value.generation = random(); published = try item(value)
            guard try await anchors.exchange(slot: slot, matchingTag: current.tag, item: published) else { throw ContentDraftIssue.storageUnavailable }
        }
        // Loading the immutable blob suspends this engine. A different instance may have
        // advanced its anchor meanwhile; never return the generation captured before that I/O.
        guard try await ciphertexts.hasPresence(slot: slot),
              try await anchors.read(slot: slot) == published else { throw ContentDraftIssue.storageUnavailable }
        return .init(value: pending, generation: published.tag)
    }
    func read() async throws -> ContentDraftJournalSnapshot? {
        try enter(); defer { busy = false }
        do { return try await readRecord() } catch { throw ContentDraftIssue.storageUnavailable }
    }
    func insert(_ pending: ContentDraftPending) async throws -> ContentDraftJournalSnapshot {
        try enter(); defer { busy = false }
        do {
            try validate(pending.mutation)
            guard !pending.dispatched else { throw ContentDraftIssue.storageUnavailable }
            let plaintext = try encode(pending.mutation)
            guard plaintext.count <= Self.maximumBlobBytes - 28 else { throw ContentDraftIssue.storageUnavailable }
            let key = random(), blob = UUID().uuidString
            var value = Anchor(schema: 1, binding: binding, blob: blob, key: key,
                digest: Data(SHA256.hash(data: plaintext)), generation: random(), state: .reserved, dispatched: false)
            let reserved = try item(value)
            let sealed = try AES.GCM.seal(plaintext, using: SymmetricKey(data: key), authenticating: binding + Data(blob.utf8))
            guard let bytes = sealed.combined, bytes.count <= Self.maximumBlobBytes else { throw ContentDraftIssue.storageUnavailable }
            let current = try await anchors.read(slot: slot)
            if let current {
                guard try await ciphertexts.hasPresence(slot: slot) else { throw ContentDraftIssue.storageUnavailable }
                let currentAnchor = try anchor(current)
                if currentAnchor.state == .empty {
                    guard try await anchors.exchange(slot: slot, matchingTag: current.tag, item: reserved) else { throw ContentDraftIssue.storageUnavailable }
                } else {
                    guard let existing = try await readRecord(), existing.value == pending else { throw ContentDraftIssue.storageUnavailable }
                    return existing
                }
            } else {
                // Existing marker + absent anchor means lost storage (including device-only
                // backup restore), not permission to create a new encryption key or intent.
                guard try await ciphertexts.createPresence(slot: slot) else { throw ContentDraftIssue.storageUnavailable }
                guard try await anchors.insert(slot: slot, item: reserved) else { throw ContentDraftIssue.storageUnavailable }
            }
            // Reserve before creating even a partial file. A thrown/ambiguous write keeps its lock.
            try await ciphertexts.insert(name: blob, bytes: bytes)
            value.state = .ready; value.generation = random()
            let ready = try item(value)
            guard try await anchors.exchange(slot: slot, matchingTag: reserved.tag, item: ready) else { throw ContentDraftIssue.storageUnavailable }
            return .init(value: pending, generation: ready.tag)
        } catch { throw ContentDraftIssue.storageUnavailable }
    }
    private func matching(_ expected: ContentDraftJournalSnapshot) async throws -> (Anchor, ContentDraftAnchorItem) {
        guard expected.generation.count == 32, try await ciphertexts.hasPresence(slot: slot),
              let current = try await anchors.read(slot: slot), current.tag == expected.generation else { throw ContentDraftIssue.storageUnavailable }
        let value = try anchor(current)
        guard value.state == .ready, try await load(value) == expected.value else { throw ContentDraftIssue.storageUnavailable }
        return (value, current)
    }
    func replace(_ old: ContentDraftJournalSnapshot, with new: ContentDraftPending) async throws -> ContentDraftJournalSnapshot {
        try enter(); defer { busy = false }
        do {
            guard old.value.mutation == new.mutation, new.dispatched else { throw ContentDraftIssue.storageUnavailable }
            var (value, current) = try await matching(old)
            value.dispatched = true; value.generation = random()
            let next = try item(value)
            guard try await anchors.exchange(slot: slot, matchingTag: current.tag, item: next) else { throw ContentDraftIssue.storageUnavailable }
            return .init(value: new, generation: next.tag)
        } catch { throw ContentDraftIssue.storageUnavailable }
    }
    func clear(matching pending: ContentDraftJournalSnapshot) async throws {
        try enter(); defer { busy = false }
        do {
            var (value, current) = try await matching(pending)
            value.state = .clearing; value.generation = random()
            let tombstone = try item(value)
            guard try await anchors.exchange(slot: slot, matchingTag: current.tag, item: tombstone) else { throw ContentDraftIssue.storageUnavailable }
            // Only a committed tombstone may delete ciphertext. Crash recovery finishes this
            // exact clear; no newer generation's blob or anchor can be removed.
            try await finishClear(value, tombstone)
        } catch { throw ContentDraftIssue.storageUnavailable }
    }
}
