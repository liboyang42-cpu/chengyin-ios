import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// BK-LIKE: explicit `type` on every `/api/topic/like`, settled only by a fresh readback.
/// Synthetic accounts and topic IDs only; nothing is sent.
@MainActor final class TopicLikeDirectionTests: XCTestCase {
    private let base = URL(string: "https://example.com/fixture")!
    private func factory() throws -> TopicLikeOperationFactory { .init(configuration: try .init(baseURL: base)) }
    private func body(_ request: URLRequest) -> String { String(data: request.httpBody ?? Data(), encoding: .utf8) ?? "" }
    private func scope(_ account: Int = 11, epoch: UInt64 = 1) throws -> TopicLikeScope {
        try .init(accountID: account, epoch: epoch, namespace: "synthetic-like")
    }
    private let ok = Data(#"{"code":200,"msg":"点赞成功"}"#.utf8)

    func testEveryDirectionSendsAnExplicitTypeNeverTheLegacyDefault() throws {
        let cases: [(TopicLikeDirection, String)] = [(.like, "1"), (.unlike, "0")]
        for (direction, field) in cases {
            let r = try factory().request(topicID: 201, direction: direction, token: "synthetic-only")
            XCTAssertEqual(r.url, base.appendingPathComponent("api/topic/like")); XCTAssertEqual(r.httpMethod, "POST")
            XCTAssertTrue(body(r).contains("name=\"id\"\r\n\r\n201\r\n"))
            XCTAssertTrue(body(r).contains("name=\"type\"\r\n\r\n\(field)\r\n"), "type=\(field) must be explicit")
            XCTAssertEqual(body(r).components(separatedBy: "name=\"type\"").count, 2)
        }
        XCTAssertEqual(TopicLikeDirection(liked: true), .like); XCTAssertEqual(TopicLikeDirection(liked: false), .unlike)
        XCTAssertThrowsError(try factory().request(topicID: 0, direction: .like, token: "synthetic-only"))
        XCTAssertThrowsError(try factory().request(topicID: 201, direction: .like, token: " "))
    }
    func testAcknowledgementCarriesNoLikeStateAndUncertaintyIsUnknown() {
        XCTAssertEqual(TopicLikeWriteOutcome.decode(data: ok, status: 200), .acknowledged)
        XCTAssertEqual(TopicLikeWriteOutcome.decode(data: Data(#"{"code":500,"msg":"主题不存在"}"#.utf8), status: 200), .rejected("主题不存在"))
        XCTAssertEqual(TopicLikeWriteOutcome.decode(data: Data(#"{"code":401}"#.utf8), status: 200), .unauthorized)
        XCTAssertEqual(TopicLikeWriteOutcome.decode(data: Data(), status: 401), .unauthorized)
        XCTAssertEqual(TopicLikeWriteOutcome.decode(data: Data("<html>".utf8), status: 200), .unknown)
        XCTAssertEqual(TopicLikeWriteOutcome.decode(data: ok, status: 502), .unknown)
    }
    func testLikeUnlikeLikeSettlesOnlyThroughReadback() throws {
        let ledger = TopicLikeLedger(), s = try scope()
        for direction in [TopicLikeDirection.like, .unlike, .like] {
            let write = try XCTUnwrap(ledger.begin(topicID: 201, direction: direction, scope: s))
            XCTAssertEqual(ledger.states[201], .sending(direction))
            XCTAssertTrue(ledger.complete(write, outcome: .acknowledged, scope: s))
            XCTAssertEqual(ledger.states[201], .awaitingReadback(direction))
            XCTAssertNil(ledger.confirmedLiked(topicID: 201), "An acknowledgement is not server truth")
            let read = try XCTUnwrap(ledger.beginReadback(topicID: 201, scope: s))
            XCTAssertTrue(ledger.observe(read, liked: direction.liked, scope: s))
            XCTAssertEqual(ledger.confirmedLiked(topicID: 201), direction.liked)
        }
    }
    func testDuplicateTapOfPendingDirectionIsCoalesced() throws {
        let ledger = TopicLikeLedger(), s = try scope()
        let first = try XCTUnwrap(ledger.begin(topicID: 201, direction: .like, scope: s))
        XCTAssertNil(ledger.begin(topicID: 201, direction: .like, scope: s))
        ledger.complete(first, outcome: .acknowledged, scope: s)
        XCTAssertNil(ledger.begin(topicID: 201, direction: .like, scope: s), "Same direction awaiting readback")
        XCTAssertNotNil(ledger.begin(topicID: 202, direction: .like, scope: s), "Other topics are independent")
    }
    func testOutOfOrderResponsesNeverSettleOnTheOlderIntent() throws {
        let ledger = TopicLikeLedger(), s = try scope()
        let like = try XCTUnwrap(ledger.begin(topicID: 201, direction: .like, scope: s))
        let unlike = try XCTUnwrap(ledger.begin(topicID: 201, direction: .unlike, scope: s))
        XCTAssertTrue(ledger.complete(unlike, outcome: .acknowledged, scope: s))
        // The older like is still in flight: a read now cannot tell which request the server saw last.
        let early = try XCTUnwrap(ledger.beginReadback(topicID: 201, scope: s))
        XCTAssertFalse(ledger.complete(like, outcome: .acknowledged, scope: s), "Superseded response is ignored")
        XCTAssertEqual(ledger.states[201], .awaitingReadback(.unlike))
        XCTAssertFalse(ledger.observe(early, liked: false, scope: s))
        // Server applied the older like last: the readback wins and the mismatch is surfaced.
        let read = try XCTUnwrap(ledger.beginReadback(topicID: 201, scope: s))
        XCTAssertTrue(ledger.observe(read, liked: true, scope: s))
        XCTAssertEqual(ledger.states[201], .mismatch(requested: .unlike, liked: true))
        XCTAssertEqual(ledger.confirmedLiked(topicID: 201), true)
    }
    func testReadStartedBeforeANewerWriteIsRejected() throws {
        let ledger = TopicLikeLedger(), s = try scope()
        let read = try XCTUnwrap(ledger.beginReadback(topicID: 201, scope: s))
        let write = try XCTUnwrap(ledger.begin(topicID: 201, direction: .like, scope: s))
        ledger.complete(write, outcome: .acknowledged, scope: s)
        XCTAssertFalse(ledger.observe(read, liked: false, scope: s))
        XCTAssertEqual(ledger.states[201], .awaitingReadback(.like))
    }
    func testUnknownOutcomeBlocksResendUntilReadbackAndRejectionIsDefinite() throws {
        let ledger = TopicLikeLedger(), s = try scope()
        let write = try XCTUnwrap(ledger.begin(topicID: 201, direction: .unlike, scope: s))
        ledger.complete(write, outcome: .unknown, scope: s)
        XCTAssertNil(ledger.begin(topicID: 201, direction: .unlike, scope: s))
        XCTAssertNil(ledger.begin(topicID: 201, direction: .like, scope: s))
        let read = try XCTUnwrap(ledger.beginReadback(topicID: 201, scope: s))
        XCTAssertTrue(ledger.observe(read, liked: false, scope: s))
        XCTAssertEqual(ledger.states[201], .confirmed(liked: false))
        let rejected = try XCTUnwrap(ledger.begin(topicID: 201, direction: .like, scope: s))
        ledger.complete(rejected, outcome: .rejected("主题不存在"), scope: s)
        XCTAssertEqual(ledger.states[201], .rejected(.like, message: "主题不存在"))
        XCTAssertNotNil(ledger.begin(topicID: 201, direction: .like, scope: s))
    }
    func testAccountOrEpochSwitchDropsStateAndLateResponses() throws {
        for replacement in [try scope(12), try scope(epoch: 2)] {
            let ledger = TopicLikeLedger(), s = try scope()
            let write = try XCTUnwrap(ledger.begin(topicID: 201, direction: .like, scope: s))
            let read = try XCTUnwrap(ledger.beginReadback(topicID: 202, scope: s))
            XCTAssertFalse(ledger.complete(write, outcome: .acknowledged, scope: replacement))
            XCTAssertFalse(ledger.observe(read, liked: true, scope: replacement))
            XCTAssertTrue(ledger.states.isEmpty); XCTAssertNil(ledger.confirmedLiked(topicID: 201))
            XCTAssertNotNil(ledger.begin(topicID: 201, direction: .like, scope: replacement))
            XCTAssertEqual(ledger.scope, replacement)
            XCTAssertFalse(ledger.complete(write, outcome: .acknowledged, scope: replacement), "Old account ticket stays dead")
            XCTAssertEqual(ledger.states[201], .sending(.like))
        }
    }
    func testSignedOutOrUnauthorizedClearsEverything() throws {
        let ledger = TopicLikeLedger(), s = try scope()
        XCTAssertNil(ledger.begin(topicID: 201, direction: .like, scope: nil))
        let write = try XCTUnwrap(ledger.begin(topicID: 201, direction: .like, scope: s))
        ledger.complete(write, outcome: .unauthorized, scope: s)
        XCTAssertTrue(ledger.states.isEmpty); XCTAssertNil(ledger.scope)
    }
}
