import XCTest
@testable import QuestifyCore

final class RunAuthorityContractTests: XCTestCase {
    private func receipt(_ intent: RunActionIntent, decision: String, version: Int64, run: String = "ACTIVE", node: String = "SUCCEEDED", retry: Bool = false, reason: String? = nil, requestId: String? = nil) throws -> RunActionReceipt {
        let reasonField = reason.map { ",\"reasonCode\":\"\($0)\"" } ?? ""
        let json = "{\"runId\":\"\(intent.runId)\",\"requestId\":\"\(requestId ?? intent.requestId)\",\"decision\":\"\(decision)\",\"stateVersion\":\(version),\"runStatus\":\"\(run)\",\"nodeId\":\"\(intent.nodeId)\",\"nodeStatus\":\"\(node)\",\"safeToRetry\":\(retry)\(reasonField)}"
        return try JSONDecoder().decode(RunActionReceipt.self, from: Data(json.utf8))
    }
    private func projection() throws -> RunAuthorityProjection {
        try RunAuthorityProjection(runId: "run-1", stateVersion: 4, status: .active, nodes: ["n1": .available, "n2": .locked])
    }

    func testBodyIsCanonicalAndCarriesNoRewardOrCompletion() throws {
        let intent = try RunActionIntent(runId: "run-1", nodeId: "n1", expectedStateVersion: 4, payload: .choice(optionId: "o1"), requestId: "request-0001")
        let body = String(decoding: try intent.body(), as: UTF8.self)
        XCTAssertEqual(body, "{\"expectedStateVersion\":4,\"kind\":\"CHOICE\",\"nodeId\":\"n1\",\"payload\":{\"optionId\":\"o1\"},\"requestId\":\"request-0001\",\"runId\":\"run-1\",\"schemaVersion\":1}")
        for forbidden in ["reward", "score", "completed", "timestamp"] { XCTAssertFalse(body.contains(forbidden)) }
        XCTAssertThrowsError(try RunActionIntent(runId: "run-1", nodeId: "n1", expectedStateVersion: 4, payload: .answer(text: String(repeating: "x", count: 501))))
    }

    func testLockedNodeAndStaleVersionAreRefusedLocally() throws {
        var run = try projection()
        XCTAssertThrowsError(try run.begin(RunActionIntent(runId: "run-1", nodeId: "n2", expectedStateVersion: 4, payload: .choice(optionId: "o1"))))
        XCTAssertThrowsError(try run.begin(RunActionIntent(runId: "run-1", nodeId: "n1", expectedStateVersion: 3, payload: .choice(optionId: "o1")))) { XCTAssertEqual($0 as? RunAuthorityIssue, .staleVersion) }
    }

    func testUnknownResultKeepsPendingAndSameRequestRetries() throws {
        var run = try projection()
        let intent = try RunActionIntent(runId: "run-1", nodeId: "n1", expectedStateVersion: 4, payload: .choice(optionId: "o1"), requestId: "request-0002")
        try run.begin(intent)
        XCTAssertEqual(try run.resolve(nil), .unknown)
        XCTAssertEqual(run.pending, intent)
        XCTAssertNoThrow(try run.begin(intent)) // exact retry allowed
        let other = try RunActionIntent(runId: "run-1", nodeId: "n1", expectedStateVersion: 4, payload: .choice(optionId: "o2"), requestId: "request-0002")
        XCTAssertThrowsError(try run.begin(other)) { XCTAssertEqual($0 as? RunAuthorityIssue, .payloadConflict) }
        XCTAssertEqual(try run.resolve(receipt(intent, decision: "APPLIED", version: 5)), .applied)
        XCTAssertEqual(run.stateVersion, 5); XCTAssertEqual(run.nodes["n1"], .succeeded); XCTAssertNil(run.pending)
    }

    func testConflictRequestsRefreshAndMismatchedReceiptIsRejected() throws {
        var run = try projection()
        let intent = try RunActionIntent(runId: "run-1", nodeId: "n1", expectedStateVersion: 4, payload: .scan(evidenceRef: "ev-1"), requestId: "request-0003")
        try run.begin(intent)
        XCTAssertThrowsError(try run.resolve(receipt(intent, decision: "APPLIED", version: 5, requestId: "request-9999"))) { XCTAssertEqual($0 as? RunAuthorityIssue, .receiptMismatch) }
        XCTAssertThrowsError(try run.resolve(receipt(intent, decision: "APPLIED", version: 7)))
        XCTAssertEqual(try run.resolve(receipt(intent, decision: "VERSION_CONFLICT", version: 6, node: "AVAILABLE", retry: true)), .refreshRequired(serverVersion: 6))
        XCTAssertEqual(run.stateVersion, 4)
    }

    func testLateSnapshotsAndTerminalOverwritesAreIgnored() throws {
        var run = try RunAuthorityProjection(runId: "run-1", stateVersion: 9, status: .completed, nodes: ["n1": .succeeded])
        XCTAssertFalse(try run.adopt(snapshotVersion: 8, status: .active, nodes: ["n1": .available]))
        XCTAssertThrowsError(try run.adopt(snapshotVersion: 10, status: .active, nodes: ["n1": .available])) { XCTAssertEqual($0 as? RunAuthorityIssue, .terminal) }
        XCTAssertThrowsError(try run.begin(RunActionIntent(runId: "run-1", nodeId: "n1", expectedStateVersion: 9, payload: .choice(optionId: "o1")))) { XCTAssertEqual($0 as? RunAuthorityIssue, .terminal) }
    }
}
