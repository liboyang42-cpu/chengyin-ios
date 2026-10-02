import Foundation

public struct PlayPausedRecord: Codable, Equatable {
    public static let maximumSeconds = 7 * 24 * 3600
    public let elapsedSeconds: Int
    public let savedAt: Int64
    public init(elapsedSeconds: Int, savedAt: Int64) throws {
        guard (0...Self.maximumSeconds).contains(elapsedSeconds), savedAt > 0 else { throw APIError.invalidRequest }
        self.elapsedSeconds = elapsedSeconds; self.savedAt = savedAt
    }
    private enum CodingKeys: String, CodingKey { case elapsedSeconds, savedAt }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(elapsedSeconds: c.decode(Int.self, forKey: .elapsedSeconds), savedAt: c.decode(Int64.self, forKey: .savedAt))
    }
    public static func reconcile(local: Self?, remote: PlayPausedRead?) -> Self? {
        guard let remote else { return local } // Read failed: preserve legitimate local snapshot.
        if remote.endedAt > 0, remote.endedAt >= (local?.savedAt ?? 0) { return nil }
        guard let candidate = remote.record else { return local }
        guard let local else { return candidate }
        return candidate.savedAt > local.savedAt ? candidate : local
    }
}
public struct PlayPausedRead: Equatable {
    public let record: PlayPausedRecord?
    public let endedAt: Int64
    public init(record: PlayPausedRecord? = nil, endedAt: Int64 = 0) { self.record = record; self.endedAt = endedAt }
    init(_ raw: PlayWireValue) throws {
        let saved = Int64(raw["savedAt"].tolerantInteger ?? 0)
        if raw["runState"].text?.uppercased() == "ENDED" { self.init(endedAt: max(0, saved)); return }
        if raw["runState"].text?.uppercased() == "PAUSED", let elapsed = raw["elapsedSeconds"].tolerantInteger {
            self.init(record: try? PlayPausedRecord(elapsedSeconds: elapsed, savedAt: saved)); return
        }
        self.init()
    }
}
public struct PlayContinueRun: Equatable, Identifiable {
    public let scope: PlaySessionScope
    public let elapsedSeconds: Int?
    public let title: String?
    public var id: String { scope.fields.keys.first! + ":" + String(scope.id) }
    init?(_ raw: PlayWireValue) {
        let activity = raw["activityId"].tolerantInteger ?? 0, topic = raw["topicId"].tolerantInteger ?? 0
        // Source activity is the run identity even when its topic metadata is also present.
        guard activity > 0 || topic > 0 else { return nil }
        scope = activity > 0 ? .activity(activity) : .topic(topic)
        let elapsed = raw["elapsedSeconds"].tolerantInteger
        elapsedSeconds = elapsed.flatMap { $0 >= 0 ? $0 : nil }; title = raw["title"].text
    }
}
public struct PlayRunClock: Equatable {
    public enum Phase: String { case idle, running, paused, ended }
    public private(set) var phase: Phase = .idle
    public private(set) var elapsedSeconds: Int = 0
    private var anchor: TimeInterval?
    public init() {}
    public mutating func restore(_ record: PlayPausedRecord?) {
        anchor = nil; elapsedSeconds = record?.elapsedSeconds ?? 0; phase = record == nil ? .idle : .paused
    }
    public mutating func start(monotonicNow: TimeInterval) throws {
        guard monotonicNow.isFinite, phase == .idle || phase == .paused else { throw PlayExperienceError.invalidAction }
        anchor = monotonicNow; phase = .running
    }
    public func elapsed(monotonicNow: TimeInterval) -> Int {
        guard let anchor, monotonicNow.isFinite, monotonicNow >= anchor else { return elapsedSeconds }
        let delta = min(Double(PlayPausedRecord.maximumSeconds), monotonicNow - anchor)
        return min(PlayPausedRecord.maximumSeconds, elapsedSeconds + Int(delta))
    }
    public mutating func pause(monotonicNow: TimeInterval, savedAt: Int64) throws -> PlayPausedRecord {
        guard phase == .running else { throw PlayExperienceError.invalidAction }
        let record = try PlayPausedRecord(elapsedSeconds: elapsed(monotonicNow: monotonicNow), savedAt: savedAt)
        elapsedSeconds = record.elapsedSeconds; anchor = nil; phase = .paused; return record
    }
    public mutating func end(monotonicNow: TimeInterval) {
        elapsedSeconds = elapsed(monotonicNow: monotonicNow); anchor = nil; phase = .ended
    }
}
/// No default disk implementation: production must inject reviewed secure storage.
/// Namespace/account/scope are embedded; no token or evidence is persisted.
@MainActor public protocol PlayPausedStorage: AnyObject {
    func read(key: String) throws -> PlayPausedRecord?
    func write(_ record: PlayPausedRecord?, key: String) throws
    func tombstone(key: String) throws -> Int64?
    func writeTombstone(_ savedAt: Int64, key: String) throws
}
@MainActor public final class PlayMemoryPausedStorage: PlayPausedStorage {
    private var records: [String: PlayPausedRecord] = [:]
    private var tombstones: [String: Int64] = [:]
    public init() {}
    public func read(key: String) throws -> PlayPausedRecord? { records[key] }
    public func write(_ record: PlayPausedRecord?, key: String) throws { records[key] = record }
    public func tombstone(key: String) throws -> Int64? { tombstones[key] }
    public func writeTombstone(_ savedAt: Int64, key: String) throws {
        guard savedAt > 0 else { throw APIError.invalidRequest }; tombstones[key] = max(tombstones[key] ?? 0, savedAt)
    }
}
public enum PlayRunStorageKey {
    public static func make(session: PlayExperienceSession, scope: PlaySessionScope) -> String {
        let parts = [session.namespace, String(session.accountID), scope.fields.keys.first!, String(scope.id)]
        return "play.run.v2:" + parts.map { "\($0.utf8.count):\($0)" }.joined()
    }
}
