import XCTest
@testable import QuestifyCore

final class NonCashRewardTests: XCTestCase {
    private func reward(_ state: NonCashReward.State = .awarded, quantity: Int = 1,
                        from: Double = 100, until: Double = 200, conditions: String = "Store only") -> NonCashReward {
        NonCashReward(awardId: "test", contextType: .map, contextId: "map", releaseId: "release", instanceId: "season",
                      rulesVersion: "1", merchantId: "merchant", storeId: "store", rewardTitle: "Item", quantity: quantity,
                      validFrom: Date(timeIntervalSince1970: from), validUntil: Date(timeIntervalSince1970: until),
                      redemptionConditions: conditions, state: state, awardedAt: Date(timeIntervalSince1970: 90),
                      asOf: Date(timeIntervalSince1970: 100))
    }
    func testExactExpiryAndNotYetValidAreNeverPresentable() {
        XCTAssertFalse(reward().canPresent(at: Date(timeIntervalSince1970: 99)))
        XCTAssertTrue(reward().canPresent(at: Date(timeIntervalSince1970: 100)))
        XCTAssertTrue(reward().canPresent(at: Date(timeIntervalSince1970: 199)))
        XCTAssertFalse(reward().canPresent(at: Date(timeIntervalSince1970: 200)))
    }
    func testTerminalStatesCannotReactivateWithAnEarlierClock() {
        for state in [NonCashReward.State.redeemed, .expired, .reversed] {
            XCTAssertFalse(reward(state).canPresent(at: Date(timeIntervalSince1970: 150)))
        }
    }
    func testMalformedTermsAndQuantityFailClosed() {
        for value in [reward(quantity: 0), reward(quantity: -1), reward(from: 200, until: 100),
                      reward(from: 100, until: 100), reward(conditions: " \n")] {
            XCTAssertFalse(value.canPresent(at: Date(timeIntervalSince1970: 150)))
        }
    }
    func testRepeatedPresentationDoesNotConsumeOrExtendTheAward() {
        let value = reward()
        for _ in 0..<3 { XCTAssertTrue(value.canPresent(at: Date(timeIntervalSince1970: 150))) }
        XCTAssertEqual(value.state, .awarded)
        XCTAssertEqual(value.validUntil, Date(timeIntervalSince1970: 200))
        XCTAssertEqual(value.rewardKind, "PHYSICAL")
        XCTAssertEqual(value.instanceId, "season")
    }
}
