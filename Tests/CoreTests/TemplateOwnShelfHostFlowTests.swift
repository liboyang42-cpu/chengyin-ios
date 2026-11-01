import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

/// Authored runtime coverage for the own-shelf host flow. Apple execution is NOT_RUN here.
@MainActor final class TemplateOwnShelfHostFlowTests: XCTestCase {
    private final class Wire: TemplateAuthoringTransport {
        var authority: TemplateAuthoringAuthority = .injectedHTTP
        var requests: [TemplateAuthoringRequest] = []
        var replies: [Result<(Data, Int), Error>] = []
        func send(_ request: TemplateAuthoringRequest) async throws -> (Data, Int) {
            requests.append(request)
            return try replies.removeFirst().get()
        }
    }
    private func session() throws -> TemplateAuthoringSession {
        try .init(accountID: 7, namespace: "fixture", epoch: 1, authorizationRevision: "player")
    }
    private func page(_ rows: [[String: Any]], total: Int? = nil) throws -> TemplateOwnShelfPage {
        var body: [String: Any] = ["rows": rows]
        if let total { body["total"] = total }
        let data = try JSONSerialization.data(withJSONObject: ["code": 200, "data": body])
        return try TemplateOwnShelfPage.decode(data, httpStatus: 200)
    }
    func testSameMyListResponseKeepsRatingUseCountDurationCreatedAndReason() throws {
        let result = try page([[
            "id": 7, "title": "Owned", "draftStatus": 1, "status": 1, "checkStatus": 1, "publishStatus": 1,
            "rating": 4.5, "useNum": "12", "duration": 0, "createTime": " 2026-10-01 10:00:00 ", "reason": "需补充说明"
        ]])
        XCTAssertEqual(result.rows.first?.publishStatus, 1)
        XCTAssertEqual(result.rowStates[7]?.personal, .approved)
        XCTAssertEqual(result.rowStates[7]?.market, .notSubmitted)
        let facts = try XCTUnwrap(result.cardFacts[7])
        XCTAssertEqual(facts.rating, Decimal(string: "4.5"))
        XCTAssertEqual(facts.useCount, 12)
        XCTAssertEqual(facts.durationMinutes, 0)
        XCTAssertEqual(facts.createTime, "2026-10-01 10:00:00")
        XCTAssertEqual(facts.reviewFeedback, "需补充说明")
        XCTAssertEqual(result.rows.map(\.id), Array(result.cardFacts.keys))
        let plan = TemplateOwnShelfMarketPlan(try XCTUnwrap(result.rowStates[7]))
        XCTAssertEqual(plan.action, .submitReview)
        XCTAssertFalse(plan.isDispatchable)
        XCTAssertNil(plan.action?.publishTarget)
    }
    func testMalformedCardColumnsRemainOnTheLegalRow() throws {
        let result = try page([[
            "id": 7, "title": "Owned", "draftStatus": 1, "status": 1, "checkStatus": 1,
            "rating": "high", "useNum": -1, "reason": "  "
        ], ["id": 8, "title": "Next"]])
        let first = try XCTUnwrap(result.cardFacts[7])
        XCTAssertNil(first.rating); XCTAssertNil(first.useCount); XCTAssertNil(first.reviewFeedback); XCTAssertNil(first.createTime)
        XCTAssertEqual(first.durationMinutes, 0)
        XCTAssertEqual(result.cardFacts[8]?.durationMinutes, 0)
        XCTAssertEqual(Set(result.rows.map(\.id)), Set(result.cardFacts.keys))
        XCTAssertEqual(Set(result.rows.map(\.id)), Set(result.rowStates.keys))
    }
    func testLeaveNewKeywordAndAuthClearCardFactsWithStates() async throws {
        let row: [String: Any] = ["id": 7, "title": "Owned", "draftStatus": 1, "status": 1, "checkStatus": 1,
                                  "rating": 1, "useNum": 3, "reason": "保留"]
        let wire = Wire(); let owner = try session()
        wire.replies = [.success((try JSONSerialization.data(withJSONObject: ["code": 200, "data": ["rows": [row], "total": 1]]), 200))]
        let reader = TemplateOwnShelfReader(adapter: .init(transport: wire), currentSession: { owner })
        await reader.refresh(keyword: "q")
        XCTAssertEqual(reader.cardFacts[7]?.reviewFeedback, "保留")
        XCTAssertEqual(Set(reader.rows.map(\.id)), Set(reader.cardFacts.keys))
        reader.leave()
        XCTAssertTrue(reader.rows.isEmpty); XCTAssertTrue(reader.rowStates.isEmpty); XCTAssertTrue(reader.cardFacts.isEmpty)
        wire.replies = [.success((try JSONSerialization.data(withJSONObject: ["code": 200, "data": ["rows": [row], "total": 1]]), 200)),
                        .failure(APIError.unauthorized)]
        await reader.refresh(keyword: "q")
        XCTAssertFalse(reader.cardFacts.isEmpty)
        await reader.refresh(keyword: "other")
        XCTAssertTrue(reader.cardFacts.isEmpty); XCTAssertTrue(reader.rowStates.isEmpty)
    }
    func testPersonalPublishStatusDoesNotDispatchTheMarketplacePlan() throws {
        let listed = try page([[
            "id": 9, "title": "Owned", "draftStatus": 0, "publishStatus": 1,
            "marketTemplateId": 90, "marketStatus": 1, "marketPublishStatus": 1, "reason": "个人反馈"
        ]])
        let plan = TemplateOwnShelfMarketPlan(try XCTUnwrap(listed.rowStates[9]))
        XCTAssertEqual(plan.action, .delist)
        XCTAssertEqual(plan.action?.publishTarget, 0)
        XCTAssertFalse(plan.isDispatchable)
        XCTAssertEqual(listed.rows.first?.publishStatus, 1)
        XCTAssertEqual(listed.cardFacts[9]?.reviewFeedback, "个人反馈")
        XCTAssertEqual(listed.rowStates[9]?.market, .listed)
    }
}
