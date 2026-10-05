import XCTest
@testable import QuestifyCore

final class PlayGameplayModeTests: XCTestCase {
    private func snapshot(_ rows: String, mode: Int = 2, total: Int? = nil, done: Int? = nil, registered: Bool = true) throws -> PlaySnapshot {
        let counts = (total.map { ",\"total\":\($0)" } ?? "") + (done.map { ",\"doneCount\":\($0)" } ?? "")
        let raw = "{\"mode\":\(mode),\"registered\":\(registered),\"playable\":true\(counts),\"nodes\":[\(rows)]}"
        return try .init(scope: .activity(41), result: JSONDecoder().decode(PlayNodesResult.self, from: Data(raw.utf8)))
    }
    func testOnlyExactServerModesResolve() {
        XCTAssertEqual(PlayGameplayMode(serverValue: 1), .cityOrientation)
        XCTAssertEqual(PlayGameplayMode(serverValue: 2), .freeExploration)
        for value in [nil, 0, -1, 3] as [Int?] { XCTAssertNil(PlayGameplayMode(serverValue: value)) }
    }
    func testVariableStoreCountKeepsServerOrderNotSortIDOrSixCardLimit() throws {
        for count in [1, 3, 4, 5, 6, 9] {
            let ids = Array((1...count).reversed())
            let rows = ids.map { "{\"nodeId\":\($0),\"sortId\":\($0),\"done\":false}" }.joined(separator: ",")
            let value = try XCTUnwrap(FreeExplorationPresentation(snapshot: snapshot(rows)))
            XCTAssertEqual(value.stores.map(\.id), ids); XCTAssertEqual(value.stores.count, count)
            XCTAssertNil(value.total); XCTAssertNil(value.redeemed)
        }
    }
    func testOrientationAndUnregisteredReadCannotBecomeFreeStoreCards() throws {
        XCTAssertNil(FreeExplorationPresentation(snapshot: try snapshot(#"{"nodeId":1,"done":false}"#, mode: 1)))
        let value = try XCTUnwrap(FreeExplorationPresentation(snapshot: snapshot(#"{"nodeId":1,"done":false}"#, registered: false)))
        XCTAssertTrue(value.stores.isEmpty)
    }
    func testOneRemainingFreeStoreDoesNotBecomeNextOrientationTask() throws {
        let row = #"{"nodeId":1,"done":false,"arrived":false}"#
        XCTAssertNil(PlayTaskSummaryPresentation(snapshot: try snapshot(row, total: 1, done: 0)).currentNodeID)
        XCTAssertEqual(PlayTaskSummaryPresentation(snapshot: try snapshot(row, mode: 1, total: 1, done: 0)).currentNodeID, 1)
    }
    func testArrivalOptionalGamePhotoAndRedemptionRemainSeparateFacts() throws {
        let cases: [(String, FreeExplorationPresentation.StoreState)] = [
            (#"{"nodeId":1,"done":false,"arrived":false}"#, .available),
            (#"{"nodeId":1,"done":false,"arrived":true,"gameDone":true}"#, .arrived),
            (#"{"nodeId":1,"done":false,"arrived":true,"selfReported":true}"#, .proofRecorded),
            (#"{"nodeId":1,"done":true,"arrived":true,"selfReported":true}"#, .redeemed)]
        for (row, expected) in cases {
            let value = try snapshot(row)
            XCTAssertEqual(FreeExplorationPresentation.state(of: value.visibleNodes[0], in: value), expected)
        }
    }
    func testOnlyCurrentSourceBackedStoreEvidenceStepsAreEligible() throws {
        let valid: [(String, PlayNodeTask)] = [
            (#"{"nodeId":1,"done":false,"arrived":false,"hasGame":true}"#, .merchantScan),
            (#"{"nodeId":1,"done":false,"arrived":true,"selfReported":false,"hasGame":false}"#, .merchantPhoto),
            (#"{"nodeId":1,"done":false,"arrived":true,"selfReported":false,"hasGame":true,"gameDone":true}"#, .merchantPhoto)]
        for (row, expected) in valid {
            let value = try snapshot(row)
            XCTAssertEqual(FreeExplorationPresentation.evidenceTask(for: value.visibleNodes[0], in: value), expected)
        }
        for row in [#"{"nodeId":1,"done":false}"#, #"{"nodeId":1,"done":false,"arrived":true,"selfReported":false}"#,
                    #"{"nodeId":1,"done":false,"arrived":true,"selfReported":false,"hasGame":true,"gameDone":false}"#,
                    #"{"nodeId":1,"done":true,"arrived":true,"selfReported":true}"#,
                    #"{"nodeId":1,"done":false,"arrived":false,"locked":true}"#] {
            let value = try snapshot(row)
            XCTAssertNil(FreeExplorationPresentation.evidenceTask(for: value.visibleNodes[0], in: value))
        }
    }
    func testPhotoOrConflictingCountersDoNotClaimFullRedemption() throws {
        let row = #"{"nodeId":1,"done":false,"arrived":true,"selfReported":true}"#
        for done in [0, 1, 2] {
            XCTAssertFalse(try XCTUnwrap(FreeExplorationPresentation(snapshot: snapshot(row, total: 1, done: done))).isFullyRedeemed)
        }
        XCTAssertTrue(try XCTUnwrap(FreeExplorationPresentation(snapshot: snapshot(#"{"nodeId":1,"done":true}"#, total: 1, done: 1))).isFullyRedeemed)
    }
}
