import XCTest
@testable import QuestifyCore

final class ProjectEditCompletionRulesTests: XCTestCase {
    private func configured(raw: ProjectEditJSON? = nil) -> ProjectEditCompletionRules {
        var rules = ProjectEditCompletionRules(raw: raw); rules.bingoEnabled = true
        for position in 0..<9 {
            rules.cells[position].label = "position-\(position)"
            rules.cells[position].couponID = String(100 + position)
            rules.cells[position].feedbackText = "reward-\(position)"
        }
        return rules
    }
    func testPhysicalPositionRoundTripDespiteSOrder() throws {
        let rules = configured(); let wire = try rules.serialized(matching: nil)
        let reopened = ProjectEditCompletionRules(raw: wire)
        XCTAssertEqual(ProjectEditCompletionRules.displayOrder, [0, 1, 2, 5, 4, 3, 6, 7, 8])
        XCTAssertEqual(reopened.cells, rules.cells); XCTAssertTrue(reopened.bingoEnabled)
        for position in ProjectEditCompletionRules.displayOrder { XCTAssertEqual(reopened.cells[position].couponID, String(100 + position)) }
    }
    func testUnknownRootKeysPreservedWhileEditingKnownRules() throws {
        let source = ProjectEditJSON.string(#"{"future":{"version":8,"enabled":true},"nodeCompletion":{"mode":"AT_LEAST","requiredCount":2}}"#)
        var rules = configured(raw: source); rules.cells[5].feedbackText = "changed"
        let serialized = try XCTUnwrap(try rules.serialized(matching: source)?.text)
        let root = try JSONDecoder().decode(ProjectEditJSON.self, from: Data(serialized.utf8)).object
        XCTAssertEqual(root?["future"], .object(["version": .number(8), "enabled": .bool(true)]))
        XCTAssertEqual(root?["nodeCompletion"], .object(["mode": .string("AT_LEAST"), "requiredCount": .number(2)]))
    }
    func testMalformedAndFutureNestedShapesAreLosslessReadOnly() throws {
        let sources = ["{bad", "[]", "null", #"{"nodeCompletion":{"mode":"FUTURE"}}"#,
            #"{"nodeCompletion":{"mode":"ALL","future":true}}"#,
            #"{"bingo":{"enabled":true,"future":1,"cells":[]}}"#,
            #"{"bingo":{"enabled":true,"cells":[{"nodeId":71}]}}"#]
        for text in sources {
            let source = ProjectEditJSON.string(text); var rules = ProjectEditCompletionRules(raw: source)
            XCTAssertTrue(rules.readOnly, text); rules.mode = "ALL"; rules.bingoEnabled = false
            XCTAssertEqual(try rules.serialized(matching: source), source)
        }
        let source = ProjectEditJSON.object(["future": .bool(true)])
        XCTAssertTrue(ProjectEditCompletionRules(raw: source).readOnly)
        XCTAssertEqual(try ProjectEditCompletionRules(raw: source).serialized(matching: source), source)
    }
    func testDisableRemovesWireKeyButRetainsUnsavedCellsForReenable() throws {
        var rules = configured(); let cells = rules.cells; rules.bingoEnabled = false
        let text = try XCTUnwrap(try rules.serialized(matching: nil)?.text)
        XCTAssertFalse(text.contains("bingo")); XCTAssertEqual(rules.cells, cells)
        rules.bingoEnabled = true
        XCTAssertEqual(ProjectEditCompletionRules(raw: try rules.serialized(matching: nil)).cells, cells)
    }
    func testRewardCountCouponAndUTF16Validation() throws {
        var rules = ProjectEditCompletionRules(raw: nil); rules.bingoEnabled = true
        XCTAssertEqual(rules.issueKey, "projectEdit.completion.rewardRequired")
        rules.cells[0].feedbackText = "reward"; XCTAssertNil(rules.issueKey)
        rules.cells[0].label = String(repeating: "😀", count: 13); XCTAssertEqual(rules.issueKey, "projectEdit.completion.invalidLength")
        rules.cells[0].label = ""
        for invalid in ["-1", "1.5", "abc", "999999999999999999999999"] {
            rules.cells[0].couponID = invalid; XCTAssertEqual(rules.issueKey, "projectEdit.completion.invalidCoupon")
            XCTAssertThrowsError(try rules.serialized(matching: nil))
        }
        rules.cells[0].couponID = "0"; rules.mode = "AT_LEAST"; rules.requiredCount = "0"
        XCTAssertEqual(rules.issueKey, "projectEdit.completion.invalidCount")
        rules.requiredCount = "3"; XCTAssertNil(rules.issueKey)
        rules.cells.removeLast(); XCTAssertEqual(rules.issueKey, "projectEdit.completion.invalidCells")
    }
    func testServerCountAndSixteenKiBLimitsBeforeReview() throws {
        var draft = ProjectEditSyntheticFixtures.draft()
        var rules = configured(); rules.mode = "AT_LEAST"; rules.requiredCount = "2"
        draft.completionRules = rules
        XCTAssertTrue(ProjectEditValidation.issues(draft).contains { $0.key == "projectEdit.completion.tooManyNodes" })
        XCTAssertThrowsError(try ProjectEditContract.payload(draft, topicID: 71, scope: .full))
        rules.requiredCount = "1"; XCTAssertNil(rules.validationIssue(totalNodes: 1))
        let source = ProjectEditJSON.string("{\"future\":\"" + String(repeating: "a", count: 17000) + "\"}")
        let large = configured(raw: source)
        XCTAssertEqual(large.validationIssue(totalNodes: 1), "projectEdit.completion.tooLarge")
        XCTAssertThrowsError(try large.serialized(matching: source))
    }
    func testDraftPayloadAndLocalEnvelopeRoundTrip() throws {
        var draft = ProjectEditSyntheticFixtures.draft(); draft.completionRules = configured()
        let decoded = try JSONDecoder().decode(ProjectEditDraft.self, from: JSONEncoder().encode(draft))
        XCTAssertEqual(decoded, draft)
        let payload = try ProjectEditContract.payload(decoded, topicID: 71, scope: .full)
        XCTAssertEqual(ProjectEditCompletionRules(raw: payload["completeRuleJson"]).cells, configured().cells)
        XCTAssertEqual(try ProjectEditStoryContract.path(payload: payload, baseline: nil), ProjectEditStoryContract.updatePath)
        let whitelist = try ProjectEditContract.payload(decoded, topicID: 71, scope: .whitelist)
        XCTAssertNil(whitelist["completeRuleJson"])
        XCTAssertFalse(decoded.whitelistLockedFieldsEqual(to: ProjectEditSyntheticFixtures.draft()))
    }
    func testOldDraftWithoutNewOptionalPropertyStillDecodes() throws {
        let original = ProjectEditSyntheticFixtures.draft()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        json.removeValue(forKey: "completionRules")
        let decoded = try JSONDecoder().decode(ProjectEditDraft.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.completionRules); XCTAssertEqual(decoded, original)
    }
    func testUnknownRawSurvivesUnrelatedFullSaveByteForByte() throws {
        var draft = ProjectEditSyntheticFixtures.draft(); let source = ProjectEditJSON.string(" {broken future ")
        draft.preserved["completeRuleJson"] = source
        let payload = try ProjectEditContract.payload(draft, topicID: 71, scope: .full)
        XCTAssertEqual(payload["completeRuleJson"], source)
    }
    func testEditDetailActuallyRestoresCompleteRuleJson() throws {
        let source = try XCTUnwrap(try configured().serialized(matching: nil)?.text)
        let detail: [String: Any] = ["code": 200, "data": ["editScope": "FULL", "topic": ["id": 71, "productType": 1, "updateTime": "r1", "completeRuleJson": source], "chapters": [], "tickets": []]]
        let snapshot = try ProjectEditContract.decodeEditDetail(JSONSerialization.data(withJSONObject: detail), expectedTopicID: 71, owner: .personal)
        XCTAssertEqual(snapshot.draft.preserved["completeRuleJson"], .string(source))
        XCTAssertEqual(ProjectEditCompletionRules(raw: snapshot.draft.preserved["completeRuleJson"]).cells, configured().cells)
    }
    func testCityToFreeExploreCopyUsesAllEvenWithImportedAtLeast() throws {
        var city = ProjectEditSyntheticFixtures.draft()
        city.preserved["completeRuleJson"] = .string(#"{"nodeCompletion":{"mode":"AT_LEAST","requiredCount":2},"future":{"keep":true}}"#)
        for edited in [false, true] {
            if edited { city.completionRules = configured(raw: city.preserved["completeRuleJson"]) }
            var copy = try ProjectDraftModeCopy.copy(city, to: .freeExplore)
            copy.recruitDeadline = "2030-04-20"
            let payload = try ProjectEditContract.payload(copy, topicID: nil, scope: .full)
            let rules = ProjectEditCompletionRules(raw: payload["completeRuleJson"])
            XCTAssertEqual(rules.mode, "ALL")
            XCTAssertTrue(payload["completeRuleJson"]?.text?.contains("future") == true)
        }
    }
    func testEditsCannotAttachToDifferentImportedSource() {
        XCTAssertThrowsError(try configured().serialized(matching: .string("{}")))
    }
    @MainActor func testRuleChangeInvalidatesReviewAndSessionSwitchPreventsDispatch() async throws {
        var session: ProjectEditSession? = try .init(accountID: 901, epoch: 1, storageNamespace: "fixture-cn")
        let service = ProjectEditSyntheticService(); let coordinator = ProjectEditCoordinator(initial: service.snapshot, service: service, store: .init(storage: ProjectEditMemoryStorage()), currentSession: { session })
        await coordinator.load(); var draft = try XCTUnwrap(coordinator.snapshot?.draft); draft.completionRules = configured()
        coordinator.prepare(draft); let old = try XCTUnwrap(coordinator.confirmation)
        draft.completionRules?.cells[0].feedbackText = "revised"
        coordinator.prepare(draft); XCTAssertNotEqual(coordinator.confirmation, old)
        await coordinator.confirm(old); XCTAssertTrue(service.submissions.isEmpty)
        let current = try XCTUnwrap(coordinator.confirmation); session = nil
        await coordinator.confirm(current); XCTAssertTrue(service.submissions.isEmpty)
    }
    @MainActor func testWhitelistRejectsChangedRulesBeforeReview() async throws {
        let session = try ProjectEditSession(accountID: 901, epoch: 1, storageNamespace: "fixture-cn")
        let service = ProjectEditSyntheticService(snapshot: ProjectEditSyntheticFixtures.snapshot(scope: .whitelist))
        let coordinator = ProjectEditCoordinator(initial: service.snapshot, service: service, store: .init(storage: ProjectEditMemoryStorage()), currentSession: { session })
        await coordinator.load(); var draft = try XCTUnwrap(coordinator.snapshot?.draft); draft.completionRules = configured()
        coordinator.prepare(draft); XCTAssertNil(coordinator.confirmation); XCTAssertTrue(service.submissions.isEmpty)
    }
}
