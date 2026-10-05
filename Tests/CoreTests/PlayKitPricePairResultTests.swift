import XCTest
@testable import QuestifyCore

final class PlayKitPricePairResultTests: XCTestCase {
    private func segment(_ changes: [String: PlayWireValue] = [:]) -> PlayWireValue {
        var values: [String: PlayWireValue] = [
            "items": .array([.object(["id": .string("a"), "name": .string("A")]), .object(["id": .string("b"), "name": .string("B")])]),
            "attempts": .int(1), "finished": .bool(false), "passed": .bool(false), "lastPickId": .string("a")
        ]
        values.merge(changes) { _, new in new }; return .object(values)
    }
    func testRetryUsesLastServerPickAndNeverRevealsUnfinishedAnswer() throws {
        let result = try XCTUnwrap(PlayKitPricePairResult(segment: segment(["answerId": .string("b"), "maxTries": .int(1)])))
        XCTAssertEqual(result.lastPickID, "a"); XCTAssertFalse(result.finished); XCTAssertFalse(result.passed)
        XCTAssertNil(result.answerID)
        XCTAssertFalse(PlayKitScreenProjection(kind: .pricePair, segment: segment(["maxTries": .int(1)])).complete)
    }
    func testSuccessAndExhaustionUseExplicitTerminalServerAnswer() throws {
        let success = try XCTUnwrap(PlayKitPricePairResult(segment: segment(["finished": .bool(true), "passed": .bool(true), "answerId": .string("a")])))
        XCTAssertEqual(success.answerID, "a"); XCTAssertTrue(success.passed)
        let failure = try XCTUnwrap(PlayKitPricePairResult(segment: segment(["finished": .bool(true), "answerId": .string("b")])))
        XCTAssertEqual(failure.lastPickID, "a"); XCTAssertEqual(failure.answerID, "b"); XCTAssertFalse(failure.passed)
    }
    func testMissingMalformedAndContradictoryVerdictsDoNotMarkCards() {
        let cases: [[String: PlayWireValue]] = [
            ["attempts": .int(0)], ["attempts": .int(-1)], ["attempts": .number(1.5)],
            ["attempts": .string("1")], ["attempts": .bool(true)], ["attempts": .null],
            ["finished": .null], ["finished": .string("true")], ["passed": .null],
            ["passed": .string("false")], ["passed": .bool(true)],
            ["lastPickId": .string("missing")], ["lastPickId": .int(1)], ["lastPickId": .string("")],
            ["finished": .bool(true)], ["finished": .bool(true), "answerId": .string("missing")],
            ["finished": .bool(true), "answerId": .int(1)],
            ["finished": .bool(true), "answerId": .string("a")],
            ["finished": .bool(true), "passed": .bool(true), "answerId": .string("b")]
        ]
        for changes in cases { XCTAssertNil(PlayKitPricePairResult(segment: segment(changes)), String(describing: changes)) }
    }
    func testMalformedOrAmbiguousCardIdentitiesFailClosed() {
        let cases: [[PlayWireValue]] = [[], [.object(["id": .string("a")]), .object(["id": .string("a")])],
                                    [.object(["id": .string("a")]), .object(["id": .int(1)])],
                                    [.object(["id": .string("a")]), .object(["id": .string("")])]]
        for rows in cases {
            XCTAssertNil(PlayKitPricePairResult(segment: segment(["items": .array(rows)])))
        }
    }
    func testFreshSegmentReplacesReceiptWithoutSelectingOrRetainingPriorAnswer() throws {
        let old = try XCTUnwrap(PlayKitPricePairResult(segment: segment(["finished": .bool(true), "answerId": .string("b")])))
        let next = try XCTUnwrap(PlayKitPricePairResult(segment: segment(["lastPickId": .string("b")])) )
        XCTAssertEqual(old.answerID, "b"); XCTAssertEqual(next.lastPickID, "b"); XCTAssertNil(next.answerID)
        XCTAssertNil(PlayKitPricePairResult(segment: segment(["attempts": .int(0), "lastPickId": .string("")])))
    }
}
