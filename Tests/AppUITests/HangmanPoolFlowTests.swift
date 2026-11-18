import XCTest

/// F03 letter pool: tap a candidate to fill the first empty slot, tap a filled slot to
/// return it, clear, submit through the shared review; wrong answers keep the letters.
final class HangmanPoolFlowTests: XCTestCase {
    private var runningApp: XCUIApplication?
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: runningApp); runningApp?.terminate(); runningApp = nil }
    private func launch(question: Bool = false, language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset-language", "--uitesting-module", "letterPoolGame", "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]
        if question { app.launchArguments.append("--letter-pool-question") }
        runningApp = app; app.launch()
        let first = app.buttons[(question ? "playkit.letterPool" : "playkit.hangman") + ".candidate.0"]
        XCTAssertTrue(first.waitForExistence(timeout: 5), app.debugDescription)
        return app
    }
    private func tap(_ id: String, _ app: XCUIApplication) {
        let element = app.buttons[id]
        XCTAssertTrue(element.waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertTrue(revealFixtureElement(element, in: app), app.debugDescription); element.tap()
    }
    private func confirm(_ submit: String, _ app: XCUIApplication) {
        tap(submit, app)
        let confirm = app.buttons["playkit.review.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertTrue(revealFixtureElement(confirm, in: app), app.debugDescription); confirm.tap()
    }
    private func waitForWrites(_ count: String, _ app: XCUIApplication) {
        let writes = app.staticTexts["letterPool.fixture.writes"]
        expectation(for: NSPredicate(format: "label == %@", count), evaluatedWith: writes)
        waitForExpectations(timeout: 5)
    }
    // Fixture pool order: C X A Y B. Slots: 0 _, 1 _, 2 "-", 3 _, 4 "D".
    func testCandidatesFillFirstEmptySlotAndFilledSlotReturnsCharacter() {
        let app = launch()
        XCTAssertFalse(app.buttons["playkit.hangman.slot.2"].exists, "Separator is not tappable")
        XCTAssertFalse(app.buttons["playkit.hangman.slot.4"].exists, "Prefilled letter is not tappable")
        tap("playkit.hangman.candidate.2", app) // A -> slot 0
        tap("playkit.hangman.candidate.4", app) // B -> slot 1
        XCTAssertEqual(app.buttons["playkit.hangman.slot.0"].label, "A")
        XCTAssertEqual(app.buttons["playkit.hangman.slot.1"].label, "B")
        XCTAssertFalse(app.buttons["playkit.hangman.candidate.2"].isEnabled, "A used candidate is greyed out")
        tap("playkit.hangman.slot.0", app) // A returns to the pool
        XCTAssertTrue(app.buttons["playkit.hangman.candidate.2"].isEnabled)
        tap("playkit.hangman.candidate.0", app) // C fills the first empty slot (0)
        XCTAssertEqual(app.buttons["playkit.hangman.slot.0"].label, "C")
        XCTAssertFalse(app.buttons["playkit.submit.hangman"].isEnabled, "Slot 3 is still empty")
        tap("playkit.hangman.clear", app)
        XCTAssertEqual(app.buttons["playkit.hangman.slot.1"].label, "Empty slot")
        XCTAssertEqual(app.staticTexts["letterPool.fixture.writes"].label, "0")
    }
    func testWrongAnswerKeepsLettersThenCorrectAnswerSolves() {
        let app = launch()
        tap("playkit.hangman.candidate.2", app); tap("playkit.hangman.candidate.1", app); tap("playkit.hangman.candidate.0", app) // A X C
        confirm("playkit.submit.hangman", app)
        waitForWrites("1", app)
        XCTAssertEqual(app.staticTexts["letterPool.fixture.payload"].label, "0=A,1=X,3=C")
        XCTAssertTrue(app.staticTexts["playkit.hangman.notYet"].waitForExistence(timeout: 3) || app.otherElements["playkit.hangman.notYet"].exists, app.debugDescription)
        XCTAssertEqual(app.buttons["playkit.hangman.slot.0"].label, "A")
        XCTAssertEqual(app.buttons["playkit.hangman.slot.1"].label, "X")
        XCTAssertEqual(app.buttons["playkit.hangman.slot.3"].label, "C")
        tap("playkit.hangman.slot.1", app); tap("playkit.hangman.candidate.4", app) // replace X with B
        confirm("playkit.submit.hangman", app)
        waitForWrites("2", app)
        XCTAssertEqual(app.staticTexts["letterPool.fixture.payload"].label, "0=A,1=B,3=C")
        XCTAssertTrue(app.staticTexts["playkit.hangman.solved"].waitForExistence(timeout: 3) || app.otherElements["playkit.hangman.solved"].exists, app.debugDescription)
        XCTAssertFalse(app.buttons["playkit.submit.hangman"].exists)
    }
    func testQuestionLetterPoolSubmitsPickedCharactersInSlotOrder() {
        let app = launch(question: true, language: "zh-Hans")
        // Fixture pool order: 丙 甲 丁 乙.
        XCTAssertEqual(app.buttons["playkit.letterPool.candidate.1"].label, "候选字 甲")
        tap("playkit.letterPool.candidate.1", app); tap("playkit.letterPool.candidate.3", app)
        XCTAssertEqual(app.buttons["playkit.letterPool.slot.0"].label, "甲")
        XCTAssertEqual(app.buttons["playkit.letterPool.slot.1"].label, "乙")
        XCTAssertTrue(app.buttons["清空"].exists)
        confirm("playkit.submit.qa", app)
        waitForWrites("1", app)
        XCTAssertEqual(app.staticTexts["letterPool.fixture.payload"].label, "甲乙")
    }
}
