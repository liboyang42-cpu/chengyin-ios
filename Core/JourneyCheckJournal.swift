import Foundation

/// Write-ahead lock stores only check identity, never credentials, dice, narrative or GPS.
/// One key per account/operational-region/session/topic/node prevents relaunch replay.
@MainActor public protocol JourneyCheckJournal {
    func pending(session: PlayExperienceSession, scope: PlaySessionScope, topicID: Int, nodeID: Int) throws -> String?
    func save(checkID: String?, session: PlayExperienceSession, scope: PlaySessionScope, topicID: Int, nodeID: Int) throws
}
@MainActor public final class JourneyStoredCheckJournal: JourneyCheckJournal {
    private let read: (String) throws -> Data?
    private let write: (Data, String) throws -> Void
    public init(read: @escaping (String) throws -> Data?, write: @escaping (Data, String) throws -> Void) {
        self.read = read; self.write = write
    }
    private func key(_ session: PlayExperienceSession, _ scope: PlaySessionScope, _ topicID: Int, _ nodeID: Int) -> String {
        let owner = "\(session.namespace.utf8.count):\(session.namespace):\(session.accountID):\(scope.fields.keys.sorted().joined()):\(scope.id):\(topicID):\(nodeID)"
        return "journey-check.v1." + Data(owner.utf8).base64EncodedString()
    }
    public func pending(session: PlayExperienceSession, scope: PlaySessionScope, topicID: Int, nodeID: Int) throws -> String? {
        guard let data = try read(key(session, scope, topicID, nodeID)) else { return nil }
        let value = try JSONDecoder().decode(String.self, from: data)
        return value.isEmpty ? nil : value
    }
    public func save(checkID: String?, session: PlayExperienceSession, scope: PlaySessionScope, topicID: Int, nodeID: Int) throws {
        try write(JSONEncoder().encode(checkID ?? ""), key(session, scope, topicID, nodeID))
    }
}
@MainActor public final class JourneyMemoryCheckJournal: JourneyCheckJournal {
    private var values: [String: Data] = [:]
    public init() {}
    private lazy var store = JourneyStoredCheckJournal(read: { [weak self] in self?.values[$0] }, write: { [weak self] in self?.values[$1] = $0 })
    public func pending(session: PlayExperienceSession, scope: PlaySessionScope, topicID: Int, nodeID: Int) throws -> String? {
        try store.pending(session: session, scope: scope, topicID: topicID, nodeID: nodeID)
    }
    public func save(checkID: String?, session: PlayExperienceSession, scope: PlaySessionScope, topicID: Int, nodeID: Int) throws {
        try store.save(checkID: checkID, session: session, scope: scope, topicID: topicID, nodeID: nodeID)
    }
}
