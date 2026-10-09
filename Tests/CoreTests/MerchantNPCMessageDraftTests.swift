import XCTest
@testable import QuestifyCore

@MainActor final class MerchantNPCMessageDraftTests: XCTestCase {
    func test299300And301CodePointBoundaries() {
        for count in [299, 300, 301] {
            let raw = String(repeating: "a", count: count)
            let draft = MerchantNPCMessageDraft(raw)
            XCTAssertEqual(draft.codePointCount, count)
            XCTAssertEqual(draft.isValid, count <= 300)
            XCTAssertEqual(draft.message, raw)
        }
    }
    func testCJKAndSupplementaryEmojiCountByCodePointNotBytesOrUTF16() {
        for scalar in ["界", "😀"] {
            let raw = String(repeating: scalar, count: 300)
            let draft = MerchantNPCMessageDraft(raw)
            XCTAssertEqual(draft.codePointCount, 300); XCTAssertTrue(draft.isValid)
            XCTAssertGreaterThan(raw.utf8.count, 300)
            XCTAssertFalse(MerchantNPCMessageDraft(raw + scalar).isValid)
        }
        XCTAssertEqual(String(repeating: "😀", count: 300).utf16.count, 600)
    }
    func testJoinedEmojiAndCombiningMarksDoNotCountAsSingleGraphemes() {
        let family = "👩‍👩‍👧‍👦"
        XCTAssertEqual(family.count, 1); XCTAssertEqual(family.unicodeScalars.count, 7)
        XCTAssertEqual(MerchantNPCMessageDraft(String(repeating: family, count: 42)).codePointCount, 294)
        XCTAssertFalse(MerchantNPCMessageDraft(String(repeating: family, count: 43)).isValid)
        let combining = "e\u{0301}"
        XCTAssertEqual(combining.count, 1)
        XCTAssertTrue(MerchantNPCMessageDraft(String(repeating: combining, count: 150)).isValid)
        XCTAssertEqual(MerchantNPCMessageDraft(String(repeating: combining, count: 151)).codePointCount, 302)
    }
    func testUTF16SurrogatePairBecomesOneSwiftUnicodeScalar() {
        let raw = String(decoding: [UInt16(0xD83D), UInt16(0xDE00)], as: UTF16.self)
        XCTAssertEqual(raw, "😀"); XCTAssertEqual(MerchantNPCMessageDraft(raw).codePointCount, 1)
        // Swift String repairs unpaired UTF-16 on decoding; the transmitted value
        // is U+FFFD, not an ill-formed surrogate silently counted as half an emoji.
        let repaired = String(decoding: [UInt16(0xD83D)], as: UTF16.self)
        XCTAssertEqual(repaired.unicodeScalars.first?.value, 0xFFFD)
        XCTAssertEqual(MerchantNPCMessageDraft(repaired).codePointCount, 1)
    }
    func testAllJavaTrimEdgeValuesAreRemovedBeforeCounting() {
        let edges = (0...32).map { String(UnicodeScalar($0)!) }.joined()
        let raw = edges + String(repeating: "a", count: 300) + edges
        let draft = MerchantNPCMessageDraft(raw)
        XCTAssertTrue(draft.isValid); XCTAssertEqual(draft.codePointCount, 300)
        XCTAssertEqual(draft.message, String(repeating: "a", count: 300))
        XCTAssertEqual(raw.unicodeScalars.count, 366)
        XCTAssertFalse(MerchantNPCMessageDraft(edges).isValid)
    }
    func testNBSPAndOtherNonASCIIWhitespaceArePreservedLikeJavaTrim() {
        let raw = "\u{00A0}\u{0085}\u{2003}Question\u{2003}\u{0085}\u{00A0}"
        let draft = MerchantNPCMessageDraft(raw)
        XCTAssertTrue(draft.message.utf8.elementsEqual(raw.utf8)); XCTAssertEqual(draft.codePointCount, 14)
        XCTAssertTrue(MerchantNPCMessageDraft("\u{00A0}").isValid)
        XCTAssertFalse(MerchantNPCMessageDraft("\u{00A0}" + String(repeating: "x", count: 300)).isValid)
    }
    func testInteriorNewlinesAndControlsStayInThePayload() {
        let raw = " \n\tA\nB\u{0000}C\t \r"
        let draft = MerchantNPCMessageDraft(raw)
        XCTAssertTrue(draft.message.utf8.elementsEqual("A\nB\u{0000}C".utf8))
        XCTAssertEqual(draft.codePointCount, 5)
    }
    func testRawCanonicalUnicodeRepresentationsAreNotNormalized() {
        let composed = MerchantNPCMessageDraft("\u{00E9}")
        let decomposed = MerchantNPCMessageDraft("e\u{0301}")
        XCTAssertEqual(composed.codePointCount, 1); XCTAssertEqual(decomposed.codePointCount, 2)
        XCTAssertFalse(composed.message.utf8.elementsEqual(decomposed.message.utf8))
    }
    func testProjectionKeepsOverLimitOriginalDraftUntruncated() {
        let raw = "  " + String(repeating: "界", count: 301) + "\n"
        let draft = MerchantNPCMessageDraft(raw)
        XCTAssertFalse(draft.isValid); XCTAssertEqual(draft.codePointCount, 301)
        XCTAssertEqual(raw.unicodeScalars.count, 304)
        XCTAssertEqual(draft.message, String(repeating: "界", count: 301))
    }
    func testInvalidNewMessageDoesNotCreateRequestOrCallTransport() async {
        for raw in ["", " \n\t\u{0000}", String(repeating: "x", count: 301), String(repeating: "👩‍👩‍👧‍👦", count: 43)] {
            let (flow, wire, _) = setup()
            let completion = await flow.send(raw)
            XCTAssertNil(completion); XCTAssertTrue(wire.requests.isEmpty)
            XCTAssertNil(flow.requestID); XCTAssertNil(flow.message); XCTAssertNil(flow.reply)
            XCTAssertTrue(flow.canSend); XCTAssertTrue(flow.conversationHistory.turns.isEmpty)
        }
    }
    func testValidBoundarySendsOnlyExistingPayloadWithExactServerNormalization() async throws {
        for raw in [String(repeating: "a", count: 299), String(repeating: "😀", count: 300),
                    "\u{0000}\t " + String(repeating: "a", count: 300) + "\u{001F}", "\u{00A0}Question\u{00A0}"] {
            let (flow, wire, _) = setup(); let completion = await flow.send(raw)
            XCTAssertNotNil(completion); XCTAssertEqual(wire.requests.count, 1)
            let request = try XCTUnwrap(wire.requests.first)
            XCTAssertEqual(request.path, "/api/ai/npc/merchant-chat"); XCTAssertEqual(request.method, "POST")
            let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
            XCTAssertEqual(Set(payload.keys), Set(["requestId", "bizId", "message"]))
            let message = try XCTUnwrap(payload["message"] as? String)
            XCTAssertTrue(message.utf8.elementsEqual(MerchantNPCMessageDraft.normalized(raw).utf8))
            XCTAssertTrue(try XCTUnwrap(flow.message).utf8.elementsEqual(message.utf8))
        }
    }
    func testOverLimitAttemptPreservesPreviousCompletedConversation() async {
        let (flow, wire, _) = setup(); let receipt = await flow.send("Previous")
        let reply = flow.reply; let history = flow.conversationHistory.turns
        XCTAssertNotNil(receipt)
        let invalid = await flow.send(String(repeating: "x", count: 301))
        XCTAssertNil(invalid); XCTAssertEqual(wire.requests.count, 1)
        XCTAssertEqual(flow.message, "Previous"); XCTAssertEqual(flow.reply, reply)
        XCTAssertEqual(flow.conversationHistory.turns, history)
    }
    func testUnknownRetryKeepsOriginalIDAndBytesDespiteNewDraftAttempt() async throws {
        let (flow, wire, _) = setup(); wire.unknown = true
        let raw = " \u{00A0}Original\u{00A0}\n"
        let receipt = await flow.send(raw); let id = try XCTUnwrap(flow.requestID)
        let originalBody = try XCTUnwrap(wire.requests.first?.body)
        XCTAssertNil(receipt); XCTAssertEqual(flow.failure, .unknownOutcome)
        let invalid = await flow.send(String(repeating: "x", count: 301))
        XCTAssertNil(invalid); XCTAssertEqual(flow.requestID, id); XCTAssertEqual(wire.requests.count, 1)
        XCTAssertTrue(try XCTUnwrap(flow.message).utf8.elementsEqual("\u{00A0}Original\u{00A0}".utf8))
        wire.unknown = false; let retried = await flow.retry(requestID: id)
        XCTAssertEqual(retried?.requestID, id); XCTAssertEqual(wire.requests.count, 2)
        XCTAssertEqual(wire.requests[1].body, originalBody)
    }
    func testValidationDoesNotBypassGrantOrScopeGates() async {
        let (flow, wire, state) = setup(); state.grants.legal = false
        let denied = await flow.send("Valid"); XCTAssertNil(denied); XCTAssertTrue(wire.requests.isEmpty)
        state.grants.legal = true; state.scope = nil
        let stale = await flow.send("Valid"); XCTAssertNil(stale); XCTAssertTrue(wire.requests.isEmpty)
    }
    private func setup() -> (MerchantNPCChatCoordinator, Wire, State) {
        let wire = Wire(); let state = State()
        let flow = MerchantNPCChatCoordinator(scope: state.scope!, client: .init(transport: wire), currentScope: { state.scope }, grants: { state.grants })
        return (flow, wire, state)
    }
    @MainActor private final class State {
        var scope: MerchantNPCScope? = .init(accountID: 7, namespace: "synthetic", epoch: UUID(), merchantRowID: PublicMerchantRowID(9)!, accessRevision: UUID())
        var grants: MerchantNPCGrants = { var value = MerchantNPCGrants(); value.server = true; value.provider = true; value.legal = true; return value }()
    }
    @MainActor private final class Wire: MerchantNPCHTTPTransport {
        var requests: [MerchantNPCHTTPRequest] = []; var unknown = false
        func perform(_ request: MerchantNPCHTTPRequest) async throws -> MerchantNPCHTTPResponse {
            requests.append(request)
            if unknown { throw MerchantNPCFailure.unknownOutcome }
            let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
            let id = try XCTUnwrap(sent["requestId"] as? String)
            let data: [String: Any] = ["requestId": id, "outcomeStatus": "SUCCEEDED", "safetyDecision": "PASS", "retryable": false, "safeText": "Safe reply"]
            return .init(status: 200, body: try JSONSerialization.data(withJSONObject: ["code": 200, "data": data]))
        }
    }
}
