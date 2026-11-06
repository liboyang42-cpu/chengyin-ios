import Foundation
import CryptoKit

/// Deliberately excludes coordinates, tokens, provider samples and grant observation payloads.
public struct PersonalLocationSharePendingRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: String { request.requestKey }
    public let namespace: String
    public let accountId: Int64
    public let request: PersonalLocationShareCreate
    public let choicesDigest: String
    public var serverRequestHash: String?
    public var stopRequested: Bool
    public init(scope: PersonalLocationShareScope, request: PersonalLocationShareCreate) throws {
        namespace = scope.namespace; accountId = scope.accountId; self.request = request
        choicesDigest = try Self.digest(request); serverRequestHash = nil; stopRequested = false
    }
    public func validate(scope: PersonalLocationShareScope) throws {
        guard namespace == scope.namespace, accountId == scope.accountId,
              UUID(uuidString: request.requestKey) != nil, request.recipientId > 0, request.recipientId != accountId,
              choicesDigest == (try Self.digest(request)) else { throw PersonalLocationShareFailure.invalidContract }
    }
    private static func digest(_ request: PersonalLocationShareCreate) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return SHA256.hash(data: try encoder.encode(request)).map { String(format: "%02x", $0) }.joined()
    }
}
@MainActor public protocol PersonalLocationShareJournaling: AnyObject {
    func records(scope: PersonalLocationShareScope) throws -> [PersonalLocationSharePendingRecord]
    func put(_ record: PersonalLocationSharePendingRecord, scope: PersonalLocationShareScope) throws
    func remove(requestKey: String, scope: PersonalLocationShareScope) throws
}
/// Atomic account/realm-scoped metadata only. Corruption fails closed rather than erasing an unknown write.
@MainActor public final class PersonalLocationShareFileJournal: PersonalLocationShareJournaling {
    private let directory: URL
    public init(directory: URL) { self.directory = directory }
    private func file(scope: PersonalLocationShareScope) -> URL {
        let identity = "\(scope.namespace.utf8.count):\(scope.namespace):\(scope.accountId)"
        let name = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name).appendingPathExtension("json")
    }
    public func records(scope: PersonalLocationShareScope) throws -> [PersonalLocationSharePendingRecord] {
        let url = file(scope: scope)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        guard data.count <= 1_048_576 else { throw PersonalLocationShareFailure.journalUnavailable }
        let records = try JSONDecoder().decode([PersonalLocationSharePendingRecord].self, from: data)
        guard Set(records.map(\.id)).count == records.count else { throw PersonalLocationShareFailure.journalUnavailable }
        for record in records { try record.validate(scope: scope) }
        return records
    }
    private func save(_ records: [PersonalLocationSharePendingRecord], scope: PersonalLocationShareScope) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(records.sorted { $0.id < $1.id })
        guard data.count <= 1_048_576 else { throw PersonalLocationShareFailure.journalUnavailable }
        #if os(iOS)
        try data.write(to: file(scope: scope), options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: file(scope: scope), options: .atomic)
        #endif
        var resource = file(scope: scope)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try resource.setResourceValues(values)
    }
    public func put(_ record: PersonalLocationSharePendingRecord, scope: PersonalLocationShareScope) throws {
        try record.validate(scope: scope)
        var values = try records(scope: scope)
        if let old = values.first(where: { $0.id == record.id }) {
            guard old.request == record.request, old.choicesDigest == record.choicesDigest,
                  !old.stopRequested || record.stopRequested,
                  old.serverRequestHash == nil || old.serverRequestHash == record.serverRequestHash else { throw PersonalLocationShareFailure.invalidContract }
        }
        values.removeAll { $0.id == record.id }; values.append(record)
        try save(values, scope: scope)
    }
    public func remove(requestKey: String, scope: PersonalLocationShareScope) throws {
        try save(records(scope: scope).filter { $0.id != requestKey }, scope: scope)
    }
}
