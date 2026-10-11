import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private func hintTemplate(first: String? = "Look at the sign", second: String? = "Check its colour", answer: String? = "Blue", method: MerchantTemplateMethod = .gps) -> MerchantNodeTemplate {
    var value = MerchantNodeTemplate(); value.id = 71; value.title = "Hints"; value.method = method
    value.hints = .init(hint1: first, hint2: second, answerReveal: answer, method: method)
    return value
}

final class MerchantTemplateHintsContractTests: XCTestCase {
    func testSupportedMethodsMatchMiniTextChoiceAndGPS() {
        XCTAssertEqual(MerchantTemplateMethod.allCases.filter { MerchantTemplateHints.supports($0) }.map(\.rawValue), [1, 3, 5])
        XCTAssertFalse(MerchantTemplateHints.supports(nil))
    }
    func testStrictOptionalDecodeRejectsMalformedValuesAndOmitsMissing() throws {
        for raw in ["{}", #"{"hint1":null,"hint2":null,"answerReveal":null}"#] {
            let value = try JSONDecoder().decode(MerchantNodeTemplate.self, from: Data(raw.utf8))
            XCTAssertFalse(value.hints.enabled); XCTAssertTrue(value.hints.fields.isEmpty)
        }
        for raw in [#"{"hint1":1}"#, #"{"hint2":[]}"#, #"{"answerReveal":true}"#] {
            XCTAssertThrowsError(try JSONDecoder().decode(MerchantNodeTemplate.self, from: Data(raw.utf8)))
        }
    }
    func testAbsentHintsDoNotInventMethodDependentDraftDifference() throws {
        let value = try JSONDecoder().decode(MerchantNodeTemplate.self, from: Data(#"{"validationMethod":5}"#.utf8))
        XCTAssertEqual(value.hints, MerchantTemplateHints())
        XCTAssertEqual(MerchantTemplateHints(method: .photo), MerchantTemplateHints(method: .gps))
    }
    func testUneditedSourceKeepsExactOptionalStringsIncludingWhitespace() throws {
        let raw = #"{"validationMethod":5,"hint1":"  First\nline  ","answerReveal":""}"#
        let value = try JSONDecoder().decode(MerchantNodeTemplate.self, from: Data(raw.utf8))
        XCTAssertEqual(value.fields["hint1"] as? String, "  First\nline  ")
        XCTAssertNil(value.fields["hint2"]); XCTAssertEqual(value.fields["answerReveal"] as? String, "")
        XCTAssertFalse(value.hints.isEdited); XCTAssertTrue(value.hints.enabled)
    }
    func testEnableEditWritesOnlyThreeExistingKeysWithoutTrimmingOrToggleFlag() throws {
        var value = hintTemplate(first: nil, second: nil, answer: nil)
        value.hints.setEnabled(true); value.hints.update(.hint1, text: " First ")
        value.hints.update(.hint2, text: "Second"); value.hints.update(.answerReveal, text: "Answer")
        let request = try XCTUnwrap(MerchantOperationsDraft.template(value).previews().first)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.json) as? [String: Any])
        XCTAssertEqual(request.path, "api/merchant/city-node/template/submit")
        XCTAssertEqual(body["hint1"] as? String, " First "); XCTAssertEqual(body["hint2"] as? String, "Second")
        XCTAssertEqual(body["answerReveal"] as? String, "Answer")
        XCTAssertNil(body["hintEnabled"]); XCTAssertNil(body["hints"]); XCTAssertNil(body["merchantGuide"])
    }
    func testDisableExplicitlyClearsAllAndReenableDoesNotRestoreRemovedDraftText() {
        var hints = hintTemplate().hints; hints.setEnabled(false)
        XCTAssertEqual(hints.fields, ["hint1": "", "hint2": "", "answerReveal": ""])
        XCTAssertEqual(hints.clearedFields, [.hint1, .hint2, .answerReveal]); XCTAssertTrue(hints.previewStages.isEmpty)
        hints.update(.hint1, text: "Ignored while off"); XCTAssertEqual(hints.text(.hint1), "")
        hints.setEnabled(true); XCTAssertEqual(hints.text(.hint1), ""); XCTAssertTrue(hints.previewStages.isEmpty)
    }
    func testPartialClearIdentifiesOnlyTheClearedPersistedField() {
        var hints = hintTemplate().hints; hints.update(.hint2, text: "")
        XCTAssertEqual(hints.clearedFields, [.hint2]); XCTAssertEqual(hints.fields["answerReveal"], "Blue")
        XCTAssertEqual(hints.previewStages, [.hint1, .answerReveal])
    }
    func testPreviewStagesAreOrderedNonemptyAndDoNotMutateDraft() {
        let hints = MerchantTemplateHints(hint1: "One", hint2: "Two", answerReveal: "Answer", method: .gps)
        let before = hints; XCTAssertEqual(hints.previewStages, [.hint1, .hint2, .answerReveal])
        XCTAssertEqual(hints.previewStages.map(hints.text), ["One", "Two", "Answer"])
        XCTAssertEqual(hints, before); XCTAssertFalse(hints.isEdited)
        let answerOnly = MerchantTemplateHints(hint1: "  ", answerReveal: "Answer", method: .gps)
        XCTAssertEqual(answerOnly.previewStages, [.answerReveal])
    }
    func testMethodSwitchCannotSilentlyDropEnabledHints() throws {
        var value = hintTemplate(); value.method = .photo
        XCTAssertEqual(value.blocker, "merchant.hints.methodConflict")
        XCTAssertThrowsError(try MerchantOperationsDraft.template(value).previews())
        XCTAssertEqual(value.hints.fields["hint1"], "Look at the sign")
        value.method = .gps; XCTAssertNil(value.blocker)
        value.method = .photo; value.hints.setEnabled(false)
        XCTAssertNil(value.blocker); XCTAssertNoThrow(try MerchantOperationsDraft.template(value).previews())
        XCTAssertEqual(value.fields["answerReveal"] as? String, "")
    }
    func testUneditedIncompatibleLegacyGroupSurvivesUnrelatedEdits() throws {
        var value = hintTemplate(method: .photo); value.description = "Only description changed"
        XCTAssertNil(value.blocker); XCTAssertNoThrow(try MerchantOperationsDraft.template(value).previews())
        XCTAssertEqual(value.fields["hint1"] as? String, "Look at the sign")
        value.hints.update(.hint1, text: "Changed")
        XCTAssertEqual(value.blocker, "merchant.hints.methodConflict")
        value.hints.setEnabled(false); XCTAssertNil(value.blocker)
    }
    func testRepeatedNoOpChangesDoNotCreateEditIntent() {
        var hints = hintTemplate().hints; let before = hints
        hints.setEnabled(true); hints.update(.hint1, text: "Look at the sign")
        XCTAssertEqual(hints, before)
        var empty = MerchantTemplateHints(); empty.setEnabled(false); XCTAssertFalse(empty.isEdited)
    }
    func testAIHintsStayUnmappedAndLocalPlansStillBlockSubmission() throws {
        var value = hintTemplate()
        let result = try MerchantTemplateAssistResult(.object(["hint1": .string("AI hint"), "hint2": .string("AI hint two"), "answerReveal": .string("AI answer")]))
        let merged = result.merge(into: value, captured: value, edits: .init(), capturedEdits: .init())
        XCTAssertEqual(merged.hints, value.hints)
        for key in ["hint1", "hint2", "answerReveal"] { XCTAssertTrue(result.unsupportedKeys.contains(key)) }
        var plan = MerchantTemplateExitPlan(); plan.offlineAlternative = "Printed card"; plan.failureExit = "Stop playing"
        value.exitPlan = plan
        XCTAssertThrowsError(try MerchantOperationsDraft.template(value).previews()) {
            XCTAssertEqual($0 as? MerchantOperationsFailure, .liveWritesDisabled)
        }
    }
}

@MainActor final class MerchantTemplateHintsCoordinatorTests: XCTestCase {
    func testFrozenReviewCancelStaleConfirmAndDiscardPreserveAllThreeFields() async throws {
        let reader = MerchantOperationsFixtureReader(); let source = hintTemplate()
        reader.replace(.template(71), with: .draft(.template(source)))
        let coordinator = MerchantOperationsCoordinator(reader: reader, destination: .template(71))
        await coordinator.load(); var edited = source; edited.hints.update(.hint1, text: "New first hint")
        coordinator.edit(.template(edited)); coordinator.prepare(); let review = try XCTUnwrap(coordinator.confirmation)
        coordinator.cancelConfirmation(); XCTAssertEqual(coordinator.draft, .template(edited))
        edited.hints.setEnabled(false); coordinator.edit(.template(edited))
        if case .template(let frozen) = review.draft { XCTAssertEqual(frozen.hints.fields["hint1"], "New first hint"); XCTAssertEqual(frozen.hints.fields["hint2"], "Check its colour") }
        else { XCTFail() }
        await coordinator.confirm(review); XCTAssertEqual(reader.saveCount, 0)
        coordinator.discardChanges(); XCTAssertEqual(coordinator.draft, .template(source)); XCTAssertFalse(coordinator.isDirty)
    }
    func testAcknowledgedDisableReadbackClearsGroupAndDoesNotReplay() async throws {
        let reader = MerchantOperationsFixtureReader(); let source = hintTemplate()
        reader.replace(.template(71), with: .draft(.template(source)))
        let coordinator = MerchantOperationsCoordinator(reader: reader, destination: .template(71))
        await coordinator.load(); var edited = source; edited.hints.setEnabled(false)
        coordinator.edit(.template(edited)); coordinator.prepare(); let review = try XCTUnwrap(coordinator.confirmation)
        await coordinator.confirm(review)
        guard case .template(let returned) = coordinator.draft else { return XCTFail() }
        XCTAssertFalse(returned.hints.enabled); XCTAssertFalse(returned.hints.isEdited)
        XCTAssertEqual(returned.hints.fields, ["hint1": "", "hint2": "", "answerReveal": ""])
        XCTAssertEqual(reader.saveCount, 1); XCTAssertFalse(coordinator.isDirty)
        await coordinator.confirm(review); XCTAssertEqual(reader.saveCount, 1)
        await coordinator.load(); XCTAssertEqual(coordinator.draft, .template(returned))
    }
    func testAccountChangeRejectsPreviouslyReviewedHintEdits() async throws {
        let reader = MerchantOperationsFixtureReader(); let source = hintTemplate()
        reader.replace(.template(71), with: .draft(.template(source)))
        let coordinator = MerchantOperationsCoordinator(reader: reader, destination: .template(71))
        await coordinator.load(); var edited = source; edited.hints.update(.answerReveal, text: "Different explanation")
        coordinator.edit(.template(edited)); coordinator.prepare(); let review = try XCTUnwrap(coordinator.confirmation)
        reader.switchAccount(); await coordinator.confirm(review); XCTAssertEqual(reader.saveCount, 0)
    }
}

private final class HintTransport: HTTPTransport {
    var replies: [String] = [], requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); guard !replies.isEmpty else { throw APIError.malformedResponse }
        return (Data(replies.removeFirst().utf8), 200)
    }
}
@MainActor private final class HintJournal: OperationPendingJournal {
    var record: OperationPendingRecord?
    func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? { record }
    func write(_ record: OperationPendingRecord) throws { self.record = record }
    func clear(_ record: OperationPendingRecord) throws { self.record = nil }
}
@MainActor final class MerchantTemplateHintsServiceTests: XCTestCase {
    private let access = #"{"code":200,"data":{"active":true,"merchant":{"id":31},"roleCode":"MERCHANT_OWNER","permissions":["merchant:project:manage"]}}"#
    private let initial = #"{"code":200,"data":{"id":71,"title":"Hints","validationMethod":5,"hint1":"Look at the sign","hint2":"Check its colour","answerReveal":"Blue"}}"#
    private func setup(_ transport: HintTransport, approved: Bool = true) throws -> (MerchantOperationsSessionReader, HintJournal) {
        let api = try APIConfiguration(baseURL: URL(string: "https://example.test/prod-api")!)
        let session = try MerchantOperationsSession(accountID: 7, epoch: 1, token: "synthetic-token", storageNamespace: "hint-test")
        let approval = try OperationEndpointApproval(baseURL: api.baseURL, namespace: session.storageNamespace, accountID: session.accountID, paths: ["api/merchant/city-node/template/submit"])
        let journal = HintJournal()
        return (MerchantOperationsSessionReader(service: MerchantOperationsService(configuration: api, transport: transport), currentSession: { session }, approval: approved ? approval : nil, journal: journal), journal)
    }
    private func exerciseSave(disable: Bool) async throws {
        let transport = HintTransport()
        let canonical = disable ? ["hint1": "", "hint2": "", "answerReveal": ""] : ["hint1": "Canonical first", "hint2": "Canonical second", "answerReveal": "Canonical answer"]
        var data: [String: Any] = ["id": 71, "title": "Hints", "validationMethod": 5]
        for (key, value) in canonical { data[key] = value }
        let returned = String(decoding: try JSONSerialization.data(withJSONObject: ["code": 200, "data": data]), as: UTF8.self)
        transport.replies = [access, initial, access, initial, access, initial, #"{"code":200,"data":71}"#, access, returned]
        let (reader, journal) = try setup(transport)
        let coordinator = MerchantOperationsCoordinator(reader: reader, destination: .template(71))
        await coordinator.load(); var edited = hintTemplate()
        if disable { edited.hints.setEnabled(false) } else {
            edited.hints.update(.hint1, text: " Proposed first "); edited.hints.update(.hint2, text: "Proposed second")
            edited.hints.update(.answerReveal, text: "Proposed answer")
        }
        coordinator.edit(.template(edited)); coordinator.prepare(); let review = try XCTUnwrap(coordinator.confirmation)
        await coordinator.confirm(review)
        let saves = transport.requests.filter { $0.url?.path.hasSuffix("/template/submit") == true }
        XCTAssertEqual(saves.count, 1)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(saves.first?.httpBody)) as? [String: Any])
        for (key, value) in edited.hints.fields { XCTAssertEqual(payload[key] as? String, value) }
        XCTAssertNil(payload["hintEnabled"]); XCTAssertNil(payload["hints"])
        guard case .template(let source) = coordinator.draft else { return XCTFail() }
        XCTAssertEqual(source.hints.fields, canonical); XCTAssertFalse(source.hints.isEdited)
        XCTAssertEqual(transport.requests.last?.url?.path, "/prod-api/api/template/myinfo")
        XCTAssertNil(journal.record); XCTAssertFalse(coordinator.isDirty)
        let count = transport.requests.count; await coordinator.confirm(review); XCTAssertEqual(transport.requests.count, count)
    }
    func testApprovedFakeTransportSendsThreeFieldsAndServerReadbackWins() async throws {
        try await exerciseSave(disable: false)
    }
    func testApprovedDisableSendsThreeEmptyStringsAndReadsBackDisabled() async throws {
        try await exerciseSave(disable: true)
    }
    func testMissingApprovalSendsNothing() async throws {
        let transport = HintTransport(); let (reader, _) = try setup(transport, approved: false)
        XCTAssertFalse(reader.canSave)
        do { _ = try await reader.saveTemplateReviewed(hintTemplate(), baseline: hintTemplate()); XCTFail() }
        catch { XCTAssertEqual(error as? MerchantOperationsFailure, .liveWritesDisabled) }
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testChangedServerHintsDuringReviewRejectBeforeWrite() async throws {
        let transport = HintTransport()
        transport.replies = [access, initial, access, initial.replacingOccurrences(of: "Look at the sign", with: "Changed elsewhere")]
        let (reader, _) = try setup(transport)
        let coordinator = MerchantOperationsCoordinator(reader: reader, destination: .template(71))
        await coordinator.load(); var edited = hintTemplate(); edited.hints.update(.hint1, text: "My edit")
        coordinator.edit(.template(edited)); coordinator.prepare(); let review = try XCTUnwrap(coordinator.confirmation)
        await coordinator.confirm(review)
        XCTAssertEqual(coordinator.issue, .key("merchant.operations.conflict"))
        XCTAssertFalse(transport.requests.contains { $0.url?.path.hasSuffix("/template/submit") == true })
        XCTAssertEqual(coordinator.draft, .template(edited))
    }
}
