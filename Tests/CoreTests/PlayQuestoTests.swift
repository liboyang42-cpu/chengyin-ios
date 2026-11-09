import XCTest
@testable import QuestifyCore

/// Synthetic payloads shaped like the integrate/questo-ui-20261110 controllers. No live backend.
final class PlayQuestoTests: XCTestCase {
    private func wire(_ json: String) throws -> PlayWireValue { try JSONDecoder().decode(PlayWireValue.self, from: Data(json.utf8)) }
    private func layer(_ level: Int, _ type: String, usable: Bool = true, unlocked: Bool = false, free: Bool = false, cost: Int = 0, reason: String = "OK") -> String {
        #"{"level":\#(level),"type":"\#(type)","usable":\#(usable),"unlocked":\#(unlocked),"free":\#(free),"costPoints":\#(cost),"freeQuota":0,"reason":"\#(reason)"}"#
    }

    // MARK: Help ladder

    func testLayersRenderInAuthorOrderWithThreeButtonStatesAndReviewIsFree() throws {
        let view = try PlayHelpView(data: wire(#"{"runId":9,"nodeId":3,"enabled":true,"layers":[\#(layer(1, "TEXT", unlocked: true, free: true)),\#(layer(2, "LETTER", free: true)),\#(layer(3, "ANSWER", cost: 40)),\#(layer(4, "SKIP"))]}"#))
        XCTAssertEqual(view.layers.map(\.level), [1, 2, 3, 4])
        XCTAssertEqual(view.hintLayers.map(\.level), [1, 2, 3])
        XCTAssertEqual(view.state(of: view.layers[0]), .review)
        XCTAssertEqual(view.state(of: view.layers[1]), .free)
        XCTAssertEqual(view.state(of: view.layers[2]), .needsPrevious)
        XCTAssertEqual(view.state(of: view.layers[3]), .unavailable(nil), "SKIP is never a hint button")
        XCTAssertTrue(view.skipAvailable)
    }
    func testCostShownOnlyWhenEarlierLayersAreUnlocked() throws {
        let view = try PlayHelpView(data: wire(#"{"runId":9,"nodeId":3,"enabled":true,"layers":[\#(layer(1, "TEXT", unlocked: true)),\#(layer(2, "ANSWER", cost: 30))]}"#))
        XCTAssertEqual(view.state(of: view.layers[1]), .cost(30))
        XCTAssertFalse(view.skipAvailable, "no SKIP layer, no skip button")
    }
    func testUnknownTypeAndServerReasonAreUnavailableNotGuessed() throws {
        let view = try PlayHelpView(data: wire(#"{"runId":9,"nodeId":3,"enabled":true,"layers":[\#(layer(1, "LOCATION", usable: false, reason: "LOCATION_TOOLS_NOT_WIRED")),\#(layer(2, "HOLOGRAM"))]}"#))
        XCTAssertEqual(view.state(of: view.layers[0]), .unavailable("LOCATION_TOOLS_NOT_WIRED"))
        XCTAssertEqual(view.state(of: view.layers[1]), .unavailable(nil))
    }
    func testDisabledLadderKeepsLegacyEntryAndMismatchIsMalformed() throws {
        let off = try PlayHelpView(data: wire(#"{"runId":9,"nodeId":3,"enabled":false,"layers":[]}"#))
        XCTAssertFalse(off.enabled); XCTAssertTrue(off.layers.isEmpty)
        XCTAssertThrowsError(try PlayHelpView(data: wire(#"{"runId":9,"nodeId":3,"enabled":true,"layers":[]}"#)))
        XCTAssertThrowsError(try PlayHelpView(data: wire(#"{"runId":9,"nodeId":3,"enabled":true,"layers":[\#(layer(1, "TEXT")),\#(layer(1, "TEXT"))]}"#)))
    }
    func testUseReceiptShowsChargeOnlyWhenChargedAndReplayIsZeroCost() throws {
        let replay = try PlayHelpUse(data: wire(#"{"runId":9,"nodeId":3,"level":2,"type":"LETTER","content":"E","applied":false,"alreadyUnlocked":true,"chargedPoints":0,"balanceAfter":120}"#))
        XCTAssertFalse(replay.showsCharge); XCTAssertEqual(replay.content, "E")
        let paid = try PlayHelpUse(data: wire(#"{"runId":9,"nodeId":3,"level":3,"type":"ANSWER","content":"ENDLESS","applied":true,"alreadyUnlocked":false,"chargedPoints":20,"balanceAfter":100}"#))
        XCTAssertTrue(paid.showsCharge); XCTAssertEqual(paid.balanceAfter, 100)
    }
    func testNotScoredReceiptNeverShowsZero() throws {
        let receipt = try PlayHelpReceipt(data: wire(#"{"scoreState":"NOT_SCORED","baseScore":null,"bonus":null,"helpDeduction":null,"skipDeduction":null,"netScore":null,"pointsCharged":20,"skipped":false,"assisted":false,"reason":"NO_BASE_SCORE","levels":[{"level":1,"type":"TEXT","free":false,"pointsCharged":20}]}"#))
        XCTAssertFalse(receipt.showsScore); XCTAssertNil(receipt.netScore); XCTAssertEqual(receipt.pointsCharged, 20); XCTAssertEqual(receipt.levels.count, 1)
        let skipped = try PlayHelpReceipt(data: wire(#"{"scoreState":"SCORED","baseScore":100,"bonus":0,"helpDeduction":0,"skipDeduction":100,"netScore":0,"pointsCharged":0,"skipped":true,"assisted":true,"levels":[]}"#))
        XCTAssertTrue(skipped.showsScore); XCTAssertEqual(skipped.netScore, 0); XCTAssertTrue(skipped.skipped)
    }
    func testIntentLedgerReusesRequestIdUntilSettled() {
        var ledger = PlayHelpIntentLedger(); let intent = PlayHelpIntentLedger.Intent(runID: 9, nodeID: 3, level: 2)
        var n = 0; let make = { () -> String in n += 1; return "id-\(n)" }
        let first = ledger.requestID(for: intent, make: make)
        XCTAssertEqual(ledger.requestID(for: intent, make: make), first, "unknown result re-checks with the same id")
        ledger.settle(intent)
        XCTAssertNotEqual(ledger.requestID(for: intent, make: make), first)
    }

    @MainActor private final class Recorder: HTTPTransport {
        var replies: [(Data, Int)] = []; var requests: [URLRequest] = []; var fail = false
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request); if fail { throw URLError(.timedOut) }; return replies.removeFirst()
        }
    }
    @MainActor func testServiceIsDefaultOffAndTimeoutIsUnknownWithSameRequestId() async throws {
        let transport = Recorder(); let config = try APIConfiguration(baseURL: URL(string: "https://example.com/native")!)
        let off = PlayHelpService(configuration: config, transport: transport)
        do { _ = try await off.view(.route(runID: 9), nodeID: 3, token: "synthetic-token"); XCTFail() } catch { XCTAssertEqual(error as? PlayExperienceError, .disabled) }
        XCTAssertTrue(transport.requests.isEmpty)
        let on = PlayHelpService(configuration: config, transport: transport, enabled: true)
        transport.fail = true
        let outcome = try await on.use(.route(runID: 9), nodeID: 3, level: 2, requestID: "abc-1", token: "synthetic-token")
        XCTAssertEqual(outcome, .unknown(requestID: "abc-1"))
        let body = try JSONDecoder().decode(PlayWireValue.self, from: transport.requests[0].httpBody!)
        XCTAssertEqual(body["action"].text, "HELP"); XCTAssertEqual(body["requestId"].text, "abc-1")
        XCTAssertEqual(transport.requests[0].url?.path, "/native/api/play/help/use")
    }
    @MainActor func testPointsInsufficientIsARefusalWithReasonCodeAndAdvancedRouteIsSeparate() async throws {
        let transport = Recorder(); let config = try APIConfiguration(baseURL: URL(string: "https://example.com/native")!)
        transport.replies = [(Data(#"{"code":400,"msg":"积分不足","reasonCode":"POINTS_INSUFFICIENT"}"#.utf8), 200)]
        let service = PlayHelpService(configuration: config, transport: transport, enabled: true)
        let outcome = try await service.use(.advanced(sessionID: 5), nodeID: 3, level: 1, requestID: "abc-2", token: "synthetic-token")
        guard case .refused(let refusal) = outcome else { return XCTFail() }
        XCTAssertTrue(refusal.pointsInsufficient); XCTAssertEqual(refusal.message, "积分不足")
        XCTAssertEqual(transport.requests[0].url?.path, "/native/api/play/help/advanced/use")
    }

    // MARK: Gameplay

    func testHangmanProjectionAndPayloadsNeverCarryTheAnswer() throws {
        let p = try PlayHangmanProjection(raw: wire(#"{"length":7,"blankCount":5,"caseSensitive":false,"solved":false,"display":"E_____S","slots":[{"i":0,"ch":"E","kind":"PREFILLED"},{"i":1,"kind":"BLANK"},{"i":2,"kind":"BLANK"},{"i":3,"kind":"BLANK"},{"i":4,"kind":"BLANK"},{"i":5,"kind":"BLANK"},{"i":6,"ch":"S","kind":"PREFILLED"}]}"#))
        XCTAssertNil(p.answerText); XCTAssertEqual(p.slots.filter { $0.kind == .blank }.count, 5)
        XCTAssertEqual(try p.inputPayload(" NDLES "), ["input": .string("NDLES")])
        XCTAssertEqual(try p.slotPayload([1: "N"]), ["slots": .object(["1": .string("N")])])
        XCTAssertThrowsError(try p.slotPayload([0: "X"]), "prefilled slot is not editable")
        XCTAssertThrowsError(try p.slotPayload([1: "NN"]))
        XCTAssertEqual(try PlayKitActionCatalog.payload(kind: "hangman", action: "SUBMIT_HANGMAN", detail: p.inputPayload("NDLES")), ["input": .string("NDLES")])
        XCTAssertThrowsError(try PlayKitActionCatalog.payload(kind: "hangman", action: "SUBMIT_HANGMAN", detail: [:]))
    }
    func testHangmanSolvedReceiptShowsServerAnswerAndCJKSlots() throws {
        let p = try PlayHangmanProjection(raw: wire(#"{"length":3,"blankCount":1,"caseSensitive":false,"solved":true,"display":"城瘾王","verdict":"CORRECT","answerText":"城瘾王","slots":[{"i":0,"ch":"城","kind":"PREFILLED"},{"i":1,"ch":"瘾","kind":"FILLED"},{"i":2,"ch":"王","kind":"PREFILLED"}]}"#))
        XCTAssertEqual(p.verdict, .correct); XCTAssertEqual(p.answerText, "城瘾王")
        XCTAssertThrowsError(try p.inputPayload("x"), "solved: no further submission")
    }
    func testOptionImagesAcceptOnlyHttpsOrSitePathsAndFallBackToText() throws {
        let base = URL(string: "https://example.com/native")!
        let ok = try PlayChoiceOption(raw: wire(#"{"id":"a","label":"Nicolas","img":"https://cdn.example.com/a.jpg","alt":"red coat"}"#), baseURL: base)
        XCTAssertEqual(ok.imageURL?.host, "cdn.example.com"); XCTAssertEqual(ok.accessibilityLabel, "Nicolas，red coat")
        for bad in ["http://x.com/a.jpg", "//x.com/a.jpg", "data:image/png;base64,AA", "media-asset:12", "a\\b.jpg"] {
            let option = try PlayChoiceOption(raw: .object(["id": .string("b"), "label": .string("B"), "img": .string(bad)]), baseURL: base)
            XCTAssertNil(option.imageURL, bad)
        }
        XCTAssertEqual(try PlayChoiceOption(raw: wire(#"{"id":"c","label":"C","img":"/media/c.jpg"}"#), baseURL: base).imageURL?.absoluteString, "https://example.com/media/c.jpg")
    }
    func testAccusationThreeEndingsAndNoGuessing() throws {
        let view = try PlayAccusationView(raw: wire(#"{"enabled":true,"suspects":[{"id":"a","name":"Ada","identity":"Butler","testimony":[{"key":"clue.a","text":"Saw the door"}]},{"id":"b","name":"Bo"}],"earlyAccuse":{"allowed":true}}"#), baseURL: nil)
        XCTAssertEqual(view.suspects.map(\.id), ["a", "b"]); XCTAssertEqual(view.suspects[1].testimony, []); XCTAssertTrue(view.earlyAccuseAllowed)
        XCTAssertFalse(PlayAccusationOutcome.decided(try wire(#"{"enabled":true}"#)))
        XCTAssertEqual(PlayAccusationOutcome(accusation: try wire(#"{"result":{"verdict":"CORRECT","early":false},"screen":"Case closed text"}"#)).ending, .solved)
        let early = PlayAccusationOutcome(accusation: try wire(#"{"result":{"verdict":"CORRECT","early":true}}"#))
        XCTAssertEqual(early.ending, .closedEarly); XCTAssertFalse(early.celebrates, "closed early is not a success")
        XCTAssertEqual(PlayAccusationOutcome(accusation: try wire(#"{"result":{"verdict":"WRONG","canRetry":true},"screen":"lose"}"#)).screenText, nil)
        XCTAssertEqual(PlayAccusationOutcome(accusation: try wire(#"{"result":{"verdict":"FAILED"},"screen":"lose"}"#)).screenText, "lose")
        XCTAssertEqual(PlayAccusationOutcome(accusation: try wire(#"{"result":{"verdict":"MAYBE"}}"#)).ending, .confirming)
        XCTAssertEqual(PlayAccusationOutcome.confirming.ending, .confirming)
    }
    func testClueTransformDefaultsToStandard() throws {
        XCTAssertEqual(PlayClueTransform(raw: try wire(#"{"mode":"MIRROR"}"#)), .mirror)
        XCTAssertEqual(PlayClueTransform(raw: try wire(#"{"mode":"CYPHER"}"#)), .standard)
        XCTAssertEqual(PlayClueTransform(raw: .null), .standard)
    }

    // MARK: Arrival and capability

    func testArrivalRefusalUsesStableCodesAndServerFlags() throws {
        let refusal = try XCTUnwrap(PlayArrivalRefusal(envelope: wire(#"{"code":500,"msg":"还没到这一站附近","errorCode":"ARRIVE_TOO_FAR","retryable":true,"arrivalReasonCode":"ARRIVE_TOO_FAR","canRetry":true,"approvedFallbacks":["12","12","13"]}"#)))
        XCTAssertEqual(refusal.reason, .tooFar); XCTAssertTrue(refusal.canRetry); XCTAssertEqual(refusal.approvedFallbackNodeIDs, ["12", "13"])
        XCTAssertNil(PlayArrivalRefusal(envelope: try wire(#"{"code":500,"msg":"x"}"#)))
        XCTAssertEqual(PlayArrivalReason(code: "ARRIVE_NEW_THING"), .other("ARRIVE_NEW_THING"))
    }
    func testArrivalReadingPlaysOncePerReceipt() throws {
        XCTAssertNil(PlayArrivalReading(data: try wire(#"{"arrivalReading":{"level":4,"log":"x"}}"#)))
        XCTAssertEqual(PlayArrivalReading(data: try wire(#"{"arrivalReading":{"level":2,"log":"风从站台尽头吹来"}}"#))?.level, 2)
        var ledger = PlayArrivalReadingLedger()
        XCTAssertTrue(ledger.shouldPlay(runID: "r", nodeID: 3, receipt: "a1"))
        XCTAssertFalse(ledger.shouldPlay(runID: "r", nodeID: 3, receipt: "a1"))
        XCTAssertEqual(PlayArrivalFields.locationTimestamp(Date(timeIntervalSince1970: 1_700_000_000.5)), ["locationTimestamp": "1700000000500"])
        XCTAssertEqual(PlayArrivalFields.locationTimestamp(nil), [:])
    }
    func testCompatibilityUndeclaredIsUnconfirmedNeverSupportedOrBlocked() throws {
        let undeclared = try XCTUnwrap(PlayContentCompatibility(data: wire(#"{"compatibility":{"supported":null,"source":"UNDECLARED","missingCapabilities":[]}}"#)))
        XCTAssertEqual(undeclared.verdict, .unconfirmed); XCTAssertFalse(undeclared.blocksStart)
        let malformed = try XCTUnwrap(PlayContentCompatibility(data: wire(#"{"compatibility":{"supported":true,"source":"DECLARED_MALFORMED","missingCapabilities":[]}}"#)))
        XCTAssertEqual(malformed.verdict, .unconfirmed)
        let missing = try XCTUnwrap(PlayContentCompatibility(data: wire(#"{"compatibility":{"supported":false,"source":"DECLARED","missingCapabilities":[{"key":"game.accusation","minVersion":1,"declaredVersion":null}]}}"#)))
        XCTAssertTrue(missing.blocksStart); XCTAssertEqual(missing.missing.map(\.key), ["game.accusation"])
        XCTAssertNil(PlayContentCompatibility(data: .object([:])))
    }
    func testDeclarationWireIsSortedAndDropsUnsafeKeys() {
        let d = PlayClientCapabilityDeclaration(clientVersion: "1.0", capabilities: ["game.qa": 1, "answer.text": 2, "bad,key": 1, "x@y": 1, "zero": 0])
        XCTAssertEqual(d.wireValue, "answer.text@2,game.qa@1")
        XCTAssertEqual(d.fields["clientPlatform"], "ios")
        XCTAssertEqual(d.json["supportedCapabilities"], .string("answer.text@2,game.qa@1"))
    }
}
