import Foundation
import CryptoKit

@MainActor public protocol ClubGovernanceIntentStoring: AnyObject {
    var isDurable: Bool { get }
    func contains(_ key: String) throws -> Bool
    func reserve(_ key: String) async throws
}
/// Metadata-only monotonic journal. Neither cancellation, HTTP failure nor relaunch proves
/// rollback. Reconciliation requires independent source-backed evidence; there is no retry API.
@MainActor public final class ClubGovernanceFileIntentStore: ClubGovernanceIntentStoring {
    private let directory: URL
    public let isDurable = true
    public init(directory: URL) { self.directory = directory }
    private func url(_ key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest + ".pending")
    }
    public func contains(_ key: String) throws -> Bool { FileManager.default.fileExists(atPath: url(key).path) }
    public func reserve(_ key: String) async throws {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("pending".utf8).write(to: url(key), options: [.withoutOverwriting])
        } catch { throw ClubGovernanceFailure.outcomeLocked }
    }
}
