import XCTest
@testable import QuestifyCore

final class CityGameProjectionTests: XCTestCase {
    private func board(_ id: String = "b1", season: String = "s1", rules: String = "rules1") -> CityReadBoard {
        CityReadBoard(gameId: "g1", boardId: id, regionId: "r1", seasonId: season, rulesReleaseId: rules,
            rulesHash: String(repeating: "a", count: 64), lifecycle: "OPEN", title: "Synthetic board", revision: 4)
    }
    private func point(_ id: String = "point1", latitude: Double = 1, mine: Bool = false) -> CityReadPoint {
        CityReadPoint(pointId: id, title: "Synthetic point", latitude: latitude, longitude: 2, mine: mine)
    }
    private func read(board: CityReadBoard? = nil, membership: CityMembership = .joined,
                      participation: CityParticipation? = CityParticipation(participationId: "p1", membershipVersion: 1),
                      points: [CityReadPoint]? = nil) -> CityReadSnapshot {
        CityReadSnapshot(board: board ?? self.board(), membership: membership, participation: participation, points: points ?? [point()])
    }
    private func offer(_ id: String = "service1", fee: Int64 = 0) -> CityServiceOffer {
        CityServiceOffer(serviceId: id, title: "Synthetic service", memberPointsFee: fee)
    }
    private func property(_ id: String = "property1", version: Int64 = 7, services: [CityServiceOffer] = []) -> CityPropertyState {
        CityPropertyState(propertyId: id, pointId: "point1", role: .operable, status: .held, stateVersion: version,
            heldByMyTeam: false, protectedUntilMillis: nil, services: services, challenge: nil, taskAttemptKept: false)
    }
    private func snapshot(board: String = "b1", season: String = "s1", rules: String = "rules1", version: Int64 = 5,
                          sequence: Int64 = 9, properties: [CityPropertyState]? = nil, round: Int64? = 1) -> CityGameSnapshot {
        CityGameSnapshot(contract: "CITY_GAME_SNAPSHOT_V1", scope: "CITY", boardId: board, seasonId: season,
            boardVersion: version, sequence: sequence, lifecycle: .open, roundSeq: round,
            rules: CityRulesSummary(rulesReleaseId: rules, ruleVersion: "synthetic", validFromMillis: 1, validUntilMillis: nil,
                actionsRemaining: 1, actionsPerRound: 2, holdingLimit: 3), properties: properties ?? [property()],
            memberPoints: nil, neutralTasksAvailable: true)
    }

    func testCurrentCompleteReadAndSelectionAreAccepted() throws {
        let target = property(services: [offer()]), value = snapshot(properties: [target])
        try value.validate(against: read())
        XCTAssertTrue(value.contains(target))
        XCTAssertTrue(value.offers(offer(), on: target))
    }

    func testUnavailableMembershipAndMissingParticipationAreRejected() {
        XCTAssertThrowsError(try snapshot().validate(against: read(membership: .unavailable)))
        XCTAssertThrowsError(try snapshot().validate(against: read(participation: nil)))
        XCTAssertThrowsError(try snapshot(round: nil).validate(against: read(membership: .notJoined)))
    }

    func testInvalidBoardOrParticipationIsRejected() {
        XCTAssertThrowsError(try snapshot().validate(against: read(board: board("invalid/board"))))
        XCTAssertThrowsError(try snapshot().validate(against: read(participation: CityParticipation(participationId: "bad/id", membershipVersion: 1))))
    }

    func testUnavailablePointProjectionCannotValidateEvenAnEmptyBoard() {
        let missing = CityReadSnapshot(board: board(), membership: .joined, participation: read().participation, points: nil)
        XCTAssertThrowsError(try snapshot(properties: []).validate(against: missing))
    }

    func testDuplicateInvalidOrOversizedPointProjectionIsRejected() {
        XCTAssertThrowsError(try snapshot().validate(against: read(points: [point(), point()])))
        XCTAssertThrowsError(try snapshot().validate(against: read(points: [point(latitude: .nan)])))
        XCTAssertThrowsError(try snapshot().validate(against: read(points: (0...200).map { point("point\($0)") })))
    }

    func testNotJoinedReadCannotCarryMinePointFacts() throws {
        let guest = read(membership: .notJoined, participation: nil, points: [point(mine: true)])
        XCTAssertThrowsError(try snapshot(round: nil).validate(against: guest))
        try snapshot(round: nil).validate(against: read(membership: .notJoined, participation: nil))
    }

    func testUnknownAndStalePropertyVersionsAreRejectedAsSelections() {
        let current = property(version: 8), value = snapshot(properties: [current])
        XCTAssertFalse(value.contains(property("other")))
        XCTAssertFalse(value.contains(property(version: 7)))
        XCTAssertTrue(value.contains(current))
    }

    func testUnpublishedAndChangedServiceFeesAreRejectedAsSelections() {
        let current = property(services: [offer(fee: 2)]), value = snapshot(properties: [current])
        XCTAssertFalse(value.offers(offer("unpublished"), on: current))
        XCTAssertFalse(value.offers(offer(fee: 1), on: current))
        XCTAssertTrue(value.offers(offer(fee: 2), on: current))
        // A stale property cannot smuggle its own service collection into the current board.
        let stale = property(version: 6, services: [offer(fee: 1)])
        XCTAssertFalse(value.offers(offer(fee: 1), on: stale))
    }

    func testVersionOrSequenceRegressionIsRejected() {
        XCTAssertThrowsError(try snapshot(version: 4).validate(against: read(), previous: snapshot()))
        XCTAssertThrowsError(try snapshot(sequence: 8).validate(against: read(), previous: snapshot()))
    }

    func testWatermarkCannotBeReusedAcrossBoardsSeasonsOrRules() {
        XCTAssertThrowsError(try snapshot().validate(against: read(), previous: snapshot(board: "other")))
        XCTAssertThrowsError(try snapshot().validate(against: read(), previous: snapshot(season: "other")))
        XCTAssertThrowsError(try snapshot().validate(against: read(), previous: snapshot(rules: "other")))
    }

    func testEqualAndAdvancingWatermarksAreAccepted() throws {
        let previous = snapshot()
        try previous.validate(against: read(), previous: previous)
        try snapshot(version: 6, sequence: 10).validate(against: read(), previous: previous)
    }
}
