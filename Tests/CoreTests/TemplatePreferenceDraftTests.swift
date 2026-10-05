import Foundation
import XCTest
@testable import QuestifyCore

final class TemplatePreferenceDraftTests: XCTestCase {
    private let example = TemplatePreferenceDraftCheck.example
    func testSourceExampleAndCompletePreview() {
        let report = TemplatePreferenceDraftCheck.inspect(example)
        XCTAssertEqual(report.status, .valid)
        for path in ["$.steps[0].key", "$.steps[0].options[0].scores.compact", "$.tiebreak.title", "$.results.open.nextStepDays", "$.tagOutput.recipientLabel", "$.tagOutput.revocable", "$.tagConsumes[0]"] {
            XCTAssertTrue(report.fields.contains { $0.path == path }, path)
        }
    }
    func testIntegerLexicalKindCannotUseReadonlyPreviewCoercion() {
        for wrong in ["\"7\"", "7.0", "7e0", "true", "8", "null"] {
            let report = TemplatePreferenceDraftCheck.inspect(example.replacingOccurrences(of: "\"nextStepDays\":7", with: "\"nextStepDays\":" + wrong))
            XCTAssertEqual(report.status, .invalid, wrong)
            XCTAssertEqual(report.messageKey, "templateAuthor.preference.error.days", wrong)
        }
        for wrong in ["\"2\"", "2.0", "2e0", "-1", "3", "true"] {
            let report = TemplatePreferenceDraftCheck.inspect(example.replacingOccurrences(of: "\"compact\":2", with: "\"compact\":" + wrong))
            XCTAssertEqual(report.status, .invalid, wrong)
            XCTAssertEqual(report.messageKey, "templateAuthor.preference.error.score", wrong)
        }
    }
    func testInvalidOrEditedTextNeverUsesPriorPreview() {
        XCTAssertTrue(TemplatePreferenceDraftCheck.inspect(example).canPreview)
        for invalid in ["", "{", "null", "[]", "{}", example + "[]"] {
            let result = TemplatePreferenceDraftCheck.inspect(invalid)
            XCTAssertFalse(result.canPreview); XCTAssertTrue(result.fields.isEmpty)
        }
    }
    func testUnknownFieldsSurviveAsUninterpreted() {
        let source = example.replacingOccurrences(of: "\"steps\":", with: "\"future\":{\"large\":9007199254740993,\"precise\":0.1234567890123456789},\"steps\":")
        let result = TemplatePreferenceDraftCheck.inspect(source)
        XCTAssertEqual(result.status, .valid); XCTAssertTrue(result.unknownPaths.contains("$.future"))
        XCTAssertTrue(source.contains("9007199254740993")); XCTAssertTrue(source.contains("0.1234567890123456789"))
    }
    func testResourceBudgetIsIncompleteAndNotSemanticRejection() {
        for raw in [String(repeating: " ", count: 1_048_577), String(repeating: "[", count: 66) + "0" + String(repeating: "]", count: 66)] {
            XCTAssertEqual(TemplatePreferenceDraftCheck.inspect(raw).status, .incomplete)
        }
        XCTAssertEqual(TemplatePreferenceDraftCheck.inspect(example, workLimit: 0).status, .incomplete)
        XCTAssertEqual(TemplatePreferenceDraftCheck.inspect(example, workLimit: -1).status, .incomplete)
    }
    func testUnsupportedCoercionsAreNotClaimedToBeBackendInvalid() {
        for raw in [example.replacingOccurrences(of: "\"revocable\":true", with: "\"revocable\":\"true\""), example.replacingOccurrences(of: "\"key\":\"space\"", with: "\"key\":123")] {
            XCTAssertEqual(TemplatePreferenceDraftCheck.inspect(raw).status, .unsupported)
        }
    }
    func testNoncanonicalIdentifiersAreUnsupportedWithoutRewriting() {
        let raw = example.replacingOccurrences(of: "space", with: "e\u{301}")
        XCTAssertEqual(TemplatePreferenceDraftCheck.inspect(raw).status, .unsupported)
        XCTAssertTrue(raw.contains("e\u{301}"))
    }
    func testDuplicateKeysAndUnreachableDimensionsAndChoiceEvidence() {
        let duplicate = example.replacingOccurrences(of: "\"key\":\"tradeoff\"", with: "\"key\":\"space\"")
        XCTAssertEqual(TemplatePreferenceDraftCheck.inspect(duplicate).messageKey, "templateAuthor.preference.error.duplicate")
        let unreachable = example.replacingOccurrences(of: "\"open\":2", with: "\"compact\":2").replacingOccurrences(of: "\"open\":1", with: "\"compact\":1")
        XCTAssertEqual(TemplatePreferenceDraftCheck.inspect(unreachable).messageKey, "templateAuthor.preference.error.reachable")
        XCTAssertEqual(TemplatePreferenceDraftCheck.inspect(example.replacingOccurrences(of: "{{choices}}", with: "unexplained")).messageKey, "templateAuthor.preference.error.evidence")
    }
}

@MainActor final class TemplatePreferenceDraftPersistenceTests: XCTestCase {
    func testRawIncompleteAndUnknownSourceRoundtripsThroughExistingOwnerStore() throws {
        let session = try TemplateAuthoringSession(accountID: 7, namespace: "preference-local-test", epoch: 1, authorizationRevision: "test")
        let storage = TemplateAuthoringMemoryStorage(), store = TemplateAuthoringLocalStore(storage: storage)
        let identity = TemplateAuthoringIdentity()
        for raw in ["{\n  unfinished ", "\n" + TemplatePreferenceDraftCheck.example + "\n", #"{"future":9007199254740993,"precise":0.1234567890123456789}"#] {
            var draft = TemplateAuthoringDraft(title: "Local preference"); draft.validationMethod = .preference; draft.preferenceJson = raw
            try store.save(draft, session: session, identity: identity)
            guard case .ready(let envelope) = store.load(session: session, identity: identity) else { return XCTFail("Missing local envelope") }
            XCTAssertEqual(envelope.draft.validationMethod, .preference)
            XCTAssertEqual(Array(try XCTUnwrap(envelope.draft.preferenceJson).utf8), Array(raw.utf8))
            let other = try TemplateAuthoringSession(accountID: 8, namespace: session.namespace, epoch: 1, authorizationRevision: "test")
            XCTAssertEqual(store.load(session: other, identity: identity), .missing)
        }
    }
    func testOldDraftWithoutPreferenceFieldDoesNotConvertMethod() throws {
        var draft = TemplateAuthoringDraft(title: "Legacy"); draft.validationMethod = .text
        let encoded = try JSONEncoder().encode(draft)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any]); object.removeValue(forKey: "preferenceJson")
        let restored = try JSONDecoder().decode(TemplateAuthoringDraft.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(restored.validationMethod, .text); XCTAssertNil(restored.preferenceJson)
    }
    func testExistingOwnerSeedStillRefused() throws {
        let session = try TemplateAuthoringSession(accountID: 7, namespace: "preference-owner-test", epoch: 1, authorizationRevision: "test")
        let coordinator = TemplateAuthoringCoordinator(store: .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { session })
        var source = TemplateAuthoringDraft(title: "Owner"); source.id = AuthoringPlayTemplateID(rawValue: 123); source.validationMethod = .preference; source.preferenceJson = TemplatePreferenceDraftCheck.example
        coordinator.open(seed: source)
        XCTAssertEqual(coordinator.state, .blocked); XCTAssertNil(coordinator.draft.preferenceJson)
    }
}
