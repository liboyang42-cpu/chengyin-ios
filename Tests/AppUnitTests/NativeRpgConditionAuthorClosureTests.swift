import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class NativeRpgConditionAuthorClosureTests: XCTestCase {
    private let original = #" {"schemaVersion":2,"conditions":{"enabled":true,"maxActive":5},"future":{"note":"original"}} "#
    private func draft(_ raw: String? = nil) -> ProjectEditDraft {
        var value = ProjectEditSyntheticFixtures.draft(); value.baseRevision = "condition-r1"
        value.preserved["journeyRules"] = .string(raw ?? original); return value
    }
    private func editor(_ value: ProjectEditDraft) throws -> NativeRpgConditionAuthorDraft {
        try .init(original: value.preserved["journeyRules"])
    }
    private final class Owner { var session: ProjectEditSession? = try? .init(accountID: 7, epoch: 1, storageNamespace: "condition-author") }
    private func setup(scope: ProjectEditScope = .full) async -> (ProjectEditModel, Owner, ProjectEditMemoryStorage, ProjectEditSyntheticService) {
        let owner = Owner(), storage = ProjectEditMemoryStorage(), snapshot = ProjectEditSnapshot(topicID: 101, scope: scope, draft: draft())
        let service = ProjectEditSyntheticService(snapshot: snapshot)
        let model = ProjectEditModel(coordinator: .init(initial: snapshot, service: service, store: .init(storage: storage), currentSession: { owner.session }))
        await model.load(); return (model, owner, storage, service)
    }
    func testMissingLegacyUnknownAndNonObjectRulesAreNotInvented() {
        for raw in [#"{}"#, #"{"schemaVersion":1}"#, #"{"schemaVersion":3}"#, #"{"schemaVersion":2,"conditions":false}"#, #"{"schemaVersion":2,"conditions":null}"#, "[]", "{"] {
            XCTAssertThrowsError(try editor(draft(raw)), raw)
        }
        XCTAssertThrowsError(try NativeRpgConditionAuthorDraft(original: nil))
        XCTAssertThrowsError(try NativeRpgConditionAuthorDraft(original: .null))
    }
    func testReadingMissingConditionsDoesNotCreateModuleOrDefaults() throws {
        let value = draft(#"{"schemaVersion":2}"#), author = try editor(value)
        XCTAssertFalse(author.enabled); XCTAssertNil(author.rules["conditions"])
        XCTAssertThrowsError(try author.applying(to: value))
        XCTAssertEqual(value.preserved["journeyRules"]?.text, #"{"schemaVersion":2}"#)
    }
    func testExplicitDeclarationUsesOnlyOriginalBooleanAndCapacityFive() throws {
        let value = draft(#"{"schemaVersion":2}"#); var author = try editor(value)
        author.configure(true)
        let changed = try author.applying(to: value)
        XCTAssertEqual(try editor(changed).rules["conditions"], .object(["enabled": .bool(true), "maxActive": .number(5)]))
        XCTAssertEqual(Set(try editor(changed).rules.keys), ["schemaVersion", "conditions"])
    }
    func testNoOpAndToggleBackPreserveExactOriginalBytes() throws {
        let value = draft(); var author = try editor(value)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(try author.applying(to: value)), ProjectEditPendingMaterials.exactData(value))
        author.configure(false); author.configure(true)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(try author.applying(to: value)), ProjectEditPendingMaterials.exactData(value))
    }
    func testExplicitDisableDoesNotDeleteConditionsOrUnknownSiblings() throws {
        let value = draft(); var author = try editor(value); author.configure(false)
        let changed = try author.applying(to: value), reread = try editor(changed)
        XCTAssertFalse(reread.enabled); XCTAssertEqual(reread.rules["conditions"]?.object?["maxActive"], .number(5))
        XCTAssertEqual(reread.rules["future"], author.rules["future"])
        var restored = changed; restored.preserved["journeyRules"] = value.preserved["journeyRules"]
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(restored), ProjectEditPendingMaterials.exactData(value))
    }
    func testUnknownConditionFieldsRemainPreservedAndRejectApply() throws {
        let value = draft(#"{"schemaVersion":2,"conditions":{"enabled":true,"maxActive":5,"future":1}}"#)
        var author = try editor(value); author.configure(false)
        XCTAssertEqual(author.rules["conditions"]?.object?["future"], .number(1))
        XCTAssertThrowsError(try author.applying(to: value))
    }
    func testNonstandardCapacityRequiresExplicitDeclaration() throws {
        let value = draft(#"{"schemaVersion":2,"conditions":{"enabled":true,"maxActive":4}}"#)
        var author = try editor(value)
        XCTAssertThrowsError(try author.applying(to: value))
        XCTAssertEqual(author.rules["conditions"]?.object?["maxActive"], .number(4))
        author.configure(true)
        XCTAssertEqual(try editor(author.applying(to: value)).rules["conditions"]?.object?["maxActive"], .number(5))
    }
    func testChangedOriginalBytesRejectEquivalentUnicodeReplacement() throws {
        let raw = "{\"schemaVersion\":2,\"conditions\":{\"enabled\":true,\"maxActive\":5},\"future\":\"e\u{301}\"}"
        let replacement = raw.replacingOccurrences(of: "e\u{301}", with: "é")
        var author = try editor(draft(raw)); author.configure(false)
        XCTAssertThrowsError(try author.applying(to: draft(replacement)))
    }
    func testDuplicateEscapedAndUnicodeEquivalentKeysFailClosed() {
        let values = [#"{"schemaVersion":2,"schemaVersion":2}"#,
                      #"{"schemaVersion":2,"conditions":{"enabled":true,"enabled":false}}"#,
                      #"{"schemaVersion":2,"future":[{"x":1,"x":2}]}"#,
                      #"{"schemaVersion":2,"future":{"x":1,"\u0078":2}}"#,
                      "{\"schemaVersion\":2,\"future\":{\"é\":1,\"e\u{301}\":2}}"]
        for raw in values { XCTAssertThrowsError(try editor(draft(raw)), raw) }
    }
    func testOversizedAndExcessivelyNestedOriginalDoNotEnterEditor() {
        let large = #"{"schemaVersion":2,"future":""# + String(repeating: "a", count: 1_048_576) + #""}"#
        let nested = #"{"schemaVersion":2,"future":"# + String(repeating: "[", count: 130) + "0" + String(repeating: "]", count: 130) + "}"
        XCTAssertThrowsError(try editor(draft(large))); XCTAssertThrowsError(try editor(draft(nested)))
    }
    func testOriginalPayloadAndReadbackCarryExactJourneyRulesButWhitelistDoesNot() throws {
        let value = draft(); var author = try editor(value); author.configure(false); let changed = try author.applying(to: value)
        let payload = try ProjectEditContract.payload(changed, topicID: 101, scope: .full, baseline: .init(topicID: 101, scope: .full, draft: value))
        XCTAssertEqual(payload["journeyRules"], changed.preserved["journeyRules"])
        var topic = payload; topic["updateTime"] = .string("condition-r2")
        let response: ProjectEditJSON = .object(["code": .number(200), "data": .object(["editScope": .string("FULL"), "topic": .object(topic), "chapters": payload["chapters"] ?? .array([]), "tickets": payload["tickets"] ?? .array([])])])
        let reread = try ProjectEditContract.decodeEditDetail(JSONEncoder().encode(response), expectedTopicID: 101, owner: .personal)
        XCTAssertEqual(reread.draft.preserved["journeyRules"], changed.preserved["journeyRules"])
        let limited = try ProjectEditContract.payload(changed, topicID: 101, scope: .whitelist, baseline: .init(topicID: 101, scope: .whitelist, draft: changed))
        XCTAssertNil(limited["journeyRules"])
    }
    func testOriginalLocalSaveFailureKeepsDraftAndAllowsSameReviewRetry() async throws {
        let (model, _, storage, service) = await setup(), lease = try XCTUnwrap(model.captureStarterLease())
        let before = ProjectEditPendingMaterials.exactData(model.draft), revision = model.draftMutationRevision
        var author = try editor(model.draft); author.configure(false); let proposed = try author.applying(to: model.draft)
        storage.failWrites = true; XCTAssertFalse(model.persistLocalChange(proposed, lease: lease))
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before); XCTAssertEqual(model.draftMutationRevision, revision)
        XCTAssertTrue(service.submissions.isEmpty)
        storage.failWrites = false; XCTAssertTrue(model.persistLocalChange(proposed, lease: lease))
        XCTAssertFalse(try editor(model.draft).enabled); XCTAssertTrue(service.submissions.isEmpty)
    }
    func testChangedAccountEpochAndNamespaceRejectOriginalSaveLease() async throws {
        for session in [try ProjectEditSession(accountID: 8, epoch: 1, storageNamespace: "condition-author"),
                        try ProjectEditSession(accountID: 7, epoch: 2, storageNamespace: "condition-author"),
                        try ProjectEditSession(accountID: 7, epoch: 1, storageNamespace: "other-condition-author")] {
            let (model, owner, _, service) = await setup(), lease = try XCTUnwrap(model.captureStarterLease())
            let before = ProjectEditPendingMaterials.exactData(model.draft)
            var author = try editor(model.draft); author.configure(false); let proposed = try author.applying(to: model.draft)
            owner.session = session; XCTAssertFalse(model.persistLocalChange(proposed, lease: lease))
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before); XCTAssertTrue(service.submissions.isEmpty)
        }
    }
    func testWhitelistAndFrozenScopesCannotCreateAuthorSaveLease() async {
        for scope in [ProjectEditScope.whitelist, .sellingFrozen] {
            let (model, _, _, service) = await setup(scope: scope)
            XCTAssertFalse(model.fullEdit); XCTAssertNil(model.captureStarterLease()); XCTAssertTrue(service.submissions.isEmpty)
        }
    }
    func testUIKeepsOriginalFullEditABAPreviewAndRetirementFences() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("App/NativeRpgConditionAuthorView.swift"), encoding: .utf8)
        for clause in ["scenePhase == .active && model.fullEdit && model.confirmation == nil", "model.isCurrentStarterLease(capture.lease)", "model.draftMutationRevision == capture.revision", "storageNamespace.utf8.elementsEqual", "model.coordinator.snapshot == capture.snapshot", "ProjectEditPendingMaterials.exactData(model.draft) == capture.bytes", "ProjectEditPendingMaterials.exactData(next) == expected.bytes", "bufferRevision == expected.revision", "review?.id == expected.id", "guard model.persistLocalChange(next, lease: capture.lease) else", ".onChange(of: model.editorIncarnation)", ".onDisappear { retire() }"] {
            XCTAssertTrue(source.contains(clause), clause)
        }
        XCTAssertFalse(source.contains("TemplateAuthoringModel")); XCTAssertFalse(source.contains("persistStagedRpgDraft")); XCTAssertFalse(source.contains("URLSession"))
        XCTAssertTrue(source.contains("模板状态效果编辑尚未接入"))
    }
    func testActualProjectEntryHostsWithoutChangingOrSubmittingRules() async {
        let (model, _, _, service) = await setup(); let before = ProjectEditPendingMaterials.exactData(model.draft)
        let host = UIHostingController(rootView: NavigationStack { Form { NativeRpgConditionAuthorEntry(model: model) } }
            .environment(\.scenePhase, .active).environment(\.dynamicTypeSize, .accessibility5))
        host.loadViewIfNeeded(); host.view.frame = CGRect(x: 0, y: 0, width: 320, height: 640); host.view.setNeedsLayout(); host.view.layoutIfNeeded()
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before); XCTAssertTrue(service.submissions.isEmpty)
    }
}
