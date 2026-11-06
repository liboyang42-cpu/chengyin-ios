import XCTest
@testable import QuestifyCore

final class BackendRolloutAllowlistSwitchboardContractTests: XCTestCase {
    func testAllSixCanonicalSwitchesPassSwitchboardReadiness() {
        let result = BackendRolloutAllowlistSwitchboardContract.evaluate()
        XCTAssertEqual(BackendRolloutAllowlistSwitchboardContract.canonicalSwitches.count, 6)
        XCTAssertEqual(result.totalSwitches, 6)
        XCTAssertEqual(result.safeSwitches, 6)
        XCTAssertTrue(result.allDefaultFailClosed)
        XCTAssertTrue(result.isSwitchboardReady)
    }

    func testAccidentalDefaultTrueSwitchIsRejected() {
        var switches = BackendRolloutAllowlistSwitchboardContract.canonicalSwitches
        switches[0] = RolloutSwitchDescriptor(
            id: "switch-auth-sms-send",
            switchName: "SMS Verification Send Gate (BK-AUTH-01)",
            defaultsToFailClosedFalse: false,
            hasDeterministicDisabledFallbackCopy: true,
            prerequisiteSignoffTicket: "SIGNOFF-BK-AUTH-01-SMS"
        )

        let result = BackendRolloutAllowlistSwitchboardContract.evaluate(switches: switches)
        XCTAssertFalse(switches[0].isSafeForRelease)
        XCTAssertEqual(result.totalSwitches, 6)
        XCTAssertEqual(result.safeSwitches, 5)
        XCTAssertFalse(result.allDefaultFailClosed)
        XCTAssertFalse(result.isSwitchboardReady)
    }

    func testMissingDeterministicFallbackCopyRejectsSwitchSafety() {
        var switches = BackendRolloutAllowlistSwitchboardContract.canonicalSwitches
        switches[3] = RolloutSwitchDescriptor(
            id: "switch-square-topic-like-write",
            switchName: "Square & Topic Like/Unlike Write Gate (BK-SOC-01 / BK-TOP-01)",
            defaultsToFailClosedFalse: true,
            hasDeterministicDisabledFallbackCopy: false,
            prerequisiteSignoffTicket: "SIGNOFF-BK-SOC-TOP-01-LIKE"
        )

        let result = BackendRolloutAllowlistSwitchboardContract.evaluate(switches: switches)
        XCTAssertFalse(switches[3].isSafeForRelease)
        XCTAssertEqual(result.totalSwitches, 6)
        XCTAssertEqual(result.safeSwitches, 5)
        XCTAssertTrue(result.allDefaultFailClosed)
        XCTAssertFalse(result.isSwitchboardReady)
    }

    func testEmptyPrerequisiteSignoffTicketRejectsSwitchSafety() {
        var switches = BackendRolloutAllowlistSwitchboardContract.canonicalSwitches
        switches[5] = RolloutSwitchDescriptor(
            id: "switch-asset-withdrawal-apply",
            switchName: "Wallet Asset Withdrawal Apply Gate (BK-ASSET-01)",
            defaultsToFailClosedFalse: true,
            hasDeterministicDisabledFallbackCopy: true,
            prerequisiteSignoffTicket: "   "
        )

        let result = BackendRolloutAllowlistSwitchboardContract.evaluate(switches: switches)
        XCTAssertFalse(switches[5].isSafeForRelease)
        XCTAssertEqual(result.totalSwitches, 6)
        XCTAssertEqual(result.safeSwitches, 5)
        XCTAssertTrue(result.allDefaultFailClosed)
        XCTAssertFalse(result.isSwitchboardReady)
    }
}
