import XCTest
@testable import QuestifyCore

final class GrowthBadgeParityTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }
    private func badges(_ json: String) throws -> [GrowthCenterBadge] { try decode([GrowthCenterBadge].self, json) }

    func testFirstCenterReadNeverCelebratesAndLaterReadsReportOnlyNewCodes() throws {
        var tracker = GrowthBadgeUnlockTracker()
        XCTAssertEqual(tracker.observe(try badges(#"[{"badgeCode":"A","badgeName":"Alpha"}]"#)), [])
        let next = try badges(#"[{"badgeCode":"A","badgeName":"Alpha"},{"badgeCode":"B","badgeName":"Beta"},{"badgeName":"Named only"}]"#)
        XCTAssertEqual(tracker.observe(next).compactMap(\.displayName), ["Beta", "Named only"])
        XCTAssertEqual(tracker.observe(next), [])
    }
    func testResetDropsTheBaselineSoAnotherScopeDoesNotCelebrate() throws {
        var tracker = GrowthBadgeUnlockTracker()
        _ = tracker.observe(try badges(#"[{"badgeCode":"A"}]"#))
        tracker.reset()
        XCTAssertEqual(tracker.observe(try badges(#"[{"badgeCode":"A"},{"badgeCode":"B"}]"#)), [])
    }
    func testBadgeWithoutCodeOrNameIsNeverReportedAsNew() throws {
        var tracker = GrowthBadgeUnlockTracker()
        _ = tracker.observe([])
        XCTAssertEqual(tracker.observe(try badges(#"[{"badgeCode":"  ","badgeName":""}]"#)), [])
    }

    func testPodiumKeepsServerOrderAndOnlyHighlightsARankedViewer() throws {
        let board = try decode(GrowthLeaderboard.self, #"{"metric":"point","period":"total","list":[{"rank":1,"memberId":1,"score":30},{"rank":2,"memberId":2,"score":20},{"rank":3,"memberId":3,"score":10},{"rank":4,"memberId":4,"score":5}],"me":{"rank":4,"memberId":4,"score":5}}"#)
        let podium = GrowthLeaderboardPodium(board: board)
        XCTAssertEqual([podium.first?.memberID, podium.second?.memberID, podium.third?.memberID], [1, 2, 3])
        XCTAssertEqual(podium.rest.map(\.memberID), [4])
        XCTAssertEqual(podium.me?.rank, 4)
        let unranked = try decode(GrowthLeaderboard.self, #"{"metric":"exp","period":"week","list":[{"rank":1,"memberId":9,"score":1}],"me":{"rank":null,"score":0}}"#)
        let short = GrowthLeaderboardPodium(board: unranked)
        XCTAssertNil(short.me); XCTAssertNil(short.second); XCTAssertNil(short.third); XCTAssertEqual(short.rest, [])
        XCTAssertFalse(short.isEmpty)
        let empty = try decode(GrowthLeaderboard.self, #"{"metric":"point","period":"total","list":[],"me":{"rank":null,"score":0}}"#)
        XCTAssertTrue(GrowthLeaderboardPodium(board: empty).isEmpty)
    }

    func testForbiddenGrowthReadIsItsOwnStateNotSignInOrOutage() {
        XCTAssertEqual(GrowthCenterIssue(APIError.httpStatus(403)), .denied)
        XCTAssertEqual(GrowthCenterIssue(GrowthCenterReadFailure.rejected(code: 403, message: "x")), .denied)
        XCTAssertEqual(GrowthCenterIssue(APIError.httpStatus(503)), .unavailable)
        XCTAssertEqual(GrowthCenterIssue(APIError.unauthorized), .login)
        XCTAssertEqual(GrowthCenterIssue.denied.localizationKey, "growth.denied")
    }

    private func wall(identities: String, medals: String?) throws -> ProfileBadgeWall {
        ProfileBadgeWall(identities: try decode([ProfileIdentityBadge].self, identities),
                         medals: try medals.map { try decode([ProfileMedal].self, $0) })
    }
    func testWallSummaryCountsLitIdentitiesAndAllReceivedMedals() throws {
        let value = try wall(identities: #"[{"badgeCode":"A","badgeName":"A","unlocked":true},{"badgeCode":"B","badgeName":"B","unlocked":false}]"#,
                             medals: #"[{"medalName":"City","kind":"city"},{"badgeCode":"W","medalName":"Walker","kind":"achievement"}]"#)
        XCTAssertEqual(ObjectBadgeWallSummary(wall: value), ObjectBadgeWallSummary(wall: value))
        let summary = ObjectBadgeWallSummary(wall: value)
        XCTAssertEqual([summary.unlocked, summary.total, summary.locked], [3, 4, 1])
        let partial = ObjectBadgeWallSummary(wall: try wall(identities: #"[{"badgeCode":"A","unlocked":true}]"#, medals: nil))
        XCTAssertEqual([partial.unlocked, partial.total], [1, 1])
    }
    func testFocusReadbackClaimsOnlyRowsActuallyOnTheWall() throws {
        let value = try wall(identities: #"[{"badgeCode":"LIT","badgeName":"Lit","unlocked":true},{"badgeCode":"DARK","badgeName":"Dark","unlocked":false}]"#,
                             medals: #"[{"badgeCode":"W","medalName":"Walker","kind":"achievement"},{"medalName":"City","kind":"city"}]"#)
        XCTAssertNil(ObjectBadgeWallFocus.resolve(code: nil, wall: value))
        XCTAssertNil(ObjectBadgeWallFocus.resolve(code: " ", wall: value))
        XCTAssertEqual(ObjectBadgeWallFocus.resolve(code: "LIT", wall: value), .unlocked(name: "Lit"))
        XCTAssertEqual(ObjectBadgeWallFocus.resolve(code: "DARK", wall: value), .locked(name: "Dark"))
        XCTAssertEqual(ObjectBadgeWallFocus.resolve(code: "W", wall: value), .unlocked(name: "Walker"))
        XCTAssertEqual(ObjectBadgeWallFocus.resolve(code: "MISSING", wall: value), .notOnWall)
    }

    func testCollectionReadAccessSeparatesLoginDeniedAndRetryableFailures() {
        XCTAssertEqual(CollectionReadAccess(APIError.unauthorized), .login)
        XCTAssertEqual(CollectionReadAccess(APIError.httpStatus(403)), .denied)
        XCTAssertEqual(CollectionReadAccess(APIError.businessCode(403)), .denied)
        XCTAssertNil(CollectionReadAccess(APIError.httpStatus(503)))
        XCTAssertNil(CollectionReadAccess(URLError(.timedOut)))
    }
    @MainActor func testObjectCardDeniedReadIsRecordedAndClearedByTheNextSuccess() async {
        let reader = ObjectCardFixtureReader(), model = ObjectCardCollectionModel()
        reader.denyNext = true
        await model.load(category: .all, reader: reader)
        XCTAssertTrue(model.failed); XCTAssertEqual(model.access, .denied); XCTAssertNil(model.collection)
        await model.load(category: .all, reader: reader)
        XCTAssertFalse(model.failed); XCTAssertNil(model.access); XCTAssertNotNil(model.collection)
        reader.failNext = true
        await model.load(category: .all, reader: reader)
        XCTAssertTrue(model.failed); XCTAssertNil(model.access)
    }

    func testAvatarFallbackPileModeAndCollageSlot() {
        let blankAvatar = GrowthLeaderboardAvatarBadge(nickname: "   ", memberID: 7)
        XCTAssertEqual(blankAvatar.monogram, "匿")
        XCTAssertTrue((0..<6).contains(blankAvatar.paletteIndex))

        let namedAvatar = GrowthLeaderboardAvatarBadge(nickname: "chengyin", memberID: 12)
        XCTAssertEqual(namedAvatar.monogram, "C")

        var mode = ObjectCardPileMode.scatteredPile
        XCTAssertEqual(mode.buttonLabel, "✦ 收拢")
        mode.toggle()
        XCTAssertEqual(mode, .gatheredGrid)
        XCTAssertEqual(mode.buttonLabel, "✦ 散开")
        XCTAssertEqual(mode.toggled(), .scatteredPile)

        let slot0 = StampAlbumCollageSlot(index: 0)
        let slot3 = StampAlbumCollageSlot(index: 3)
        XCTAssertTrue((-4.0...4.0).contains(slot0.rotationDegrees))
        XCTAssertTrue((-4.0...4.0).contains(slot3.rotationDegrees))
        XCTAssertNotEqual(slot0.rotationDegrees, slot3.rotationDegrees)
        XCTAssertEqual(StampAlbumCollageSlot.sourcePageSize, 50)
        XCTAssertEqual(StampAlbumCollageSlot.fixturePageSize, 20)
    }
}
