import XCTest
@testable import QuestifyCore

final class PlayBranchHistoryTests: XCTestCase {
    private func project(_ log: String? = PlayBranchHistorySyntheticFixtures.recorded) throws -> PlayBranchHistoryPresentation {
        .init(snapshot: try PlayBranchHistorySyntheticFixtures.snapshot(log: log))
    }
    func testAbsentNullWrongShapeAndOversizedHistoryDoNotBreakOldRouteDecode() throws {
        for log in [nil, "null", "{}", "42", "true", "\"bad\""] as [String?] {
            let snapshot = try PlayBranchHistorySyntheticFixtures.snapshot(log: log)
            XCTAssertNil(snapshot.route?.decisionLog)
            XCTAssertEqual(PlayBranchHistoryPresentation(snapshot: snapshot).state, .unavailable)
            XCTAssertEqual(snapshot.route?.sessionID, 501)
        }
        let oversized = "[" + Array(repeating: #"{"fromNodeId":701,"toNodeId":702}"#, count: 201).joined(separator: ",") + "]"
        let snapshot = try PlayBranchHistorySyntheticFixtures.snapshot(log: oversized)
        XCTAssertNil(snapshot.route?.decisionLog)
        XCTAssertEqual(snapshot.route?.version, 2)
    }
    func testExactlyTwoHundredRecordsAcceptedAndNotTruncated() throws {
        let log = "[" + Array(repeating: #"{"fromNodeId":701,"toNodeId":702}"#, count: 200).joined(separator: ",") + "]"
        let value = try project(log)
        XCTAssertEqual(value.rows.count, 200); XCTAssertEqual(value.rows.last?.id, 199)
    }
    func testEmptyIsDifferentFromMissingAndAllMalformed() throws {
        XCTAssertEqual(try project("[]").state, .empty)
        XCTAssertEqual(try project(nil).state, .unavailable)
        let invalid = try project("[null,false,{},[]]")
        XCTAssertEqual(invalid.state, .unavailable); XCTAssertTrue(invalid.containsInvalidEntries)
    }
    func testBadIDsAreSkippedWithoutChangingOtherRouteFacts() throws {
        let invalid = ["0", "-1", "true", "null", "1.5", "\"1e3\"", "\"+1\"", "\" 701 \"", "9223372036854775808", "\"9223372036854775808\""]
        for id in invalid {
            for row in ["{\"fromNodeId\":\(id),\"toNodeId\":702}", "{\"fromNodeId\":701,\"toNodeId\":\(id)}"] {
                let value = try project("[\(row)]")
                XCTAssertTrue(value.rows.isEmpty, row); XCTAssertTrue(value.containsInvalidEntries)
            }
        }
    }
    func testNumericAndDecimalStringIDsAcceptedWithoutIDTitles() throws {
        let value = try project(#"[{"fromNodeId":"701","toNodeId":999}]"#)
        XCTAssertEqual(value.rows.first?.fromName, "Synthetic courtyard / 测试庭院")
        XCTAssertNil(value.rows.first?.toName)
    }
    func testRepeatedEdgesLoopsAndReverseTimestampsKeepServerOrder() throws {
        let value = try project(#"[{"fromNodeId":702,"toNodeId":701,"edgeId":"loop","at":"2026-10-07 09:00:00"},{"fromNodeId":701,"toNodeId":702,"edgeId":"loop","at":"2026-10-07 08:00:00"}]"#)
        XCTAssertEqual(value.rows.map(\.id), [0, 1])
        XCTAssertEqual(value.rows.map(\.fromName), ["Synthetic garden / 测试花园", "Synthetic courtyard / 测试庭院"])
        XCTAssertEqual(value.rows[1].time, "2026-10-07 08:00:00")
    }
    func testInvalidMiddleRowRetainsOriginalServerSequenceNumbers() throws {
        let value = try project(#"[{"fromNodeId":701,"toNodeId":702},null,{"fromNodeId":702,"toNodeId":701}]"#)
        XCTAssertEqual(value.rows.map(\.id), [0, 2]); XCTAssertTrue(value.containsInvalidEntries)
    }
    func testHiddenNodeNeverLeaksNameEvenWhenReferencedByHistory() throws {
        let value = try project()
        XCTAssertNil(value.rows[2].toName)
        XCTAssertFalse(value.rows.contains { $0.fromName == "SECRET HIDDEN NAME" || $0.toName == "SECRET HIDDEN NAME" })
    }
    func testMissingNameLongNameAndControlTextAreNeutral() throws {
        for name in ["", String(repeating: "x", count: 513), "bad\nname"] {
            let route = PlayBranchHistorySyntheticFixtures.route(log: #"[{"fromNodeId":701,"toNodeId":702}]"#)
            let encoded = String(decoding: try JSONEncoder().encode(name), as: UTF8.self)
            let raw = PlayBranchHistorySyntheticFixtures.nodes(route: route).replacingOccurrences(of: "\"Synthetic courtyard / 测试庭院\"", with: encoded)
            let result = try JSONDecoder().decode(PlayNodesResult.self, from: Data(raw.utf8))
            let snap = try PlaySnapshot(scope: .activity(41), result: result, authority: result.routeState)
            XCTAssertNil(PlayBranchHistoryPresentation(snapshot: snap).rows.first?.fromName)
        }
    }
    func testMissingOrMalformedTimesNeverUseNowOrInferCompletion() throws {
        for at in ["null", "false", "0", "-1", "1.5", "253402300800000", "{}", "[]", "\"tomorrow\"", "\"2026-02-30 12:00:00\"", "\"2026-02-30T12:00:00Z\"", "\"2026-10-07T12:00:00\"", "\"1970-01-01 00:00:00\""] {
            let value = try project("[{\"fromNodeId\":701,\"toNodeId\":702,\"at\":\(at)}]")
            XCTAssertEqual(value.rows.count, 1); XCTAssertNil(value.rows[0].time, at)
        }
    }
    func testMillisecondsHaveExplicitUTCAndZoneLessTextStaysVerbatim() throws {
        XCTAssertEqual(try project(#"[{"fromNodeId":701,"toNodeId":702,"at":1000}]"#).rows.first?.time, "1970-01-01 00:00:01 UTC")
        for time in ["2026-10-07 08:30:00", "2026-10-07T08:30:00Z", "2026-10-07T08:30:00.123+08:00"] {
            let value = try project("[{\"fromNodeId\":701,\"toNodeId\":702,\"at\":\"\(time)\"}]")
            XCTAssertEqual(value.rows.first?.time, time)
        }
    }
    func testEdgeIDIsOptionalBoundedAndNotIdentity() throws {
        for edge in ["null", "false", "123", "\"\"", "\"" + String(repeating: "x", count: 129) + "\""] {
            let snapshot = try PlayBranchHistorySyntheticFixtures.snapshot(log: "[{\"fromNodeId\":701,\"toNodeId\":702,\"edgeId\":\(edge)}]")
            XCTAssertNil(snapshot.route?.decisionLog?.entries.first?.edgeID)
            XCTAssertEqual(PlayBranchHistoryPresentation(snapshot: snapshot).rows.count, 1)
        }
    }
    func testNonBranchOrFreeExplorationCannotOpenHistoryEvenWithLog() throws {
        let linear = PlayBranchHistorySyntheticFixtures.route(mode: "LINEAR")
        let raw = PlayBranchHistorySyntheticFixtures.nodes(route: linear)
        let result = try JSONDecoder().decode(PlayNodesResult.self, from: Data(raw.utf8))
        let snapshot = try PlaySnapshot(scope: .activity(41), result: result)
        XCTAssertNil(PlayBranchHistorySelection(snapshot: snapshot)); XCTAssertTrue(PlayBranchHistoryPresentation(snapshot: snapshot).rows.isEmpty)
        let branch = PlayBranchHistorySyntheticFixtures.nodes(route: PlayBranchHistorySyntheticFixtures.route()).replacingOccurrences(of: "\"mode\":1", with: "\"mode\":2")
        let free = try JSONDecoder().decode(PlayNodesResult.self, from: Data(branch.utf8))
        XCTAssertNil(PlayBranchHistorySelection(snapshot: try .init(scope: .activity(41), result: free, authority: free.routeState)))
    }
    func testSelectionRejectsMissingSnapshotOldVersionNewRunAndDifferentScope() throws {
        let old = try PlayBranchHistorySyntheticFixtures.snapshot()
        let selection = try XCTUnwrap(PlayBranchHistorySelection(snapshot: old))
        XCTAssertNotNil(selection.presentation(snapshot: old)); XCTAssertNil(selection.presentation(snapshot: nil))
        for changed in [try PlayBranchHistorySyntheticFixtures.snapshot(version: 3), try PlayBranchHistorySyntheticFixtures.snapshot(sessionID: 502), try PlayBranchHistorySyntheticFixtures.snapshot(scope: .activity(42)), try PlayBranchHistorySyntheticFixtures.snapshot(scope: .topic(71))] {
            XCTAssertNil(selection.presentation(snapshot: changed))
        }
    }
    func testAuthorityHistoryIsNeverMergedWithEarlierNodesRead() throws {
        let result = try PlayBranchHistorySyntheticFixtures.snapshot().result
        let authority = try JSONDecoder().decode(PlayRouteState.self, from: Data(PlayBranchHistorySyntheticFixtures.route(log: "[]", version: 3).utf8))
        let latest = try PlaySnapshot(scope: .activity(41), result: result, authority: authority)
        XCTAssertEqual(PlayBranchHistoryPresentation(snapshot: latest).state, .empty)
        for raw in [PlayBranchHistorySyntheticFixtures.route(version: 1), PlayBranchHistorySyntheticFixtures.route(sessionID: 502)] {
            let mismatch = try JSONDecoder().decode(PlayRouteState.self, from: Data(raw.utf8))
            XCTAssertThrowsError(try PlaySnapshot(scope: .activity(41), result: result, authority: mismatch))
        }
    }
    func testHistoryDoesNotChangeProgressOrAnswerAvailability() throws {
        let snapshot = try PlayBranchHistorySyntheticFixtures.snapshot()
        let before = snapshot.displayedDoneCount
        _ = PlayBranchHistorySelection(snapshot: snapshot)?.presentation(snapshot: snapshot)
        XCTAssertEqual(snapshot.displayedDoneCount, before)
        XCTAssertEqual(snapshot.answerAvailability(for: snapshot.visibleNodes[1]), .branchReadOnly)
    }
}
