import XCTest
@testable import QuestifyCore

final class SettingsIdentityApplicationsTests: XCTestCase {
    func testOnlySignedInPlayerViewIsOfferedApplications() {
        XCTAssertTrue(SettingsIdentityApplications.isOffered(toRole: "player"))
        XCTAssertFalse(SettingsIdentityApplications.isOffered(toRole: "merchant"))
        XCTAssertFalse(SettingsIdentityApplications.isOffered(toRole: "club"))
        XCTAssertFalse(SettingsIdentityApplications.isOffered(toRole: nil))
    }
}
