import XCTest
@testable import QuestifyCore

final class ScanPayloadTests: XCTestCase {
    func testMissingOrEmptyPayloadDoesNotFinishSession() {
        var gate = ScanPayloadGate()
        XCTAssertNil(gate.take(nil))
        XCTAssertNil(gate.take(""))
        XCTAssertFalse(gate.isFinished)
        XCTAssertEqual(gate.take("fixture-code"), "fixture-code")
        XCTAssertTrue(gate.isFinished)
    }

    func testPayloadIsNotTrimmedNormalizedOrInterpreted() {
        let payload = "  https://example.invalid/扫码?code=A%2FB&label=e\u{301}\n"
        var gate = ScanPayloadGate()
        let result = gate.take(payload)
        XCTAssertEqual(result, payload)
        // String equality permits canonically equivalent Unicode. Compare UTF-8
        // too so a future normalization step cannot silently alter the payload.
        XCTAssertEqual(result.map { Array($0.utf8) }, Array(payload.utf8))
    }

    func testWhitespaceIsPreservedForHostValidation() {
        var gate = ScanPayloadGate()
        XCTAssertEqual(gate.take(" \n"), " \n")
    }

    func testRepeatedAndDifferentLaterCallbacksAreIgnored() {
        var gate = ScanPayloadGate()
        XCTAssertEqual(gate.take("first-fixture"), "first-fixture")
        XCTAssertNil(gate.take("first-fixture"))
        XCTAssertNil(gate.take("second-fixture"))
    }

    func testCancellationRejectsLateCallbacks() {
        var gate = ScanPayloadGate()
        gate.cancel()
        gate.cancel()
        XCTAssertNil(gate.take("late-fixture"))
        XCTAssertTrue(gate.isFinished)
    }

    func testNewPresentationUsesAnIndependentGate() {
        var previous = ScanPayloadGate()
        XCTAssertEqual(previous.take("fixture-code"), "fixture-code")
        var next = ScanPayloadGate()
        XCTAssertEqual(next.take("fixture-code"), "fixture-code")
    }
}
