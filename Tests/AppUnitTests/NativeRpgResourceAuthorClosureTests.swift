import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class NativeRpgResourceAuthorClosureTests: XCTestCase {
    private let original = #" {"schemaVersion":2,"hp":{"enabled":true,"init":5,"max":10},"morale":{"enabled":true,"init":2,"max":10},"recovery":{"stageRestMoraleFloor":3,"future":"keep"},"future":{"note":"original"}} "#
    private func draft(_ raw: String? = nil) -> ProjectEditDraft {
        var value = ProjectEditSyntheticFixtures.draft(); value.baseRevision = "resource-r1"
        value.preserved["journeyRules"] = .string(raw ?? original); return value
    }
    private final class Owner { var session: ProjectEditSession? = try? .init(accountID: 7, epoch: 1, storageNamespace: "resource-author") }
    private func setup(scope: ProjectEditScope = .full) async -> (ProjectEditModel, Owner, ProjectEditMemoryStorage, ProjectEditSyntheticService) {
        let owner = Owner(), storage = ProjectEditMemoryStorage(), snapshot = ProjectEditSnapshot(topicID: 101, scope: scope, draft: draft())
        let service = ProjectEditSyntheticService(snapshot: snapshot)
        let model = ProjectEditModel(coordinator: .init(initial: snapshot, service: service, store: .init(storage: storage), currentSession: { owner.session }))
        await model.load(); return (model, owner, storage, service)
    }
    func testMissingSchemaOneAndUnknownSchemaDoNotCreateDefaults() {
        for raw in [#"{}"#, #"{"schemaVersion":1}"#, #"{"schemaVersion":3}"#, #"{"schemaVersion":2,"hp":false}"#] {
            XCTAssertThrowsError(try NativeRpgResourceAuthorDraft(draft: draft(raw)))
        }
        var missing = draft(); missing.preserved["journeyRules"] = nil
        XCTAssertThrowsError(try NativeRpgResourceAuthorDraft(draft: missing))
    }
    func testNoOpPreservesExactOriginalBytesIncludingUnknownValues() throws {
        let value = draft(), editor = try NativeRpgResourceAuthorDraft(draft: value)
        XCTAssertTrue(editor.issues.isEmpty)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(try editor.applying(to: value)), ProjectEditPendingMaterials.exactData(value))
    }
    func testEditedAbsentResourceRequiresAllThreeExplicitDeclarations() throws {
        let value = draft(#"{"schemaVersion":2}"#); var editor = try NativeRpgResourceAuthorDraft(draft: value)
        editor.edit("luck", "init", "1"); XCTAssertFalse(editor.issues.isEmpty)
        editor.edit("luck", "max", "3"); XCTAssertFalse(editor.issues.isEmpty)
        editor.edit("luck", "enabled", "true"); XCTAssertTrue(editor.issues.isEmpty)
        let changed = try editor.applying(to: value)
        XCTAssertEqual(try NativeRpgResourceAuthorDraft(draft: changed).text("luck", "init"), "1")
        XCTAssertNil(editor.rules["hp"])
    }
    func testOriginalResourceBoundsAndInitialMaximumRelationshipRemainStrict() throws {
        for (name, maximum) in [("hp", "21"), ("luck", "6"), ("morale", "1001"), ("inspiration", "1001")] {
            var editor = try NativeRpgResourceAuthorDraft(draft: draft())
            editor.edit(name, "enabled", "true"); editor.edit(name, "init", "0"); editor.edit(name, "max", maximum)
            XCTAssertFalse(editor.issues.isEmpty); XCTAssertThrowsError(try editor.applying(to: draft()))
        }
        var editor = try NativeRpgResourceAuthorDraft(draft: draft())
        editor.edit("hp", "init", "11"); XCTAssertFalse(editor.issues.isEmpty)
        editor.restore("hp"); XCTAssertTrue(editor.issues.isEmpty)
    }
    func testUnknownResourceFieldsAreNotSilentlyDeleted() throws {
        let value = draft(#"{"schemaVersion":2,"hp":{"enabled":true,"max":10,"init":2,"future":1}}"#)
        let editor = try NativeRpgResourceAuthorDraft(draft: value)
        XCTAssertFalse(editor.issues.isEmpty); XCTAssertEqual(editor.rules["hp"]?.object?["future"], .number(1))
        XCTAssertThrowsError(try editor.applying(to: value))
    }
    func testRecoveryFloorIsExplicitAndBoundedByExistingMoraleMaximum() throws {
        var absent = try NativeRpgResourceAuthorDraft(draft: draft(#"{"schemaVersion":2}"#))
        absent.editStageMoraleFloor("3"); XCTAssertFalse(absent.issues.isEmpty)
        var editor = try NativeRpgResourceAuthorDraft(draft: draft())
        editor.editStageMoraleFloor("11"); XCTAssertFalse(editor.issues.isEmpty)
        editor.editStageMoraleFloor("4"); XCTAssertTrue(editor.issues.isEmpty)
        editor.editStageMoraleFloor(""); XCTAssertEqual(editor.stageMoraleFloorText, "")
        XCTAssertEqual(editor.rules["recovery"]?.object?["future"], .string("keep"))
        editor.restoreStageMoraleFloor(); XCTAssertEqual(editor.stageMoraleFloorText, "3")
    }
    func testLoweringMaximumCannotSilentlyRewriteOriginalRecoveryFloor() throws {
        var editor = try NativeRpgResourceAuthorDraft(draft: draft())
        editor.edit("morale", "max", "2")
        XCTAssertFalse(editor.issues.isEmpty); XCTAssertEqual(editor.stageMoraleFloorText, "3")
        editor.restore("morale"); XCTAssertTrue(editor.issues.isEmpty)
    }
    func testChangedOriginalBytesRejectUnicodeEquivalentReplacement() throws {
        let raw = "{\"schemaVersion\":2,\"future\":\"e\u{301}\"}", replacement = "{\"schemaVersion\":2,\"future\":\"é\"}"
        let editor = try NativeRpgResourceAuthorDraft(draft: draft(raw))
        XCTAssertThrowsError(try editor.applying(to: draft(replacement)))
    }
    func testDuplicateAndUnicodeEquivalentJSONKeysFailBeforeDictionaryDecode() {
        let samples = [#"{"schemaVersion":2,"schemaVersion":2}"#,
                       #"{"schemaVersion":2,"hp":{"enabled":true,"init":1,"max":2,"max":3}}"#,
                       #"{"schemaVersion":2,"future":[{"x":1,"x":2}]}"#,
                       #"{"schemaVersion":2,"future":{"x":1,"\u0078":2}}"#,
                       "{\"schemaVersion\":2,\"future\":{\"é\":1,\"e\u{301}\":2}}"]
        for raw in samples { XCTAssertThrowsError(try NativeRpgResourceAuthorDraft(draft: draft(raw)), raw) }
    }
    func testMalformedNonObjectAndOversizedOriginalAreNotRepaired() {
        for raw in ["{", "[]", String(repeating: " ", count: 24 * 1024 + 1)] {
            XCTAssertThrowsError(try NativeRpgResourceAuthorDraft(draft: draft(raw)))
        }
    }
    func testOnlyRulesChangeAndUnknownTopLevelAndRecoveryValuesSurvive() throws {
        let value = draft(); var editor = try NativeRpgResourceAuthorDraft(draft: value)
        editor.edit("hp", "init", "6"); var changed = try editor.applying(to: value)
        let reread = try NativeRpgResourceAuthorDraft(draft: changed)
        XCTAssertEqual(reread.rules["future"], editor.rules["future"])
        XCTAssertEqual(reread.rules["recovery"], editor.rules["recovery"])
        changed.preserved["journeyRules"] = value.preserved["journeyRules"]
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(changed), ProjectEditPendingMaterials.exactData(value))
    }
    func testExistingPayloadReadbackAndWhitelistUseUnchangedContracts() throws {
        let value = draft(); var editor = try NativeRpgResourceAuthorDraft(draft: value); editor.edit("hp", "init", "6")
        let changed = try editor.applying(to: value)
        let payload = try ProjectEditContract.payload(changed, topicID: 101, scope: .full, baseline: .init(topicID: 101, scope: .full, draft: value))
        XCTAssertEqual(payload["journeyRules"], changed.preserved["journeyRules"])
        var topic = payload; topic["updateTime"] = .string("resource-r2")
        let response: ProjectEditJSON = .object(["code": .number(200), "data": .object(["editScope": .string("FULL"), "topic": .object(topic), "chapters": payload["chapters"] ?? .array([]), "tickets": payload["tickets"] ?? .array([])])])
        let reread = try ProjectEditContract.decodeEditDetail(JSONEncoder().encode(response), expectedTopicID: 101, owner: .personal)
        XCTAssertEqual(reread.draft.preserved["journeyRules"], changed.preserved["journeyRules"])
        let restricted = try ProjectEditContract.payload(changed, topicID: 101, scope: .whitelist, baseline: .init(topicID: 101, scope: .whitelist, draft: changed))
        XCTAssertNil(restricted["journeyRules"])
    }
    func testExistingLocalPersistenceFailureKeepsOriginalAndAllowsSameReviewRetry() async throws {
        let (model, _, storage, service) = await setup(), lease = try XCTUnwrap(model.captureStarterLease())
        let before = ProjectEditPendingMaterials.exactData(model.draft)
        var editor = try NativeRpgResourceAuthorDraft(draft: model.draft); editor.edit("hp", "init", "6")
        let proposed = try editor.applying(to: model.draft)
        storage.failWrites = true; XCTAssertFalse(model.persistLocalChange(proposed, lease: lease))
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before); XCTAssertTrue(service.submissions.isEmpty)
        storage.failWrites = false; XCTAssertTrue(model.persistLocalChange(proposed, lease: lease))
        XCTAssertEqual(try NativeRpgResourceAuthorDraft(draft: model.draft).text("hp", "init"), "6")
        XCTAssertTrue(service.submissions.isEmpty)
    }
    func testChangedAccountOrEpochRejectsStaleLocalSaveLease() async throws {
        for account in [7, 8] {
            let (model, owner, _, service) = await setup(), lease = try XCTUnwrap(model.captureStarterLease())
            var editor = try NativeRpgResourceAuthorDraft(draft: model.draft); editor.edit("hp", "init", "6")
            let proposed = try editor.applying(to: model.draft), before = ProjectEditPendingMaterials.exactData(model.draft)
            owner.session = try .init(accountID: account, epoch: 2, storageNamespace: "resource-author")
            XCTAssertFalse(model.persistLocalChange(proposed, lease: lease))
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before); XCTAssertTrue(service.submissions.isEmpty)
        }
    }
    func testOriginalUIRetainsABAExactPreviewAndFullEditFences() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("App/NativeRpgResourceAuthorView.swift"), encoding: .utf8)
        for clause in ["model.draftMutationRevision == capture.revision", "model.editorIncarnation == capture.incarnation", "scenePhase == .active", "model.confirmation == nil", "model.isCurrentStarterLease(capture.lease)", "ProjectEditPendingMaterials.exactData(model.draft) == capture.draftBytes", "proposedText.utf8.elementsEqual(reviewedText.utf8)", "guard model.persistLocalChange(proposed,lease:capture.lease) else"] {
            XCTAssertTrue(source.contains(clause), clause)
        }
        XCTAssertFalse(source.contains("URLSession")); XCTAssertFalse(source.contains("coordinator.submit"))
    }
    func testActualEntryRendersWithoutOpeningOrChangingResourceDefinitions() async {
        let (model, _, _, service) = await setup(); let before = ProjectEditPendingMaterials.exactData(model.draft)
        let host = UIHostingController(rootView: NavigationStack { Form { NativeRpgResourceAuthorEntry(model: model) } }
            .environment(\.scenePhase, .active).environment(\.dynamicTypeSize, .accessibility5))
        host.loadViewIfNeeded(); host.view.frame = CGRect(x: 0, y: 0, width: 320, height: 640); host.view.setNeedsLayout(); host.view.layoutIfNeeded()
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before); XCTAssertTrue(service.submissions.isEmpty)
    }
}
