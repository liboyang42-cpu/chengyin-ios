import XCTest
@testable import QuestifyCore

final class CoopPoolApplicationDraftTests: XCTestCase {
    private func pool(state: String = "open", hasClub: CoopFlowJSON = .bool(true), rows: [CoopFlowJSON]? = nil) -> CoopFlowJSON {
        .object(["hasClub": hasClub, "rows": .array(rows ?? [.object(["topicId": .id(10), "name": .string("Topic"), "state": .string(state)])])])
    }
    func testOldCallDefaultsToSourceEmptyMessage() throws {
        let body = try CoopFlowMutation.apply(topicID: 10).body()
        XCTAssertEqual(body, .object(["topicId": .id(10), "message": .string("")]))
        XCTAssertEqual(CoopFlowMutation.apply(topicID: 10).path, "api/coop/pool/apply")
    }
    func testOriginalWhitespaceNewlinesAndUnicodeRemainExactBytes() throws {
        let raw = "  带队\n e\u{301} 👩‍💻 \t", draft = try CoopPoolApplicationDraft(topicID: 10, message: raw)
        let value = try XCTUnwrap(draft.mutation().body()["message"].text)
        XCTAssertTrue(value.utf8.elementsEqual(raw.utf8))
    }
    func testBlankWhitespaceIsNotTrimmedToEmptyOrOmitted() throws {
        for raw in ["", " ", "\n\t"] { XCTAssertEqual(try CoopFlowMutation.apply(topicID: 10, message: raw).body()["message"], .string(raw)) }
    }
    func testFiveHundredScalarsPassAndFiveHundredOneRejects() throws {
        XCTAssertNoThrow(try CoopPoolApplicationDraft(topicID: 10, message: String(repeating: "a", count: 500)).mutation())
        XCTAssertThrowsError(try CoopFlowMutation.apply(topicID: 10, message: String(repeating: "a", count: 501)).body()) { XCTAssertEqual($0 as? CoopFlowFailure, .invalid("message")) }
    }
    func testCombiningMarksCountSeparatelyFromSwiftCharacters() throws {
        let exact = String(repeating: "e\u{301}", count: 250), over = exact + "\u{301}"
        XCTAssertEqual(exact.count, 250); XCTAssertEqual(exact.unicodeScalars.count, 500)
        XCTAssertNoThrow(try CoopPoolApplicationDraft(topicID: 10, message: exact).mutation())
        XCTAssertThrowsError(try CoopPoolApplicationDraft(topicID: 10, message: over).mutation())
    }
    func testSupplementaryEmojiDoNotUseJavaUTF16UnitCount() throws {
        let raw = String(repeating: "😀", count: 500)
        XCTAssertEqual(raw.utf16.count, 1000); XCTAssertEqual(raw.unicodeScalars.count, 500)
        XCTAssertNoThrow(try CoopPoolApplicationDraft(topicID: 10, message: raw).mutation())
    }
    func testZWJSequenceUsesCodePointBudgetWithoutTruncation() throws {
        let raw = String(repeating: "👩‍💻", count: 167), draft = try CoopPoolApplicationDraft(topicID: 10, message: raw)
        XCTAssertEqual(draft.messageScalarCount, 501); XCTAssertFalse(draft.isValid)
        XCTAssertThrowsError(try draft.mutation()); XCTAssertTrue(draft.message.utf8.elementsEqual(raw.utf8))
    }
    func testInvalidTopicCannotProduceDraftOrBody() {
        for id in [0, -1] { XCTAssertThrowsError(try CoopPoolApplicationDraft(topicID: id)); XCTAssertThrowsError(try CoopFlowMutation.apply(topicID: id, message: "message").body()) }
    }
    func testDraftEqualityDoesNotNormalizeDifferentMessageBytes() throws {
        XCTAssertNotEqual(try CoopPoolApplicationDraft(topicID: 10, message: "é"), try CoopPoolApplicationDraft(topicID: 10, message: "e\u{301}"))
    }
    func testExistingImmutableReviewContainsExactMessageAndNoRecipientOverride() throws {
        let raw = "  experience \n", review = try CoopFlowRequestReviewContext(operation: .apply(topicID: 10, message: raw))
        XCTAssertEqual(review.requestBody, .object(["topicId": .id(10), "message": .string(raw)]))
        XCTAssertTrue(review.rows.contains { $0.id == "message" && $0.value == .text(raw) })
        for key in ["clubId", "merchantId", "toId", "inviteType", "confirmation"] { XCTAssertEqual(review.requestBody[key], .null) }
    }
    func testWithdrawRequestIsByteEquivalentToOriginalShape() throws { XCTAssertEqual(try CoopFlowMutation.withdraw(topicID: 10).body(), .object(["topicId": .id(10)])) }
    func testApplicableStatesAcceptOneExactTopic() throws {
        for state in ["open", "declined", "withdrawn"] { XCTAssertEqual(try CoopPoolApplicationSelection(pool: pool(state: state), topicID: 10).topicID, 10) }
    }
    func testAppliedInvitedTakenAndUnknownStatesReject() {
        for state in ["applied", "invited", "taken", "cooped", "converted", ""] { XCTAssertThrowsError(try CoopPoolApplicationSelection(pool: pool(state: state), topicID: 10)) }
    }
    func testMissingClubEvidenceCannotCreateLocalApplicationContext() {
        for value in [CoopFlowJSON.bool(false), .null, .string("true")] { XCTAssertThrowsError(try CoopPoolApplicationSelection(pool: pool(hasClub: value), topicID: 10)) }
    }
    func testMissingOrDuplicateTopicRejectsAmbiguousSelection() {
        let row: CoopFlowJSON = .object(["topicId": .id(10), "state": .string("open")])
        XCTAssertThrowsError(try CoopPoolApplicationSelection(pool: pool(rows: []), topicID: 10))
        XCTAssertThrowsError(try CoopPoolApplicationSelection(pool: pool(rows: [row, row]), topicID: 10))
        XCTAssertThrowsError(try CoopPoolApplicationSelection(pool: pool(), topicID: 11))
    }
    func testSourceRowAndPoolChangesProduceDifferentSelection() throws {
        let old = try CoopPoolApplicationSelection(pool: pool(), topicID: 10)
        let row: CoopFlowJSON = .object(["topicId": .id(10), "name": .string("Different merchant topic"), "state": .string("open")])
        XCTAssertNotEqual(old, try CoopPoolApplicationSelection(pool: pool(rows: [row]), topicID: 10))
        XCTAssertNotEqual(old, try CoopPoolApplicationSelection(pool: pool(state: "withdrawn"), topicID: 10))
    }
}

@MainActor final class CoopPoolApplicationCompatibilityTests: XCTestCase {
    func testNewMessageRetainsOriginalSourcePermissionRead() async throws {
        let reader = Reader(), evidence = CoopFlowSourceEvidenceReader(reader: reader), session = try XCTUnwrap(reader.session)
        let result = try await evidence.freshEvidence(for: .apply(topicID: 10, message: "note"), session: session)
        XCTAssertTrue(result.permitted); XCTAssertEqual(reader.resources, [.pool])
        reader.hasClub = false
        let denied = try await evidence.freshEvidence(for: .apply(topicID: 10, message: "note"), session: session)
        XCTAssertFalse(denied.permitted)
    }
    func testMessageCannotEscapeOriginalUnknownAccountTopicLock() async throws {
        let reader = Reader(), executor = Executor(), locks = Locks()
        let coordinator = CoopFlowCoordinator(current: { reader.session }, evidence: CoopFlowSourceEvidenceReader(reader: reader), executor: executor, locks: locks)
        locks.locked = true
        for message in ["", "changed text", " \n"] {
            do { _ = try await coordinator.prepare(.apply(topicID: 10, message: message)); XCTFail() }
            catch { XCTAssertEqual(error as? CoopFlowFailure, .ambiguous) }
        }
        XCTAssertTrue(locks.keys.allSatisfy { $0 == "7:pool-topic-10" }); XCTAssertEqual(executor.calls, 0)
    }
    func testOriginalCoordinatorDefaultDisablementRetainsExactReviewMessage() async throws {
        let reader = Reader(), executor = Executor(), locks = Locks()
        let coordinator = CoopFlowCoordinator(current: { reader.session }, evidence: CoopFlowSourceEvidenceReader(reader: reader), executor: executor, locks: locks)
        let review = try await coordinator.prepare(.apply(topicID: 10, message: " exact \n"))
        XCTAssertEqual(review.requestBody["message"], .string(" exact \n"))
        do { _ = try await coordinator.confirm(review); XCTFail() } catch { XCTAssertEqual(error as? CoopFlowFailure, .disabled) }
        XCTAssertEqual(executor.calls, 0)
    }
    @MainActor private final class Reader: CoopFlowReading {
        var session: CoopFlowSession? = try! .init(accountID: 7, epoch: 1, token: "synthetic-fixture")
        var hasClub = true, resources: [CoopFlowRead] = []
        func read(_ resource: CoopFlowRead) async throws -> CoopFlowJSON {
            resources.append(resource); return .object(["hasClub": .bool(hasClub), "rows": .array([.object(["topicId": .id(10), "state": .string("open")])])])
        }
        func settlement(source: CoopFlowSettlement.Source, id: Int) async throws -> CoopFlowSettlement { throw CoopFlowFailure.disabled }
    }
    @MainActor private final class Executor: CoopFlowExecuting {
        var calls = 0
        func permitsDispatch(_ operation: CoopFlowMutation) -> Bool { false }
        func execute(_ operation: CoopFlowMutation, session: CoopFlowSession) async throws -> CoopFlowJSON { calls += 1; throw CoopFlowFailure.disabled }
    }
    @MainActor private final class Locks: CoopFlowLockStore {
        var locked = false, keys: [String] = []
        func contains(_ key: String) throws -> Bool { keys.append(key); return locked }
        func acquire(_ key: String) throws { XCTFail("No write lock should be acquired") }
        func complete(_ key: String) throws { XCTFail("No existing lock should be cleared") }
    }
}
