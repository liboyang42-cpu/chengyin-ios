import Foundation

/// The original journal owner hash and record bytes are unchanged. The production
/// composition supplies protected device-only storage; there is no plaintext fallback.
@MainActor final class NativeChannelProgressSecureJournalStorage: NativeChannelProgressJournalStorage {
    private let storage: any ProjectEditDataStorage
    init(storage: any ProjectEditDataStorage) { self.storage = storage }
    func read(_ key: String) throws -> Data? { try storage.read(key) }
    func write(_ data: Data, key: String) throws { try storage.write(data, key: key) }
    func remove(_ key: String) throws { try storage.remove(key) }
}
