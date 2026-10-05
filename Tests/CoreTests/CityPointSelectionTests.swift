import XCTest
@testable import QuestifyCore

final class CityPointSelectionTests: XCTestCase {
    private func point(_ id: String = "point-a", title: String = "Same location", latitude: Double = 31, mine: Bool = false) -> CityReadPoint {
        .init(pointId: id, title: title, latitude: latitude, longitude: 121, mine: mine)
    }
    private func snapshot(gameID: String = "game-a", boardID: String = "board-a", region: String = "city-a", title: String = "Official city", season: String = "season-a", release: String = "release-a",
                          hash: String = String(repeating: "a", count: 64), revision: Int64 = 1,
                          lifecycle: String = "OPEN", membership: CityMembership = .joined,
                          participationID: String = "participation-a", membershipVersion: Int64 = 1,
                          points: [CityReadPoint]? = nil) -> CityReadSnapshot {
        .init(board: .init(gameId: gameID, boardId: boardID, regionId: region, seasonId: season,
                          rulesReleaseId: release, rulesHash: hash, lifecycle: lifecycle, title: title, revision: revision),
              membership: membership,
              participation: membership == .joined ? .init(participationId: participationID, membershipVersion: membershipVersion) : nil,
              points: points)
    }
    private func context(_ snapshot: CityReadSnapshot, readID: UUID = UUID()) throws -> CityPointMapContext {
        try XCTUnwrap(CityPointMapContext(readID: readID, snapshot: snapshot))
    }
    func testSameNameAndCoincidentCoordinatesRequireExactCanonicalID() throws {
        let a = point(), b = point("point-b", mine: true), current = try context(snapshot(points: [a, b]))
        let selection = try XCTUnwrap(CityPointSelection(pointID: b.pointId, rendered: current, current: current))
        XCTAssertEqual(selection.point(in: current), b)
        XCTAssertNotEqual(selection.point(in: current), a)
        XCTAssertEqual(selection.pointID, "point-b")
        XCTAssertNil(CityPointSelection(pointID: "Same location", rendered: current, current: current))
        XCTAssertNil(CityPointSelection(pointID: "POINT-B", rendered: current, current: current))
        XCTAssertNil(CityPointSelection(pointID: "missing", rendered: current, current: current))
        XCTAssertNil(CityPointSelection(pointID: "", rendered: current, current: current))
    }
    func testExactSnapshotAndEveryBoardMembershipRevisionFieldFenceSelection() throws {
        let points = [point()], original = try context(snapshot(points: points))
        let selection = try XCTUnwrap(CityPointSelection(pointID: "point-a", rendered: original, current: original))
        let variants = [snapshot(gameID: "game-b", points: points), snapshot(region: "city-b", points: points),
                        snapshot(title: "Updated title", points: points), snapshot(boardID: "board-b", points: points), snapshot(season: "season-b", points: points),
                        snapshot(release: "release-b", points: points), snapshot(hash: String(repeating: "b", count: 64), points: points),
                        snapshot(revision: 2, points: points), snapshot(lifecycle: "FROZEN", points: points),
                        snapshot(membership: .notJoined, points: points), snapshot(participationID: "participation-b", points: points),
                        snapshot(membershipVersion: 2, points: points)]
        for variant in variants {
            let changed = try context(variant, readID: original.readID)
            XCTAssertNil(selection.point(in: changed))
            XCTAssertNil(CityPointSelection(pointID: "point-a", rendered: original, current: changed))
        }
    }
    func testReplacingRemovingOrReorderingProjectionRejectsOldTapAndCard() throws {
        let a = point(), b = point("point-b"), original = try context(snapshot(points: [a, b]))
        let selection = try XCTUnwrap(CityPointSelection(pointID: a.pointId, rendered: original, current: original))
        for points in [[point(title: "Changed title"), b], [point(latitude: 32), b], [point(mine: true), b], [b], [], [b, a]] {
            let changed = try context(snapshot(points: points), readID: original.readID)
            XCTAssertNil(selection.point(in: changed))
            XCTAssertNil(CityPointSelection(pointID: a.pointId, rendered: original, current: changed))
        }
    }
    func testNewReadOrReaderRejectsIdenticalProjectionAndSameID() throws {
        let value = snapshot(points: [point()]), original = try context(value), refreshed = try context(value)
        let selection = try XCTUnwrap(CityPointSelection(pointID: "point-a", rendered: original, current: original))
        XCTAssertNotEqual(original.readID, refreshed.readID)
        XCTAssertNil(selection.point(in: refreshed))
        XCTAssertNil(CityPointSelection(pointID: "point-a", rendered: original, current: refreshed))
        XCTAssertNotNil(CityPointSelection(pointID: "point-a", rendered: refreshed, current: refreshed))
    }
    func testUnavailableAndVerifiedEmptyAreNeverFabricatedSelections() throws {
        XCTAssertNil(CityPointMapContext(readID: UUID(), snapshot: snapshot(points: nil)))
        XCTAssertNil(CityPointMapContext(readID: UUID(), snapshot: snapshot(membership: .unavailable, points: [point()])))
        let empty = try context(snapshot(points: []))
        XCTAssertEqual(empty.points, [])
        XCTAssertNil(CityPointSelection(pointID: "point-a", rendered: empty, current: empty))
        let original = try context(snapshot(points: [point()]))
        let selection = try XCTUnwrap(CityPointSelection(pointID: "point-a", rendered: original, current: original))
        XCTAssertNil(selection.point(in: nil))
        XCTAssertNil(CityPointSelection(pointID: "point-a", rendered: original, current: nil))
    }
    func testDuplicateInvalidOversizedAndUnverifiedOwnStatusProjectionsFailClosed() {
        for points in [[point(), point()], [point("")], [point(latitude: .nan)], [point(latitude: 91)],
                       (0...200).map { point("point-\($0)") }] {
            XCTAssertNil(CityPointMapContext(readID: UUID(), snapshot: snapshot(points: points)))
        }
        XCTAssertNil(CityPointMapContext(readID: UUID(), snapshot: snapshot(membership: .notJoined, points: [point(mine: true)])))
        XCTAssertNil(CityPointMapContext(readID: UUID(), snapshot: snapshot(revision: -1, points: [point()])))
        XCTAssertNil(CityPointMapContext(readID: UUID(), snapshot: snapshot(membershipVersion: -1, points: [point()])))
    }
    func testReselectingSamePointHasNewDismissalIdentity() throws {
        let current = try context(snapshot(points: [point()]))
        let first = try XCTUnwrap(CityPointSelection(pointID: "point-a", rendered: current, current: current))
        let next = try XCTUnwrap(CityPointSelection(pointID: "point-a", rendered: current, current: current))
        XCTAssertNotEqual(first.id, next.id)
        XCTAssertNotEqual(first, next)
        XCTAssertEqual(first.point(in: current), next.point(in: current))
    }
    func testDensityCountsOnlySuppliedCanonicalPointsWithoutCollapsingIdentity() throws {
        let current = try context(snapshot(points: [point(), point("point-b"), point("point-c")]))
        let grouped = MapMarkerDensity.groups(current.points.prefix(2).map { .init(id: $0.pointId, x: 12, y: 12) }, diameter: 72)
        XCTAssertEqual(grouped, [["point-a", "point-b"]])
        XCTAssertFalse(grouped.flatMap { $0 }.contains("point-c"))
        for id in try XCTUnwrap(grouped.first) {
            XCTAssertEqual(CityPointSelection(pointID: id, rendered: current, current: current)?.point(in: current)?.pointId, id)
        }
    }
}
