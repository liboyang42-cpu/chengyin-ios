import Foundation
import CryptoKit

/// Future-only original wire input. This is neither authority nor a server fingerprint/receipt.
public struct ClubSeriesOriginalRequest: Codable, Equatable {
    public let version: Int
    public let realm: String
    public let accountID: Int
    public let lockKey: String
    public let fields: [String: ClubGovernanceValue]
    public init(realm: String, accountID: Int, lockKey: String, command: ClubGovernanceCommand) throws {
        guard command.operation == .createSeries, !realm.isEmpty, accountID > 0, !lockKey.isEmpty else {
            throw ClubGovernanceFailure.invalidRequest
        }
        version = 1; self.realm = realm; self.accountID = accountID
        self.lockKey = lockKey; fields = command.fields
    }
    fileprivate func validate(key: String, realm: String, accountID: Int) throws {
        guard version == 1, self.realm == realm, self.accountID == accountID, lockKey == key,
              let club = fields["clubId"]?.int, let topic = fields["topicId"]?.int else {
            throw ClubGovernanceFailure.outcomeLocked
        }
        var values = fields; values.removeValue(forKey: "clubId"); values.removeValue(forKey: "topicId")
        // Revalidate only the original wire shape. Do not resolve a default lead, materialize
        // dates, issue authority or turn this historical input into a dispatch command.
        let checked = try ClubGovernanceCommand(operation: .createSeries,
            scope: .init(clubID: club, topicID: topic), values: values)
        guard checked.fields == fields else { throw ClubGovernanceFailure.outcomeLocked }
    }
}

@MainActor public protocol ClubSeriesOriginalRequestStoring: AnyObject {
    func contains(lockKey: String) throws -> Bool
    func reserve(_ request: ClubSeriesOriginalRequest) throws
    func read(lockKey: String, realm: String, accountID: Int) throws -> ClubSeriesOriginalRequest?
}

/// Opt-in, immutable, no overwrite/delete/retry API. Legacy generic pending files are untouched.
@MainActor public final class ClubSeriesOriginalRequestFileStore: ClubSeriesOriginalRequestStoring {
    private let directory: URL
    public init(directory: URL) { self.directory = directory }
    private func url(_ key: String) -> URL {
        let name = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name + ".series-v1.json")
    }
    public func contains(lockKey: String) throws -> Bool {
        FileManager.default.fileExists(atPath: url(lockKey).path)
    }
    public func reserve(_ request: ClubSeriesOriginalRequest) throws {
        try request.validate(key: request.lockKey, realm: request.realm, accountID: request.accountID)
        let data = try JSONEncoder().encode(request)
        guard data.count <= 65_536 else { throw ClubGovernanceFailure.outcomeLocked }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url(request.lockKey), options: [.withoutOverwriting])
        guard try read(lockKey: request.lockKey, realm: request.realm, accountID: request.accountID) == request else {
            throw ClubGovernanceFailure.outcomeLocked
        }
    }
    public func read(lockKey: String, realm: String, accountID: Int) throws -> ClubSeriesOriginalRequest? {
        let file = url(lockKey)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        guard let size = attributes[.size] as? NSNumber, size.intValue <= 65_536 else {
            throw ClubGovernanceFailure.outcomeLocked
        }
        let data = try Data(contentsOf: file)
        guard data.count <= 65_536 else { throw ClubGovernanceFailure.outcomeLocked }
        let request = try JSONDecoder().decode(ClubSeriesOriginalRequest.self, from: data)
        try request.validate(key: lockKey, realm: realm, accountID: accountID)
        return request
    }
}
