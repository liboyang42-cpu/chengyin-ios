import XCTest
@testable import Questify

@MainActor final class PublishingAIPromptControlsTests: XCTestCase {
    func testStableOwnerAllowsCurrentActionOnlyOnceAndIgnoresStaleInput() {
        let flow = PublishingAIDraftFlow(client:nil,product:.city), controller = PublishingAIPromptController()
        var applied = 0
        controller.activate()
        let choose = controller.action(.oldTown,languageCode:"zh",flow:flow,applied:{ applied += 1 })
        choose(); choose(); XCTAssertEqual(applied,1); XCTAssertEqual(flow.idea,"老城建筑与咖啡")
        let stale = controller.action(.rainyDay,languageCode:"zh",flow:flow,applied:{ applied += 1 })
        flow.idea = "My own idea"; stale(); XCTAssertEqual(applied,1); XCTAssertEqual(flow.idea,"My own idea")
        controller.action(.familyWeekend,languageCode:"en",flow:flow,applied:{ applied += 1 })()
        XCTAssertEqual(applied,2); XCTAssertEqual(flow.idea,"A weekend family adventure")
    }
    func testBackgroundReentryAndSheetCloseCannotApplyOldCallbacks() {
        let flow = PublishingAIDraftFlow(client:nil,product:.city), controller = PublishingAIPromptController()
        var applied = 0
        controller.activate()
        let old = controller.action(.oldTown,languageCode:"zh",flow:flow,applied:{ applied += 1 })
        controller.retire(); old(); XCTAssertFalse(controller.canSelect(in:flow))
        controller.activate(); old(); XCTAssertEqual(flow.idea,"")
        controller.action(.rainyDay,languageCode:"zh",flow:flow,applied:{ applied += 1 })()
        XCTAssertEqual(applied,1); XCTAssertEqual(flow.idea,"雨天室内漫游")
        let closed = controller.action(.oldTown,languageCode:"zh",flow:flow,applied:{ applied += 1 })
        flow.close(); closed(); XCTAssertEqual(applied,1); XCTAssertEqual(flow.idea,"")
    }
}
