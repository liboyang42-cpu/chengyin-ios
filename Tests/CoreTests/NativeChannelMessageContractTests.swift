import XCTest
@testable import QuestifyCore

final class NativeChannelMessageContractTests: XCTestCase {
    private func id(_ value: String) -> NativeChannelMessageID { NativeChannelMessageID(rawValue: value)! }
    private func binding() throws -> NativeChannelMessageBinding { try .init(channelID: id("9007199254740993"), conversationID: id("9007199254740993"), mappingRevision: "real-source-revision") }
    private func edit(_ text: String = "edited") throws -> NativeChannelMessageCommand {
        try .init(operation: .edit, requestID: "original_request_0001", binding: binding(), messageID: id("9223372036854775807"), expectedVersion: 3, content: text)
    }
    func testIDsRemainExactStringsAndRejectNumericFloatOrNoncanonicalInput() throws {
        XCTAssertEqual(try JSONDecoder().decode(NativeChannelMessageID.self, from: Data(#""9007199254740993""#.utf8)).rawValue, "9007199254740993")
        for raw in ["9007199254740993", "9007199254740993.0", #""01""#, #""1e3""#, #""9223372036854775808""#] {
            XCTAssertThrowsError(try JSONDecoder().decode(NativeChannelMessageID.self, from: Data(raw.utf8)))
        }
    }
    func testReceiptBindsOriginalKeyOperationChannelMessageAndOriginalVersion() throws {
        let base: [String: Any] = ["request_id":"original_request_0001", "state":"APPLIED", "outcome_confirmed":true,
            "operation":"EDIT", "conversation_id":"9007199254740993", "result":["message_id":"9223372036854775807", "version":4, "revision":4, "changed":true]]
        func decode(_ value: [String: Any]) throws -> NativeChannelMessageReceipt { try JSONDecoder().decode(NativeChannelMessageReceipt.self, from: JSONSerialization.data(withJSONObject: value)) }
        XCTAssertTrue(try decode(base).verify(edit()))
        for field in ["request_id", "operation", "conversation_id"] {
            var wrong = base; wrong[field] = field == "operation" ? "RECALL" : "1234567890123456"
            XCTAssertThrowsError(try decode(wrong).verify(edit()))
        }
        var wrongVersion = base
        wrongVersion["result"] = ["message_id":"9223372036854775807", "version":99, "revision":99, "changed":true]
        XCTAssertThrowsError(try decode(wrongVersion).verify(edit()))
    }
    func testNotFoundIsUnconfirmedAndRedactedAppliedHasNoPayload() throws {
        let missing = Data(#"{"request_id":"original_request_0001","state":"NOT_FOUND","outcome_confirmed":false}"#.utf8)
        XCTAssertFalse(try JSONDecoder().decode(NativeChannelMessageReceipt.self, from: missing).verify(edit()))
        let redacted = Data(#"{"request_id":"original_request_0001","state":"APPLIED","outcome_confirmed":true,"operation":"EDIT","conversation_id":"9007199254740993","result_redacted":true}"#.utf8)
        XCTAssertTrue(try JSONDecoder().decode(NativeChannelMessageReceipt.self, from: redacted).verify(edit()))
    }
    @MainActor func testJournalComparesOriginalUnicodeBytesRatherThanNormalizedStrings() throws {
        let composed = try edit("\u{00e9}"), decomposed = try edit("e\u{0301}")
        XCTAssertEqual(composed.content, decomposed.content)
        XCTAssertFalse(NativeChannelMessageMutationJournal.sameBytes(composed, decomposed))
    }
    func testRecallDropsPayloadQuoteAndMediaAtDecodeBoundary() throws {
        let raw = Data(#"{"id":"4","conversationId":"9","version":2,"status":1,"msgType":2,"senderId":"8","content":"sensitive","extraJson":"secret","replyTo":{"id":"3","state":"VISIBLE","summary":"secret"}}"#.utf8)
        let row = try JSONDecoder().decode(NativeChannelMessageSnapshot.self, from: raw)
        XCTAssertNil(row.content); XCTAssertNil(row.extraJSON); XCTAssertNil(row.reply)
        XCTAssertNil(row.message.content); XCTAssertEqual(row.message.status, .recalled)
        XCTAssertEqual(NativeChannelMessageAttachmentAvailability.project(row), .withheld)
    }
    func testBlockedQuoteNeverRetainsServerPayload() throws {
        let quote = try JSONDecoder().decode(NativeChannelMessageQuote.self, from: Data(#"{"id":"8","state":"BLOCKED","summary":"must disappear","senderId":"99"}"#.utf8))
        XCTAssertNil(quote.summary); XCTAssertNil(quote.senderId)
    }
    func testAllSixteenDesignKindsAreDistinctAndUnknownIsNotWritable() throws {
        XCTAssertEqual(NativeChannelMessageKind.allCases.map(\.rawValue), Array(0...15))
        XCTAssertEqual(Set(NativeChannelMessageOperation.allCases.map(\.rawValue)), ["EDIT","RECALL","PIN","UNPIN","PIN_SORT"])
    }
    func testPinSortUsesActualPinIDsAndRequiresExactOriginalPermutationResult() throws {
        let command = try NativeChannelMessageCommand(operation: .sort, requestID: "pin_sort_original_0001", binding: binding(), orderedPinIDs: [id("20"),id("10")])
        XCTAssertEqual(command.body["ordered_pin_ids"] as? [String], ["20","10"])
        let result = try JSONDecoder().decode(NativeChannelMessageResult.self, from: Data(#"{"updated":2,"sort_nos":{"20":200,"10":100}}"#.utf8))
        XCTAssertNoThrow(try result.verify(command))
        let wrong = try JSONDecoder().decode(NativeChannelMessageResult.self, from: Data(#"{"updated":2,"sort_nos":{"20":100,"10":200}}"#.utf8))
        XCTAssertThrowsError(try wrong.verify(command))
    }
}
