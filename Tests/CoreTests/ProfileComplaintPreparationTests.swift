import XCTest
@testable import QuestifyCore

@MainActor final class ProfileComplaintPreparationTests: XCTestCase {
    private final class Reader: CoopFlowReading {
        var session: CoopFlowSession? = try? .init(accountID: 4, epoch: 1, token: "synthetic-token")
        var value: CoopFlowJSON = .array([.object(["topicId": .id(7), "topicName": .string("Test topic"), "registrationId": .id(99)])])
        var error: Error?
        var calls = 0
        var waits = false
        var pending: CheckedContinuation<CoopFlowJSON, Error>?
        func read(_ resource: CoopFlowRead) async throws -> CoopFlowJSON {
            XCTAssertEqual(resource, .complaintTopics); calls += 1
            if waits { return try await withCheckedThrowingContinuation { pending = $0 } }
            if let error { throw error }; return value
        }
        func settlement(source: CoopFlowSettlement.Source, id: Int) async throws -> CoopFlowSettlement { XCTFail("unrelated read"); throw APIError.notConfigured }
    }
    private func topic() throws -> [ProfileComplaintTopic] { try ProfileComplaintTopic.decode(Reader().value) }
    private func draft() -> ProfileComplaintDraft { var d = ProfileComplaintDraft(); d.topicID = 7; d.reason = "five!"; return d }
    func testSelectorPreservesTopicIDNotRegistrationID() throws { XCTAssertEqual(try topic().map(\.id), [7]) }
    func testMissingTopicIDCannotBorrowOrderOrRegistrationID() {
        XCTAssertThrowsError(try ProfileComplaintTopic.decode(.array([.object(["id": .id(7), "registrationId": .id(7)])])))
    }
    func testDuplicateTopicIDsFailClosed() {
        XCTAssertThrowsError(try ProfileComplaintTopic.decode(.array([.object(["topicId": .id(7)]), .object(["topicId": .id(7)])])))
    }
    func testInvalidIdentityAndEnvelopeFailClosed() {
        let values: [CoopFlowJSON] = [.null, .object(["rows": .array([])]), .array([.object(["topicId": .id(0)])]), .array([.object(["topicId": .string("7.1")])]), .array([.object(["topicId": .bool(true)])])]
        for value in values {
            XCTAssertThrowsError(try ProfileComplaintTopic.decode(value))
        }
    }
    func testNameUnknownDoesNotInventData() throws {
        XCTAssertNil(try ProfileComplaintTopic.decode(.array([.object(["topicId": .id(7)])])).first?.name)
        XCTAssertThrowsError(try ProfileComplaintTopic.decode(.array([.object(["topicId": .id(7), "topicName": .number(9)])])))
    }
    func testSuccessfulEmptyIsAuthoritative() throws { XCTAssertEqual(try ProfileComplaintTopic.decode(.array([])), []) }
    func testTopicValidationPrecedesTextValidation() throws {
        var d = draft(); d.topicID = 99; d.reason = ""; XCTAssertEqual(d.validation(topics: try topic()), .topic)
    }
    func testFiveUTF16UnitsAndTrimMatchMini() throws {
        var d = draft(); d.reason = " \u{FEFF}四个字!\n"; XCTAssertEqual(d.validation(topics: try topic()), .reasonShort)
        d.reason = "😀😀x"; XCTAssertNil(d.validation(topics: try topic()))
        XCTAssertEqual(d.review(topics: try topic())?.reason, "😀😀x")
    }
    func testExactTypeReasonContactAssembly() throws {
        var d = draft(); d.kind = .fees; d.reason = "  没有按约履行  "; d.contact = "  synthetic contact  "
        XCTAssertEqual(d.review(topics: try topic())?.reason, "【费用与退款】没有按约履行\n联系方式：synthetic contact")
    }
    func testAllFiveTypesAndBlankContact() throws {
        XCTAssertEqual(ProfileComplaintKind.allCases.map(\.sourceLabel), ["服务与履约", "费用与退款", "安全与纠纷", "虚假宣传", "其他"])
        var d = draft(); d.contact = "\u{FEFF} \n"; XCTAssertEqual(d.review(topics: try topic())?.reason, "five!")
    }
    func testInputLimitsRejectInsteadOfTruncate() throws {
        var d = draft(); d.reason = String(repeating: "😀", count: 250); d.contact = String(repeating: "x", count: 50)
        XCTAssertNil(d.validation(topics: try topic())); d.reason += "x"; XCTAssertEqual(d.validation(topics: try topic()), .reasonLong)
        d.reason = "five!"; d.contact += "x"; XCTAssertEqual(d.validation(topics: try topic()), .contactLong)
    }
    func testSourceTrimDoesNotRemoveNEL() throws {
        var d = draft(); d.reason = "\u{0085}abcd"; XCTAssertNil(d.validation(topics: try topic()))
        XCTAssertEqual(d.review(topics: try topic())?.reason, "\u{0085}abcd")
    }
    func testInitialUnknownThenRetryIsNotEmpty() async {
        let r = Reader(); r.error = APIError.httpStatus(503); let m = ProfileComplaintPreparationController(reader: r, isCurrent: { true })
        XCTAssertNil(m.topics); await m.load(); XCTAssertEqual(m.issue, .failed); XCTAssertNil(m.topics)
        r.error = nil; await m.load(); XCTAssertEqual(m.topics?.count, 1); XCTAssertNil(m.issue)
    }
    func testLocalReviewReturnAndCloseClear() async {
        let r = Reader(); let m = ProfileComplaintPreparationController(reader: r, isCurrent: { true }); await m.load()
        m.change { $0.topicID = 7; $0.reason = "five!" }; XCTAssertTrue(m.beginReview()); m.change { $0.reason = "ignored" }
        XCTAssertEqual(m.review?.reason, "five!"); m.continueEditing(); XCTAssertEqual(m.draft.reason, "five!")
        m.retire(); XCTAssertEqual(m.draft, .init()); XCTAssertNil(m.review); XCTAssertNil(m.topics); XCTAssertFalse(m.contextMatches)
    }
    func testRefreshFailureKeepsDraftButBlocksReviewUntilRecovery() async {
        let r = Reader(); let m = ProfileComplaintPreparationController(reader: r, isCurrent: { true }); await m.load()
        m.change { $0.topicID = 7; $0.reason = "five!" }; r.error = APIError.httpStatus(503); await m.load()
        XCTAssertEqual(m.draft.reason, "five!"); XCTAssertEqual(m.topics?.count, 1); XCTAssertFalse(m.beginReview())
        r.error = nil; await m.load(); XCTAssertTrue(m.beginReview())
    }
    func testFreshEmptyDropsSelectionWithoutErasingUnsubmittedText() async {
        let r = Reader(); let m = ProfileComplaintPreparationController(reader: r, isCurrent: { true }); await m.load()
        m.change { $0.topicID = 7; $0.reason = "five!" }; r.value = .array([]); await m.load()
        XCTAssertEqual(m.topics, []); XCTAssertNil(m.draft.topicID); XCTAssertEqual(m.draft.reason, "five!"); XCTAssertFalse(m.beginReview())
    }
    func testAuthFailureClearsPrivateDraft() async {
        let r = Reader(); let m = ProfileComplaintPreparationController(reader: r, isCurrent: { true }); await m.load()
        m.change { $0.topicID = 7; $0.contact = "synthetic" }; r.error = APIError.unauthorized; await m.load()
        XCTAssertEqual(m.draft, .init()); XCTAssertNil(m.topics); XCTAssertEqual(m.issue, .signIn)
    }
    func testAccountOrEpochChangeBlocksReviewAndClears() async throws {
        let r = Reader(); let m = ProfileComplaintPreparationController(reader: r, isCurrent: { true }); await m.load()
        m.change { $0.topicID = 7; $0.reason = "five!" }; r.session = try .init(accountID: 4, epoch: 2, token: "different-synthetic")
        XCTAssertFalse(m.beginReview()); XCTAssertEqual(m.draft, .init()); XCTAssertFalse(m.contextMatches)
    }
    func testRetiredRouteAndGuestDoNotDispatch() async {
        let r = Reader(); let m = ProfileComplaintPreparationController(reader: r, isCurrent: { false }); await m.load(); XCTAssertEqual(r.calls, 0)
        r.session = nil; let guest = ProfileComplaintPreparationController(reader: r, isCurrent: { true }); await guest.load(); XCTAssertEqual(r.calls, 0)
    }
    func testLateSuccessCannotRestoreClosedDraft() async {
        let r = Reader(); r.waits = true; let m = ProfileComplaintPreparationController(reader: r, isCurrent: { true })
        let task = Task { await m.load() }; while r.pending == nil { await Task.yield() }
        m.retire(); r.pending?.resume(returning: r.value); await task.value; XCTAssertNil(m.topics); XCTAssertEqual(m.draft, .init())
    }
    func testLateErrorAfterSwitchDoesNotOverwriteNewContext() async throws {
        let r = Reader(); r.waits = true; let m = ProfileComplaintPreparationController(reader: r, isCurrent: { true })
        let task = Task { await m.load() }; while r.pending == nil { await Task.yield() }
        r.session = try .init(accountID: 5, epoch: 2, token: "different-synthetic"); r.pending?.resume(throwing: APIError.httpStatus(503)); await task.value
        XCTAssertNil(m.issue); XCTAssertNil(m.topics); XCTAssertFalse(m.contextMatches)
    }
    func testSingleFlightAndReviewNeverReadOrWrite() async {
        let r = Reader(); r.waits = true; let m = ProfileComplaintPreparationController(reader: r, isCurrent: { true })
        let task = Task { await m.load() }; while r.pending == nil { await Task.yield() }; await m.load(); XCTAssertEqual(r.calls, 1)
        r.pending?.resume(returning: r.value); await task.value; m.change { $0.topicID = 7; $0.reason = "five!" }
        XCTAssertTrue(m.beginReview()); await m.load(); XCTAssertEqual(r.calls, 1)
    }
    func testCancelledRefreshCannotUnlockStaleReview() async {
        let r = Reader(); let m = ProfileComplaintPreparationController(reader: r, isCurrent: { true }); await m.load()
        m.change { $0.topicID = 7; $0.reason = "five!" }; r.waits = true
        let task = Task { await m.load() }; while r.pending == nil { await Task.yield() }
        task.cancel(); r.pending?.resume(returning: r.value); await task.value
        XCTAssertEqual(m.issue, .failed); XCTAssertEqual(m.draft.reason, "five!"); XCTAssertFalse(m.beginReview())
        r.waits = false; await m.load(); XCTAssertTrue(m.beginReview())
    }
}
