import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

/// Authored runtime coverage. Apple compilation/execution is NOT_RUN in this workspace.
@MainActor final class TemplateOwnShelfStateProjectionTests: XCTestCase {
    private final class Wire: TemplateAuthoringTransport {
        var authority: TemplateAuthoringAuthority = .injectedHTTP
        var requests: [TemplateAuthoringRequest] = []
        var replies: [Result<(Data, Int), Error>] = []
        var pending: [CheckedContinuation<(Data, Int), Error>] = []
        var onPending: (() -> Void)?
        func send(_ request: TemplateAuthoringRequest) async throws -> (Data, Int) {
            requests.append(request)
            if !replies.isEmpty { return try replies.removeFirst().get() }
            return try await withCheckedThrowingContinuation { pending.append($0); onPending?() }
        }
    }
    private func session(_ epoch: UInt64 = 1, role: String = "player") throws -> TemplateAuthoringSession {
        try .init(accountID: 7, namespace: "fixture", epoch: epoch, authorizationRevision: role)
    }
    private func row(_ id: Int = 7, market: Int = 0, published: Int = 0, reason: String? = nil) -> [String: Any] {
        var value: [String: Any] = ["id": id, "title": "Same owned row", "draftStatus": 1,
            "status": 1, "checkStatus": 1, "publishStatus": 0,
            "marketTemplateId": id + 100, "marketStatus": market, "marketPublishStatus": published]
        if let reason { value["marketReason"] = reason }
        return value
    }
    private func response(_ rows: [[String: Any]], total: Int? = nil) throws -> (Data, Int) {
        var body: [String: Any] = ["rows": rows]
        if let total { body["total"] = total }
        return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": body]), 200)
    }
    private func page(_ rows: [[String: Any]]) throws -> TemplateOwnShelfPage {
        let value = try response(rows)
        return try TemplateOwnShelfPage.decode(value.0, httpStatus: value.1)
    }
    private func projection(_ value: [String: Any]) throws -> TemplateOwnShelfStateProjection {
        try JSONDecoder().decode(TemplateOwnShelfStateProjection.self, from: JSONSerialization.data(withJSONObject: value))
    }
    private func paused(_ reader: TemplateOwnShelfReader, wire: Wire, keyword: String = "q") async -> Task<Void, Never> {
        let reached = expectation(description: "owned shelf read paused")
        wire.onPending = { reached.fulfill() }
        let task = Task { await reader.refresh(keyword: keyword) }
        await fulfillment(of: [reached], timeout: 2)
        wire.onPending = nil
        return task
    }
    private func assertPaired(_ reader: TemplateOwnShelfReader, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Set(reader.rows.map(\.id)), Set(reader.rowStates.keys), file: file, line: line)
    }
    func testActualMiniCounterexamplesSeparatePersonalAndMarketplaceStates() throws {
        let rejected = try page([["id": 41, "draftStatus": 1, "status": 2, "checkStatus": 2,
            "publishStatus": 1, "marketTemplateId": NSNull()]])
        XCTAssertEqual(rejected.rowStates[41]?.personal, .rejected)
        XCTAssertEqual(rejected.rowStates[41]?.market, .notSubmitted)
        let online = try page([row(42, market: 1, published: 1)])
        XCTAssertEqual(online.rows.first?.publishStatus, 0)
        XCTAssertEqual(online.rowStates[42]?.personal, .approved)
        XCTAssertEqual(online.rowStates[42]?.market, .listed)
    }
    func testPersonalReviewPrecedenceMatchesSourceMatrix() throws {
        for draft in 0...3 { for status in 0...3 { for check in 0...3 {
            let value = try projection(["draftStatus": draft, "status": status, "checkStatus": check])
            let expected: TemplateOwnShelfStateProjection.Personal
            if draft == 0 { expected = .draft }
            else if draft == 1 && status == 1 && check == 1 { expected = .approved }
            else if draft == 1 && (status == 2 || check == 2) { expected = .rejected }
            else if draft == 1 && (status == 0 || check == 0) { expected = .reviewing }
            else { expected = .unknown }
            XCTAssertEqual(value.personal, expected, "\(draft),\(status),\(check)")
        } } }
        XCTAssertEqual(try projection([:]).personal, .unknown)
        XCTAssertEqual(try projection(["draftStatus": 1, "status": 1]).personal, .unknown)
    }
    func testMarketplaceMatrixIgnoresPersonalPublishStatus() throws {
        for legacy in 0...1 { for status in 0...3 { for publish in 0...3 {
            let value = try projection(["publishStatus": legacy, "marketTemplateId": 99,
                "marketStatus": status, "marketPublishStatus": publish])
            let expected: TemplateOwnShelfStateProjection.Market = status == 0 ? .reviewing :
                status == 1 && publish == 1 ? .listed : status == 1 && publish == 0 ? .unlisted :
                status == 2 ? .rejected : .unknown
            XCTAssertEqual(value.market, expected)
        } } }
    }
    func testCanonicalOptionalTextAndMissingFieldsRemainCompatible() throws {
        var value = row(market: 1, published: 1)
        for key in ["draftStatus", "checkStatus", "marketTemplateId", "marketStatus", "marketPublishStatus"] {
            value[key] = String(describing: value[key]!)
        }
        let result = try page([value, ["id": 8]])
        XCTAssertEqual(result.rowStates[7]?.personal, .approved); XCTAssertEqual(result.rowStates[7]?.market, .listed)
        XCTAssertEqual(result.rowStates[8]?.personal, .unknown); XCTAssertEqual(result.rowStates[8]?.market, .notSubmitted)
        for id in [NSNull(), 0, "0"] as [Any] {
            XCTAssertEqual(try projection(["marketTemplateId": id]).market, .notSubmitted)
        }
        XCTAssertEqual(TemplateOwnShelfStateProjection.unknown.market, .unknown)
    }
    func testMalformedOptionalColumnsNeverInvalidateAnOtherwiseLegalRow() throws {
        let malformed: [Any] = [true, false, "", " ", "01", "1.0", "1e0", -1, 0.5, ["future": 1], [1], NSNull()]
        for raw in malformed {
            var value = row(market: 1, published: 1)
            value["draftStatus"] = raw; value["checkStatus"] = raw; value["marketStatus"] = raw
            value["marketPublishStatus"] = raw; value["marketReason"] = raw
            let result = try page([value])
            XCTAssertEqual(result.rows.map(\.id), [7]); XCTAssertEqual(result.rowStates.count, 1)
            XCTAssertEqual(result.rowStates[7]?.personal, .unknown); XCTAssertEqual(result.rowStates[7]?.market, .unknown)
        }
        for raw in [true, false, "", " ", "01", "1.0", "1e0", -1, 0.5, ["future": 1], [1]] as [Any] {
            var value = row(market: 1, published: 1); value["marketTemplateId"] = raw
            let result = try page([value])
            XCTAssertEqual(result.rows.map(\.id), [7]); XCTAssertEqual(result.rowStates[7]?.market, .unknown)
        }
    }
    func testPartialMetadataDecodingDoesNotDropOtherFieldsOrOtherRows() throws {
        var first = row(7, market: 1, published: 1, reason: "Keep this feedback")
        first["checkStatus"] = ["future": true]
        var second = row(8, market: 1, published: 1); second["marketTemplateId"] = [99]
        let result = try page([first, second, ["id": 9]])
        XCTAssertEqual(result.rows.map(\.id), [7, 8, 9])
        XCTAssertEqual(result.rowStates[7]?.personal, .unknown); XCTAssertEqual(result.rowStates[7]?.market, .listed)
        XCTAssertEqual(result.rowStates[7]?.marketReason, "Keep this feedback")
        XCTAssertEqual(result.rowStates[8]?.personal, .approved); XCTAssertEqual(result.rowStates[8]?.market, .unknown)
        XCTAssertEqual(result.rowStates[9]?.market, .notSubmitted)
    }
    func testExistingBaseDTOValidationIsNotRelaxedByTolerantDisplayColumns() throws {
        for bad in [["id": 7, "status": "1"], ["id": 7, "publishStatus": false], ["id": 0], ["id": 7, "useNum": -1]] as [[String: Any]] {
            XCTAssertThrowsError(try page([bad]))
        }
        XCTAssertThrowsError(try page([row(7), row(7)]))
        XCTAssertThrowsError(try page((1...11).map { row($0) }))
    }
    func testMarketIdentityLongBoundsAreReadFromOriginalBytesWithoutCoercion() throws {
        for literal in ["9223372036854775807", "\"9223372036854775807\""] {
            let raw = "{\"code\":200,\"data\":{\"rows\":[{\"id\":7,\"marketTemplateId\":\(literal),\"marketStatus\":1,\"marketPublishStatus\":1}]}}"
            let result = try TemplateOwnShelfPage.decode(Data(raw.utf8), httpStatus: 200)
            XCTAssertEqual(result.rowStates[7]?.market, .listed)
        }
        for literal in ["9223372036854775808", "\"9223372036854775808\"", "\"999999999999999999999999999999\""] {
            let raw = "{\"code\":200,\"data\":{\"rows\":[{\"id\":7,\"marketTemplateId\":\(literal),\"marketStatus\":1,\"marketPublishStatus\":1}]}}"
            let result = try TemplateOwnShelfPage.decode(Data(raw.utf8), httpStatus: 200)
            XCTAssertEqual(result.rows.map(\.id), [7]); XCTAssertEqual(result.rowStates[7]?.market, .unknown)
        }
    }
    func testFeedbackIsVerbatimOptionalTextAndNeverAnAction() throws {
        let reason = "  **Review** [text](https://example.test)\n请完善来源说明  "
        XCTAssertEqual(try projection(["marketReason": reason]).marketReason, reason)
        for invalid in ["", " \n ", 1, true, ["url": "https://example.test"], ["text"], NSNull()] as [Any] {
            XCTAssertNil(try projection(["marketReason": invalid]).marketReason)
        }
        let names = Set(Mirror(reflecting: try projection(row())).children.compactMap(\.label))
        XCTAssertEqual(names, ["personal", "market", "marketReason"])
    }
    func testSameIDsAndEqualBaseRowsStillReplaceChangedDisplayStates() async throws {
        let wire = Wire(), owner = try session()
        wire.replies = [.success(try response([row(market: 0)], total: 1)),
                        .success(try response([row(market: 1, published: 1, reason: "New feedback")], total: 1))]
        let reader = TemplateOwnShelfReader(adapter: .init(transport: wire), currentSession: { owner })
        await reader.refresh(keyword: "q"); let rows = reader.rows, states = reader.rowStates
        await reader.refresh(keyword: "q")
        XCTAssertEqual(reader.rows, rows); XCTAssertNotEqual(reader.rowStates, states)
        XCTAssertEqual(reader.rowStates[7]?.market, .listed); XCTAssertEqual(reader.rowStates[7]?.marketReason, "New feedback")
        XCTAssertFalse(reader.isShowingRefreshSnapshot); assertPaired(reader)
    }
    func testTransientRefreshRetainsStatesWithRowsAndRetryReplacesBoth() async throws {
        for failure in [URLError(.timedOut), APIError.httpStatus(503)] as [Error] {
            let wire = Wire(), owner = try session(); wire.replies = [.success(try response([row(market: 0)], total: 1))]
            let reader = TemplateOwnShelfReader(adapter: .init(transport: wire), currentSession: { owner })
            await reader.refresh(keyword: "q"); let rows = reader.rows, states = reader.rowStates
            let task = await paused(reader, wire: wire)
            XCTAssertEqual(reader.rows, rows); XCTAssertEqual(reader.rowStates, states); assertPaired(reader)
            try XCTUnwrap(wire.pending.first).resume(throwing: failure); await task.value
            XCTAssertEqual(reader.rowStates, states); XCTAssertTrue(reader.isShowingRefreshSnapshot); assertPaired(reader)
            await reader.loadMore(); XCTAssertEqual(wire.requests.count, 2)
            wire.replies = [.success(try response([row(market: 2, reason: "Resubmit")], total: 1))]
            await reader.refresh(keyword: "q")
            XCTAssertEqual(reader.rowStates[7]?.market, .rejected); XCTAssertEqual(reader.rowStates[7]?.marketReason, "Resubmit")
            assertPaired(reader)
        }
    }
    func testEmptyFirstPageClearsRowsAndDisplayStatesTogether() async throws {
        let wire = Wire(), owner = try session(); wire.replies = [.success(try response([row()])), .success(try response([], total: 0))]
        let reader = TemplateOwnShelfReader(adapter: .init(transport: wire), currentSession: { owner })
        await reader.refresh(); await reader.refresh()
        XCTAssertTrue(reader.rows.isEmpty); XCTAssertTrue(reader.rowStates.isEmpty); XCTAssertFalse(reader.isShowingRefreshSnapshot)
    }
    func testOverlappingContinuationCannotPartiallyReplaceOrAppendStates() async throws {
        let wire = Wire(), owner = try session()
        wire.replies = [.success(try response((1...10).map { row($0) })),
                        .success(try response([row(10, market: 2, reason: "Must not replace"), row(11)])),
                        .success(try response([row(11, market: 1, published: 1)]))]
        let reader = TemplateOwnShelfReader(adapter: .init(transport: wire), currentSession: { owner })
        await reader.refresh(); let states = reader.rowStates
        await reader.loadMore(); XCTAssertEqual(reader.rowStates, states); XCTAssertNil(reader.rowStates[11]); assertPaired(reader)
        await reader.loadMore(); XCTAssertEqual(reader.rowStates[11]?.market, .listed); XCTAssertEqual(reader.rowStates[10], states[10])
        XCTAssertEqual(wire.requests[1], wire.requests[2]); assertPaired(reader)
    }
    func testAuthContractAndCancellationErrorsClearEveryCachedState() async throws {
        let errors: [Error] = [APIError.unauthorized, APIError.httpStatus(403), TemplateAuthoringError.invalidContract,
            TemplateAuthoringRejection(message: "denied", code: 503), CancellationError(), URLError(.cancelled)]
        for failure in errors {
            let wire = Wire(), owner = try session(); wire.replies = [.success(try response([row()])), .failure(failure)]
            let reader = TemplateOwnShelfReader(adapter: .init(transport: wire), currentSession: { owner })
            await reader.refresh(); await reader.refresh()
            XCTAssertTrue(reader.rows.isEmpty); XCTAssertTrue(reader.rowStates.isEmpty); assertPaired(reader)
        }
        let wire = Wire(), owner = try session()
        wire.replies = [.success(try response((1...10).map { row($0) })), .failure(APIError.httpStatus(403))]
        let reader = TemplateOwnShelfReader(adapter: .init(transport: wire), currentSession: { owner })
        await reader.refresh(); await reader.loadMore(); XCTAssertTrue(reader.rowStates.isEmpty); assertPaired(reader)
    }
    func testMalformedBaseRowsClearStatesWithoutCommittingPartialPage() async throws {
        let wire = Wire(), owner = try session()
        wire.replies = [.success(try response([row()])), .success(try response([row(8), row(8)]))]
        let reader = TemplateOwnShelfReader(adapter: .init(transport: wire), currentSession: { owner })
        await reader.refresh(); await reader.refresh()
        XCTAssertTrue(reader.rows.isEmpty); XCTAssertTrue(reader.rowStates.isEmpty)
    }
    func testNewKeywordCannotRetainOldStateWhenRequestFails() async throws {
        let wire = Wire(), owner = try session(); wire.replies = [.success(try response([row()]))]
        let reader = TemplateOwnShelfReader(adapter: .init(transport: wire), currentSession: { owner })
        await reader.refresh(keyword: "q")
        let task = await paused(reader, wire: wire, keyword: "other")
        XCTAssertTrue(reader.rows.isEmpty); XCTAssertTrue(reader.rowStates.isEmpty)
        try XCTUnwrap(wire.pending.first).resume(throwing: URLError(.timedOut)); await task.value
        XCTAssertTrue(reader.rowStates.isEmpty); assertPaired(reader)
    }
    func testOldSuccessAndErrorCannotOverwriteNewSameIDState() async throws {
        for fails in [false, true] {
            let wire = Wire(), owner = try session(); wire.replies = [.success(try response([row()]))]
            let reader = TemplateOwnShelfReader(adapter: .init(transport: wire), currentSession: { owner })
            await reader.refresh(keyword: "q")
            let old = await paused(reader, wire: wire), new = await paused(reader, wire: wire)
            try XCTUnwrap(wire.pending.last).resume(returning: response([row(market: 1, published: 1)])); await new.value
            if fails { try XCTUnwrap(wire.pending.first).resume(throwing: APIError.httpStatus(503)) }
            else { try XCTUnwrap(wire.pending.first).resume(returning: response([row(market: 2)])) }
            await old.value; XCTAssertEqual(reader.rowStates[7]?.market, .listed); assertPaired(reader)
        }
    }
    func testScopeTransitionsABARevocationLeaveAndCancelRetireStates() async throws {
        for transition in ["owner", "epoch", "roleABA", "sessionABA", "revoke", "leave", "cancel"] {
            for fails in [false, true] {
                let wire = Wire(); wire.replies = [.success(try response([row()]))]
                let original = try session(); var owner: TemplateAuthoringSession? = original
                let reader = TemplateOwnShelfReader(adapter: .init(transport: wire), currentSession: { owner })
                await reader.refresh(keyword: "q"); let task = await paused(reader, wire: wire)
                switch transition {
                case "owner": owner = nil
                case "epoch": owner = try session(2)
                case "roleABA": owner = try session(role: "merchant"); reader.synchronizeSession(); owner = original; reader.synchronizeSession()
                case "sessionABA": owner = nil; reader.synchronizeSession(); owner = original; reader.synchronizeSession()
                case "revoke": wire.authority = .disabled
                case "leave": reader.leave()
                default: task.cancel()
                }
                if fails { try XCTUnwrap(wire.pending.first).resume(throwing: APIError.httpStatus(503)) }
                else { try XCTUnwrap(wire.pending.first).resume(returning: response([row(market: 1, published: 1)])) }
                await task.value; XCTAssertTrue(reader.rows.isEmpty, transition); XCTAssertTrue(reader.rowStates.isEmpty, transition)
            }
        }
    }
    func testAlreadyCancelledRefreshCannotDispatchOrKeepSidecars() async throws {
        let wire = Wire(), owner = try session(); wire.replies = [.success(try response([row()]))]
        let reader = TemplateOwnShelfReader(adapter: .init(transport: wire), currentSession: { owner })
        await reader.refresh(keyword: "q")
        let task = Task { await reader.refresh(keyword: "q") }; task.cancel(); await task.value
        XCTAssertEqual(wire.requests.count, 1); XCTAssertTrue(reader.rowStates.isEmpty); assertPaired(reader)
    }
    func testDisplayMetadataNeverChangesSharedDTOOrAcknowledgesPendingMutation() throws {
        let before = try page([row(market: 0)]), after = try page([row(market: 1, published: 1, reason: "Fresh")])
        XCTAssertEqual(before.rows, after.rows); XCTAssertNotEqual(before.rowStates, after.rowStates)
        let review = try TemplateOwnShelfReview(row: XCTUnwrap(before.rows.first), action: .remove, session: session(), generation: 0)
        let pending = TemplateOwnShelfPending(review: review)
        XCTAssertFalse(pending.matchesAcknowledgedReadback(after.rows)); XCTAssertFalse(pending.matchesAcknowledgedReadback([]))
        XCTAssertEqual(review.request, TemplateAuthoringContract.remove(id: review.templateID))
    }
}
