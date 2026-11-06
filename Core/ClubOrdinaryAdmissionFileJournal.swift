import Foundation
import CryptoKit
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Exact original admission marker only. Per-directory flock serializes all cooperating
/// instances/processes; fsync + atomic rename + directory sync precede dispatch.
/// This source pattern still needs actual Apple filesystem/crash/process testing.
@MainActor public final class ClubOrdinaryAdmissionFileJournal: ClubOrdinaryAdmissionJournaling {
    enum Checkpoint { case temporaryWritten, fileSynced, renamed, directorySynced }
    private struct Envelope: Codable {
        let version: Int
        let cleared: Bool
        let record: ClubOrdinaryAdmissionPending
    }
    private let directory: URL
    private let checkpoint: (Checkpoint) throws -> Void
    public convenience init(root: URL, namespace: String) {
        self.init(root: root, namespace: namespace, checkpoint: { _ in })
    }
    init(root: URL, namespace: String, checkpoint: @escaping (Checkpoint) throws -> Void) {
        let hash = SHA256.hash(data: Data(namespace.utf8)).map { String(format: "%02x", $0) }.joined()
        directory = root.appendingPathComponent(hash, isDirectory: true)
        self.checkpoint = checkpoint
    }
    public func pending(accountID: Int, clubID: Int) throws -> ClubOrdinaryAdmissionPending? {
        try locked {
            let stored = try load(accountID: accountID, clubID: clubID)
            return stored?.cleared == false ? stored?.record : nil
        }
    }
    public func reserve(_ value: ClubOrdinaryAdmissionPending) throws {
        try locked {
            try validate(value)
            guard try load(accountID: value.accountID, clubID: value.clubID)?.cleared != false else { throw APIError.invalidRequest }
            try commit(Envelope(version: 1, cleared: false, record: value))
        }
    }
    public func retire(_ value: ClubOrdinaryAdmissionPending) throws {
        try locked {
            try validate(value)
            guard let held = try load(accountID: value.accountID, clubID: value.clubID),
                  !held.cleared, held.record == value else { throw APIError.invalidRequest }
            try commit(Envelope(version: 1, cleared: true, record: value))
        }
    }
    private func validate(_ value: ClubOrdinaryAdmissionPending) throws {
        guard value.accountID > 0, value.clubID > 0, value.payloadSHA256.count == 64,
              value.payloadSHA256.allSatisfy({ "0123456789abcdef".contains($0) }) else { throw APIError.invalidRequest }
    }
    private func name(accountID: Int, clubID: Int) -> String { "\(accountID)-\(clubID).json" }
    private func load(accountID: Int, clubID: Int) throws -> Envelope? {
        guard accountID > 0, clubID > 0 else { throw APIError.invalidRequest }
        let url = directory.appendingPathComponent(name(accountID: accountID, clubID: clubID))
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW)
        if fd < 0 {
            guard errno == ENOENT else { throw APIError.notConfigured }
            return nil
        }
        defer { _ = close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              info.st_size > 0, info.st_size <= 65536 else { throw APIError.malformedResponse }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw APIError.notConfigured }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
            guard data.count <= 65536 else { throw APIError.malformedResponse }
        }
        // Read the acquired older raw marker without changing its identity/proof.
        // Malformed/unknown formats block dispatch instead of being treated as absent.
        let envelope: Envelope
        if let versioned = try? JSONDecoder().decode(Envelope.self, from: data) {
            envelope = versioned
        } else {
            envelope = Envelope(version: 1, cleared: false, record: try JSONDecoder().decode(ClubOrdinaryAdmissionPending.self, from: data))
        }
        try validate(envelope.record)
        guard envelope.version == 1, envelope.record.accountID == accountID,
              envelope.record.clubID == clubID else { throw APIError.malformedResponse }
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
        let destination = directory.appendingPathComponent(name(accountID: envelope.record.accountID, clubID: envelope.record.clubID))
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
