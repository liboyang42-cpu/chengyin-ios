import XCTest
@testable import QuestifyCore

final class MessagingHistoryTests: XCTestCase {
    private func page(_ ids: [Int], conversation: Int = 9, cursor: Int? = nil,
                      more: Bool = false, text: String = "Fixture") throws -> MessagingPage {
        var object: [String: Any] = ["list": ids.map { ["id": $0, "conversationId": conversation, "status": 0, "content": text] }, "hasMore": more]
        if let cursor { object["nextCursor"] = cursor }
        return try JSONDecoder().decode(MessagingPage.self, from: JSONSerialization.data(withJSONObject: object))
    }
    func testPagesKeepSourceOrderAndOpaqueCursorInsteadOfSortingOrGuessing() throws {
        var state = MessagingHistory(conversationID: 9)
        try state.replace(with: page([19, 11], cursor: 42, more: true))
        XCTAssertEqual(state.messages.map(\.id), [19, 11])
        XCTAssertEqual(state.nextCursor, 42)
        try state.prepend(page([8, 2], cursor: 7, more: true), requestedCursor: 42)
        XCTAssertEqual(state.messages.map(\.id), [8, 2, 19, 11])
        XCTAssertEqual(state.nextCursor, 7)
        try state.prepend(page([1]), requestedCursor: 7)
        XCTAssertEqual(state.messages.map(\.id), [1, 8, 2, 19, 11])
        XCTAssertFalse(state.hasMore)
    }
    func testDuplicateIDsAreUniqueAndIncomingCopyWinsOnOverlap() throws {
        var state = MessagingHistory(conversationID: 9)
        try state.replace(with: page([10, 10, 11], cursor: 42, more: true, text: "Old snapshot"))
        XCTAssertEqual(state.messages.map(\.id), [10, 11])
        try state.prepend(page([8, 10, 8], text: "Fresh page"), requestedCursor: 42)
        XCTAssertEqual(state.messages.map(\.id), [8, 10, 11])
        XCTAssertEqual(state.messages[1].content, "Fresh page")
        XCTAssertEqual(state.messages[2].content, "Old snapshot")
    }
    func testWrongConversationPageCannotOverwriteExistingHistory() throws {
        var state = MessagingHistory(conversationID: 9)
        try state.replace(with: page([10], cursor: 42, more: true))
        let original = state
        XCTAssertThrowsError(try state.prepend(page([1], conversation: 8), requestedCursor: 42))
        XCTAssertEqual(state, original)
        XCTAssertThrowsError(try state.replace(with: page([1], conversation: 8)))
        XCTAssertEqual(state, original)
    }
    func testStaleCursorCompletionAndRepeatedCursorDoNotAdvanceState() throws {
        var state = MessagingHistory(conversationID: 9)
        try state.replace(with: page([10], cursor: 42, more: true))
        let original = state
        XCTAssertThrowsError(try state.prepend(page([1]), requestedCursor: 41))
        XCTAssertEqual(state, original)
        XCTAssertThrowsError(try state.prepend(page([1], cursor: 42, more: true), requestedCursor: 42))
        XCTAssertEqual(state, original)
        // A retry still uses the exact original cursor.
        try state.prepend(page([1]), requestedCursor: 42)
        XCTAssertFalse(state.hasMore)
    }
    func testCursorCycleRejectsWithoutLosingValidIntermediatePage() throws {
        var state = MessagingHistory(conversationID: 9)
        try state.replace(with: page([10], cursor: 42, more: true))
        try state.prepend(page([8], cursor: 7, more: true), requestedCursor: 42)
        let valid = state
        XCTAssertThrowsError(try state.prepend(page([1], cursor: 42, more: true), requestedCursor: 7))
        XCTAssertEqual(state, valid)
    }
    func testRefreshResetsHistoryAndCursorCycleMemory() throws {
        var state = MessagingHistory(conversationID: 9)
        try state.replace(with: page([10], cursor: 42, more: true))
        try state.prepend(page([8]), requestedCursor: 42)
        XCTAssertThrowsError(try state.prepend(page([1]), requestedCursor: 42))
        try state.replace(with: page([12], cursor: 42, more: true))
        XCTAssertEqual(state.messages.map(\.id), [12])
        try state.prepend(page([8]), requestedCursor: 42)
        XCTAssertEqual(state.messages.map(\.id), [8, 12])
    }
    func testInvalidConversationCannotAcceptEvenEmptyPage() throws {
        var state = MessagingHistory(conversationID: 0)
        XCTAssertThrowsError(try state.replace(with: page([])))
    }
}
