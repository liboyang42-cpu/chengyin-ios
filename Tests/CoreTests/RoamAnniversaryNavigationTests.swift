import XCTest
@testable import QuestifyCore

final class RoamAnniversaryNavigationTests: XCTestCase {
    private func scope(account: Int = 7) throws -> RoamHistoryScope {
        try RoamHistoryScope(market: "cn", deployment: URL(string: "https://example.com/roam")!, accountID: account)
    }
    private func owner(account: Int = 7, epoch: UInt64 = 1) throws -> RoamExperienceIdentity {
        RoamExperienceIdentity(scope: try scope(account: account), epoch: epoch)
    }
    private func memory(id: String = "31", topic: String = "7001") -> RoamAnniversaryMemory {
        RoamAnniversaryMemory(id: id, topicID: topic, title: "Route", completedAt: "2025-10-19 19:42:10.120", year: 2025, yearsAgo: 1)
    }

    func testValidCardResolvesToItsOwnTopicOnly() throws {
        let item = memory()
        guard case .available(let target) = RoamAnniversaryRouteAvailability.resolve(memory: item, hasDestination: true) else { return XCTFail() }
        XCTAssertEqual(target.memoryID, "31"); XCTAssertEqual(target.topicID, "7001"); XCTAssertEqual(target.topicValue, 7001)
        XCTAssertNotEqual(target.topicID, item.id)
    }

    func testInvalidTopicIDsAreUnavailableNeverRedirected() {
        for topic in ["", "0", "-1", "+7", "01", " 7", "7 ", "7.0", "abc", "999999999999999999999"] {
            XCTAssertEqual(RoamAnniversaryRouteAvailability.resolve(memory: memory(topic: topic), hasDestination: true), .invalidTopicID, topic)
            XCTAssertNil(RoamAnniversaryRouteTarget(memory: memory(topic: topic)), topic)
        }
        XCTAssertEqual(RoamAnniversaryRouteAvailability.resolve(memory: memory(id: "x"), hasDestination: true), .invalidTopicID)
    }

    func testMissingDestinationIsAccuratelyUnavailable() {
        XCTAssertEqual(RoamAnniversaryRouteAvailability.resolve(memory: memory(), hasDestination: false), .noDestination)
        // A malformed record stays invalid even when the host has no destination.
        XCTAssertEqual(RoamAnniversaryRouteAvailability.resolve(memory: memory(topic: "0"), hasDestination: false), .invalidTopicID)
    }

    func testNormalOpenReturnRefreshesExactlyOnce() throws {
        let me = try owner(); let item = memory(); let target = try XCTUnwrap(RoamAnniversaryRouteTarget(memory: item))
        var state = RoamAnniversaryNavigationState(); state.bind(to: me)
        XCTAssertTrue(state.open(target, memory: item, currentRows: [item], owner: me))
        XCTAssertTrue(state.mayRemainOpen(target, owner: me))
        XCTAssertFalse(state.consumeReturnRefresh(owner: me), "No refresh before returning")
        state.markReturned(owner: me)
        XCTAssertFalse(state.mayRemainOpen(target, owner: me))
        XCTAssertTrue(state.consumeReturnRefresh(owner: me))
        XCTAssertFalse(state.consumeReturnRefresh(owner: me), "Return refresh must not loop")
    }

    func testOpenRequiresTheExactRenderedCardStillInCurrentRows() throws {
        let me = try owner(); let item = memory(); let target = try XCTUnwrap(RoamAnniversaryRouteTarget(memory: item))
        var state = RoamAnniversaryNavigationState(); state.bind(to: me)
        XCTAssertFalse(state.open(target, memory: item, currentRows: [], owner: me), "Paginated/refreshed away")
        XCTAssertFalse(state.open(target, memory: item, currentRows: [memory(topic: "7002")], owner: me), "Same id, replaced topic")
        XCTAssertFalse(state.open(target, memory: memory(topic: "7002"), currentRows: [memory(topic: "7002")], owner: me))
        XCTAssertNil(state.openedTarget)
    }

    func testAccountOrEpochChangeClearsNavigationAndRejectsLateCallbacks() throws {
        let me = try owner(); let other = try owner(account: 8); let nextEpoch = try owner(epoch: 2)
        let item = memory(); let target = try XCTUnwrap(RoamAnniversaryRouteTarget(memory: item))
        for foreign in [other, nextEpoch] {
            var state = RoamAnniversaryNavigationState(); state.bind(to: me)
            XCTAssertTrue(state.open(target, memory: item, currentRows: [item], owner: me))
            state.bind(to: foreign)
            XCTAssertNil(state.openedTarget); XCTAssertFalse(state.returnRefreshPending)
            XCTAssertFalse(state.mayRemainOpen(target, owner: foreign))
            // Late callbacks captured under the old owner change nothing.
            state.markReturned(owner: me)
            XCTAssertFalse(state.consumeReturnRefresh(owner: me))
            XCTAssertFalse(state.open(target, memory: item, currentRows: [item], owner: me))
            XCTAssertFalse(state.consumeReturnRefresh(owner: foreign))
        }
        var signedOut = RoamAnniversaryNavigationState(); signedOut.bind(to: me)
        XCTAssertTrue(signedOut.open(target, memory: item, currentRows: [item], owner: me))
        signedOut.bind(to: nil)
        XCTAssertFalse(signedOut.mayRemainOpen(target, owner: nil))
        XCTAssertFalse(signedOut.consumeReturnRefresh(owner: nil))
    }

    func testDateChangeAndCancellationInvalidatePendingWork() throws {
        let me = try owner(); let item = memory(); let target = try XCTUnwrap(RoamAnniversaryRouteTarget(memory: item))
        var state = RoamAnniversaryNavigationState(); state.bind(to: me)
        XCTAssertTrue(state.open(target, memory: item, currentRows: [item], owner: me))
        state.markReturned(owner: me); XCTAssertTrue(state.returnRefreshPending)
        let before = state.generation
        state.invalidate() // date switch or cancelled presentation retires it
        XCTAssertGreaterThan(state.generation, before)
        XCTAssertNil(state.openedTarget); XCTAssertFalse(state.consumeReturnRefresh(owner: me))
    }

    func testRebindingSameOwnerKeepsAnOpenRoute() throws {
        let me = try owner(); let item = memory(); let target = try XCTUnwrap(RoamAnniversaryRouteTarget(memory: item))
        var state = RoamAnniversaryNavigationState(); state.bind(to: me)
        XCTAssertTrue(state.open(target, memory: item, currentRows: [item], owner: me))
        state.bind(to: me)
        XCTAssertTrue(state.mayRemainOpen(target, owner: me))
    }
}
