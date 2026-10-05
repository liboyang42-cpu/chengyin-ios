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
@MainActor private final class TemplateAssistAccessReader: MerchantOperationsReading {
    let base = MerchantOperationsFixtureReader()
    var scope: UUID { base.scope }
    var isConfigured: Bool { base.isConfigured }
    var isAuthenticated: Bool { base.isAuthenticated }
    var isOfflineExample: Bool { true }
    var onHeldAccess: (() -> Void)?
    var continuation: CheckedContinuation<Void, Never>?
    func access() async throws -> MerchantOperationsAccess {
        if let onHeldAccess { await withCheckedContinuation { continuation = $0; onHeldAccess() } }
        return try await base.access()
    }
    func document(_ destination: MerchantOperationsDestination) async throws -> MerchantOperationsDocument { try await base.document(destination) }
    func saveExample(_ draft: MerchantOperationsDraft) async throws { try await base.saveExample(draft) }
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
    private func action(_ flow: MerchantTemplateAssistFlow, _ field: MerchantTemplateAssistField) throws -> MerchantTemplateSuggestionReview.Action {
        let review = try XCTUnwrap(flow.visibleReview)
        return review.action(for: try XCTUnwrap(review.suggestions.first { $0.field == field }))
    }
    private func accept(_ field: MerchantTemplateAssistField, in flow: MerchantTemplateAssistFlow,
                        file: StaticString = #filePath, line: UInt = #line) async throws {
        let accepted = await flow.change(try action(flow, field), .accept)
        XCTAssertTrue(accepted, file: file, line: line)
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
    func testGenerateDoesNotMutateAndOnlyExplicitFieldAcceptChangesExactDraft() async throws {
        let (reader, coordinator, client, flow) = await setup()
        let original = coordinator.draft
        await flow.generate()
        XCTAssertEqual(client.calls, 1); XCTAssertEqual(coordinator.draft, original); XCTAssertEqual(reader.saveCount, 0); XCTAssertTrue(flow.canAcceptAny)
        let titleAction = try action(flow, .title)
        try await accept(.title, in: flow)
        XCTAssertEqual(try template(coordinator).title, "Generated")
        XCTAssertEqual(try template(coordinator).questionName, "", "Accept one field cannot silently accept another")
        for field: MerchantTemplateAssistField in [.questionName, .optionA, .optionB, .validationMethod, .correctAnswer] { try await accept(field, in: flow) }
        let value = try template(coordinator)
        XCTAssertEqual(value.correctAnswer, "A"); XCTAssertNil(coordinator.confirmation); XCTAssertEqual(reader.saveCount, 0)
        let repeated = await flow.change(titleAction, .accept); XCTAssertFalse(repeated)
    }
    func testExistingContentMethodMediaAndCouponNeverOverwritten() async throws {
        let (reader, coordinator, _, flow) = await setup(id: 71)
        let before = try template(coordinator); await flow.generate()
        XCTAssertFalse(flow.canAcceptAny)
        XCTAssertEqual(try template(coordinator), before); XCTAssertEqual(try template(coordinator).couponID, 19); XCTAssertEqual(reader.saveCount, 0)
    }
    func testEditsAndIntentionalClearsDuringGenerationArePreserved() async throws {
        let (_, coordinator, client, flow) = await setup()
        client.onGenerate = {
            var draft = MerchantNodeTemplate(); draft.title = "My title"; draft.description = "My description"; draft.method = .photo; draft.optionA = "My option"
            coordinator.edit(.template(draft)); draft.description = ""; coordinator.edit(.template(draft))
        }
        await flow.generate()
        XCTAssertFalse(flow.canChange(try action(flow, .title), change: .accept))
        XCTAssertFalse(flow.canChange(try action(flow, .description), change: .accept))
        for field: MerchantTemplateAssistField in [.questionName, .optionB, .feedbackText] { try await accept(field, in: flow) }
        let value = try template(coordinator)
        XCTAssertEqual(value.title, "My title"); XCTAssertEqual(value.description, ""); XCTAssertEqual(value.method, .photo); XCTAssertEqual(value.optionA, "My option"); XCTAssertEqual(value.correctAnswer, "")
    }
    func testEditsAfterReviewAndBeforeApplyArePreserved() async throws {
        let (_, coordinator, _, flow) = await setup(); await flow.generate()
        var draft = try template(coordinator); draft.feedbackText = "Manual feedback"; coordinator.edit(.template(draft))
        try await accept(.title, in: flow); XCTAssertEqual(try template(coordinator).feedbackText, "Manual feedback")
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
    func testPermissionRevokedBeforeGenerationOrApplyNeverMutates() async throws {
        let (reader, coordinator, client, flow) = await setup(); reader.denied = true
        await flow.generate(); XCTAssertEqual(flow.failure, .permission); XCTAssertEqual(client.calls, 0)
        let (applyReader, applyCoordinator, _, applyFlow) = await setup(); await applyFlow.generate(); applyReader.denied = true
        let changed = await applyFlow.change(try action(applyFlow, .title), .accept); XCTAssertFalse(changed); XCTAssertEqual(applyFlow.failure, .permission)
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
    func testSameRecordReloadFencesOldResultAndUnknownNeverRetries() async throws {
        let (_, coordinator, _, flow) = await setup(); await flow.generate()
        let oldAction = try action(flow, .title); await coordinator.load()
        XCTAssertFalse(flow.canAcceptAny); XCTAssertNil(flow.visibleReview)
        let changed = await flow.change(oldAction, .accept); XCTAssertFalse(changed)
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
        await flow.generate(); XCTAssertEqual(flow.failure, .empty); XCTAssertNil(flow.result); XCTAssertFalse(flow.canAcceptAny); XCTAssertTrue(flow.canGenerate)
    }
    func testFinalFieldCheckAfterPermissionReadPreservesConcurrentEdits() async throws {
        for sameField in [false, true] {
            let reader = TemplateAssistAccessReader(), coordinator = MerchantOperationsCoordinator(reader: reader, destination: .template(nil))
            await coordinator.load(); let flow = MerchantTemplateAssistFlow(coordinator: coordinator, client: TemplateAssistFake())
            flow.shopName = "Synthetic"; flow.prompt = "Question"; await flow.generate()
            let action = try action(flow, .title), started = expectation(description: "permission read held")
            reader.onHeldAccess = { started.fulfill() }
            let task = Task { await flow.change(action, .accept) }
            await fulfillment(of: [started], timeout: 2)
            var current = try template(coordinator)
            if sameField { current.title = "Manual" } else { current.feedbackText = "  Preserve newest\n" }
            coordinator.edit(.template(current))
            reader.continuation?.resume(); reader.continuation = nil
            let accepted = await task.value
            XCTAssertEqual(accepted, !sameField)
            XCTAssertEqual(try template(coordinator).title, sameField ? "Manual" : "Generated")
            XCTAssertEqual(try template(coordinator).feedbackText, current.feedbackText)
            XCTAssertEqual(reader.base.saveCount, 0); XCTAssertNil(coordinator.confirmation)
        }
    }
    func testCancelOrIdentityReplacementDuringFieldPermissionReadPreventsCommit() async throws {
        for interruption in ["cancel", "discard", "owner", "task"] {
            let reader = TemplateAssistAccessReader(), coordinator = MerchantOperationsCoordinator(reader: reader, destination: .template(nil))
            await coordinator.load(); let flow = MerchantTemplateAssistFlow(coordinator: coordinator, client: TemplateAssistFake())
            flow.shopName = "Synthetic"; flow.prompt = "Question"; await flow.generate()
            let action = try action(flow, .title), before = coordinator.draft, started = expectation(description: "permission read held")
            reader.onHeldAccess = { started.fulfill() }
            let task = Task { await flow.change(action, .accept) }
            await fulfillment(of: [started], timeout: 2)
            switch interruption {
            case "cancel": flow.close()
            case "discard": coordinator.discardChanges()
            case "owner": reader.base.switchAccount()
            default: task.cancel()
            }
            reader.continuation?.resume(); reader.continuation = nil
            let accepted = await task.value
            XCTAssertFalse(accepted); XCTAssertEqual(coordinator.draft, before); XCTAssertEqual(reader.base.saveCount, 0)
        }
    }
}
