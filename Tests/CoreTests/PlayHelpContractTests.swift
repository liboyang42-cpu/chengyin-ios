import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

/// F01 hint ladder + F02 wrong-answer reply contracts. Synthetic fixtures only.
@available(macOS 14.0, *)
@MainActor final class PlayHelpContractTests: XCTestCase {
    private let scope = PlayHelpScope.run(runID: 5001, nodeID: 31)

    private func wire(_ json: String) throws -> PlayWireValue {
        try JSONDecoder().decode(PlayWireValue.self, from: Data(json.utf8))
    }
    private func service(_ transport: PlayHelpTestTransport, enabled: Set<PlayHelpCapability> = [.read, .use, .skip]) throws -> PlayHelpService {
        .init(configuration: try APIConfiguration(baseURL: URL(string: "https://example.com/fixture/")!), transport: transport, enabled: enabled)
    }
    private static let ladder = #"{"code":200,"data":{"runId":5001,"nodeId":31,"enabled":true,"remainingFreeUses":0,"layers":["#
        + #"{"level":1,"type":"TEXT","usable":true,"unlocked":true,"free":true,"costPoints":0},"#
        + #"{"level":2,"type":"TEXT","usable":true,"unlocked":false,"free":false,"costPoints":0},"#
        + #"{"level":3,"type":"ANSWER","usable":true,"unlocked":false,"free":false,"costPoints":0},"#
        + #"{"level":4,"type":"SKIP","usable":true,"unlocked":false,"free":false,"costPoints":0}]}}"#

    func testViewKeepsAuthorOrderAndSeparatesSkip() throws {
        let view = try PlayHelpView(wire(Self.ladder)["data"])
        XCTAssertTrue(view.enabled)
        XCTAssertEqual(view.rows.map(\.level), [1, 2, 3])
        XCTAssertEqual(view.rows.map(\.state), [.review, .free, .gated])
        XCTAssertEqual(view.skipLevel, 4)
        XCTAssertEqual(view.remainingFreeUses, 0)
        XCTAssertTrue(view.rows[2].isAnswer)
    }

    func testPoolTrimLayerIsARequestableHintRow() throws {
        let view = try PlayHelpView(wire(#"{"enabled":true,"layers":["#
            + #"{"level":1,"type":"POOL_TRIM","usable":true,"unlocked":false,"free":true,"costPoints":0},"#
            + #"{"level":2,"type":"ANSWER","usable":true,"unlocked":false,"free":false,"costPoints":0}]}"#))
        XCTAssertEqual(view.rows.map(\.type), ["POOL_TRIM", "ANSWER"])
        XCTAssertEqual(view.rows.first?.state, .free)
        XCTAssertTrue(PlayHelpView.renderableTypes.contains("POOL_TRIM"))
    }

    func testDisabledViewHasNoRowsAndUnknownCounterIsNil() throws {
        let view = try PlayHelpView(wire(#"{"enabled":false,"layers":[]}"#))
        XCTAssertFalse(view.enabled); XCTAssertTrue(view.rows.isEmpty); XCTAssertNil(view.skipLevel); XCTAssertNil(view.remainingFreeUses)
        XCTAssertThrowsError(try PlayHelpView(.string("x")))
    }

    func testDefaultServiceIsDormant() async throws {
        let transport = PlayHelpTestTransport { _ in XCTFail("dormant service sent a request"); return (Data(), 200) }
        do { _ = try await service(transport, enabled: []).view(scope: scope, token: "synthetic-token"); XCTFail() }
        catch { XCTAssertEqual(error as? PlayExperienceError, .disabled) }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testUseSendsExactJSONAndReadsServerContent() async throws {
        let transport = PlayHelpTestTransport { _ in
            (Data(#"{"code":200,"data":{"level":2,"type":"TEXT","content":"示例提示","applied":true,"alreadyUnlocked":false,"chargedPoints":0}}"#.utf8), 200)
        }
        let receipt = try await service(transport).use(scope: scope, level: 2, requestID: "habcdef0123456789", token: "synthetic-token")
        XCTAssertEqual(receipt.content, "示例提示")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/fixture/api/play/help/use")
        XCTAssertEqual(request.httpMethod, "POST")
        let body = try JSONDecoder().decode(PlayWireValue.self, from: request.httpBody!)
        XCTAssertEqual(body["runId"], .int(5001)); XCTAssertEqual(body["nodeId"], .int(31))
        XCTAssertEqual(body["level"], .int(2)); XCTAssertEqual(body["action"], .string("HELP"))
        XCTAssertEqual(body["requestId"], .string("habcdef0123456789"))
    }

    func testAdvancedScopeUsesAdvancedRoutesAndSessionField() async throws {
        let transport = PlayHelpTestTransport { _ in (Data(#"{"code":200,"data":{"skipped":true,"score":0,"completionMode":"SKIPPED"}}"#.utf8), 200) }
        let receipt = try await service(transport).skip(scope: .advanced(sessionID: 77, nodeID: 31), requestID: "habcdef0123456789", token: "synthetic-token")
        XCTAssertEqual(receipt.score, 0); XCTAssertEqual(receipt.completionMode, "SKIPPED")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/fixture/api/play/help/advanced/skip")
        let body = try JSONDecoder().decode(PlayWireValue.self, from: request.httpBody!)
        XCTAssertEqual(body["sessionId"], .int(77)); XCTAssertEqual(body["runId"], .null)
    }

    func testOutOfOrderRefusalIsShownAndReleasesTheRequestID() async throws {
        let transport = PlayHelpTestTransport { request in
            if request.httpMethod == "GET" { return (Data(Self.ladder.utf8), 200) }
            return (Data(#"{"code":400,"msg":"请先查看上一层提示","reasonCode":"LEVEL_OUT_OF_ORDER"}"#.utf8), 200)
        }
        let help = PlayHelpCoordinator(scope: scope, service: try service(transport), token: { "synthetic-token" })
        await help.load()
        let gated = try XCTUnwrap(help.view?.rows.first { $0.level == 2 })
        await help.use(gated)
        XCTAssertEqual(help.notice, "请先查看上一层提示")
        XCTAssertNil(help.contents[2])
        XCTAssertTrue(help.unknownLevels.isEmpty)
    }

    func testLostResponseRetriesWithTheSameRequestID() async throws {
        var calls = 0
        let transport = PlayHelpTestTransport { request in
            if request.httpMethod == "GET" { return (Data(Self.ladder.utf8), 200) }
            calls += 1
            if calls == 1 { throw URLError(.networkConnectionLost) }
            return (Data(#"{"code":200,"data":{"level":2,"type":"TEXT","content":"示例提示","applied":false,"alreadyUnlocked":true,"chargedPoints":0}}"#.utf8), 200)
        }
        let help = PlayHelpCoordinator(scope: scope, service: try service(transport), token: { "synthetic-token" })
        await help.load()
        let row = try XCTUnwrap(help.view?.rows.first { $0.level == 2 })
        await help.use(row)
        XCTAssertEqual(help.unknownLevels, [2])
        await help.use(row)
        XCTAssertEqual(help.contents[2], "示例提示")
        let ids = transport.requests.filter { $0.httpMethod == "POST" }.compactMap { request -> PlayWireValue? in
            try? JSONDecoder().decode(PlayWireValue.self, from: request.httpBody ?? Data())
        }.map { $0["requestId"] }
        XCTAssertEqual(ids.count, 2); XCTAssertEqual(ids[0], ids[1])
    }

    func testLedgerKeepsOneIDUntilSettled() {
        var ledger = PlayHelpRequestLedger()
        let first = ledger.requestID(scope, operation: "skip", level: 0)
        XCTAssertEqual(ledger.requestID(scope, operation: "skip", level: 0), first)
        XCTAssertTrue(PlayHelpService.validRequestID(first))
        ledger.settle(scope, operation: "skip", level: 0)
        XCTAssertNil(ledger.pendingID(scope, operation: "skip", level: 0))
        XCTAssertNotEqual(ledger.requestID(scope, operation: "skip", level: 0), first)
    }

    func testNoRightAnswerChoiceReadsAsRecordedOnlyForJudgeFalsePick() throws {
        XCTAssertTrue(PlayKitNoRightAnswer.applies(kind: .qa, segment: try wire(#"{"mode":"PICK","judge":false}"#)))
        XCTAssertFalse(PlayKitNoRightAnswer.applies(kind: .qa, segment: try wire(#"{"mode":"PICK"}"#)))
        XCTAssertFalse(PlayKitNoRightAnswer.applies(kind: .qa, segment: try wire(#"{"mode":"TYPE","judge":false}"#)))
        XCTAssertFalse(PlayKitNoRightAnswer.applies(kind: .branch, segment: try wire(#"{"mode":"PICK","judge":false}"#)))
    }

    func testWrongReplyIsShownOnlyAfterAWrongTry() throws {
        XCTAssertEqual(PlayKitWrongReply.text(segment: try wire(#"{"attempts":1,"passed":false,"lastFeedback":"前两个字母对了"}"#)), "前两个字母对了")
        XCTAssertNil(PlayKitWrongReply.text(segment: try wire(#"{"attempts":0,"lastFeedback":"x"}"#)))
        XCTAssertNil(PlayKitWrongReply.text(segment: try wire(#"{"attempts":2,"passed":true,"lastFeedback":"x"}"#)))
        XCTAssertNil(PlayKitWrongReply.text(segment: try wire(#"{"attempts":2,"passed":false,"lastFeedback":"  "}"#)))
    }
}

private final class PlayHelpTestTransport: HTTPTransport {
    private let reply: (URLRequest) throws -> (Data, Int)
    private(set) var requests: [URLRequest] = []
    init(_ reply: @escaping (URLRequest) throws -> (Data, Int)) { self.reply = reply }
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return try reply(request) }
}
