import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor private final class TemplateAssistFake: MerchantTemplateAssistServing {
    var session: PublishingSession? = .init(namespace: "synthetic", accountID: 901, epoch: UUID(), role: "merchant", region: .china)
    var canGenerate = true
    var calls = 0
    var cancelled = 0
    var failure: MerchantTemplateAssistFailure?
    var onGenerate: (() -> Void)?
    var suspend = false
    var continuation: CheckedContinuation<Void, Never>?
    var value: ProjectEditJSON = .object(["template": .object(["title": .string("Generated"), "questionName": .string("Which sign?"), "optionA": .string("Lantern"), "optionB": .string("Clock"), "correctAnswer": .string("A"), "validationMethod": .number(3), "description": .string("Generated description"), "feedbackText": .string("Well done")])])
    func generate(_ input: MerchantTemplateAssistInput) async throws -> MerchantTemplateAssistResult {
        calls += 1; onGenerate?()
        if suspend { await withCheckedContinuation { continuation = $0 } }
        if let failure { throw failure }
        return try .init(value)
    }
    func cancel() { cancelled += 1 }
}
@MainActor final class MerchantTemplateAssistTests: XCTestCase {
    private func setup(id: Int? = nil) async -> (MerchantOperationsFixtureReader, MerchantOperationsCoordinator, TemplateAssistFake, MerchantTemplateAssistFlow) {
        let reader = MerchantOperationsFixtureReader()
        let coordinator = MerchantOperationsCoordinator(reader: reader, destination: .template(id))
        await coordinator.load()
        let client = TemplateAssistFake()
        let flow = MerchantTemplateAssistFlow(coordinator: coordinator, client: client)
        flow.shopName = "Synthetic shop"; flow.prompt = "A sign quiz"
        return (reader, coordinator, client, flow)
    }
    private func template(_ coordinator: MerchantOperationsCoordinator) throws -> MerchantNodeTemplate {
        guard case .template(let value) = coordinator.draft else { throw MerchantTemplateAssistFailure.stale }; return value
    }
    func testExactInputContractRequiresShopNameAndPrompt() throws {
        XCTAssertThrowsError(try MerchantTemplateAssistInput(shopName: " ", prompt: "quiz", method: nil)) { XCTAssertEqual($0 as? MerchantTemplateAssistFailure, .shopNameRequired) }
        XCTAssertThrowsError(try MerchantTemplateAssistInput(shopName: "shop", prompt: "\n", method: nil)) { XCTAssertEqual($0 as? MerchantTemplateAssistFailure, .promptRequired) }
        let input = try MerchantTemplateAssistInput(shopName: " shop ", prompt: " quiz ", method: .quiz)
        XCTAssertEqual(input.assistance.request.path, "api/ai/template/fill")
        XCTAssertEqual(input.assistance.request.fields, ["shopName": .string("shop"), "extraNote": .string("quiz"), "category": .string(""), "reward": .string(""), "playStyle": .string(""), "validationMethod": .number(3)])
    }
    func testNoRequestOnOpenEmptyInputOrDefaultDisabled() async {
        let (_, coordinator, client, flow) = await setup()
        XCTAssertEqual(client.calls, 0)
        flow.prompt = " "; await flow.generate(); XCTAssertEqual(flow.failure, .promptRequired); XCTAssertEqual(client.calls, 0)
        let disabled = MerchantTemplateAssistFlow(coordinator: coordinator, client: nil)
        XCTAssertFalse(disabled.canGenerate); await disabled.generate(); XCTAssertEqual(disabled.failure, .disabled)
    }
    func testTemplateNodeAndRootWrappersWithTemplatePrecedence() throws {
        let data: ProjectEditJSON = .object(["questionAnswer": .string("answer")])
        for response in [data, .object(["node": data]), .object(["template": data]), .object(["template": .null, "node": data])] {
            XCTAssertEqual(try MerchantTemplateAssistResult(response).text("questionAnswer"), "answer")
        }
        let preferred = try MerchantTemplateAssistResult(.object(["template": data, "node": .object(["questionAnswer": .string("wrong")])]))
        XCTAssertEqual(preferred.text("questionAnswer"), "answer")
    }
    func testSixFieldEmptyRuleAndParseFailure() throws {
        XCTAssertTrue(try MerchantTemplateAssistResult(.object(["title": .string("title"), "description": .string("description")])).isEmpty)
        for key in ["storyText", "ruleInstructions", "questionName", "questionAnswer", "hint1", "hint2"] {
            XCTAssertFalse(try MerchantTemplateAssistResult(.object([key: .string("value")])).isEmpty)
        }
        XCTAssertThrowsError(try MerchantTemplateAssistResult(.object(["parseError": .string("bad"), "template": .object(["questionName": .string("ignored")])])))
        XCTAssertThrowsError(try MerchantTemplateAssistResult(.object(["questionName": .array([])])))
    }
    func testGenerateDoesNotMutateAndOnlyExplicitApplyReturnsToExactDraft() async throws {
        let (reader, coordinator, client, flow) = await setup()
        let original = coordinator.draft
        await flow.generate()
        XCTAssertEqual(client.calls, 1); XCTAssertEqual(coordinator.draft, original); XCTAssertEqual(reader.saveCount, 0); XCTAssertTrue(flow.canApply)
        let returned = await flow.apply(), value = try XCTUnwrap(returned)
        XCTAssertEqual(coordinator.draft, original); XCTAssertEqual(value.title, "Generated"); XCTAssertEqual(value.correctAnswer, "A")
        coordinator.edit(.template(value))
        XCTAssertEqual(try template(coordinator), value); XCTAssertNil(coordinator.confirmation); XCTAssertEqual(reader.saveCount, 0)
        let repeated = await flow.apply(); XCTAssertNil(repeated)
    }
    func testExistingContentMethodMediaAndCouponNeverOverwritten() async throws {
        let (reader, coordinator, _, flow) = await setup(id: 71)
        let before = try template(coordinator); await flow.generate()
        XCTAssertFalse(flow.canApply)
        XCTAssertEqual(flow.preview, before); XCTAssertEqual(try template(coordinator).couponID, 19); XCTAssertEqual(reader.saveCount, 0)
    }
    func testEditsAndIntentionalClearsDuringGenerationArePreserved() async throws {
        let (_, coordinator, client, flow) = await setup()
        client.onGenerate = {
            var draft = MerchantNodeTemplate(); draft.title = "My title"; draft.description = "My description"; draft.method = .photo; draft.optionA = "My option"
            coordinator.edit(.template(draft)); draft.description = ""; coordinator.edit(.template(draft))
        }
        await flow.generate()
        let returned = await flow.apply(), value = try XCTUnwrap(returned)
        XCTAssertEqual(value.title, "My title"); XCTAssertEqual(value.description, ""); XCTAssertEqual(value.method, .photo); XCTAssertEqual(value.optionA, "My option"); XCTAssertEqual(value.correctAnswer, "")
    }
    func testEditsAfterReviewAndBeforeApplyArePreserved() async throws {
        let (_, coordinator, _, flow) = await setup(); await flow.generate()
        var draft = try template(coordinator); draft.feedbackText = "Manual feedback"; coordinator.edit(.template(draft))
        let returned = await flow.apply(); XCTAssertEqual(returned?.feedbackText, "Manual feedback")
    }
    func testUnsupportedFieldsAndStorySummaryStayVisibleAndOutOfSaveFields() throws {
        let story = String(repeating: "故事", count: 20)
        let result = try MerchantTemplateAssistResult(.object(["storyText": .string(story), "medalName": .string("Badge"), "hint1": .string("Hint"), "hint2": .string("Hint two"), "answerReveal": .string("Reveal"), "ruleInstructions": .string("Rules"), "futureField": .object(["value": .number(1)]), "validationMethod": .number(99)]))
        XCTAssertEqual(result.unsupportedKeys, ["answerReveal", "futureField", "hint1", "hint2", "medalName", "ruleInstructions", "storyText", "validationMethod"])
        XCTAssertEqual(result.display("storyText"), story)
        let draft = MerchantNodeTemplate(), merged = result.merge(into: draft, captured: draft, edits: .init(), capturedEdits: .init())
        XCTAssertEqual(merged.description, String(story.prefix(30))); XCTAssertNil(merged.method)
        XCTAssertNil(merged.fields["medalName"]); XCTAssertNil(merged.fields["storyText"]); XCTAssertNil(merged.fields["futureField"])
    }
    func testInvalidCorrectAnswerOrMismatchedOptionIsNeverGuessed() throws {
        for correct in ["E", "D", "A"] {
            let result = try MerchantTemplateAssistResult(.object(["questionName": .string("Quiz"), "validationMethod": .number(3), "optionA": .string("AI A"), "optionB": .string("AI B"), "correctAnswer": .string(correct)]))
            var draft = MerchantNodeTemplate(); if correct == "A" { draft.optionA = "Manual A" }
            let merged = result.merge(into: draft, captured: draft, edits: .init(), capturedEdits: .init())
            XCTAssertEqual(merged.correctAnswer, "")
        }
    }
    func testPermissionAndProviderFailuresHaveDifferentRetryBehavior() async {
        XCTAssertEqual(MerchantTemplateAssistFailure.rejection("当前身份暂不支持AI创作,请切换到俱乐部或商家身份"), .permission)
        XCTAssertEqual(MerchantTemplateAssistFailure.rejection("AI 服务暂时不可用,请稍后重试"), .provider)
        let (_, _, client, flow) = await setup(); client.failure = .permission
        await flow.generate(); XCTAssertEqual(flow.failure, .permission); XCTAssertFalse(flow.canGenerate)
        let (_, _, retryClient, retry) = await setup(); retryClient.failure = .provider
        await retry.generate(); XCTAssertEqual(retry.failure, .provider); XCTAssertTrue(retry.canGenerate)
        retryClient.failure = nil; await retry.generate(); XCTAssertNotNil(retry.result)
    }
    func testPermissionRevokedBeforeGenerationOrApplyNeverMutates() async {
        let (reader, coordinator, client, flow) = await setup(); reader.denied = true
        await flow.generate(); XCTAssertEqual(flow.failure, .permission); XCTAssertEqual(client.calls, 0)
        let (applyReader, applyCoordinator, _, applyFlow) = await setup(); await applyFlow.generate(); applyReader.denied = true
        let returned = await applyFlow.apply(); XCTAssertNil(returned); XCTAssertEqual(applyFlow.failure, .permission)
        XCTAssertFalse(coordinator.isDirty); XCTAssertFalse(applyCoordinator.isDirty); XCTAssertEqual(applyReader.saveCount, 0)
    }
    func testCancelAndSessionOrDraftReplacementDiscardLateResults() async {
        let (_, coordinator, client, flow) = await setup(); client.onGenerate = { flow.cancel() }
        await flow.generate(); XCTAssertEqual(flow.failure, .cancelled); XCTAssertNil(flow.result); XCTAssertFalse(coordinator.isDirty)
        let (_, _, changedClient, changed) = await setup(); changedClient.onGenerate = { changedClient.session = nil }
        await changed.generate(); XCTAssertEqual(changed.failure, .stale); XCTAssertNil(changed.result)
        let (_, replacedCoordinator, replacedClient, replaced) = await setup(); replacedClient.onGenerate = { replacedCoordinator.discardChanges() }
        await replaced.generate(); XCTAssertEqual(replaced.failure, .stale); XCTAssertNil(replaced.result)
    }
    func testSameRecordReloadFencesOldResultAndUnknownNeverRetries() async {
        let (_, coordinator, _, flow) = await setup(); await flow.generate(); await coordinator.load()
        XCTAssertFalse(flow.canApply); let returned = await flow.apply(); XCTAssertNil(returned)
        let (_, _, client, unknown) = await setup(); client.failure = .unknown
        await unknown.generate(); XCTAssertEqual(unknown.failure, .unknown); XCTAssertFalse(unknown.canGenerate)
    }
    func testRepeatedGenerateIsIgnoredAndTaskCancellationCannotApply() async {
        let (_, coordinator, client, flow) = await setup()
        let started = expectation(description: "Synthetic request entered")
        client.suspend = true; client.onGenerate = { started.fulfill() }
        let request = Task { await flow.generate() }
        await fulfillment(of: [started], timeout: 2)
        XCTAssertTrue(flow.busy)
        await flow.generate(); XCTAssertEqual(client.calls, 1); XCTAssertNil(flow.failure)
        request.cancel(); client.continuation?.resume(); client.continuation = nil
        await request.value
        XCTAssertEqual(flow.failure, .cancelled); XCTAssertFalse(flow.busy); XCTAssertNil(flow.result)
        XCTAssertFalse(coordinator.isDirty)
    }
    func testEmptyResponseHasNoApplyAndCanRetry() async {
        let (_, _, client, flow) = await setup(); client.value = .object(["title": .string("Only title")])
        await flow.generate(); XCTAssertEqual(flow.failure, .empty); XCTAssertNil(flow.result); XCTAssertFalse(flow.canApply); XCTAssertTrue(flow.canGenerate)
    }
}
