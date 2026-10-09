import Foundation

/// Stable account/deployment key deliberately survives navigation and reauthentication.
/// Only attempt metadata is durable: no token, selected bytes, raw profile or URL.
public struct ProfileAvatarJournalKey: Codable, Equatable {
    public let accountID: Int
    public let namespace: String
    public let realm: String
    public init(scope: ProfileAvatarScope) { accountID = scope.identity.accountID; namespace = scope.namespace; realm = scope.realm }
    var storageKey: String { "profile-avatar.v1." + ProfileAvatarExact.hash(ProfileAvatarExact.strings([String(accountID), namespace, realm])) }
    var isValid: Bool {
        guard accountID > 0, !namespace.isEmpty, namespace.utf8.count <= 4096, let url = URL(string: realm) else { return false }
        return url.scheme == "https" && url.host != nil && url.user == nil && url.password == nil && url.query == nil && url.fragment == nil
    }
}
public struct ProfileAvatarJournalEntry: Codable, Equatable {
    public enum Phase: String, Codable {
        case pending, acknowledged, stageReserved, locallyStaged, rejected
        public var permitsNewSelection: Bool { self == .locallyStaged || self == .rejected }
    }
    public let key: ProfileAvatarJournalKey
    public let attemptID: UUID
    public let targetID: UUID
    public let selectedDigest: String
    public let phase: Phase
}
@MainActor public protocol ProfileAvatarJournaling: AnyObject {
    func entry(for key: ProfileAvatarJournalKey) throws -> ProfileAvatarJournalEntry?
    func begin(key: ProfileAvatarJournalKey, attemptID: UUID, targetID: UUID, selectedDigest: String) throws
    func record(key: ProfileAvatarJournalKey, attemptID: UUID, phase: ProfileAvatarJournalEntry.Phase) throws
}
@MainActor public final class StoredProfileAvatarJournal: ProfileAvatarJournaling {
    private struct Envelope: Codable { let version: Int; let entry: ProfileAvatarJournalEntry }
    private let read: (String) throws -> Data?
    private let write: (Data, String) throws -> Void
    public init(read: @escaping (String) throws -> Data? = { _ in throw ProfileAvatarFailure.disabled },
                write: @escaping (Data, String) throws -> Void = { _, _ in throw ProfileAvatarFailure.disabled }) {
        self.read = read; self.write = write
    }
    public func entry(for key: ProfileAvatarJournalKey) throws -> ProfileAvatarJournalEntry? {
        guard key.isValid else { throw ProfileAvatarFailure.storage }
        guard let bytes = try read(key.storageKey) else { return nil }
        guard bytes.count <= 16384, let value = try? JSONDecoder().decode(Envelope.self, from: bytes),
              value.version == 1, value.entry.key == key, value.entry.selectedDigest.count == 64,
              value.entry.selectedDigest.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw ProfileAvatarFailure.storage }
        return value.entry
    }
    public func begin(key: ProfileAvatarJournalKey, attemptID: UUID, targetID: UUID, selectedDigest: String) throws {
        guard try entry(for: key)?.phase.permitsNewSelection ?? true,
              selectedDigest.count == 64, selectedDigest.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw ProfileAvatarFailure.storage }
        try persist(.init(key: key, attemptID: attemptID, targetID: targetID, selectedDigest: selectedDigest, phase: .pending))
    }
    public func record(key: ProfileAvatarJournalKey, attemptID: UUID, phase: ProfileAvatarJournalEntry.Phase) throws {
        guard let old = try entry(for: key), old.attemptID == attemptID else { throw ProfileAvatarFailure.storage }
        let permitted: Bool
        switch (old.phase, phase) {
        case (.pending, .acknowledged), (.pending, .rejected), (.acknowledged, .stageReserved), (.stageReserved, .locallyStaged): permitted = true
        default: permitted = false
        }
        guard permitted else { throw ProfileAvatarFailure.storage }
        try persist(.init(key: key, attemptID: old.attemptID, targetID: old.targetID, selectedDigest: old.selectedDigest, phase: phase))
    }
    private func persist(_ entry: ProfileAvatarJournalEntry) throws {
        let bytes = try JSONEncoder().encode(Envelope(version: 1, entry: entry))
        guard bytes.count <= 16384 else { throw ProfileAvatarFailure.storage }
        try write(bytes, entry.key.storageKey)
        guard try read(entry.key.storageKey) == bytes else { throw ProfileAvatarFailure.storage }
    }
}
