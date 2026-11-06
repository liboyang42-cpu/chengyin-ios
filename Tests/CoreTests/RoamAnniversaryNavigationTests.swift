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
        let lease = try XCTUnwrap(state.openedPresentation)
        XCTAssertEqual(lease.target, target)
        XCTAssertTrue(state.mayRemainOpen(lease, owner: me))
        XCTAssertFalse(state.completeReturn(presentation: nil, owner: me), "A return without the lease is nothing")
        XCTAssertTrue(state.mayRemainOpen(lease, owner: me), "Rejected return must not close the route")
        XCTAssertTrue(state.completeReturn(presentation: lease, owner: me))
        XCTAssertFalse(state.mayRemainOpen(lease, owner: me))
        XCTAssertFalse(state.completeReturn(presentation: lease, owner: me), "Return refresh must not loop")
    }

    func testLateReturnFromRouteACannotClearOrConsumeRouteB() throws {
        let me = try owner()
        let a = memory(id: "31", topic: "7001"), b = memory(id: "12", topic: "7002")
        let targetA = try XCTUnwrap(RoamAnniversaryRouteTarget(memory: a))
        let targetB = try XCTUnwrap(RoamAnniversaryRouteTarget(memory: b))
        var state = RoamAnniversaryNavigationState(); state.bind(to: me)
        XCTAssertTrue(state.open(targetA, memory: a, currentRows: [a, b], owner: me))
        let leaseA = try XCTUnwrap(state.openedPresentation)
        XCTAssertTrue(state.completeReturn(presentation: leaseA, owner: me), "A really closed")
        XCTAssertTrue(state.open(targetB, memory: b, currentRows: [a, b], owner: me))
        let leaseB = try XCTUnwrap(state.openedPresentation)
        XCTAssertNotEqual(leaseA.generation, leaseB.generation)
        // A's late disappearance/return arrives after B opened, same owner.
        state.noteCovered(leaseA, owner: me)
        XCTAssertFalse(state.completeReturn(presentation: leaseA, owner: me))
        XCTAssertTrue(state.mayRemainOpen(leaseB, owner: me), "Late A must not clear B")
        XCTAssertEqual(state.openedTarget, targetB)
        XCTAssertTrue(state.completeReturn(presentation: leaseB, owner: me), "Only B's own return consumes")
        XCTAssertFalse(state.completeReturn(presentation: leaseA, owner: me))
    }

    func testReopenedSameTargetMintsANewLeaseAndOldLeaseIsStale() throws {
        let me = try owner(); let item = memory(); let target = try XCTUnwrap(RoamAnniversaryRouteTarget(memory: item))
        var state = RoamAnniversaryNavigationState(); state.bind(to: me)
        XCTAssertTrue(state.open(target, memory: item, currentRows: [item], owner: me))
        let first = try XCTUnwrap(state.openedPresentation)
        XCTAssertTrue(state.completeReturn(presentation: first, owner: me))
        XCTAssertTrue(state.open(target, memory: item, currentRows: [item], owner: me))
        let second = try XCTUnwrap(state.openedPresentation)
        XCTAssertEqual(first.target, second.target); XCTAssertNotEqual(first.generation, second.generation)
        XCTAssertFalse(state.completeReturn(presentation: first, owner: me), "Same target is not the same presentation")
        XCTAssertTrue(state.mayRemainOpen(second, owner: me))
    }

    func testCoveredByChildDrillDownIsNotAReturn() throws {
        let me = try owner(); let item = memory(); let target = try XCTUnwrap(RoamAnniversaryRouteTarget(memory: item))
        var state = RoamAnniversaryNavigationState(); state.bind(to: me)
        XCTAssertTrue(state.open(target, memory: item, currentRows: [item], owner: me))
        let lease = try XCTUnwrap(state.openedPresentation)
        // The detail disappears because it pushed a child page, then reappears.
        state.noteCovered(lease, owner: me)
        XCTAssertTrue(state.mayRemainOpen(lease, owner: me), "Covered detail keeps its route")
        XCTAssertEqual(state.openedPresentation, lease)
        // Only the later true pop completes, and only once.
        XCTAssertTrue(state.completeReturn(presentation: lease, owner: me))
        XCTAssertFalse(state.completeReturn(presentation: lease, owner: me))
    }

    func testOpenRequiresTheExactRenderedCardStillInCurrentRows() throws {
        let me = try owner(); let item = memory(); let target = try XCTUnwrap(RoamAnniversaryRouteTarget(memory: item))
        var state = RoamAnniversaryNavigationState(); state.bind(to: me)
        XCTAssertFalse(state.open(target, memory: item, currentRows: [], owner: me), "Paginated/refreshed away")
        XCTAssertFalse(state.open(target, memory: item, currentRows: [memory(topic: "7002")], owner: me), "Same id, replaced topic")
        XCTAssertFalse(state.open(target, memory: memory(topic: "7002"), currentRows: [memory(topic: "7002")], owner: me))
        XCTAssertNil(state.openedTarget); XCTAssertNil(state.openedPresentation)
    }

    func testAccountOrEpochChangeClearsNavigationAndRejectsLateCallbacks() throws {
        let me = try owner(); let other = try owner(account: 8); let nextEpoch = try owner(epoch: 2)
        let item = memory(); let target = try XCTUnwrap(RoamAnniversaryRouteTarget(memory: item))
        for foreign in [other, nextEpoch] {
            var state = RoamAnniversaryNavigationState(); state.bind(to: me)
            XCTAssertTrue(state.open(target, memory: item, currentRows: [item], owner: me))
            let lease = try XCTUnwrap(state.openedPresentation)
            state.bind(to: foreign)
            XCTAssertNil(state.openedTarget); XCTAssertNil(state.openedPresentation)
            XCTAssertFalse(state.mayRemainOpen(lease, owner: foreign))
            // Late callbacks carrying the old lease and old owner change nothing.
            state.noteCovered(lease, owner: me)
            XCTAssertFalse(state.completeReturn(presentation: lease, owner: me))
            XCTAssertFalse(state.open(target, memory: item, currentRows: [item], owner: me))
            XCTAssertFalse(state.completeReturn(presentation: lease, owner: foreign))
        }
        var signedOut = RoamAnniversaryNavigationState(); signedOut.bind(to: me)
        XCTAssertTrue(signedOut.open(target, memory: item, currentRows: [item], owner: me))
        let lease = try XCTUnwrap(signedOut.openedPresentation)
        signedOut.bind(to: nil)
        XCTAssertFalse(signedOut.mayRemainOpen(lease, owner: nil))
        XCTAssertFalse(signedOut.completeReturn(presentation: lease, owner: nil))
    }

    func testDateChangeAndCancellationInvalidatePendingWork() throws {
        let me = try owner(); let item = memory(); let target = try XCTUnwrap(RoamAnniversaryRouteTarget(memory: item))
        var state = RoamAnniversaryNavigationState(); state.bind(to: me)
        XCTAssertTrue(state.open(target, memory: item, currentRows: [item], owner: me))
        let lease = try XCTUnwrap(state.openedPresentation)
        let before = state.generation
        state.invalidate() // date switch or cancelled presentation retires it
        XCTAssertGreaterThan(state.generation, before)
        XCTAssertNil(state.openedTarget)
        XCTAssertFalse(state.completeReturn(presentation: lease, owner: me))
        state.noteCovered(lease, owner: me)
        XCTAssertNil(state.openedPresentation)
    }

    func testRebindingSameOwnerKeepsAnOpenRoute() throws {
        let me = try owner(); let item = memory(); let target = try XCTUnwrap(RoamAnniversaryRouteTarget(memory: item))
        var state = RoamAnniversaryNavigationState(); state.bind(to: me)
        XCTAssertTrue(state.open(target, memory: item, currentRows: [item], owner: me))
        let lease = try XCTUnwrap(state.openedPresentation)
        state.bind(to: me)
        XCTAssertTrue(state.mayRemainOpen(lease, owner: me))
    }
}
