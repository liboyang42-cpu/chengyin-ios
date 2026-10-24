import XCTest
@testable import QuestifyCore

final class PlayTaskOutcomePresentationTests: XCTestCase {
    private func snapshot(_ nodes: String, extra: String = "", mode: Int = 1) throws -> PlaySnapshot {
        let raw = "{\"mode\":\(mode),\"playable\":true,\"registered\":true,\"nodes\":[\(nodes)]\(extra)}"
        let result = try JSONDecoder().decode(PlayNodesResult.self, from: Data(raw.utf8))
        return try PlaySnapshot(scope: .activity(41), result: result, authority: result.routeState?.isBranch == true ? result.routeState : nil)
    }
    private func value(_ snapshot: PlaySnapshot?, nodeID: Int = 1, phase: String = "ready", current: Bool = true, unresolved: Bool = false) -> PlayTaskOutcomePresentation {
        .init(snapshot: snapshot, nodeID: nodeID, phase: phase, isCurrentRead: current, unresolved: unresolved)
    }
    func testCurrentIncompleteTaskIsPendingRatherThanSuccess() throws {
        let result = value(try snapshot(#"{"nodeId":1,"done":false}"#))
        XCTAssertEqual(result.state, .pending); XCTAssertEqual(result.continuation, .none)
        XCTAssertNil(result.nextNodeID)
    }
    func testCompletedCurrentTaskShowsOnlyUniqueAvailableNextName() throws {
        let result = value(try snapshot(#"{"nodeId":1,"done":true},{"nodeId":2,"name":"Synthetic next","done":false}"#))
        XCTAssertEqual(result.state, .completed); XCTAssertEqual(result.continuation, .nextTask)
        XCTAssertEqual(result.nextNodeID, 2); XCTAssertEqual(result.nextNodeName, "Synthetic next")
    }
    func testMultipleBranchesRemainAnExplicitChoiceWithoutPickingFirst() throws {
        for nodes in [#"{"nodeId":1,"done":true},{"nodeId":2,"done":false},{"nodeId":3,"done":false}"#,
                      #"{"nodeId":1,"done":true},{"nodeId":3,"done":false},{"nodeId":2,"done":false}"#] {
            let result = value(try snapshot(nodes))
            XCTAssertEqual(result.continuation, .chooseTask); XCTAssertNil(result.nextNodeID); XCTAssertNil(result.nextNodeName)
        }
    }
    func testLockedAndUnknownNodesCannotBeOfferedAsNext() throws {
        let result = value(try snapshot(#"{"nodeId":1,"done":true},{"nodeId":2,"done":false,"locked":true},{"nodeId":3}"#))
        XCTAssertEqual(result.continuation, .overview); XCTAssertNil(result.nextNodeID)
    }
    func testBranchHiddenNodeNameIsNeverExposed() throws {
        let result = value(try snapshot(#"{"nodeId":1,"done":false},{"nodeId":2,"name":"Hidden","done":false},{"nodeId":3,"name":"Visible","done":false}"#,
            extra: #", "routeState":{"routeMode":"BRANCH_GRAPH","sessionId":501,"version":3,"status":"ACTIVE","nodeStates":{"1":"COMPLETED","2":"HIDDEN","3":"PLAYABLE"}}"#))
        XCTAssertEqual(result.state, .completed); XCTAssertEqual(result.nextNodeID, 3)
        XCTAssertEqual(result.nextNodeName, "Visible")
    }
    func testFinishedRequiresExistingAuthoritativeJourneyCompletion() throws {
        let complete = value(try snapshot(#"{"nodeId":1,"done":true}"#, extra: #", "total":1,"doneCount":1"#))
        XCTAssertEqual(complete.continuation, .finished)
        let noTotal = value(try snapshot(#"{"nodeId":1,"done":true}"#))
        XCTAssertEqual(noTotal.continuation, .overview)
    }
    func testReceiptOrStaleSnapshotCannotSupplyCompletion() throws {
        let complete = try snapshot(#"{"nodeId":1,"done":true}"#)
        for phase in ["idle", "future", "ready"] {
            let result = value(complete, phase: phase, current: false)
            XCTAssertNotEqual(result.state, .completed); XCTAssertNil(result.nextNodeID)
        }
        XCTAssertEqual(value(nil).state, .unavailable)
    }
    func testInFlightAndReadbackStatesDoNotBorrowOldCompletedFlags() throws {
        let complete = try snapshot(#"{"nodeId":1,"done":true}"#)
        for (phase, expected) in [("loading", PlayTaskOutcomePresentation.State.loading), ("reviewing", .reviewing), ("submitting", .submitting), ("needsReadback", .needsReadback)] {
            let result = value(complete, phase: phase, unresolved: true)
            XCTAssertEqual(result.state, expected); XCTAssertEqual(result.continuation, .none)
        }
    }
    func testUnresolvedResultRemainsUnknownEvenWithDoneReadback() throws {
        let complete = try snapshot(#"{"nodeId":1,"done":true}"#)
        for phase in ["ready", "failed", "unknown"] {
            let result = value(complete, phase: phase, unresolved: true)
            XCTAssertEqual(result.state, .unknown); XCTAssertNil(result.nextNodeID)
        }
    }
    func testReadFailureIsSeparateFromUnknownMutationOutcome() throws {
        let current = try snapshot(#"{"nodeId":1,"done":false}"#)
        XCTAssertEqual(value(current, phase: "failed").state, .failed)
        XCTAssertEqual(value(current, phase: "unknown").state, .unknown)
    }
    func testAnotherModeOrMissingCurrentNodeCannotLookComplete() throws {
        XCTAssertEqual(value(try snapshot(#"{"nodeId":1,"done":true}"#, mode: 2)).state, .unavailable)
        XCTAssertEqual(value(try snapshot(#"{"nodeId":2,"done":true}"#)).state, .unavailable)
    }
    func testUnavailableRegistrationDoesNotPromoteAnOldDoneFlag() throws {
        let raw = #"{"mode":1,"registered":false,"playable":false,"nodes":[{"nodeId":1,"done":true}]}"#
        let snapshot = try PlaySnapshot(scope: .activity(41), result: JSONDecoder().decode(PlayNodesResult.self, from: Data(raw.utf8)))
        XCTAssertEqual(value(snapshot).state, .unavailable); XCTAssertEqual(value(snapshot).continuation, .none)
    }
}
