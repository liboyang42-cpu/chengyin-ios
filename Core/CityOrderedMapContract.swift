import Foundation

/// Authorized delivery of actual committed CITY source events. Never a poll/observation counter.
struct CityOrderedMapReply: Decodable {
    let contract, scope, mode, kind, streamId, scopeHash, cursor: String
    let sequence, boardVersion, capturedAtMillis, validUntilMillis: Int64
    let grantsAction, grantsNavigation: Bool
    let snapshot: CityCurrentSnapshot?
    let versions: [String: [String: Int64]]?
    let afterSequence: Int64?
    let batches: [CityOrderedMapBatch]?
}
struct CityOrderedMapBatch: Decodable, Equatable {
    let batchId: String
    let firstSequence, lastSequence: Int64
    let events: [CityOrderedMapEvent]
}
struct CityOrderedMapEvent: Decodable, Equatable {
    let eventId, aggregate, component, type: String
    let sequence, aggregateVersion: Int64
    let point: CityCurrentSnapshot.Point
}

/// Value staging: the caller commits a whole validated reply, never a partial business batch.
struct CityOrderedMapState {
    private(set) var snapshot: CityCurrentSnapshot
    private(set) var versions: [String: [String: Int64]]
    let streamID, scopeHash: String
    private(set) var sequence: Int64
    private var validUntilMillis: Int64
    private var seen: [String: CityOrderedMapEvent] = [:]
    private var batchesSeen: [String: CityOrderedMapBatch] = [:]
    var cursor: String { streamID + "." + String(sequence) }
    private static let maxSafe: Int64 = 9_007_199_254_740_991
    private static let components: Set<String> = ["SLOT", "MERCHANT", "PLATFORM"]

    init(_ reply: CityOrderedMapReply, query: CityCurrentSnapshotQuery) throws {
        try Self.validateHeader(reply, query: query)
        guard reply.kind == "SNAPSHOT", reply.sequence == 0, reply.afterSequence == nil, reply.batches == nil,
              let snapshot = reply.snapshot, (try? snapshot.validate(query, now: reply.capturedAtMillis)) != nil,
              snapshot.capturedAtMillis == reply.capturedAtMillis, let versions = reply.versions else { throw CityOrderedMapFailure.malformed }
        try Self.validateVersions(versions, points: snapshot.points)
        self.snapshot = snapshot; self.versions = versions
        streamID = reply.streamId; scopeHash = reply.scopeHash; sequence = 0; validUntilMillis = reply.validUntilMillis
        try validateDeadline(reply)
    }
    mutating func ingest(_ reply: CityOrderedMapReply, requestedSequence: Int64, query: CityCurrentSnapshotQuery) throws {
        try Self.validateHeader(reply, query: query)
        guard reply.kind == "DELTAS", reply.streamId == streamID, reply.scopeHash == scopeHash,
              reply.afterSequence == requestedSequence, requestedSequence == sequence, reply.capturedAtMillis >= snapshot.capturedAtMillis,
              reply.snapshot == nil, reply.versions == nil, let batches = reply.batches, batches.count <= 500,
              batches.reduce(0, { $0 + $1.events.count }) <= 500 else { throw CityOrderedMapFailure.malformed }
        try validateDeadline(reply)
        var points = Dictionary(uniqueKeysWithValues: snapshot.points.map { ($0.pointId, $0) })
        for batch in batches.sorted(by: { $0.firstSequence < $1.firstSequence }) {
            guard Self.hex(batch.batchId), batch.firstSequence > 0, batch.lastSequence >= batch.firstSequence,
                  batch.lastSequence <= Self.maxSafe, batch.lastSequence - batch.firstSequence < 500,
                  !batch.events.isEmpty else { throw CityOrderedMapFailure.malformed }
            if let prior = batchesSeen[batch.batchId], prior != batch { throw CityOrderedMapFailure.malformed }
            var unique: [Int64: CityOrderedMapEvent] = [:]
            var ids: [String: Int64] = [:]
            for event in batch.events {
                guard Self.hex(event.eventId), event.type == "POINT_REPLACED", Self.components.contains(event.component),
                      (batch.firstSequence...batch.lastSequence).contains(event.sequence),
                      event.aggregate == event.point.pointId, !event.point.grantsAction, !event.point.grantsNavigation,
                      (0...Self.maxSafe).contains(event.aggregateVersion) else { throw CityOrderedMapFailure.malformed }
                if let prior = unique[event.sequence], prior != event { throw CityOrderedMapFailure.malformed }
                if let prior = ids[event.eventId], prior != event.sequence { throw CityOrderedMapFailure.malformed }
                unique[event.sequence] = event; ids[event.eventId] = event.sequence
            }
            guard unique.count == Int(batch.lastSequence - batch.firstSequence + 1) else { throw CityOrderedMapFailure.malformed }
            let events = unique.values.sorted { $0.sequence < $1.sequence }
            if batch.lastSequence <= sequence {
                // Unknown/evicted old IDs are not silently trusted as duplicates.
                guard events.allSatisfy({ seen[$0.eventId] == $0 }) else { throw CityOrderedMapFailure.malformed }
                continue
            }
            guard batch.firstSequence == sequence + 1 else { throw CityOrderedMapFailure.malformed }
            for event in events {
                guard event.sequence == sequence + 1, seen[event.eventId] == nil,
                      let before = points[event.aggregate], Self.samePublicPlace(before, event.point),
                      Self.componentChange(event.component, before: before, after: event.point),
                      let previous = versions[event.aggregate]?[event.component], event.aggregateVersion > previous else { throw CityOrderedMapFailure.malformed }
                if event.component == "MERCHANT", event.point.merchantVersion != event.aggregateVersion { throw CityOrderedMapFailure.malformed }
                if event.component == "PLATFORM", event.point.platformVersion != event.aggregateVersion { throw CityOrderedMapFailure.malformed }
                versions[event.aggregate]?[event.component] = event.aggregateVersion
                points[event.aggregate] = event.point; sequence = event.sequence; seen[event.eventId] = event
            }
            guard sequence == batch.lastSequence else { throw CityOrderedMapFailure.malformed }
            batchesSeen[batch.batchId] = batch
        }
        guard sequence == reply.sequence else { throw CityOrderedMapFailure.malformed }
        let ordered = points.values.sorted { $0.pointId < $1.pointId }
        try Self.validateVersions(versions, points: ordered)
        validUntilMillis = reply.validUntilMillis
        snapshot = snapshot.replacingOrderedPoints(ordered, capturedAtMillis: reply.capturedAtMillis)
        do { try snapshot.validate(query, now: reply.capturedAtMillis) } catch { throw CityOrderedMapFailure.malformed }
        // Memory only. Restart always gets a fresh original snapshot, not this cursor.
        if seen.count > 512 {
            let kept = seen.values.sorted { $0.sequence > $1.sequence }.prefix(512)
            seen = Dictionary(uniqueKeysWithValues: kept.map { ($0.eventId, $0) })
        }
        if batchesSeen.count > 128 {
            let kept = batchesSeen.values.sorted { $0.lastSequence > $1.lastSequence }.prefix(128)
            batchesSeen = Dictionary(uniqueKeysWithValues: kept.map { ($0.batchId, $0) })
        }
    }
    func read(_ reply: CityOrderedMapReply, started: TimeInterval) throws -> CityOrderedMapRead {
        try .init(snapshot: snapshot, requestStartedUptime: started, additionalDeadlineMillis: reply.validUntilMillis)
    }
    private func validateDeadline(_ reply: CityOrderedMapReply) throws {
        guard reply.validUntilMillis <= validUntilMillis else { throw CityOrderedMapFailure.malformed }
        if let permit = snapshot.validUntilMillis, reply.validUntilMillis > permit { throw CityOrderedMapFailure.malformed }
    }
    private static func validateHeader(_ reply: CityOrderedMapReply, query: CityCurrentSnapshotQuery) throws {
        guard reply.contract == "CITY_TRANSACTIONAL_MAP_V1", reply.scope == "CITY", reply.mode == "TRANSACTIONAL_EVENTS_V1",
              UUID(uuidString: reply.streamId)?.uuidString.lowercased() == reply.streamId, hex(reply.scopeHash),
              (0...maxSafe).contains(reply.sequence), reply.cursor == reply.streamId + "." + String(reply.sequence),
              reply.boardVersion == query.revision, !reply.grantsAction, !reply.grantsNavigation,
              (1...maxSafe).contains(reply.capturedAtMillis), reply.validUntilMillis > reply.capturedAtMillis,
              reply.validUntilMillis <= maxSafe else { throw CityOrderedMapFailure.malformed }
    }
    private static func validateVersions(_ versions: [String: [String: Int64]], points: [CityCurrentSnapshot.Point]) throws {
        guard Set(versions.keys) == Set(points.map(\.pointId)), versions.count <= 200 else { throw CityOrderedMapFailure.malformed }
        for point in points {
            guard let values = versions[point.pointId], Set(values.keys).isSubset(of: components), values.values.allSatisfy({ (0...maxSafe).contains($0) }),
                  (values["MERCHANT"] == nil) == (values["PLATFORM"] == nil),
                  (values["MERCHANT"] ?? 0) == point.merchantVersion, (values["PLATFORM"] ?? 0) == point.platformVersion,
                  (values["SLOT"] != nil) == (point.ownership != "NOT_EVALUATED") else { throw CityOrderedMapFailure.malformed }
        }
    }
    private static func hex(_ value: String) -> Bool { value.range(of: "\\A[a-f0-9]{64}\\z", options: .regularExpression) != nil }
    private static func componentChange(_ component: String, before a: CityCurrentSnapshot.Point, after b: CityCurrentSnapshot.Point) -> Bool {
        switch component {
        case "SLOT": return a.availability == b.availability && a.merchantVersion == b.merchantVersion && a.platformVersion == b.platformVersion
        case "MERCHANT": return a.mine == b.mine && a.ownership == b.ownership && a.platformVersion == b.platformVersion
        case "PLATFORM": return a.mine == b.mine && a.ownership == b.ownership && a.merchantVersion == b.merchantVersion
        default: return false
        }
    }
    private static func samePublicPlace(_ a: CityCurrentSnapshot.Point, _ b: CityCurrentSnapshot.Point) -> Bool {
        a.pointId == b.pointId && a.title == b.title && a.latitude == b.latitude && a.longitude == b.longitude &&
        a.datum == b.datum && a.domain == b.domain && a.collectedAt == b.collectedAt && a.coordinateAssurance == b.coordinateAssurance &&
        a.grantsNavigation == b.grantsNavigation && a.grantsAction == b.grantsAction
    }
}
private extension CityCurrentSnapshot {
    func replacingOrderedPoints(_ points: [CityCurrentSnapshot.Point], capturedAtMillis: Int64) -> CityCurrentSnapshot {
        .init(contract: contract, scope: scope, mode: mode, deltaStatus: deltaStatus, deltaReason: deltaReason,
              board: board, boardVersion: boardVersion, membership: membership, participation: participation,
              points: points, mapRead: mapRead, viewport: viewport, datum: datum, zoom: zoom, layers: layers,
              complete: complete, capturedAtMillis: capturedAtMillis, validUntilMillis: validUntilMillis,
              grantsNavigation: grantsNavigation, grantsAction: grantsAction)
    }
}

public enum CityOrderedMapFailure: Error, Equatable { case disabled, staleSession, malformed, expired, unavailable, unauthorized, snapshotChanged, queryTooBroad }
/// Private stream deadline also bounds display; monotonic lifetime cannot be extended by wall-clock rollback.
public struct CityOrderedMapRead {
    public let snapshot: CityCurrentSnapshot
    private let expiresAtUptime: TimeInterval
    private let deadline: Int64
    init(snapshot: CityCurrentSnapshot, requestStartedUptime: TimeInterval, additionalDeadlineMillis: Int64) throws {
        let until = min(snapshot.validUntilMillis ?? additionalDeadlineMillis, additionalDeadlineMillis)
        guard until > snapshot.capturedAtMillis else { throw CityOrderedMapFailure.expired }
        self.snapshot = snapshot; deadline = until
        expiresAtUptime = requestStartedUptime + Double(until - snapshot.capturedAtMillis) / 1000
    }
    public func isFresh() -> Bool { ProcessInfo.processInfo.systemUptime < expiresAtUptime && Date().timeIntervalSince1970 * 1000 < Double(deadline) }
}
