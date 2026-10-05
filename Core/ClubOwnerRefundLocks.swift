import Foundation
import CryptoKit

@MainActor public protocol ClubOwnerRefundLocking: AnyObject {
    func contains(_ key: String) throws -> Bool
    func acquire(_ key: String) throws
}
/// Durable metadata-only lock. Same-account relogin, reopening and relaunch cannot replay.
/// No names, tokens, reasons, amounts, receipt details or raw IDs are written to disk.
@MainActor public final class ClubOwnerRefundFileLocks: ClubOwnerRefundLocking {
    private let directory: URL?
    public init(directory: URL?) { self.directory = directory }
    private func url(_ key: String) throws -> URL {
        guard let directory else { throw ClubOwnerRefundFailure.storage }
        let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hash + ".pending")
    }
    public func contains(_ key: String) throws -> Bool { FileManager.default.fileExists(atPath: try url(key).path) }
    public func acquire(_ key: String) throws {
        let path = try url(key)
        do {
            try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            // Exclusive creation also treats any partial/corrupt existing file as locked.
            try Data("pending".utf8).write(to: path, options: [.withoutOverwriting])
        } catch { throw ClubOwnerRefundFailure.storage }
    }

}
