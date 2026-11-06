import Foundation
import CryptoKit

/// No default primitive: composition must explicitly inject the reviewed system actor.
/// Only encrypted value data contains the private payload. Metadata is an opaque scoped key/tag.
@MainActor final class NativeHomeReturnKeychainJournal: NativeHomeReturnSecureJournaling {
    let scope: PrivateHomeJournalScope
    private let key: String
    private let primitive: any PrivateHomeKeychainPrimitive
    private struct Record: Codable {
        let schema: Int
        let namespace: String
        let accountID: Int
        let request: NativeHomeRestoreRequest
        let payloadFingerprint: Data
        let generationTag: Data
    }
    init(storageScope: RegionalSessionStorageScope, owner: PlayExperienceSession, primitive: any PrivateHomeKeychainPrimitive) throws {
        guard storageScope.service == owner.namespace else { throw NativeHomeReturnFailure.storageUnavailable }
        scope = PrivateHomeJournalScope(owner: owner); self.primitive = primitive
        let identity = try JSONEncoder().encode([owner.namespace, String(owner.accountID)])
        key = "home-return.v1:" + SHA256.hash(data: identity).map { String(format: "%02x", $0) }.joined()
    }
    private func decode(_ item: PrivateHomeKeychainItem) throws -> NativeHomeRestoreRequest {
        guard item.bytes.count <= 8_192, item.tag.count == 32 else { throw NativeHomeReturnFailure.storageUnavailable }
        do {
            // Reject ambiguous stored JSON before typed decoding can collapse identity keys.
            // The existing byte cap bounds parsing; retain original bytes for decode and recovery.
            guard let text = String(data: item.bytes, encoding: .utf8),
                  let root = try? ContentDraftJSON.parse(text), case .object = root else { throw NativeHomeReturnFailure.storageUnavailable }
            let record = try JSONDecoder().decode(Record.self, from: item.bytes)
            guard record.schema == 1, record.namespace == scope.namespace, record.accountID == scope.accountID else { throw NativeHomeReturnFailure.storageUnavailable }
            try record.request.validateNative()
            guard record.generationTag == item.tag, try fingerprint(record.request) == record.payloadFingerprint else { throw NativeHomeReturnFailure.storageUnavailable }
            return record.request
        } catch { throw NativeHomeReturnFailure.storageUnavailable }
    }
    private func fingerprint(_ request: NativeHomeRestoreRequest) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return Data(SHA256.hash(data: try encoder.encode(request)))
    }
    func read() async throws -> NativeHomeRestoreRequest? {
        guard let item = try await primitive.read(key: key) else { return nil }
        return try decode(item)
    }
    func save(_ request: NativeHomeRestoreRequest) async throws {
        try request.validateNative()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        // Metadata tag is random, never derived from request body.
        let tag = Data(SHA256.hash(data: Data((UUID().uuidString + UUID().uuidString).utf8)))
        let data = try encoder.encode(Record(schema: 1, namespace: scope.namespace, accountID: scope.accountID,
            request: request, payloadFingerprint: fingerprint(request), generationTag: tag))
        guard data.count <= 8_192 else { throw NativeHomeReturnFailure.storageUnavailable }
        let item = PrivateHomeKeychainItem(bytes: data, tag: tag)
        let inserted = try await primitive.insert(key: key, item: item)
        if inserted { return }
        // Another writer owns the slot. Never replace it. Only the same exact request may resume.
        guard let existing = try await primitive.read(key: key) else { throw NativeHomeReturnFailure.storageUnavailable }
        let stored = try decode(existing)
        guard stored == request else { throw NativeHomeReturnFailure.storageUnavailable }
    }
    func clear(matching request: NativeHomeRestoreRequest) async throws {
        guard let item = try await primitive.read(key: key) else { throw NativeHomeReturnFailure.storageUnavailable }
        let stored = try decode(item)
        guard stored == request else { throw NativeHomeReturnFailure.storageUnavailable }
        // Include immutable random record-generation tag in the OS delete query: a replacement between read/delete survives.
        let removed = try await primitive.remove(key: key, matchingTag: item.tag)
        guard removed else { throw NativeHomeReturnFailure.storageUnavailable }
    }
}
