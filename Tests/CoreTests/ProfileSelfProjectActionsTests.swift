import XCTest
@testable import QuestifyCore

/// F14b: the visible "更多" menu and the long-press menu share one action list.
final class ProfileSelfProjectActionsTests: XCTestCase {
    private func row(_ extra: String = "") throws -> CreatorContentProject {
        try JSONDecoder().decode(CreatorContentProject.self, from: Data((#"{"id":7,"bizType":"topic","title":"示例站点","ownerType":"member""# + extra + "}").utf8))
    }
    func testDecodesFreeExploreAndLifecycleTolerantly() throws {
        let plain = try row()
        XCTAssertFalse(plain.freeExplore); XCTAssertNil(plain.lifecycle)
        let flagged = try row(#","freeExplore":true,"lifecycle":2"#)
        XCTAssertTrue(flagged.freeExplore); XCTAssertEqual(flagged.lifecycle, 2)
        let numeric = try row(#","freeExplore":1,"lifecycle":"1""#)
        XCTAssertTrue(numeric.freeExplore); XCTAssertEqual(numeric.lifecycle, 1)
    }
    func testEditForFreeExploreRecruitingOrAwaitingPriceOnly() throws {
        for lifecycle in [1, 2] {
            XCTAssertEqual(ProfileSelfProjectActions.actions(for: try row(#","freeExplore":true,"lifecycle":\#(lifecycle)"#), editingAvailable: true), [.open, .edit])
        }
        for lifecycle in [0, 3, 7] {
            XCTAssertEqual(ProfileSelfProjectActions.actions(for: try row(#","freeExplore":true,"lifecycle":\#(lifecycle)"#), editingAvailable: true), [.open])
        }
        XCTAssertEqual(ProfileSelfProjectActions.actions(for: try row(#","freeExplore":false,"lifecycle":1"#), editingAvailable: true), [.open])
        XCTAssertEqual(ProfileSelfProjectActions.actions(for: try row(#","state":"draft""#), editingAvailable: true), [.open, .edit])
    }
    func testNoEditorOrClubOwnerMeansNoEditAction() throws {
        let candidate = try row(#","freeExplore":true,"lifecycle":2"#)
        XCTAssertEqual(ProfileSelfProjectActions.actions(for: candidate, editingAvailable: false), [.open])
        let club = try JSONDecoder().decode(CreatorContentProject.self, from: Data(#"{"id":8,"bizType":"topic","ownerType":"club","freeExplore":true,"lifecycle":2}"#.utf8))
        XCTAssertFalse(ProfileSelfProjectActions.canEdit(club))
    }
    func testActionTitles() {
        XCTAssertEqual(ProfileSelfProjectAction.edit.title(zh: true), "编辑")
        XCTAssertEqual(ProfileSelfProjectAction.open.title(zh: true), "查看")
    }
}
