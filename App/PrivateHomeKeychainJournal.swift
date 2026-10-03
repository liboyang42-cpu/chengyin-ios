import Foundation
import Security
import CryptoKit

struct PrivateHomeKeychainItem: Sendable {
    let bytes: Data
    let tag: Data
}
/// Typed seam: tests supply an actor-backed synthetic vault. No Security API runs in those tests.
protocol PrivateHomeKeychainPrimitive: Sendable {
    func read(key: String) async throws -> PrivateHomeKeychainItem?
    /// true means inserted; false means the unique primary key already exists. Never upsert.
    func insert(key: String, item: PrivateHomeKeychainItem) async throws -> Bool
    /// Conditional delete: atomically matches the exact opaque content tag. Never blind-delete.
    func remove(key: String, matchingTag: Data) async throws -> Bool
}

/// This non-main actor calls Security synchronously without suspension inside an OS operation.
/// OS uniqueness/attribute matching protects separate actor instances/processes as well.
actor PrivateHomeSystemKeychain: PrivateHomeKeychainPrimitive {
    private let service: String
    /// Alternate namespaces are for isolated OS integration tests; production keeps its canonical service.
    init(service: String = "questify.private-home.pending.v1") { self.service = service }
    private func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: key, kSecAttrSynchronizable as String: false,
         kSecUseDataProtectionKeychain as String: true]
    }
    func read(key: String) throws -> PrivateHomeKeychainItem? {
        var request = query(key)
        request[kSecReturnAttributes as String] = true; request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        request[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let value = result as? [String: Any],
              let data = value[kSecValueData as String] as? Data, data.count <= 8_192,
              let tag = value[kSecAttrGeneric as String] as? Data, tag.count == 32,
              (value[kSecAttrAccessible as String] as? String) == (kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String),
              (value[kSecAttrSynchronizable as String] as? NSNumber)?.boolValue == false else { throw PrivateHomeIssue.storageUnavailable }
        return PrivateHomeKeychainItem(bytes: data, tag: tag)
    }
    func insert(key: String, item: PrivateHomeKeychainItem) throws -> Bool {
        guard item.bytes.count <= 8_192, item.tag.count == 32 else { throw PrivateHomeIssue.storageUnavailable }
        var request = query(key)
        request[kSecValueData as String] = item.bytes; request[kSecAttrGeneric as String] = item.tag
        request[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(request as CFDictionary, nil)
        if status == errSecDuplicateItem { return false }
        guard status == errSecSuccess else { throw PrivateHomeIssue.storageUnavailable }; return true
    }
    func remove(key: String, matchingTag: Data) throws -> Bool {
        guard matchingTag.count == 32 else { throw PrivateHomeIssue.storageUnavailable }
        var request = query(key); request[kSecAttrGeneric as String] = matchingTag
        request[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        let status = SecItemDelete(request as CFDictionary)
        if status == errSecItemNotFound { return false }
        guard status == errSecSuccess else { throw PrivateHomeIssue.storageUnavailable }; return true
    }
}

/// No default primitive: composition must explicitly inject the reviewed system actor.
/// Only encrypted value data contains the private payload. Metadata is an opaque scoped key/tag.
@MainActor final class PrivateHomeKeychainJournal: PrivateHomeSecureJournaling {
    let scope: PrivateHomeJournalScope
    private let key: String
    private let primitive: any PrivateHomeKeychainPrimitive
    private struct Record: Codable {
        let schema: Int
        let namespace: String
        let accountID: Int
        let mutation: PrivateHomeMutation
        let payloadFingerprint: Data
        let generationTag: Data
    }
    init(storageScope: RegionalSessionStorageScope, owner: PlayExperienceSession, primitive: any PrivateHomeKeychainPrimitive) throws {
        guard storageScope.service == owner.namespace else { throw PrivateHomeIssue.storageUnavailable }
        scope = PrivateHomeJournalScope(owner: owner); self.primitive = primitive
        let identity = try JSONEncoder().encode([owner.namespace, String(owner.accountID)])
        key = SHA256.hash(data: identity).map { String(format: "%02x", $0) }.joined()
    }
    private func decode(_ item: PrivateHomeKeychainItem) throws -> PrivateHomeMutation {
        guard item.bytes.count <= 8_192, item.tag.count == 32 else { throw PrivateHomeIssue.storageUnavailable }
        do {
            let record = try JSONDecoder().decode(Record.self, from: item.bytes)
            guard record.schema == 1, record.namespace == scope.namespace, record.accountID == scope.accountID else { throw PrivateHomeIssue.storageUnavailable }
            try record.mutation.validate()
            guard record.generationTag == item.tag, try fingerprint(record.mutation) == record.payloadFingerprint else { throw PrivateHomeIssue.storageUnavailable }
            return record.mutation
        } catch { throw PrivateHomeIssue.storageUnavailable }
    }
    private func fingerprint(_ mutation: PrivateHomeMutation) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return Data(SHA256.hash(data: try encoder.encode(mutation)))
    }
    func read() async throws -> PrivateHomeMutation? {
        guard let item = try await primitive.read(key: key) else { return nil }
        return try decode(item)
    }
    func save(_ mutation: PrivateHomeMutation) async throws {
        try mutation.validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        // Metadata tag is random, never derived from coordinates or their low-entropy fingerprint.
        let tag = Data(SHA256.hash(data: Data((UUID().uuidString + UUID().uuidString).utf8)))
        let data = try encoder.encode(Record(schema: 1, namespace: scope.namespace, accountID: scope.accountID,
            mutation: mutation, payloadFingerprint: fingerprint(mutation), generationTag: tag))
        guard data.count <= 8_192 else { throw PrivateHomeIssue.storageUnavailable }
        let item = PrivateHomeKeychainItem(bytes: data, tag: tag)
        let inserted = try await primitive.insert(key: key, item: item)
        if inserted { return }
        // Another writer owns the slot. Never replace it. Only the same exact request may resume.
        guard let existing = try await primitive.read(key: key) else { throw PrivateHomeIssue.storageUnavailable }
        let stored = try decode(existing)
        guard stored == mutation else { throw PrivateHomeIssue.storageUnavailable }
    }
    func clear(matching mutation: PrivateHomeMutation) async throws {
        guard let item = try await primitive.read(key: key) else { throw PrivateHomeIssue.storageUnavailable }
        let stored = try decode(item)
        guard stored == mutation else { throw PrivateHomeIssue.storageUnavailable }
        // Include immutable random record-generation tag in the OS delete query: a replacement between read/delete survives.
        let removed = try await primitive.remove(key: key, matchingTag: item.tag)
        guard removed else { throw PrivateHomeIssue.storageUnavailable }
    }
}
