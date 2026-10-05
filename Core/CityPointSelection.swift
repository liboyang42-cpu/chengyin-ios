import Foundation

/// Ephemeral presentation input issued only from the reader's current safe projection.
/// The read identity changes on every load/cancel and across reader instances. The
/// complete snapshot binds board, season, rules/hash/revision, membership and points.
/// No account credentials, additional source objects or business actions are stored.
public struct CityPointMapContext: Equatable, Sendable {
    public let readID: UUID
    public let snapshot: CityReadSnapshot
    public let points: [CityReadPoint]

    init?(readID: UUID, snapshot: CityReadSnapshot) {
        guard snapshot.board.valid, snapshot.membership != .unavailable,
              (snapshot.membership == .joined && snapshot.participation?.valid == true)
                || (snapshot.membership == .notJoined && snapshot.participation == nil),
              let points = snapshot.points, points.count <= 200,
              Set(points.map(\.pointId)).count == points.count,
              points.allSatisfy({ $0.valid && (!$0.mine || snapshot.membership == .joined) }) else { return nil }
        self.readID = readID; self.snapshot = snapshot; self.points = points
    }
}

/// Selection is only a local display choice. A stale tap cannot select a same-ID
/// replacement or survive a new reader/read, even when the response is identical.
public struct CityPointSelection: Equatable, Sendable, Identifiable {
    public let id = UUID()
    public let pointID: String
    private let context: CityPointMapContext

    public init?(pointID: String, rendered: CityPointMapContext, current: CityPointMapContext?) {
        guard rendered == current, rendered.points.filter({ $0.pointId == pointID }).count == 1 else { return nil }
        self.pointID = pointID; context = rendered
    }

    public func point(in current: CityPointMapContext?) -> CityReadPoint? {
        guard context == current else { return nil }
        return context.points.first { $0.pointId == pointID }
    }
}
