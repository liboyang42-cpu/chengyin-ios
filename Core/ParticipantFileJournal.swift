import Foundation
import CryptoKit
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Participant-only implementation of the existing pending-marker contract.
/// No credentials, contact payload, epoch, or server receipt is persisted.
/// Success means file sync + atomic replacement + directory sync have all returned
/// successfully. Apple uses F_FULLFSYNC as an additional file barrier; unsupported
/// barriers fail closed. This contract still requires Apple filesystem/kill testing.
@MainActor public final class ParticipantFileJournal: OperationPendingJournal {
    enum Checkpoint { case temporaryWritten, fileSynced, renamed, directorySynced }
    private struct Envelope: Codable {
        let version: Int
        let cleared: Bool
        let record: OperationPendingRecord
    }
    private let directory: URL
    private let legacy: (any OperationPendingJournal)?
    private let checkpoint: (Checkpoint) throws -> Void
    public convenience init(directory: URL, legacy: (any OperationPendingJournal)? = nil) {
        self.init(directory: directory, legacy: legacy, checkpoint: { _ in })
    }
    init(directory: URL, legacy: (any OperationPendingJournal)?, checkpoint: @escaping (Checkpoint) throws -> Void) {
        self.directory = directory; self.legacy = legacy; self.checkpoint = checkpoint
    }
    public static func applicationSupport(legacy: (any OperationPendingJournal)? = nil) -> any OperationPendingJournal {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return ParticipantJournalUnavailable()
        }
        return ParticipantFileJournal(directory: base.appendingPathComponent("QuestifyParticipantPending-v1", isDirectory: true), legacy: legacy)
    }
    public func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? {
        try locked {
            let envelope = try loadOrImport(owner: ownerKey, target: targetKey)
            return envelope?.cleared == false ? envelope?.record : nil
        }
    }
    public func write(_ record: OperationPendingRecord) throws {
        try locked {
            try validate(record)
            if let held = try loadOrImport(owner: record.ownerKey, target: record.targetKey), !held.cleared,
               held.record != record { throw APIError.invalidRequest }
            // Repeat the barrier even for the same ID after an uncertain previous write.
            try commit(Envelope(version: 1, cleared: false, record: record))
        }
    }
    public func clear(_ record: OperationPendingRecord) throws {
        try locked {
            try validate(record)
            guard let held = try loadOrImport(owner: record.ownerKey, target: record.targetKey),
                  !held.cleared, held.record == record else { throw APIError.invalidRequest }
            // Durable tombstone, not unlink: a legacy defaults marker must never revive.
            // Only the coordinator's original authoritative completion invokes clear.
            try commit(Envelope(version: 1, cleared: true, record: record))
        }
    }
    private func validate(_ record: OperationPendingRecord) throws {
        guard !record.ownerKey.isEmpty, record.ownerKey.utf8.count <= 8192,
              record.targetKey == "profile.participants", record.acknowledgedSteps == 0 else { throw APIError.invalidRequest }
    }
    private func name(owner: String, target: String) -> String {
        let bytes = Data("\(owner.utf8.count):\(owner):\(target.utf8.count):\(target)".utf8)
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() + ".json"
    }
    private func loadOrImport(owner: String, target: String) throws -> Envelope? {
        guard !owner.isEmpty, owner.utf8.count <= 8192, target == "profile.participants" else { throw APIError.invalidRequest }
        let url = directory.appendingPathComponent(name(owner: owner, target: target))
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW)
        if fd < 0 {
            guard errno == ENOENT else { throw APIError.notConfigured }
            guard let prior = try legacy?.pending(ownerKey: owner, targetKey: target) else { return nil }
            try validate(prior)
            guard prior.ownerKey.utf8.elementsEqual(owner.utf8), prior.targetKey == target else { throw APIError.malformedResponse }
            let imported = Envelope(version: 1, cleared: false, record: prior)
            try commit(imported) // Never trust a legacy cache write as the dispatch barrier.
            return imported
        }
        defer { _ = close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              info.st_size > 0, info.st_size <= 65536 else { throw APIError.malformedResponse }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = buffer.withUnsafeMutableBytes { raw in read(fd, raw.baseAddress, raw.count) }
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw APIError.notConfigured }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
            guard data.count <= 65536 else { throw APIError.malformedResponse }
        }
        let envelope: Envelope
        do { envelope = try JSONDecoder().decode(Envelope.self, from: data) }
        catch { throw APIError.malformedResponse }
        try validate(envelope.record)
        guard envelope.version == 1, envelope.record.ownerKey.utf8.elementsEqual(owner.utf8),
              envelope.record.targetKey == target else { throw APIError.malformedResponse }
        return envelope
    }
    private func locked<T>(_ operation: () throws -> T) throws -> T {
        guard directory.isFileURL else { throw APIError.invalidConfiguration }
        try ensureDirectory(directory)
        let fd = open(directory.appendingPathComponent(".lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, mode_t(0o600))
        guard fd >= 0 else { throw APIError.notConfigured }
        defer { _ = flock(fd, LOCK_UN); _ = close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw APIError.notConfigured }
        return try operation()
    }
    private func ensureDirectory(_ url: URL) throws {
        var info = stat()
        if lstat(url.path, &info) == 0 {
            guard (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) else { throw APIError.notConfigured }
            // A prior mkdir may have succeeded before its parent sync failed.
            // Do not treat an existing directory entry as a completed barrier.
            try syncDirectory(url.deletingLastPathComponent())
            return
        }
        guard errno == ENOENT else { throw APIError.notConfigured }
        let parent = url.deletingLastPathComponent()
        guard parent.path != url.path else { throw APIError.notConfigured }
        try ensureDirectory(parent)
        if mkdir(url.path, mode_t(0o700)) != 0 {
            guard errno == EEXIST else { throw APIError.notConfigured }
            try ensureDirectory(url)
        }
        try syncDirectory(parent)
    }
    private func syncDirectory(_ url: URL) throws {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw APIError.notConfigured }
        defer { _ = close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR), fsync(fd) == 0 else { throw APIError.notConfigured }
    }
    private func commit(_ envelope: Envelope) throws {
        let bytes = try JSONEncoder().encode(envelope)
        guard bytes.count <= 65536 else { throw APIError.invalidRequest }
        let destination = directory.appendingPathComponent(name(owner: envelope.record.ownerKey, target: envelope.record.targetKey))
        let temporary = directory.appendingPathComponent(".pending-" + UUID().uuidString)
        let fd = open(temporary.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, mode_t(0o600))
        guard fd >= 0 else { throw APIError.notConfigured }
        defer { _ = close(fd); _ = unlink(temporary.path) }
        try bytes.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { throw APIError.invalidRequest }
            var written = 0
            while written < raw.count {
                #if canImport(Darwin)
                let count = Darwin.write(fd, base.advanced(by: written), raw.count - written)
                #else
                let count = Glibc.write(fd, base.advanced(by: written), raw.count - written)
                #endif
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw APIError.notConfigured }
                written += count
            }
        }
        try checkpoint(.temporaryWritten)
        guard fsync(fd) == 0 else { throw APIError.notConfigured }
        #if canImport(Darwin)
        guard fcntl(fd, F_FULLFSYNC) == 0 else { throw APIError.notConfigured }
        #endif
        try checkpoint(.fileSynced)
        guard rename(temporary.path, destination.path) == 0 else { throw APIError.notConfigured }
        try checkpoint(.renamed)
        try syncDirectory(directory)
        try checkpoint(.directorySynced)
    }
}
@MainActor private final class ParticipantJournalUnavailable: OperationPendingJournal {
    func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? { throw APIError.notConfigured }
    func write(_ record: OperationPendingRecord) throws { throw APIError.notConfigured }
    func clear(_ record: OperationPendingRecord) throws { throw APIError.notConfigured }
}
