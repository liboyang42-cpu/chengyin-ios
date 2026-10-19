import XCTest
@testable import QuestifyCore

final class MyProjectListPresentationTests: XCTestCase {
    private func project(_ json: String) throws -> CreatorContentProject {
        try JSONDecoder().decode(CreatorContentProject.self, from: Data(json.utf8))
    }

    func testLegacyTypeMapsToMiniProgramTabs() {
        XCTAssertEqual(MyProjectTab(legacyType: "club_activity"), .activity)
        XCTAssertEqual(MyProjectTab(legacyType: "template"), .template)
        XCTAssertEqual(MyProjectTab(legacyType: "simple_topic"), .topic)
        XCTAssertEqual(MyProjectTab(legacyType: nil), .topic)
        XCTAssertEqual(MyProjectTab.allCases.map(\.rawValue), ["topic", "activity", "template"])
    }

    func testPendingRowsSortFirstAndStable() throws {
        let rows = try ["running", "pending", "draft", "completed", "rejected", "draft"].enumerated().map { index, state in
            try project(#"{"id":\#(index + 1),"bizType":"topic","state":"\#(state)"}"#)
        }
        XCTAssertEqual(MyProjectListPresentation.sorted(rows).map(\.sourceID), [5, 3, 6, 2, 1, 4])
    }

    func testTabsFilterByBizTypeAndTemplateNeverReusesProjectRows() throws {
        let rows = [try project(#"{"id":1,"bizType":"topic"}"#), try project(#"{"id":2,"bizType":"activity"}"#),
                    try project(#"{"id":3,"bizType":"template"}"#)]
        XCTAssertEqual(MyProjectListPresentation.rows(for: .topic, in: rows).map(\.sourceID), [1])
        XCTAssertEqual(MyProjectListPresentation.rows(for: .activity, in: rows).map(\.sourceID), [2])
        XCTAssertTrue(MyProjectListPresentation.rows(for: .template, in: rows).isEmpty)
    }

    func testRoleIsCoHostOnlyForMerchantActivity() {
        XCTAssertEqual(MyProjectListPresentation.roleKey(bizType: "activity", ownerType: "merchant"), "myProject.role.coHost")
        XCTAssertEqual(MyProjectListPresentation.roleKey(bizType: "topic", ownerType: "merchant"), "myProject.role.host")
        XCTAssertEqual(MyProjectListPresentation.roleKey(bizType: "activity", ownerType: "club"), "myProject.role.host")
    }

    func testWhenTextMatchesMiniProgramFormatting() {
        let f = MyProjectListPresentation.whenText
        XCTAssertEqual(f("2026-08-23 19:20:00", "2026-08-23 21:00:00", true), "8月23日 19:20—21:00")
        XCTAssertEqual(f("2026-08-23T19:20:00", "2026-08-25T21:00:00", true), "8月23日 – 8月25日")
        XCTAssertEqual(f("2026-08-23 00:00:00", "2026-08-23 00:00:00", true), "8月23日 全天")
        XCTAssertEqual(f("2026-08-23 19:20:00", nil, true), "8月23日 19:20")
        XCTAssertEqual(f("2026-08-23 19:20:00", "2026-08-23 21:00:00", false), "Aug 23 19:20—21:00")
        XCTAssertNil(f(nil, "2026-08-23", true))
        XCTAssertNil(f("soon", nil, true))
    }

    func testCardRoutesFollowStateAndEditability() throws {
        XCTAssertEqual(MyProjectListPresentation.card(try project(#"{"id":4,"bizType":"topic","state":"draft"}"#)).route, .topicEditor(4))
        XCTAssertEqual(MyProjectListPresentation.card(try project(#"{"id":4,"bizType":"topic","state":"running"}"#)).route, .projectHome(4))
        XCTAssertEqual(MyProjectListPresentation.card(try project(#"{"id":5,"bizType":"activity","state":"rejected","ownerType":"club"}"#)).route, .activityEditor(5))
        XCTAssertEqual(MyProjectListPresentation.card(try project(#"{"id":5,"bizType":"activity","state":"rejected","ownerType":"merchant"}"#)).route, .activityDetail(5))
        XCTAssertEqual(MyProjectListPresentation.card(try project(#"{"id":5,"bizType":"activity","state":"running"}"#)).route, .activityDetail(5))
    }

    func testRowOperationsMirrorDecorate() throws {
        let online = MyProjectListPresentation.card(try project(#"{"id":1,"bizType":"topic","state":"running","ownerType":"member","acceptStatus":"clubOpen"}"#))
        XCTAssertEqual(online.operations, [.viewApplies, .toggle, .cancel])
        XCTAssertEqual(online.toggleKey, "myProject.op.toggleOff")
        let offline = MyProjectListPresentation.card(try project(#"{"id":1,"bizType":"topic","state":"offline","ownerType":"club"}"#))
        XCTAssertEqual(offline.operations, [.toggle, .delete])
        XCTAssertEqual(offline.toggleKey, "myProject.op.toggleOn")
        let coHost = MyProjectListPresentation.card(try project(#"{"id":2,"bizType":"activity","state":"running","ownerType":"merchant","signupCount":3}"#))
        XCTAssertTrue(coHost.operations.isEmpty)
        let sold = MyProjectListPresentation.card(try project(#"{"id":2,"bizType":"activity","state":"running","ownerType":"club","signupCount":3}"#))
        XCTAssertEqual(sold.operations, [.edit, .toggle, .cancel])
        XCTAssertTrue(MyProjectListPresentation.card(try project(#"{"id":3,"bizType":"topic","state":"draft"}"#)).pending)
    }

    func testEmptyCopyDependsOnTabAndPublishRight() {
        XCTAssertEqual(MyProjectListPresentation.emptyKeys(for: .activity, canPublishActivity: true).detail, "myProject.empty.activityPublish")
        XCTAssertNil(MyProjectListPresentation.emptyKeys(for: .activity, canPublishActivity: false).detail)
        XCTAssertEqual(MyProjectListPresentation.emptyKeys(for: .template, canPublishActivity: false).title, "myProject.empty.template")
    }

    func testEmptyCTAOnlyOffersActivityToPublishers() {
        XCTAssertEqual(MyProjectListPresentation.emptyCTAKey(for: .topic, canPublishActivity: false), "myProject.cta.topic")
        XCTAssertEqual(MyProjectListPresentation.emptyCTAKey(for: .activity, canPublishActivity: true), "myProject.cta.activity")
        XCTAssertNil(MyProjectListPresentation.emptyCTAKey(for: .activity, canPublishActivity: false))
        XCTAssertNil(MyProjectListPresentation.emptyCTAKey(for: .template, canPublishActivity: true))
    }
}
