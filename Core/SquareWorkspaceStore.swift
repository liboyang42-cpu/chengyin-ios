import Foundation

/// Host must inject protected storage (Keychain or data-protected equivalent), never UserDefaults.
@MainActor public protocol SquareWorkspacePrivateStorage: AnyObject {
    func read(key: String) throws -> Data?
    func write(_ data: Data, key: String) throws
}
public struct SquareWorkspaceLocalEntry: Codable, Equatable, Identifiable {
    public var id: String { draft.workflowID }
    public var draft: SquareWorkspaceDraft
    public var lane: SquareWorkspaceLane
    public var pending: Bool
    public var receipt: String?
    public var updatedAt: Date
}
private struct SquareWorkspaceLocalEnvelope: Codable {
    let version: Int
    let ownerKey: String
    var entries: [SquareWorkspaceLocalEntry]
}
@MainActor public final class SquareWorkspaceStore {
    private let storage: any SquareWorkspacePrivateStorage
    public init(storage: any SquareWorkspacePrivateStorage) { self.storage = storage }
    private func key(_ session: SquareWorkspaceSession) -> String { "square.workspace.v1." + Data(session.ownerKey.utf8).base64EncodedString() }
    public func entries(session: SquareWorkspaceSession) throws -> [SquareWorkspaceLocalEntry] {
        guard let data = try storage.read(key: key(session)) else { return [] }
        let envelope = try JSONDecoder().decode(SquareWorkspaceLocalEnvelope.self, from: data)
        guard envelope.version == 1, envelope.ownerKey == session.ownerKey else { throw SquareWorkspaceFailure.sessionChanged }
        return envelope.entries
    }
    public func save(_ entry: SquareWorkspaceLocalEntry, session: SquareWorkspaceSession) throws {
        var all = try entries(session: session); all.removeAll { $0.id == entry.id }; all.append(entry)
        try storage.write(JSONEncoder().encode(SquareWorkspaceLocalEnvelope(version: 1, ownerKey: session.ownerKey, entries: all)), key: key(session))
    }
    public func discard(workflowID: String, session: SquareWorkspaceSession) throws {
        var all = try entries(session: session)
        guard !all.contains(where: { $0.id == workflowID && $0.pending }) else { throw SquareWorkspaceFailure.pending }
        all.removeAll { $0.id == workflowID }
        try storage.write(JSONEncoder().encode(SquareWorkspaceLocalEnvelope(version: 1, ownerKey: session.ownerKey, entries: all)), key: key(session))
    }
}
/// Explicitly synthetic, volatile storage. Production host must not use this as durable storage.
@MainActor public final class SquareWorkspaceMemoryStorage: SquareWorkspacePrivateStorage {
    private var values: [String: Data] = [:]
    public init() {}
    public func read(key: String) throws -> Data? { values[key] }
    public func write(_ data: Data, key: String) throws { values[key] = data }
}
