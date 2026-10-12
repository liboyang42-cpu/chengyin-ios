import XCTest
@testable import QuestifyCore

final class ClubAIDesignFeedbackTests: XCTestCase {
    private let owner = PublishingSession(namespace: "synthetic", accountID: 7, epoch: UUID(), role: "club", region: .china)
    private func context(_ operation: UUID = UUID(), copy: String = "  Exact\npromo 👋  ", generation: Int? = 1) -> ClubAIDesignFeedbackContext {
        .init(clubID: 41, session: owner, operationID: operation, resultGeneration: generation, promoCopy: copy)
    }
    private func ready(_ value: ClubAIDesignFeedbackContext) -> ClubAIDesignFeedbackState {
        var state = ClubAIDesignFeedbackState(); state.bind(value); state.appear(); return state
    }
    func testThreeExactMiniProgramIdeas() {
        XCTAssertEqual(ClubAIDesignIdea.allCases.map(\.text), ["静安 情侣 夜间 Citywalk 90分钟", "外滩 亲子 半天 城市打卡", "苏州河 摄影 徒步 2小时"])
        XCTAssertEqual(Set(ClubAIDesignIdea.allCases.map(\.id)).count, 3)
    }
    func testChoiceReplacesIdeaWithoutGenerating() throws {
        let value = context(), state = ready(value), permit = try XCTUnwrap(state.permit(value, generating: false))
        XCTAssertEqual(state.choose(.bund, permit: permit, current: value, generating: false), ClubAIDesignIdea.bund.text)
        XCTAssertEqual(state.phase, .idle)
    }
    func testBusyRefusesChoiceAndCopy() throws {
        let value = context(); var state = ready(value); let permit = try XCTUnwrap(state.permit(value, generating: false))
        XCTAssertNil(state.permit(value, generating: true))
        XCTAssertNil(state.choose(.bund, permit: permit, current: value, generating: true))
        XCTAssertNil(state.beginCopy(permit, current: value, generating: true))
    }
    func testNilIdentityAndInvalidClubCannotInteract() {
        for value in [ClubAIDesignFeedbackContext(clubID: 41, session: nil, operationID: UUID()), .init(clubID: 0, session: owner, operationID: UUID())] {
            let state = ready(value); XCTAssertNil(state.permit(value, generating: false))
        }
    }
    func testCopyPreservesEveryByteAndOnlyConfirmedOutcomeSucceeds() throws {
        let value = context(); var state = ready(value); let permit = try XCTUnwrap(state.permit(value, generating: false))
        let attempt = try XCTUnwrap(state.beginCopy(permit, current: value, generating: false))
        XCTAssertTrue(attempt.text.utf8.elementsEqual(value.promoCopy.utf8)); XCTAssertEqual(state.phase, .copying)
        XCTAssertTrue(state.completeCopy(attempt, succeeded: true, current: value, generating: false)); XCTAssertEqual(state.phase, .copied)
    }
    func testFailureSupportsExplicitRetryWithoutFalseSuccess() throws {
        let value = context(); var state = ready(value); let permit = try XCTUnwrap(state.permit(value, generating: false))
        let first = try XCTUnwrap(state.beginCopy(permit, current: value, generating: false))
        XCTAssertTrue(state.completeCopy(first, succeeded: false, current: value, generating: false)); XCTAssertEqual(state.phase, .failed)
        let retry = try XCTUnwrap(state.beginCopy(permit, current: value, generating: false))
        XCTAssertNotEqual(first, retry); XCTAssertTrue(state.completeCopy(retry, succeeded: true, current: value, generating: false))
    }
    func testDuplicateInFlightAndLateCompletionAreRejected() throws {
        let value = context(); var state = ready(value); let permit = try XCTUnwrap(state.permit(value, generating: false))
        let attempt = try XCTUnwrap(state.beginCopy(permit, current: value, generating: false))
        XCTAssertNil(state.beginCopy(permit, current: value, generating: false))
        XCTAssertTrue(state.completeCopy(attempt, succeeded: false, current: value, generating: false))
        XCTAssertFalse(state.completeCopy(attempt, succeeded: true, current: value, generating: false)); XCTAssertEqual(state.phase, .failed)
    }
    func testNewOperationRetiresOldFeedbackEvenWithSameTextAndGeneration() throws {
        let value = context(); var state = ready(value); let permit = try XCTUnwrap(state.permit(value, generating: false))
        let attempt = try XCTUnwrap(state.beginCopy(permit, current: value, generating: false)); let newer = context()
        state.bind(newer); XCTAssertEqual(state.phase, .idle)
        XCTAssertFalse(state.completeCopy(attempt, succeeded: true, current: newer, generating: false))
        XCTAssertNil(state.choose(.jingan, permit: permit, current: newer, generating: false))
    }
    func testLeaveReenterSameContextRetiresOldPermit() throws {
        let value = context(); var state = ready(value); let old = try XCTUnwrap(state.permit(value, generating: false))
        state.leave(); state.appear(); XCTAssertFalse(state.accepts(old, current: value, generating: false))
        XCTAssertNotNil(state.permit(value, generating: false))
    }
    func testIdentityAndContextABARejectsOldPermit() throws {
        let value = context(); var state = ready(value); let old = try XCTUnwrap(state.permit(value, generating: false))
        let other = ClubAIDesignFeedbackContext(clubID: 41, session: .init(namespace: "other", accountID: 7, epoch: owner.epoch, role: "club", region: .china), operationID: value.operationID)
        state.bind(other); state.bind(value); XCTAssertFalse(state.accepts(old, current: value, generating: false))
    }
    func testCurrentTextComparisonIsByteExact() {
        let operation = UUID(); XCTAssertNotEqual(context(operation, copy: "é"), context(operation, copy: "e\u{301}"))
        XCTAssertNotEqual(context(operation, copy: "text"), context(operation, copy: " text"))
    }
    func testMissingResultAndEmptyCopyCannotStart() throws {
        for value in [context(copy: ""), context(generation: nil)] {
            var state = ready(value); let permit = try XCTUnwrap(state.permit(value, generating: false))
            XCTAssertNil(state.beginCopy(permit, current: value, generating: false))
        }
    }
    func testMissingCurrentResultRetiresPendingSuccess() throws {
        let value = context(); var state = ready(value); let permit = try XCTUnwrap(state.permit(value, generating: false))
        let attempt = try XCTUnwrap(state.beginCopy(permit, current: value, generating: false))
        XCTAssertFalse(state.completeCopy(attempt, succeeded: true, current: nil, generating: false)); XCTAssertEqual(state.phase, .idle)
    }
}
