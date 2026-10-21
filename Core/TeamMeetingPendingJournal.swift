import Foundation

/// Durable confirm-intent for an already-confirmed team's meeting.
/// Stores owner, namespace, team, meeting, and request only.
/// The live call still uses the existing meetingId/teamId/nonce body; that body is not this file.
/// There is no mapping onto an R9 ticket or challenge.
public enum TeamMeetingIntentPhase: String, Equatable, Sendable {
    case prepared, unknown, confirmed, refused, cancelledBeforeSend
    public var needsLookup: Bool { self == .prepared || self == .unknown }
    /// A refused confirm may use a new request. Every other phase keeps the original request.
    public var blocksNewSend: Bool { self != .refused }
}

public enum TeamMeetingJournalIssue: Error, Equatable {
    case invalid, conflict, saveFailed
}

public struct TeamMeetingOwner: Equatable, Sendable {
    public let accountID: Int
    public let namespace: String
    public init(accountID: Int, namespace: String) throws {
        guard accountID > 0, ReformWire.id(namespace) else { throw TeamMeetingJournalIssue.invalid }
        self.accountID = accountID
        self.namespace = namespace
    }
}

public struct TeamMeetingIntentRecord: Equatable, Sendable {
    public let ownerID: Int
    public let namespace, teamId, meetingId, requestId: String
    public var phase: TeamMeetingIntentPhase
    public var needsLookup: Bool { phase.needsLookup }
    public var blocksNewSend: Bool { phase.blocksNewSend }
}

@MainActor public protocol TeamMeetingPendingWriting: AnyObject {
    func read(_ key: String) throws -> Data?
    func writeAtomic(_ key: String, _ data: Data) throws
    func list() throws -> [String]
}

@MainActor public final class TeamMeetingPendingDirectory: TeamMeetingPendingWriting {
    private let root: URL
    public init(root: URL) { self.root = root }
    private func file(_ key: String) throws -> URL {
        guard TeamMeetingIntentWire.fileKey(key) else { throw TeamMeetingJournalIssue.invalid }
        return root.appendingPathComponent(key + ".intent", isDirectory: false)
    }
    public func read(_ key: String) throws -> Data? {
        let url = try file(key)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isSymbolicLink != true, values.isRegularFile == true, let size = values.fileSize, (1...4_096).contains(size) else { throw TeamMeetingJournalIssue.saveFailed }
        return try Data(contentsOf: url)
    }
    public func writeAtomic(_ key: String, _ data: Data) throws {
        guard (1...4_096).contains(data.count) else { throw TeamMeetingJournalIssue.saveFailed }
        let url = try file(key)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]), values.isSymbolicLink == true { throw TeamMeetingJournalIssue.saveFailed }
        try data.write(to: url, options: .atomic)
        let readBack = try Data(contentsOf: url)
        guard readBack == data else {
            try? FileManager.default.removeItem(at: url)
            throw TeamMeetingJournalIssue.saveFailed
        }
    }
    public func list() throws -> [String] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        let names = try FileManager.default.contentsOfDirectory(atPath: root.path)
        return names.filter { $0.hasSuffix(".intent") }.map { String($0.dropLast(".intent".count)) }
    }
}

@MainActor public final class TeamMeetingPendingJournal {
    private let writer: any TeamMeetingPendingWriting
    public init(writer: any TeamMeetingPendingWriting) { self.writer = writer }
    public convenience init(root: URL) { self.init(writer: TeamMeetingPendingDirectory(root: root)) }
    /// ponytail: check-then-write is single-process. The file replace is atomic; add a lock if two processes share this directory.
    public func prepare(owner: TeamMeetingOwner, teamId: String, meetingId: String, requestId: String) throws -> TeamMeetingIntentRecord {
        guard ReformWire.id(teamId), ReformWire.id(meetingId), ReformWire.requestID(requestId) else { throw TeamMeetingJournalIssue.invalid }
        if let existing = try record(owner: owner, teamId: teamId, meetingId: meetingId) {
            if existing.requestId == requestId, existing.phase == .prepared { return existing }
            if existing.phase == .refused, existing.requestId != requestId {
                return try write(TeamMeetingIntentRecord(ownerID: owner.accountID, namespace: owner.namespace, teamId: teamId, meetingId: meetingId, requestId: requestId, phase: .prepared))
            }
            throw TeamMeetingJournalIssue.conflict
        }
        return try write(TeamMeetingIntentRecord(ownerID: owner.accountID, namespace: owner.namespace, teamId: teamId, meetingId: meetingId, requestId: requestId, phase: .prepared))
    }
    public func markUnknown(owner: TeamMeetingOwner, teamId: String, meetingId: String, requestId: String) throws -> TeamMeetingIntentRecord {
        let existing = try require(owner: owner, teamId: teamId, meetingId: meetingId, requestId: requestId)
        guard existing.phase == .prepared || existing.phase == .unknown else { throw TeamMeetingJournalIssue.conflict }
        var next = existing
        next.phase = .unknown
        return try write(next)
    }
    public func finish(owner: TeamMeetingOwner, teamId: String, meetingId: String, requestId: String, verified: Bool) throws -> TeamMeetingIntentRecord {
        let existing = try require(owner: owner, teamId: teamId, meetingId: meetingId, requestId: requestId)
        guard existing.phase == .unknown || existing.phase == .prepared || existing.phase == (verified ? .confirmed : .refused) else { throw TeamMeetingJournalIssue.conflict }
        var next = existing
        next.phase = verified ? .confirmed : .refused
        return try write(next)
    }
    public func markCancelledBeforeSend(owner: TeamMeetingOwner, teamId: String, meetingId: String, requestId: String) throws -> TeamMeetingIntentRecord {
        let existing = try require(owner: owner, teamId: teamId, meetingId: meetingId, requestId: requestId)
        guard existing.phase == .prepared || existing.phase == .cancelledBeforeSend else { throw TeamMeetingJournalIssue.conflict }
        var next = existing
        next.phase = .cancelledBeforeSend
        return try write(next)
    }
    public func record(owner: TeamMeetingOwner, teamId: String, meetingId: String) throws -> TeamMeetingIntentRecord? {
        guard let data = try writer.read(key(owner: owner, teamId: teamId, meetingId: meetingId)) else { return nil }
        let decoded = try TeamMeetingIntentWire.decode(data)
        guard decoded.ownerID == owner.accountID, decoded.namespace == owner.namespace, decoded.teamId == teamId, decoded.meetingId == meetingId else { throw TeamMeetingJournalIssue.saveFailed }
        return decoded
    }
    /// Non-terminal intent for this owner and team. Other accounts and other teams are invisible.
    public func outstanding(owner: TeamMeetingOwner, teamId: String) -> TeamMeetingIntentRecord? {
        guard let rows = try? list(owner: owner, teamId: teamId) else { return nil }
        return rows.first { $0.phase == .unknown } ?? rows.first { $0.phase == .prepared }
    }
    public func list(owner: TeamMeetingOwner, teamId: String) throws -> [TeamMeetingIntentRecord] {
        guard ReformWire.id(teamId) else { throw TeamMeetingJournalIssue.invalid }
        var rows: [TeamMeetingIntentRecord] = []
        for name in try writer.list() {
            guard let data = try writer.read(name), let decoded = try? TeamMeetingIntentWire.decode(data) else { continue }
            guard decoded.ownerID == owner.accountID, decoded.namespace == owner.namespace, decoded.teamId == teamId else { continue }
            rows.append(decoded)
        }
        return rows
    }
    private func require(owner: TeamMeetingOwner, teamId: String, meetingId: String, requestId: String) throws -> TeamMeetingIntentRecord {
        guard let existing = try record(owner: owner, teamId: teamId, meetingId: meetingId), existing.requestId == requestId else { throw TeamMeetingJournalIssue.conflict }
        return existing
    }
    private func write(_ record: TeamMeetingIntentRecord) throws -> TeamMeetingIntentRecord {
        let data = try TeamMeetingIntentWire.encode(record)
        let storageKey = key(owner: TeamMeetingOwner(accountID: record.ownerID, namespace: record.namespace), teamId: record.teamId, meetingId: record.meetingId)
        try writer.writeAtomic(storageKey, data)
        guard let loaded = try writer.read(storageKey), loaded == data, let decoded = try? TeamMeetingIntentWire.decode(loaded), decoded == record else {
            throw TeamMeetingJournalIssue.saveFailed
        }
        return decoded
    }
    private func key(owner: TeamMeetingOwner, teamId: String, meetingId: String) -> String {
        let raw = "\(owner.accountID)\n\(owner.namespace)\n\(teamId)\n\(meetingId)"
        return Data(raw.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "=", with: "")
    }
}

enum TeamMeetingIntentWire {
    static let fields: Set<String> = ["schema", "ownerID", "namespace", "teamId", "meetingId", "requestId", "phase"]
    static func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }
    static func fileKey(_ key: String) -> Bool {
        key.range(of: "\\A[A-Za-z0-9_-]{1,1024}\\z", options: .regularExpression) != nil
    }
    static func encode(_ record: TeamMeetingIntentRecord) throws -> Data {
        let object: [String: Any] = [
            "schema": "team-meeting-intent-v1",
            "ownerID": record.ownerID,
            "namespace": record.namespace,
            "teamId": record.teamId,
            "meetingId": record.meetingId,
            "requestId": record.requestId,
            "phase": record.phase.rawValue
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let decoded = try decode(data)
        guard decoded == record else { throw TeamMeetingJournalIssue.saveFailed }
        return data
    }
    static func decode(_ data: Data) throws -> TeamMeetingIntentRecord {
        guard (1...4_096).contains(data.count), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], Set(object.keys) == fields else { throw TeamMeetingJournalIssue.saveFailed }
        guard let schema = object["schema"] as? String, schema == "team-meeting-intent-v1",
              let ownerID = integer(object["ownerID"]), ownerID > 0,
              let namespace = object["namespace"] as? String, ReformWire.id(namespace),
              let teamId = object["teamId"] as? String, ReformWire.id(teamId),
              let meetingId = object["meetingId"] as? String, ReformWire.id(meetingId),
              let requestId = object["requestId"] as? String, ReformWire.requestID(requestId),
              let phaseRaw = object["phase"] as? String, let phase = TeamMeetingIntentPhase(rawValue: phaseRaw)
        else { throw TeamMeetingJournalIssue.saveFailed }
        return TeamMeetingIntentRecord(ownerID: ownerID, namespace: namespace, teamId: teamId, meetingId: meetingId, requestId: requestId, phase: phase)
    }
}
