import XCTest
@testable import QuestifyCore

final class PlayContractTests: XCTestCase {
    private func decodeResult(_ json: String) throws -> PlayNodesResult { try JSONDecoder().decode(PlayNodesResult.self, from: Data(json.utf8)) }
    private func makeSnapshot(node: String, extras: String = "") throws -> PlaySnapshot {
        let value = try decodeResult("{\"topicId\":71,\"mode\":1,\"playable\":true,\"nodes\":[\(node)]\(extras)}")
        return try PlaySnapshot(scope: .activity(41), result: value)
    }
    func testSparseFactsRemainUnknownRatherThanInventingZeroOrCompletion() throws {
        let result = try decodeResult(#"{"nodes":[{"nodeId":7}]}"#)
        XCTAssertNil(result.playable); XCTAssertNil(result.total); XCTAssertNil(result.registered)
        XCTAssertNil(result.nodes[0].done); XCTAssertNil(result.nodes[0].xp); XCTAssertNil(result.nodes[0].durationMinutes)
        XCTAssertFalse(result.allDone)
        XCTAssertEqual(try PlaySnapshot(scope: .activity(41), result: result).availability, .unknown)
    }
    func testMissingNullMalformedAndDuplicateNodesAreNotEmptyStates() {
        for raw in [#"{}"#, #"{"nodes":null}"#, #"{"nodes":{}}"#, #"{"nodes":[null]}"#,
                    #"{"nodes":[{"nodeId":0}]}"#, #"{"nodes":[{"nodeId":7},{"nodeId":7}]}"#] {
            XCTAssertThrowsError(try decodeResult(raw), raw)
        }
        XCTAssertNoThrow(try decodeResult(#"{"nodes":[]}"#))
    }
    func testNumericStringsAndDocumentedBooleanRepresentations() throws {
        let result = try decodeResult(#"{"mode":"1","playable":"true","registered":"0","total":"2","doneCount":1,"nodes":[{"nodeId":"7","done":1,"arrived":"1","locked":false,"duration":"12"}]}"#)
        XCTAssertEqual(result.mode, 1); XCTAssertEqual(result.playable, true); XCTAssertNil(result.registered)
        XCTAssertEqual(result.nodes[0].done, true); XCTAssertEqual(result.nodes[0].durationMinutes, 12)
        XCTAssertThrowsError(try self.decodeResult(#"{"nodes":[{"nodeId":true}]}"#))
        XCTAssertThrowsError(try self.decodeResult(#"{"playable":"sometimes","nodes":[]}"#))
    }
    func testRegistrationPrecedesEmptyAndExpirationTextIsNotLocallyInterpreted() throws {
        let result = try decodeResult(#"{"registered":false,"playable":false,"nodes":[],"expiresAt":"2001-01-01 00:00:00"}"#)
        let snapshot = try PlaySnapshot(scope: .activity(41), result: result)
        XCTAssertEqual(snapshot.availability, .registrationRequired)
        XCTAssertEqual(result.expiresAt, "2001-01-01 00:00:00")
        let playable = try self.decodeResult(#"{"playable":true,"nodes":[{"nodeId":7}],"expiresAt":"2001-01-01"}"#)
        XCTAssertEqual(try PlaySnapshot(scope: .activity(41), result: playable).availability, .active)
    }
    func testExactTopicIdentityAndInvalidScopeFailClosed() throws {
        let data = try decodeResult(#"{"topicId":71,"nodes":[]}"#)
        XCTAssertThrowsError(try PlaySnapshot(scope: .topic(72), result: data))
        XCTAssertThrowsError(try PlaySnapshot(scope: .activity(0), result: data))
        XCTAssertEqual(PlaySessionScope.activity(41).fields, ["activityId": "41"])
        XCTAssertEqual(PlaySessionScope.topic(71).fields, ["topicId": "71"])
    }
    func testEligibleTextAndChoiceUseServerQuestionAndExactOptionKey() throws {
        let text = try makeSnapshot(node: #"{"nodeId":7,"done":false,"validationMethod":1,"question":"Question"}"#)
        XCTAssertEqual(text.answerAvailability(for: text.result.nodes[0]), .text)
        XCTAssertNoThrow(try text.validateAnswer(nodeID: 7, answer: "My own answer"))
        XCTAssertThrowsError(try text.validateAnswer(nodeID: 7, answer: " \n "))
        let choice = try makeSnapshot(node: #"{"nodeId":7,"done":false,"validationMethod":3,"question":"Pick","options":{"A":"First","B":"Second"}}"#)
        XCTAssertNoThrow(try choice.validateAnswer(nodeID: 7, answer: "A"))
        XCTAssertThrowsError(try choice.validateAnswer(nodeID: 7, answer: "First"))
        XCTAssertThrowsError(try choice.validateAnswer(nodeID: 8, answer: "A"))
    }
    func testPrerequisiteMatrixNeverFallsBackToManufacturedProof() throws {
        let cases: [(String, PlayAnswerAvailability)] = [
            (#""locked":true"#, .locked), (#""needGps":true,"arrived":false"#, .arrivalRequired),
            (#""needScan":true"#, .arrivalRequired), (#""advancedConfigJson":{"timer":{"enabled":true}}"#, .advancedRequired),
            (#""advancedConfigJson":"broken-config""#, .advancedRequired),
            (#""questionAudio":"fixture-audio""#, .mediaUnavailable)
        ]
        for (extra, expected) in cases {
            let snapshot = try makeSnapshot(node: "{\"nodeId\":7,\"done\":false,\"validationMethod\":1,\"question\":\"Question\",\(extra)}")
            XCTAssertEqual(snapshot.answerAvailability(for: snapshot.result.nodes[0]), expected)
            XCTAssertThrowsError(try snapshot.validateAnswer(nodeID: 7, answer: "answer"))
        }
        for method in [0, 2, 4, 5, 6, 7, 99] {
            let snapshot = try makeSnapshot(node: "{\"nodeId\":7,\"done\":false,\"validationMethod\":\(method),\"needAnswer\":true,\"question\":\"Question\"}")
            XCTAssertEqual(snapshot.answerAvailability(for: snapshot.result.nodes[0]), .unsupported)
        }
    }
    func testBranchAuthorityHidesUnknownNodesPreservesLocksAndRejectsOtherSession() throws {
        let routeJSON = #"{"routeMode":"BRANCH_GRAPH","sessionId":99,"version":4,"status":"ACTIVE","nodeStates":{"7":"PLAYABLE","8":"DISCOVERED_LOCKED","9":"HIDDEN","10":"FUTURE"},"lockReasons":{"8":"Server lock reason"}}"#
        let data = try decodeResult("{\"mode\":1,\"playable\":true,\"nodes\":[{\"nodeId\":7,\"done\":false,\"validationMethod\":1,\"question\":\"Q\"},{\"nodeId\":8},{\"nodeId\":9},{\"nodeId\":10}],\"routeState\":\(routeJSON)}")
        let authority = try JSONDecoder().decode(PlayRouteState.self, from: Data(routeJSON.utf8))
        XCTAssertThrowsError(try PlaySnapshot(scope: .activity(41), result: data))
        let snapshot = try PlaySnapshot(scope: .activity(41), result: data, authority: authority)
        XCTAssertEqual(snapshot.visibleNodes.map(\.id), [7, 8])
        XCTAssertEqual(snapshot.answerAvailability(for: snapshot.visibleNodes[0]), .branchReadOnly)
        XCTAssertEqual(snapshot.lockReason(snapshot.visibleNodes[1]), "Server lock reason")
        let changed = try JSONDecoder().decode(PlayRouteState.self, from: Data(routeJSON.replacingOccurrences(of: "99", with: "100").utf8))
        XCTAssertThrowsError(try PlaySnapshot(scope: .activity(41), result: data, authority: changed))
        let older = try JSONDecoder().decode(PlayRouteState.self, from: Data(routeJSON.replacingOccurrences(of: "\"version\":4", with: "\"version\":3").utf8))
        XCTAssertThrowsError(try PlaySnapshot(scope: .activity(41), result: data, authority: older))
    }
    func testUnknownRouteStatusAndCompletedRoutesDoNotAcceptAnswers() throws {
        for status in ["COMPLETED", "EXPIRED", "FUTURE"] {
            let raw = "{\"mode\":1,\"playable\":true,\"routeState\":{\"routeMode\":\"BRANCH_GRAPH\",\"sessionId\":99,\"status\":\"\(status)\",\"version\":1,\"nodeStates\":{\"7\":\"PLAYABLE\"}},\"nodes\":[{\"nodeId\":7,\"done\":false,\"question\":\"Q\",\"validationMethod\":1}]}"
            let data = try decodeResult(raw)
            let snapshot = try PlaySnapshot(scope: .activity(41), result: data, authority: data.routeState)
            XCTAssertEqual(snapshot.availability, status == "COMPLETED" ? .completed : .unavailable)
            XCTAssertThrowsError(try snapshot.validateAnswer(nodeID: 7, answer: "answer"))
        }
    }
    func testReceiptXPAndCompletionStayUnknownWhenNotReported() throws {
        let receipt = try JSONDecoder().decode(PlayAnswerReceipt.self, from: Data(#"{"nodeId":7}"#.utf8))
        XCTAssertNil(receipt.xp); XCTAssertNil(receipt.completed); XCTAssertNil(receipt.firstTime)
        let legacy = try JSONDecoder().decode(PlayAnswerReceipt.self, from: Data(#"{"nodeId":7,"score":"0"}"#.utf8))
        XCTAssertEqual(legacy.xp, 0)
    }
}
