import XCTest
@testable import QuestifyCore

final class ClubProfileChoiceDraftTests: XCTestCase {
    private func source() -> ClubOperationsDraft {
        var d = ClubOperationsDraft(); d.name = "Club"; d.city = "City"; d.clubType = "兴趣社群"; d.activityPrefs = ["轻社交"]
        d.description = "Keep"; d.logo = "existing-logo"; d.cover = "existing-cover"; d.memberReservedQuota = "4"; d.prioritySignupEnabled = true
        return d
    }
    func testTypeIsStagedAndApplyTouchesOnlyType() throws {
        let d = source(); var editor = ClubProfileChoiceDraft(kind: .type, source: d)
        XCTAssertTrue(editor.selectType("旅行组织")); XCTAssertEqual(d.clubType, "兴趣社群")
        var expected = d; expected.clubType = "旅行组织"; XCTAssertEqual(try editor.applying(to: d), expected)
    }
    func testDirectionLimitRemoveAndReaddPreservesOrder() throws {
        let d = source(); var e = ClubProfileChoiceDraft(kind: .directions, source: d)
        XCTAssertTrue(e.toggleDirection("深度社交")); XCTAssertTrue(e.toggleDirection("RPG体验")); XCTAssertFalse(e.toggleDirection("城市定向"))
        XCTAssertTrue(e.toggleDirection("轻社交")); XCTAssertTrue(e.toggleDirection("城市定向"))
        XCTAssertEqual(e.directions, ["深度社交", "RPG体验", "城市定向"])
        var expected = d; expected.activityPrefs = e.directions; XCTAssertEqual(try e.applying(to: d), expected)
    }
    func testUnknownAndWrongKindChoicesAreRejected() {
        var type = ClubProfileChoiceDraft(kind: .type, source: source()), prefs = ClubProfileChoiceDraft(kind: .directions, source: source())
        XCTAssertFalse(type.selectType("invented")); XCTAssertFalse(type.toggleDirection("轻社交"))
        XCTAssertFalse(prefs.selectType("旅行组织")); XCTAssertFalse(prefs.toggleDirection("invented"))
    }
    func testUnchangedLegacyValuesAreNotNormalized() throws {
        var d = source(); d.clubType = "Legacy"; d.activityPrefs = ["Legacy direction"]
        for kind in [ClubProfileChoiceKind.type, .directions] { XCTAssertEqual(try ClubProfileChoiceDraft(kind: kind, source: d).applying(to: d), d) }
    }
    func testParentDraftChangeRejectsApplication() {
        let d = source(); let e = ClubProfileChoiceDraft(kind: .type, source: d); var current = d; current.name = "Updated elsewhere"
        XCTAssertThrowsError(try e.applying(to: current)) { XCTAssertEqual($0 as? ClubOperationsBlock, .changed) }
    }
    func testAppliedFieldsUseExistingUpdateWireAndOwnerSettingsStayExact() throws {
        let profile = try JSONDecoder().decode(ClubOperationsProfile.self, from: Data(#"{"id":81,"name":"Club","city":"City","clubType":"兴趣社群","activityPrefs":"轻社交","isOwner":true,"prioritySignupEnabled":1,"memberReservedQuota":4}"#.utf8))
        let d = ClubOperationsDraft(profile: profile); var e = ClubProfileChoiceDraft(kind: .directions, source: d); _ = e.toggleDirection("RPG体验")
        let command = ClubOperationsCommand.update(try e.applying(to: d), original: profile)
        let fields = try command.fields(snapshot: .init(target: .club(81), profile: profile), identity: .init(accountID: 701, epoch: 1))
        XCTAssertEqual(command.path, "api/club/update-mine"); XCTAssertEqual(fields["id"] as? Int, 81)
        XCTAssertEqual(fields["activityPrefs"] as? String, "轻社交,RPG体验"); XCTAssertEqual(fields["memberReservedQuota"] as? Int, 4)
        XCTAssertEqual(fields["prioritySignupEnabled"] as? Int, 1); XCTAssertNil(fields["memberDiscountPrice"])
    }
}
