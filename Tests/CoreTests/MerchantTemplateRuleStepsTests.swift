import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private func rulesTemplate(_ source: String? = "Find the sign\nRead the clue") -> MerchantNodeTemplate {
    var value = MerchantNodeTemplate(); value.id = 71; value.title = "Rules"; value.method = .photo
    value.ruleSteps = .init(sourceText: source); return value
}

final class MerchantTemplateRuleStepsContractTests: XCTestCase {
    func testDecodeMissingNullAndMalformedTypes() throws {
        for raw in ["{}", #"{"ruleInstructions":null}"#] {
            let value = try JSONDecoder().decode(MerchantNodeTemplate.self, from: Data(raw.utf8))
            XCTAssertEqual(value.ruleSteps.rows, [""]); XCTAssertNil(value.fields["ruleInstructions"])
        }
        for raw in [#"{"ruleInstructions":42}"#, #"{"ruleInstructions":[]}"#, #"{"ruleInstructions":true}"#] {
            XCTAssertThrowsError(try JSONDecoder().decode(MerchantNodeTemplate.self, from: Data(raw.utf8)))
        }
    }
    func testExistingRulesHydrateStepsWithoutChangingRawServerText() throws {
        let raw = #"{"ruleInstructions":"  Find sign\n\n Read clue \r\n"}"#
        let value = try JSONDecoder().decode(MerchantNodeTemplate.self, from: Data(raw.utf8))
        XCTAssertEqual(value.ruleSteps.rows, ["Find sign", "Read clue"])
        XCTAssertEqual(value.fields["ruleInstructions"] as? String, "  Find sign\n\n Read clue \r\n")
        XCTAssertFalse(value.ruleSteps.isEdited)
    }
    func testAddEditRemoveAndBlankRowsUseTheExistingLineJoinedString() {
        var rules = MerchantTemplateRuleSteps()
        rules.update(at: 0, text: " Find sign "); rules.add(); rules.update(at: 1, text: "Read clue")
        rules.add(); XCTAssertEqual(rules.rows.count, 3)
        XCTAssertEqual(rules.wireValue, "Find sign\nRead clue")
        rules.remove(at: 0); XCTAssertEqual(rules.rows, ["Read clue", ""])
        XCTAssertEqual(rules.wireValue, "Read clue"); XCTAssertNil(rules.blocker)
    }
    func testInvalidIndicesNoChangeAndFinalRowCannotBeRemoved() {
        var rules = MerchantTemplateRuleSteps(sourceText: " Keep source ")
        let original = rules
        rules.update(at: -1, text: "No"); rules.update(at: 99, text: "No")
        rules.remove(at: -1); rules.remove(at: 99); rules.remove(at: 0)
        rules.update(at: 0, text: "Keep source")
        XCTAssertEqual(rules, original)
    }
    func testAddLimitDoesNotTruncateAnOversizedLegacyTemplate() {
        var rules = MerchantTemplateRuleSteps()
        for _ in 0..<20 { rules.add() }
        XCTAssertEqual(rules.rows.count, 12); XCTAssertFalse(rules.canAdd)
        let source = (1...13).map { "Step \($0)" }.joined(separator: "\n")
        var legacy = MerchantTemplateRuleSteps(sourceText: source)
        XCTAssertEqual(legacy.rows.count, 13); XCTAssertNil(legacy.blocker)
        legacy.add(); XCTAssertEqual(legacy.wireValue, source); XCTAssertFalse(legacy.isEdited)
        legacy.update(at: 0, text: "Changed"); XCTAssertEqual(legacy.blocker, "merchant.ruleSteps.countLimit")
        legacy.remove(at: 12); XCTAssertNil(legacy.blocker); XCTAssertEqual(legacy.rows.count, 12)
    }
    func testLengthLimitsUseUTF16AndNeverSilentlyTruncate() {
        var rules = MerchantTemplateRuleSteps(sourceText: String(repeating: "x", count: 61))
        XCTAssertNil(rules.blocker); XCTAssertEqual(rules.rows[0].count, 61)
        rules.update(at: 0, text: String(repeating: "x", count: 62))
        XCTAssertEqual(rules.blocker, "merchant.ruleSteps.textLimit"); XCTAssertEqual(rules.rows[0].count, 62)
        rules.update(at: 0, text: String(repeating: "🧩", count: 30)); XCTAssertNil(rules.blocker)
        rules.update(at: 0, text: String(repeating: "🧩", count: 31))
        XCTAssertEqual(rules.blocker, "merchant.ruleSteps.textLimit")
    }
    func testPastedNewlinesBlockReviewInsteadOfSmugglingExtraSteps() {
        var value = rulesTemplate(); value.ruleSteps.update(at: 0, text: "One\nTwo")
        XCTAssertEqual(value.blocker, "merchant.ruleSteps.oneLine")
        XCTAssertThrowsError(try MerchantOperationsDraft.template(value).previews())
        XCTAssertEqual(value.ruleSteps.rows[0], "One\nTwo")
    }
    func testExplicitAllEmptyEditSendsEmptyStringWhileUntouchedMissingIsOmitted() throws {
        var value = rulesTemplate("Old rule"); value.ruleSteps.update(at: 0, text: "  ")
        XCTAssertTrue(value.ruleSteps.isClearing)
        let preview = try XCTUnwrap(MerchantOperationsDraft.template(value).previews().first)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: preview.json) as? [String: Any])
        XCTAssertEqual(body["ruleInstructions"] as? String, "")
        XCTAssertNil(body["ruleSteps"]); XCTAssertNil(body["clearRuleInstructions"])
        XCTAssertNil(rulesTemplate(nil).fields["ruleInstructions"])
    }
    func testExactWireKeyAndExistingRewardReferenceOnly() throws {
        var value = rulesTemplate(); value.couponID = 19; value.ruleSteps.update(at: 1, text: " Pick a symbol ")
        let preview = try XCTUnwrap(MerchantOperationsDraft.template(value).previews().first)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: preview.json) as? [String: Any])
        XCTAssertEqual(preview.path, "api/merchant/city-node/template/submit")
        XCTAssertEqual(body["ruleInstructions"] as? String, "Find the sign\nPick a symbol")
        XCTAssertEqual(body["couponId"] as? Int, 19)
        XCTAssertNil(body["merchantGuide"]); XCTAssertNil(body["rewardRulesJson"])
        XCTAssertNil(body["isEdited"]); XCTAssertNil(body["sourceText"])
    }
    func testAISuggestionCannotReplaceRulesAndLocalPlansStillBlockSending() throws {
        var value = rulesTemplate()
        let result = try MerchantTemplateAssistResult(.object(["ruleInstructions": .string("Unreviewed rules")]))
        let merged = result.merge(into: value, captured: value, edits: .init(), capturedEdits: .init())
        XCTAssertEqual(merged.ruleSteps, value.ruleSteps); XCTAssertTrue(result.unsupportedKeys.contains("ruleInstructions"))
        var plan = MerchantTemplateExitPlan(); plan.offlineAlternative = "Printed card"; plan.failureExit = "Stop playing"
        value.exitPlan = plan
        XCTAssertThrowsError(try MerchantOperationsDraft.template(value).previews()) {
            XCTAssertEqual($0 as? MerchantOperationsFailure, .liveWritesDisabled)
        }
    }
}

@MainActor final class MerchantTemplateRuleStepsFlowTests: XCTestCase {
    func testFrozenReviewCancelStaleConfirmAndDiscard() async throws {
        let reader = MerchantOperationsFixtureReader(); let source = rulesTemplate()
        reader.replace(.template(71), with: .draft(.template(source)))
        let coordinator = MerchantOperationsCoordinator(reader: reader, destination: .template(71))
        await coordinator.load(); var edited = source; edited.ruleSteps.update(at: 1, text: "Choose a symbol")
        coordinator.edit(.template(edited)); coordinator.prepare(); let review = try XCTUnwrap(coordinator.confirmation)
        coordinator.cancelConfirmation(); XCTAssertEqual(coordinator.draft, .template(edited))
        edited.ruleSteps.remove(at: 1); coordinator.edit(.template(edited))
        if case .template(let frozen) = review.draft { XCTAssertEqual(frozen.ruleSteps.wireValue, "Find the sign\nChoose a symbol") }
        else { XCTFail() }
        await coordinator.confirm(review); XCTAssertEqual(reader.saveCount, 0)
        coordinator.discardChanges(); XCTAssertEqual(coordinator.draft, .template(source)); XCTAssertFalse(coordinator.isDirty)
    }
    func testFixtureAcknowledgedClearReadbackConsumesEditIntentAndCannotReplay() async throws {
        let reader = MerchantOperationsFixtureReader(); let source = rulesTemplate("Old rule")
        reader.replace(.template(71), with: .draft(.template(source)))
        let coordinator = MerchantOperationsCoordinator(reader: reader, destination: .template(71))
        await coordinator.load(); var draft = source; draft.ruleSteps.update(at: 0, text: "")
        coordinator.edit(.template(draft)); coordinator.prepare(); let review = try XCTUnwrap(coordinator.confirmation)
        await coordinator.confirm(review)
        guard case .template(let returned) = coordinator.draft else { return XCTFail() }
        XCTAssertEqual(returned.ruleSteps.wireValue, ""); XCTAssertFalse(returned.ruleSteps.isEdited)
        XCTAssertFalse(coordinator.isDirty); XCTAssertEqual(reader.saveCount, 1)
        await coordinator.confirm(review); XCTAssertEqual(reader.saveCount, 1)
        await coordinator.load(); XCTAssertEqual(coordinator.draft, .template(returned))
    }
}

private final class RuleStepsTransport: HTTPTransport {
    var replies: [String] = [], requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); guard !replies.isEmpty else { throw APIError.malformedResponse }
        return (Data(replies.removeFirst().utf8), 200)
    }
}
@MainActor private final class RuleStepsJournal: OperationPendingJournal {
    var record: OperationPendingRecord?
    func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? { record }
    func write(_ record: OperationPendingRecord) throws { self.record = record }
    func clear(_ record: OperationPendingRecord) throws { self.record = nil }
}
@MainActor final class MerchantTemplateRuleStepsServiceTests: XCTestCase {
    private func exerciseApprovedSave(editedText: String, canonicalText: String) async throws {
        let access = #"{"code":200,"data":{"active":true,"merchant":{"id":31},"roleCode":"MERCHANT_OWNER","permissions":["merchant:project:manage"]}}"#
        let initial = #"{"code":200,"data":{"id":71,"title":"Rules","validationMethod":2,"ruleInstructions":"Old rule"}}"#
        let returned = String(decoding: try JSONSerialization.data(withJSONObject: ["code": 200, "data": ["id": 71, "title": "Rules", "validationMethod": 2, "ruleInstructions": canonicalText]]), as: UTF8.self)
        let transport = RuleStepsTransport()
        transport.replies = [access, initial, access, initial, access, initial, #"{"code":200,"data":71}"#, access, returned]
        let api = try APIConfiguration(baseURL: URL(string: "https://example.test/prod-api")!)
        let session = try MerchantOperationsSession(accountID: 7, epoch: 1, token: "synthetic-token", storageNamespace: "rules-test")
        let approval = try OperationEndpointApproval(baseURL: api.baseURL, namespace: session.storageNamespace, accountID: session.accountID, paths: ["api/merchant/city-node/template/submit"])
        let journal = RuleStepsJournal()
        let reader = MerchantOperationsSessionReader(service: MerchantOperationsService(configuration: api, transport: transport), currentSession: { session }, approval: approval, journal: journal)
        let coordinator = MerchantOperationsCoordinator(reader: reader, destination: .template(71))
        await coordinator.load(); var draft = rulesTemplate("Old rule"); draft.ruleSteps.update(at: 0, text: editedText)
        coordinator.edit(.template(draft)); coordinator.prepare(); let review = try XCTUnwrap(coordinator.confirmation)
        await coordinator.confirm(review)
        let saves = transport.requests.filter { $0.url?.path.hasSuffix("/template/submit") == true }
        XCTAssertEqual(saves.count, 1)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(saves.first?.httpBody)) as? [String: Any])
        XCTAssertEqual(payload["ruleInstructions"] as? String, editedText.trimmingCharacters(in: .whitespacesAndNewlines))
        XCTAssertNil(payload["ruleSteps"]); XCTAssertNil(payload["merchantGuide"])
        guard case .template(let source) = coordinator.draft else { return XCTFail() }
        XCTAssertEqual(source.ruleSteps.wireValue, canonicalText); XCTAssertFalse(source.ruleSteps.isEdited)
        XCTAssertEqual(transport.requests.last?.url?.path, "/prod-api/api/template/myinfo")
        XCTAssertNil(journal.record); XCTAssertFalse(coordinator.isDirty)
        let count = transport.requests.count; await coordinator.confirm(review); XCTAssertEqual(transport.requests.count, count)
    }
    func testApprovedSyntheticSaveUsesExistingFieldAndAuthoritativeReadbackWins() async throws {
        try await exerciseApprovedSave(editedText: " Find the sign ", canonicalText: "Server canonical instruction")
    }
    func testApprovedSyntheticClearSendsEmptyStringAndReadsBackEmpty() async throws {
        try await exerciseApprovedSave(editedText: "", canonicalText: "")
    }
    func testMissingApprovalCannotSendRules() async throws {
        let transport = RuleStepsTransport()
        let api = try APIConfiguration(baseURL: URL(string: "https://example.test/prod-api")!)
        let session = try MerchantOperationsSession(accountID: 7, epoch: 1, token: "synthetic-token", storageNamespace: "rules-denied")
        let reader = MerchantOperationsSessionReader(service: MerchantOperationsService(configuration: api, transport: transport), currentSession: { session })
        XCTAssertFalse(reader.canSave)
        do { _ = try await reader.saveTemplateReviewed(rulesTemplate(), baseline: rulesTemplate()); XCTFail() }
        catch { XCTAssertEqual(error as? MerchantOperationsFailure, .liveWritesDisabled) }
        XCTAssertTrue(transport.requests.isEmpty)
    }
}
