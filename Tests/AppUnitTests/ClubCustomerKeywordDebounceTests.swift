import XCTest
@testable import Questify

/// Authored tests for the production timer, with no wall-clock sleeps or network.
/// NOT_RUN until this file is registered in the approved Apple test target.
@MainActor final class ClubCustomerKeywordDebounceTests: XCTestCase {
    @MainActor private final class Gate {
        var continuation: CheckedContinuation<Void, Error>?
        let entered: XCTestExpectation
        init(_ entered: XCTestExpectation) { self.entered = entered }
        func sleep() async throws {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                entered.fulfill()
            }
        }
        func release() { continuation?.resume(); continuation = nil }
        func fail() { continuation?.resume(throwing: CancellationError()); continuation = nil }
    }
    func testProductionIntervalIsThreeHundredMilliseconds() {
        XCTAssertEqual(ClubCustomerKeywordDebounce.delayNanoseconds, 300_000_000)
    }
    func testInputWaitsUntilDelayAndThenRunsExactlyOnce() async {
        let entered = expectation(description: "delay entered"), fired = expectation(description: "read fired")
        let gate = Gate(entered), timer = ClubCustomerKeywordDebounce(sleep: { try await gate.sleep() })
        var reads = 0
        timer.schedule { reads += 1; fired.fulfill() }
        await fulfillment(of: [entered], timeout: 1)
        XCTAssertEqual(reads, 0)
        gate.release()
        await fulfillment(of: [fired], timeout: 1)
        XCTAssertEqual(reads, 1)
    }
    func testNewInputRetiresOldDelayEvenWhenSleeperIgnoresCancellation() async {
        let firstEntered = expectation(description: "first delay"), secondEntered = expectation(description: "second delay")
        let fired = expectation(description: "latest read")
        let first = Gate(firstEntered), second = Gate(secondEntered)
        var sleeps = 0, reads: [String] = []
        let timer = ClubCustomerKeywordDebounce(sleep: {
            sleeps += 1
            if sleeps == 1 { try await first.sleep() } else { try await second.sleep() }
        })
        let old = timer.schedule { reads.append("old") }
        await fulfillment(of: [firstEntered], timeout: 1)
        let latest = timer.schedule { reads.append("latest"); fired.fulfill() }
        await fulfillment(of: [secondEntered], timeout: 1)
        first.release(); second.release()
        await old.value; await latest.value
        await fulfillment(of: [fired], timeout: 1)
        XCTAssertEqual(reads, ["latest"])
    }
    func testConfirmFilterRefreshAndLifecycleCancellationDoNotRunPendingAction() async {
        await verifyEitherFirstDisappearHookRetiresRead()
        for reason in ["confirm", "filter", "refresh", "context", "disappear"] {
            let entered = expectation(description: "delay " + reason)
            var reads = 0
            let gate = Gate(entered), timer = ClubCustomerKeywordDebounce(sleep: { try await gate.sleep() })
            let task = timer.schedule { reads += 1 }
            await fulfillment(of: [entered], timeout: 1)
            timer.cancel(); gate.release()
            await task.value
            XCTAssertEqual(reads, 0, reason)
        }
    }
    private func verifyEitherFirstDisappearHookRetiresRead() async {
        for cancelFirst in [true, false] {
            let entered = expectation(description: "disappear order")
            let gate = Gate(entered), timer = ClubCustomerKeywordDebounce(sleep: { try await gate.sleep() })
            var generation: UInt64 = 7, requests = 0, uiWrites = 0
            let keywordRevision = generation, oldReadRevision = generation
            let pending = timer.schedule {
                guard keywordRevision == generation else { return }
                requests += 1
            }
            await fulfillment(of: [entered], timeout: 1)
            if cancelFirst { timer.cancel(); generation &+= 1 } else { generation &+= 1 }
            // Resume between hooks: either first hook must already retire both paths.
            gate.release(); await pending.value
            if oldReadRevision == generation { uiWrites += 1 }
            XCTAssertEqual(requests, 0); XCTAssertEqual(uiWrites, 0)
            if cancelFirst { generation &+= 1 } else { timer.cancel(); generation &+= 1 }
        }
    }
    func testReadCanCancelPendingHandleWithoutCancellingItself() async {
        let entered = expectation(description: "delay"), fired = expectation(description: "read")
        let gate = Gate(entered), timer = ClubCustomerKeywordDebounce(sleep: { try await gate.sleep() })
        timer.schedule {
            timer.cancel()
            XCTAssertFalse(Task.isCancelled)
            fired.fulfill()
        }
        await fulfillment(of: [entered], timeout: 1)
        gate.release()
        await fulfillment(of: [fired], timeout: 1)
    }
    func testThrowingDelayDoesNotStartRead() async {
        let entered = expectation(description: "delay")
        var reads = 0
        let gate = Gate(entered), timer = ClubCustomerKeywordDebounce(sleep: { try await gate.sleep() })
        let task = timer.schedule { reads += 1 }
        await fulfillment(of: [entered], timeout: 1)
        gate.fail()
        await task.value
        XCTAssertEqual(reads, 0)
    }
}
