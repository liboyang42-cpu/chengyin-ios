import XCTest
@testable import QuestifyCore

final class NativeChannelMessagePageActionsTests: XCTestCase {
    private let sendID = "c09-send-key-0001"
    private let editID = "c09-edit-key-0001"
    private let recallID = "c09-recall-key-001"
    private let pinID = "c09-pin-key-000001"
    private let otherID = "c09-other-key-0001"

    func testFirstJourneyChannelMessagePageSendEditRecallPinRecoverOriginal() async throws {
        let originalRequestID = sendID
        let sent = try await sendHarness(storedID: originalRequestID).send(originalRequestID, "hello")
        let edited = try await mutationHarness().edit(requestID: editID, content: "hello")
        let recalled = try await mutationHarness().recall(requestID: recallID)
        let pinned = try await mutationHarness().pin(requestID: pinID)
        XCTAssertEqual(sent.sends, 1)
        XCTAssertEqual(edited.submits, 1)
        XCTAssertEqual(recalled.submits, 1)
        XCTAssertEqual(pinned.submits, 1)
        for read in [sent.read, edited.read, recalled.read, pinned.read] {
            XCTAssertEqual(read.outcome, ImmutableReceiptProducer.outcomeUnknown)
            XCTAssertTrue(read.journalHoldsRequest)
            XCTAssertFalse(read.proofConfirmed)
            XCTAssertFalse(read.blankBody)
            XCTAssertFalse(read.missingMessageRejected)
        }
        XCTAssertEqual(sent.read.requestID, originalRequestID)
        XCTAssertEqual(sent.journal.record?.clientMessageID, originalRequestID)
        XCTAssertEqual(sent.journal.record?.content, "hello")
        XCTAssertEqual(edited.read.requestID, editID)
        XCTAssertEqual(edited.journal.command?.requestID, editID)
        XCTAssertEqual(recalled.journal.command?.requestID, recallID)
        XCTAssertEqual(pinned.journal.command?.requestID, pinID)
        XCTAssertNil(pinned.journal.command?.content)
    }

    func testAppearanceDoesNotSend() async throws {
        let harness = sendHarness(storedID: sendID)
        harness.page.appear()
        XCTAssertEqual(harness.sends, 0)
        XCTAssertNil(harness.journal.record)
        _ = try await harness.page.send(requestID: sendID, content: "hello")
        XCTAssertEqual(harness.sends, 1)
    }

    func testSameRequestReadsBackAndADifferentRequestStaysUnknownWithoutClearing() async throws {
        let edited = try await mutationHarness().edit(requestID: editID, content: "hello")
        let again = try await edited.page.edit(command: PageMutation(requestID: editID, content: "hello"))
        XCTAssertEqual(edited.submits, 1)
        XCTAssertTrue(again.journalHoldsRequest)
        XCTAssertEqual(again.outcome, ImmutableReceiptProducer.outcomeUnknown)
        let other = try await edited.page.edit(command: PageMutation(requestID: otherID, content: "other"))
        XCTAssertEqual(edited.submits, 1)
        XCTAssertFalse(other.journalHoldsRequest)
        XCTAssertEqual(other.outcome, ImmutableReceiptProducer.outcomeUnknown)
        XCTAssertEqual(other.requestID, otherID)
        XCTAssertEqual(edited.journal.command?.requestID, editID)
        XCTAssertEqual(edited.journal.command?.content, "hello")
    }

    func testBlankBodyIsInvalidAndDoesNotClearTheJournal() async throws {
        let seeded = try await mutationHarness().edit(requestID: editID, content: "hello")
        for content in [nil, "", " ", "\n", " \t "] as [String?] {
            let before = seeded.submits
            let failed = await failure { try await seeded.page.edit(command: PageMutation(requestID: otherID, content: content)) }
            XCTAssertEqual(failed, .invalidMessageContent)
            XCTAssertEqual(seeded.submits, before)
            XCTAssertEqual(seeded.journal.command?.requestID, editID)
        }
        seeded.journal.command = PageMutation(requestID: editID, content: " \n ")
        let blank = try seeded.page.readOriginal(requestID: editID, proofConfirmed: false)
        XCTAssertEqual(blank.outcome, ImmutableReceiptProducer.outcomeUnknown)
        XCTAssertTrue(blank.journalHoldsRequest)
        XCTAssertTrue(blank.blankBody)
        XCTAssertEqual(seeded.journal.command?.content, " \n ")
        let text = sendHarness(storedID: sendID)
        XCTAssertEqual(await failure { try await text.page.send(requestID: sendID, content: " ") }, .invalidMessageContent)
        XCTAssertEqual(text.sends, 0)
        XCTAssertNil(text.journal.record)
    }

    func testMissingProofStaysUnknownAndDoesNotClearTheJournal() async throws {
        let edited = try await mutationHarness().edit(requestID: editID, content: "hello")
        let missing = try edited.page.readOriginal(requestID: editID, proofConfirmed: false, messageUnavailable: true, message: nil)
        XCTAssertEqual(missing.outcome, ImmutableReceiptProducer.outcomeUnknown)
        XCTAssertFalse(missing.proofConfirmed)
        XCTAssertTrue(missing.journalHoldsRequest)
        XCTAssertFalse(missing.missingMessageRejected)
        XCTAssertEqual(edited.journal.command?.requestID, editID)
        let absent = try edited.page.readOriginal(requestID: otherID, proofConfirmed: false)
        XCTAssertEqual(absent.outcome, ImmutableReceiptProducer.outcomeUnknown)
        XCTAssertFalse(absent.journalHoldsRequest)
        XCTAssertEqual(edited.journal.command?.requestID, editID)
    }

    func testSparseUnavailableReceiptWithoutMessageIsNotRejected() async throws {
        let edited = try await mutationHarness().edit(requestID: editID, content: "hello")
        let message: MessagingMessage? = nil
        let sparse = try edited.page.readOriginal(requestID: editID, proofConfirmed: false, messageUnavailable: true, message: message)
        XCTAssertNil(message)
        XCTAssertFalse(sparse.missingMessageRejected)
        XCTAssertEqual(sparse.outcome, ImmutableReceiptProducer.outcomeUnknown)
        XCTAssertTrue(sparse.journalHoldsRequest)
        XCTAssertEqual(edited.journal.command?.requestID, editID)
        XCTAssertEqual(edited.submits, 1)
    }

    func testRequestIDIsNotRewritten() async throws {
        let text = sendHarness(storedID: sendID)
        let padded = " \(sendID) "
        XCTAssertEqual(await failure { try await text.page.send(requestID: padded, content: "hello") }, .invalidRequestID)
        XCTAssertEqual(text.sends, 0)
        XCTAssertNil(text.journal.record)
        let wide = String(repeating: "A", count: 32) + String(repeating: "b", count: 31) + "_"
        let sent = try await text.page.send(requestID: wide, content: "hello")
        XCTAssertEqual(text.sends, 1)
        XCTAssertEqual(sent.requestID, wide)
        XCTAssertEqual(text.journal.record?.clientMessageID, sendID)
        XCTAssertEqual(sent.outcome, ImmutableReceiptProducer.outcomeUnknown)
        XCTAssertFalse(sent.journalHoldsRequest)
        let minted = sendHarness(storedID: otherID)
        let mismatched = try await minted.page.send(requestID: sendID, content: "hello")
        XCTAssertEqual(minted.sends, 1)
        XCTAssertEqual(mismatched.requestID, sendID)
        XCTAssertEqual(mismatched.outcome, ImmutableReceiptProducer.outcomeUnknown)
        XCTAssertFalse(mismatched.journalHoldsRequest)
        XCTAssertEqual(minted.journal.record?.clientMessageID, otherID)
        XCTAssertEqual(minted.journal.record?.content, "hello")
    }

    private func failure(_ body: () async throws -> NativeChannelOriginalRead) async -> NotifyFailure? {
        do { _ = try await body(); return nil } catch let error as NotifyFailure { return error } catch { return nil }
    }

    private func sendHarness(storedID: String) -> SendHarness {
        let journal = PageTextJournal()
        let text = PageTextCommand(journal: journal, storedID: storedID)
        let mutation = PageMutationJournal()
        let messages = PageMessageCommand(journal: mutation)
        let page = NativeChannelMessagePageActions(textCoordinator: text, messageCoordinator: messages, textJournal: journal, mutationJournal: mutation)
        return SendHarness(page: page, text: text, journal: journal)
    }

    private func mutationHarness() -> MutationHarness {
        let journal = PageTextJournal()
        let text = PageTextCommand(journal: journal, storedID: sendID)
        let mutation = PageMutationJournal()
        let messages = PageMessageCommand(journal: mutation)
        let page = NativeChannelMessagePageActions(textCoordinator: text, messageCoordinator: messages, textJournal: journal, mutationJournal: mutation)
        return MutationHarness(page: page, messages: messages, journal: mutation)
    }
}

private struct PageTextRecord: NativeChannelOriginalTextRecord {
    let clientMessageID: String
    let content: String
}

private struct PageMutation: NativeChannelOriginalMutationIdentity {
    var requestID: String
    var content: String?
}

private final class PageTextJournal: NativeChannelOriginalTextJournal {
    var record: PageTextRecord?
    func restore() throws -> PageTextRecord? { record }
}

private final class PageMutationJournal: NativeChannelOriginalMutationJournal {
    var command: PageMutation?
    func restore() throws -> PageMutation? { command }
}

private final class PageTextCommand: NativeChannelOriginalTextCommand {
    var sends = 0
    let journal: PageTextJournal
    let storedID: String
    init(journal: PageTextJournal, storedID: String) {
        self.journal = journal
        self.storedID = storedID
    }
    func sendNew(_ text: String) async -> Bool {
        sends += 1
        journal.record = PageTextRecord(clientMessageID: storedID, content: text)
        return true
    }
}

private final class PageMessageCommand: NativeChannelOriginalMessageCommand {
    var submits = 0
    let journal: PageMutationJournal
    init(journal: PageMutationJournal) { self.journal = journal }
    func submit(_ command: PageMutation) async {
        submits += 1
        journal.command = command
    }
}

private struct SendHarness {
    let page: NativeChannelMessagePageActions<PageTextCommand, PageMessageCommand, PageTextJournal, PageMutationJournal>
    let text: PageTextCommand
    let journal: PageTextJournal
    var sends: Int { text.sends }
    func send(_ requestID: String, _ content: String) async throws -> Self {
        _ = try await page.send(requestID: requestID, content: content)
        return self
    }
    var read: NativeChannelOriginalRead { journalRead(requestID: text.storedID) }
    private func journalRead(requestID: String) -> NativeChannelOriginalRead {
        (try? page.readOriginal(requestID: requestID, proofConfirmed: false)) ?? NativeChannelOriginalRead(
            requestID: requestID, outcome: ImmutableReceiptProducer.outcomeUnknown, journalHoldsRequest: false,
            blankBody: false, missingMessageRejected: false, proofConfirmed: false)
    }
}

private struct MutationHarness {
    let page: NativeChannelMessagePageActions<PageTextCommand, PageMessageCommand, PageTextJournal, PageMutationJournal>
    let messages: PageMessageCommand
    let journal: PageMutationJournal
    var submits: Int { messages.submits }
    var read: NativeChannelOriginalRead {
        (try? page.readOriginal(requestID: journal.command?.requestID, proofConfirmed: false)) ?? NativeChannelOriginalRead(
            requestID: "", outcome: ImmutableReceiptProducer.outcomeUnknown, journalHoldsRequest: false,
            blankBody: false, missingMessageRejected: false, proofConfirmed: false)
    }
    func edit(requestID: String, content: String?) async throws -> Self {
        _ = try await page.edit(command: PageMutation(requestID: requestID, content: content))
        return self
    }
    func recall(requestID: String) async throws -> Self {
        _ = try await page.recall(command: PageMutation(requestID: requestID, content: nil))
        return self
    }
    func pin(requestID: String) async throws -> Self {
        _ = try await page.pin(command: PageMutation(requestID: requestID, content: nil))
        return self
    }
}
