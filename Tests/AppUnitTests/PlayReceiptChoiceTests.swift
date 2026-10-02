import XCTest
@testable import Questify

@MainActor final class PlayReceiptChoiceTests: XCTestCase {
    func testAcceptedChoiceSurvivesReadbackButNeverBelongsToAnotherNode() async throws {
        let reader = ReceiptChoiceReader()
        let model = PlayViewModel(reader: reader)
        await model.load()
        await model.submit(nodeID: 701, answer: "A")
        XCTAssertEqual(model.acceptedChoice(for: 701), "A")
        XCTAssertNil(model.acceptedChoice(for: 702))
        XCTAssertTrue(model.visibleSnapshot?.isDone(model.visibleSnapshot!.visibleNodes[0]) == true)
        await model.submit(nodeID: 701, answer: "B")
        XCTAssertEqual(reader.sends, 1)
        XCTAssertEqual(model.acceptedChoice(for: 701), "A")
    }
    func testSameAccountNewEpochAndLogoutHideAcceptedChoiceImmediately() async throws {
        let reader = ReceiptChoiceReader(); let model = PlayViewModel(reader: reader)
        await model.load(); await model.submit(nodeID: 701, answer: "A")
        reader.identity = .init(accountID: 1, epoch: 2, scope: .activity(41))
        XCTAssertNil(model.acceptedChoice(for: 701)); XCTAssertNil(model.visibleReceipt)
        reader.identity = nil
        XCTAssertNil(model.acceptedChoice(for: 701))
    }
    func testOrdinaryReloadAndInvalidateClearReceiptChoice() async throws {
        let reader = ReceiptChoiceReader(); let model = PlayViewModel(reader: reader)
        await model.load(); await model.submit(nodeID: 701, answer: "A")
        await model.load()
        XCTAssertNil(model.acceptedChoice(for: 701))
        model.invalidate(); XCTAssertNil(model.acceptedChoice(for: 701))
    }
    func testFailedOrMismatchedReceiptDoesNotInventAcceptedChoice() async throws {
        for wrongNode in [false, true] {
            let reader = ReceiptChoiceReader(); reader.wrongNode = wrongNode; reader.failWrite = !wrongNode
            let model = PlayViewModel(reader: reader)
            await model.load(); await model.submit(nodeID: 701, answer: "A")
            XCTAssertNil(model.acceptedChoice(for: 701)); XCTAssertNil(model.visibleReceipt)
            XCTAssertTrue(model.needsProgressCheck)
        }
    }
}
@MainActor private final class ReceiptChoiceReader: PlayReading {
    let scope = PlaySessionScope.activity(41)
    let isConfigured = true
    var identity: PlayReadIdentity? = .init(accountID: 1, epoch: 1, scope: .activity(41))
    var canSubmitAnswer = true
    let supportsAnswerSubmission = true
    var sends = 0
    var wrongNode = false
    var failWrite = false
    private var done = false
    func playSession() async throws -> PlaySnapshot {
        let source = #"{"topicId":71,"mode":1,"registered":true,"playable":true,"nodes":[{"nodeId":701,"done":DONE,"arrived":true,"locked":false,"needGps":false,"needScan":false,"validationMethod":3,"question":"Synthetic choice","options":{"A":"One","B":"Two"}}]}"#
            .replacingOccurrences(of: "DONE", with: done ? "true" : "false")
        return try PlaySnapshot(scope: scope, result: JSONDecoder().decode(PlayNodesResult.self, from: Data(source.utf8)))
    }
    func submitAnswer(nodeID: Int, answer: String) async throws -> PlayAnswerReceipt {
        sends += 1; canSubmitAnswer = false
        if failWrite { throw APIError.httpStatus(503) }
        done = true
        let source = "{\"nodeId\":\(wrongNode ? 702 : nodeID),\"firstTime\":true,\"completed\":true}"
        return try JSONDecoder().decode(PlayAnswerReceipt.self, from: Data(source.utf8))
    }
}
