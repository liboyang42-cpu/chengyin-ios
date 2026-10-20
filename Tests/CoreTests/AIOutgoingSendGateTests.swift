import Foundation
import XCTest
@testable import QuestifyCore

final class AIOutgoingSendGateTests: XCTestCase {
    private typealias Gate = AIOutgoingSendGate<String, UUID?>
    private let phone = "call 13800138000"
    private let request = UUID()

    func testCleanTextProceedsWithoutConfirmation() {
        var gate = Gate()
        XCTAssertEqual(gate.evaluate(text: "Where is the next clue?", scope: "a", request: nil), .proceed)
        XCTAssertFalse(gate.hasPendingConfirmation)
    }
    func testSensitiveTextNeedsConfirmationThenConfirmsOnce() {
        var gate = Gate()
        XCTAssertEqual(gate.evaluate(text: phone, scope: "a", request: nil), .confirm([.mainlandMobile]))
        XCTAssertTrue(gate.confirm(text: phone, scope: "a", request: nil))
        XCTAssertFalse(gate.confirm(text: phone, scope: "a", request: nil), "confirmation is single use")
    }
    func testTextChangedAfterConfirmPromptCannotSend() {
        var gate = Gate()
        _ = gate.evaluate(text: phone, scope: "a", request: nil)
        XCTAssertFalse(gate.confirm(text: phone + "0", scope: "a", request: nil))
    }
    func testAccountChangedAfterConfirmPromptCannotSend() {
        var gate = Gate()
        _ = gate.evaluate(text: phone, scope: "account-1", request: nil)
        XCTAssertFalse(gate.confirm(text: phone, scope: "account-2", request: nil))
    }
    func testCancelThenSendCannotUseOldConfirmation() {
        var gate = Gate()
        _ = gate.evaluate(text: phone, scope: "a", request: nil)
        gate.cancel()
        XCTAssertFalse(gate.confirm(text: phone, scope: "a", request: nil))
    }
    func testRegenerateThenFinalSendNeedsFreshConfirmation() {
        var gate = Gate()
        _ = gate.evaluate(text: phone, scope: "a", request: nil)          // input-box check
        XCTAssertTrue(gate.confirm(text: phone, scope: "a", request: nil))
        XCTAssertEqual(gate.evaluate(text: phone, scope: "a", request: request), .confirm([.mainlandMobile])) // final send of the review
        XCTAssertFalse(gate.confirm(text: phone, scope: "a", request: UUID()), "different request cannot reuse it")
    }
    func testReusedQuestionIsScreenedAsFinalText() {
        var gate = Gate()
        XCTAssertEqual(gate.evaluate(text: "mail a.b@example.test", scope: "a", request: request), .confirm([.email]))
    }
    func testCleanFinalTextClearsEarlierConfirmation() {
        var gate = Gate()
        _ = gate.evaluate(text: phone, scope: "a", request: nil)
        XCTAssertEqual(gate.evaluate(text: "hello", scope: "a", request: nil), .proceed)
        XCTAssertFalse(gate.confirm(text: phone, scope: "a", request: nil))
    }
}
