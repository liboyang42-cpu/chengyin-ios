import XCTest
@testable import Questify

final class PlayTimedReactionRevisionTests: XCTestCase {
    private func segment(_ rounds: Int) -> PlayWireValue {
        .object(["rounds": .integer(Int64(rounds)), "submitted": .bool(false)])
    }
    private func measure(_ initial: PlayKitReactionRun) -> PlayKitReactionRun {
        var run = initial
        run.beginAfterAcknowledgement(now: 0, randomUnit: 0)
        for index in 0..<run.rounds {
            let start = Double(index * 10)
            if index > 0 { run.arm(now: start, randomUnit: 0) }
            run.tick(now: start + 2)
            run.tap(now: start + 2.5)
        }
        return run
    }
    private func payload(_ run: PlayKitReactionRun) throws -> [String: PlayWireValue] {
        try PlayKitActionCatalog.payload(kind: "reaction", action: "SUBMIT_REACTION",
            detail: ["times": .array(run.roundsMilliseconds.map { .integer(Int64($0)) })])
    }
    func testNewRevisionUsesFiveRoundsInsteadOfPreviousThree() throws {
        let old = measure(PlayTimedReactionConfiguration.makeRun(segment: segment(3)))
        XCTAssertEqual(old.phase, .measured)
        XCTAssertThrowsError(try PlayKitInputContract.validate(kind: "reaction", action: "SUBMIT_REACTION",
            payload: payload(old), segment: segment(5)))
        let current = measure(PlayTimedReactionConfiguration.makeRun(segment: segment(5)))
        XCTAssertEqual(current.roundsMilliseconds.count, 5)
        XCTAssertNoThrow(try PlayKitInputContract.validate(kind: "reaction", action: "SUBMIT_REACTION",
            payload: payload(current), segment: segment(5)))
    }
    func testSmallerRevisionDoesNotRequireOldExtraRounds() throws {
        let current = measure(PlayTimedReactionConfiguration.makeRun(segment: segment(1)))
        XCTAssertEqual(current.phase, .measured); XCTAssertEqual(current.roundsMilliseconds.count, 1)
        XCTAssertNoThrow(try PlayKitInputContract.validate(kind: "reaction", action: "SUBMIT_REACTION",
            payload: payload(current), segment: segment(1)))
    }
    func testRestoredRevisionStartsIdleWithoutOldMeasurements() {
        var old = measure(PlayTimedReactionConfiguration.makeRun(segment: segment(3)))
        XCTAssertFalse(old.roundsMilliseconds.isEmpty)
        old = PlayTimedReactionConfiguration.makeRun(segment: segment(5))
        XCTAssertEqual(old.phase, .idle); XCTAssertTrue(old.roundsMilliseconds.isEmpty)
        XCTAssertEqual(old.rounds, 5)
    }
    func testAbsentAndNonpositiveFallbackAndCoreCapRemainUnchanged() {
        XCTAssertEqual(PlayTimedReactionConfiguration.makeRun(segment: .object([:])).rounds, 3)
        XCTAssertEqual(PlayTimedReactionConfiguration.makeRun(segment: segment(0)).rounds, 3)
        XCTAssertEqual(PlayTimedReactionConfiguration.makeRun(segment: segment(-1)).rounds, 3)
        XCTAssertEqual(PlayTimedReactionConfiguration.makeRun(segment: segment(101)).rounds, 100)
    }
}
