import XCTest
@testable import Questify

/// Runs against the actual coordinator after integration.patch is applied.
/// Sealed in-process recorder only; no production or network transport.
@MainActor final class PlayQATextReceiptRecoveryTests: XCTestCase {
    private let route = "/api/play/advanced/receipt"
    private func session(_ account: Int = 7) throws -> PlayExperienceSession {
        try .init(accountID: account, epoch: 1, namespace: "synthetic-qa-receipt", token: "synthetic-receipt-token")
    }
    private func state(version: Int = 2) -> PlayWireValue {
        .object(["sessionId": .int(1), "activityId": .int(41), "topicId": .int(71), "nodeId": .int(701),
                 "version": .int(version), "status": .string("RUNNING"),
                 "playKit": .object(["qa": .object(["mode": .string("TYPE"), "passed": .bool(false), "attempts": .int(version - 2)])])])
    }
    private func reply(_ data: PlayWireValue, code: Int = 200) throws -> Data {
        try JSONEncoder().encode(PlayWireValue.object(["code": .int(code), "data": data]))
    }
    private func unknown(_ wire: PlayRecoveryRecordingTransport, current: @escaping () -> PlayExperienceSession?) async throws -> PlayAdvancedCoordinator {
        wire.responses["/api/play/advanced/start"] = .reply(try reply(state()), 200)
        wire.responses["/api/play/advanced/action"] = .failure(.unknownResult)
        let service = PlayExperienceService(configuration: try .init(baseURL: URL(string: "https://example.com")!), transport: wire, enabled: [.reads, .advanced])
        let model = PlayAdvancedCoordinator(activityID: 41, topicID: 71, nodeID: 701, service: service, currentSession: current)
        await model.start()
        let review = try model.review(kind: "qa", action: "SUBMIT_QA", detail: ["input": .string("Synthetic frozen answer")])
        _ = await model.submit(review)
        XCTAssertEqual(model.phase, "unknown")
        return model
    }
    private func receipt(_ pending: PlayAdvancedPending, key: String? = nil) -> PlayWireValue {
        .object(["sessionId": .string("1"), "idempotencyKey": .string(key ?? pending.key), "view": state(version: 3)])
    }
    func testUnknownUsesOriginalReceiptGETAndServerVerdictWithoutAnotherPOST() async throws {
        let current = try session(), wire = PlayRecoveryRecordingTransport()
        let model = try await unknown(wire, current: { current }), pending = try XCTUnwrap(model.pending)
        wire.responses[route] = .reply(try reply(receipt(pending)), 200)
        await model.recover()
        XCTAssertNil(model.pending); XCTAssertEqual(model.phase, "ready")
        XCTAssertEqual(model.state?.playKit["qa"]["passed"].bool, false)
        let request = try XCTUnwrap(wire.requests.last)
        XCTAssertEqual(request.httpMethod, "GET"); XCTAssertNil(request.httpBody)
        XCTAssertEqual(request.url?.path, route)
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(Set(query?.map(\.name) ?? []), ["sessionId", "idempotencyKey"])
        XCTAssertEqual(query?.first { $0.name == "idempotencyKey" }?.value, pending.key)
        XCTAssertEqual(wire.requests.filter { $0.httpMethod == "POST" }.count, 2)
    }
    func test404409AndMalformedReceiptRetainExactPendingUntilMatchedReceiptArrives() async throws {
        let current = try session(), wire = PlayRecoveryRecordingTransport()
        let model = try await unknown(wire, current: { current }), pending = try XCTUnwrap(model.pending)
        for response in [try reply(.null, code: 404), try reply(.null, code: 409), try reply(receipt(pending, key: "other"))] {
            wire.responses[route] = .reply(response, 200)
            await model.recover()
            XCTAssertEqual(model.pending, pending); XCTAssertEqual(model.phase, "unknown")
            XCTAssertEqual(model.state?.version, 2)
        }
        wire.responses[route] = .reply(try reply(receipt(pending)), 200)
        await model.recover()
        XCTAssertNil(model.pending); XCTAssertEqual(model.phase, "ready")
        XCTAssertEqual(wire.requests.filter { $0.httpMethod == "POST" }.count, 2)
    }
    func testAccountSwitchBlocksReadAndKeepsOriginalUnknownRequest() async throws {
        var current: PlayExperienceSession? = try session()
        let wire = PlayRecoveryRecordingTransport(), model = try await unknown(wire, current: { current })
        let pending = try XCTUnwrap(model.pending), count = wire.requests.count
        current = try session(8)
        await model.recover(); await model.retryExact()
        XCTAssertEqual(wire.requests.count, count); XCTAssertEqual(model.pending, pending)
        XCTAssertFalse(model.isCurrent)
    }
    func testOwnerWithdrawalDuringReceiptReadCannotInstallOrDiscardOriginalPending() async throws {
        var current: PlayExperienceSession? = try session()
        let wire = PlayRecoveryRecordingTransport(), model = try await unknown(wire, current: { current })
        let pending = try XCTUnwrap(model.pending)
        wire.responses[route] = .reply(try reply(receipt(pending)), 200); wire.pauseResponse = true
        let task = Task { await model.recover() }
        while !wire.isAwaitingResponse { await Task.yield() }
        current = nil; wire.resumeResponse(); await task.value
        XCTAssertEqual(model.pending, pending); XCTAssertEqual(model.phase, "stale"); XCTAssertNil(model.state)
        XCTAssertEqual(wire.requests.filter { $0.httpMethod == "POST" }.count, 2)
    }
    func testCurrent401WithdrawsViewButRetainsOriginalPending() async throws {
        let current = try session(), wire = PlayRecoveryRecordingTransport()
        let model = try await unknown(wire, current: { current }), pending = try XCTUnwrap(model.pending)
        wire.responses[route] = .reply(try reply(.null, code: 401), 200)
        await model.recover()
        XCTAssertEqual(model.pending, pending); XCTAssertEqual(model.phase, "stale"); XCTAssertNil(model.state)
    }
}
