import XCTest
@testable import QuestifyCore

@MainActor final class WalkingNavigationPresentationTests: XCTestCase {
    func testEveryPhaseHasAnHonestStatusAndOnlyPendingPhasesLoad() {
        let cases: [(WalkingNavigationCoordinator.Phase, String, Bool)] = [
            (.ready, "walking.ready", false), (.authorizing, "walking.authorizing", true),
            (.locating, "walking.locating", true), (.routing, "walking.routing", true),
            (.navigating, "walking.navigating", false), (.nearDestination, "walking.nearDestination", false),
            (.paused, "walking.paused", false), (.cancelled, "walking.cancelled", false),
            (.failed(.network), "walking.error.network", false),
            (.failed(.staleContext), "walking.error.staleContext", false)
        ]
        for (phase, key, loading) in cases {
            XCTAssertEqual(phase.statusKey, key); XCTAssertEqual(phase.isPreparing, loading)
        }
    }
    func testCancelAndPauseCanExplicitlyRestartButStaleScopeCannot() {
        for phase in [WalkingNavigationCoordinator.Phase.ready, .paused, .cancelled, .failed(.network), .failed(.permissionDenied)] {
            XCTAssertTrue(phase.mayStart)
        }
        for phase in [WalkingNavigationCoordinator.Phase.authorizing, .locating, .routing, .navigating, .nearDestination, .failed(.staleContext)] {
            XCTAssertFalse(phase.mayStart)
        }
        XCTAssertFalse(WalkingNavigationCoordinator.Phase.failed(.staleContext).mayPause)
        XCTAssertFalse(WalkingNavigationCoordinator.Phase.paused.mayPause)
        XCTAssertTrue(WalkingNavigationCoordinator.Phase.routing.mayPause)
        XCTAssertTrue(WalkingNavigationCoordinator.Phase.failed(.weakGPS).mayPause)
    }
    func testReopenedMapQueryNeverAcceptsPreDismissalOrExpiredScopeResults() {
        let gate = SearchMapQueryGate(), firstScope = UUID(), nextScope = UUID()
        let beforeDismissal = gate.begin(scope: firstScope)
        gate.invalidate()
        let reopened = gate.begin(scope: firstScope)
        XCTAssertFalse(gate.accepts(beforeDismissal, scope: firstScope))
        XCTAssertTrue(gate.accepts(reopened, scope: firstScope))
        XCTAssertFalse(gate.accepts(reopened, scope: nextScope))
        gate.invalidate()
        let newAccount = gate.begin(scope: nextScope)
        XCTAssertFalse(gate.accepts(reopened, scope: firstScope))
        XCTAssertTrue(gate.accepts(newAccount, scope: nextScope))
    }
    func testCancelledMapTaskCannotPublishCurrentTicket() async {
        let gate = SearchMapQueryGate(), scope = UUID()
        let task = Task { @MainActor in
            let ticket = gate.begin(scope: scope)
            while !Task.isCancelled { await Task.yield() }
            return gate.accepts(ticket, scope: scope)
        }
        task.cancel()
        let accepted = await task.value
        XCTAssertFalse(accepted)
    }
}
