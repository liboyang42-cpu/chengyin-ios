import Foundation

/// Reform plan v9 §33 / W20.16 and S24: CITY snapshot + ordered deltas. The client
/// de-duplicates event ids, ignores stale or duplicate deltas and asks for a fresh
/// snapshot on any gap, cursor mismatch or season/board change. A long connection is
/// only a hint; ownership, balance, protection and fees remain server facts. The
/// GetCitySnapshot/GetCityDeltas endpoints are proposals, so this performs no I/O.
public enum CityDeltaIssue: Error, Equatable { case invalid }

public struct CityStreamCursor: Equatable, Sendable {
    public let boardId, seasonId, rulesReleaseId: String
    public let boardVersion: Int64
    public let sequence: Int64
    public init(boardId: String, seasonId: String, rulesReleaseId: String, boardVersion: Int64, sequence: Int64) throws {
        guard [boardId, seasonId, rulesReleaseId].allSatisfy(ReformWire.id), ReformWire.version(boardVersion), ReformWire.version(sequence) else { throw CityDeltaIssue.invalid }
        self.boardId = boardId; self.seasonId = seasonId; self.rulesReleaseId = rulesReleaseId; self.boardVersion = boardVersion; self.sequence = sequence
    }
    public init(board: CityReadBoard, sequence: Int64) throws {
        try self.init(boardId: board.boardId, seasonId: board.seasonId, rulesReleaseId: board.rulesReleaseId, boardVersion: board.revision, sequence: sequence)
    }
}

public struct CityDelta: Decodable, Equatable, Sendable {
    public let eventId, boardId, seasonId, aggregate, type: String
    public let sequence: Int64
    public let boardVersion: Int64
    func validate() throws {
        guard [eventId, boardId, seasonId, aggregate].allSatisfy(ReformWire.id), ReformWire.label(type, limit: 64),
              ReformWire.version(sequence), sequence > 0, ReformWire.version(boardVersion) else { throw CityDeltaIssue.invalid }
    }
}

public struct CityDeltaStream: Equatable, Sendable {
    public enum Result: Equatable, Sendable {
        /// Deltas applied in order; caller re-reads affected projections.
        case applied([CityDelta])
        /// Nothing new (duplicates / stale).
        case unchanged
        /// Gap, cursor mismatch, other season/board, or invalid delta: reload the snapshot.
        case snapshotRequired
    }
    public private(set) var cursor: CityStreamCursor
    /// Bounded memory of recently applied event ids.
    private var seen: [String] = []
    private static let seenLimit = 512
    public init(cursor: CityStreamCursor) { self.cursor = cursor }

    /// Accepts a delta page (any order). Applies the contiguous run after the cursor.
    public mutating func ingest(_ page: [CityDelta]) -> Result {
        guard page.count <= 500 else { return .snapshotRequired }
        var fresh: [CityDelta] = []
        for delta in page {
            guard (try? delta.validate()) != nil else { return .snapshotRequired }
            guard delta.boardId == cursor.boardId, delta.seasonId == cursor.seasonId else { return .snapshotRequired }
            if seen.contains(delta.eventId) || delta.sequence <= cursor.sequence { continue }
            if let duplicate = fresh.first(where: { $0.sequence == delta.sequence }) {
                if duplicate.eventId == delta.eventId { continue }
                return .snapshotRequired // two events claim one sequence.
            }
            fresh.append(delta)
        }
        guard !fresh.isEmpty else { return .unchanged }
        fresh.sort { $0.sequence < $1.sequence }
        var expected = cursor.sequence + 1, lastVersion = cursor.boardVersion
        for delta in fresh {
            guard delta.sequence == expected, delta.boardVersion >= lastVersion else { return .snapshotRequired }
            expected += 1; lastVersion = delta.boardVersion
        }
        guard let last = fresh.last, let next = try? CityStreamCursor(boardId: cursor.boardId, seasonId: cursor.seasonId, rulesReleaseId: cursor.rulesReleaseId, boardVersion: lastVersion, sequence: last.sequence) else { return .snapshotRequired }
        cursor = next
        seen.append(contentsOf: fresh.map(\.eventId))
        if seen.count > Self.seenLimit { seen.removeFirst(seen.count - Self.seenLimit) }
        return .applied(fresh)
    }

    /// A newer snapshot replaces the cursor; an older one (late response) is ignored.
    @discardableResult
    public mutating func reset(to snapshot: CityStreamCursor) -> Bool {
        if snapshot.boardId == cursor.boardId, snapshot.seasonId == cursor.seasonId,
           snapshot.sequence < cursor.sequence || (snapshot.sequence == cursor.sequence && snapshot.boardVersion <= cursor.boardVersion) { return false }
        cursor = snapshot; seen.removeAll()
        return true
    }
}
