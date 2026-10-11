import XCTest
@testable import QuestifyCore

final class ReducedMotionPreferenceTests: XCTestCase {
    func testDefaultPreferenceFollowsBothSystemStates() {
        XCTAssertFalse(ReducedMotionPreference.defaultValue)
        XCTAssertFalse(ReducedMotionPreference.effective(system: false, local: ReducedMotionPreference.defaultValue))
        XCTAssertTrue(ReducedMotionPreference.effective(system: true, local: ReducedMotionPreference.defaultValue))
    }
    func testLocalPreferenceReducesWithEitherSystemState() {
        XCTAssertTrue(ReducedMotionPreference.effective(system: false, local: true))
        XCTAssertTrue(ReducedMotionPreference.effective(system: true, local: true))
    }
    func testTurningLocalPreferenceOffNeverOverridesSystem() {
        for system in [false, true] {
            XCTAssertTrue(ReducedMotionPreference.effective(system: system, local: true))
            XCTAssertEqual(ReducedMotionPreference.effective(system: system, local: false), system)
        }
    }
}
