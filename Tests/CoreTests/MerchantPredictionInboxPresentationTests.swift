import XCTest
@testable import QuestifyCore

/// Source pages/merchant/predict/index.js shapeRound.
final class MerchantPredictionInboxPresentationTests: XCTestCase {
    func testLastDayIsUrgentInsteadOfZeroDaysLeft() {
        let today = MerchantPredictionInboxPresentation(daysLeft: 0, betCount: 0, optionCount: 2)
        XCTAssertEqual(today.deadline, .lastDay); XCTAssertTrue(today.isUrgent); XCTAssertEqual(today.bets, .none)
        let later = MerchantPredictionInboxPresentation(daysLeft: 2, betCount: 7, optionCount: 3)
        XCTAssertEqual(later.deadline, .daysLeft(2)); XCTAssertFalse(later.isUrgent); XCTAssertEqual(later.bets, .count(7)); XCTAssertEqual(later.optionCount, 3)
    }
    func testMissingOrNullNodeNameDecodesToFallback() throws {
        for name in ["", #""nodeName":null,"#] {
            let json = #"{"nodeId":81,"topicId":null,"playDay":"2026-10-01",\#(name)"question":"Q","options":[{"key":"A","label":"A"}],"betCount":0,"daysLeft":1}"#
            let round = try JSONDecoder().decode(MerchantPredictionInboxRound.self, from: Data(json.utf8))
            XCTAssertEqual(round.nodeName, "")
        }
    }
}

/// Source merchant/index todo.pendingPredict: count only, missing or negative values are zero.
final class MerchantTodoPendingPredictTests: XCTestCase {
    func testPendingPredictDecodesWithoutChangingPendingWork() throws {
        let todo = try JSONDecoder().decode(MerchantTodo.self, from: Data(#"{"pendingPredict":3}"#.utf8))
        XCTAssertEqual(todo.pendingPredict, 3); XCTAssertFalse(todo.hasPendingWork)
        XCTAssertEqual(try JSONDecoder().decode(MerchantTodo.self, from: Data("{}".utf8)).pendingPredict, 0)
        XCTAssertEqual(try JSONDecoder().decode(MerchantTodo.self, from: Data(#"{"pendingPredict":-1}"#.utf8)).pendingPredict, 0)
    }
}
